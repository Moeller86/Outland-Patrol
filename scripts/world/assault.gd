class_name Assault
extends Node3D
## Piratfæstningen til angrebsmissionerne: bygget langs en kløft på en planet.
##
##   luftskyts   – på kløftens kanter. Skyder flak mod skibe, der flyver højt; nede i
##                 kløften er man svær at ramme. Kan skydes ned med laser.
##   kontroltårne – høje, pansrede tårne. Kun bomber virker. De holder reaktorens skjold oppe.
##   brændstoftanke – på afsatser i kløften. Eksploderer og river naboerne med.
##   broer       – spænder over kløften: flyv under dem (eller over).
##   reaktor     – for enden af kløften. Når tårnene er væk, falder skjoldet: bomb den,
##                 og kom væk, før den går kritisk.
##
## Værten ejer målenes liv; alle maskiner bygger fæstningen ens ud fra planeten.

signal server_target_destroyed(idx: int, kind: String)

const K = preload("res://scripts/world/model_kit.gd")

const KINDS := {
	"flak": {"hp": 4.0, "r": 5.0, "laser": true, "label": "LUFTSKYTS"},
	"tower": {"hp": 10.0, "r": 7.0, "laser": false, "label": "KONTROLTÅRN"},
	"tank": {"hp": 2.0, "r": 5.5, "laser": true, "label": "TANK"},
	"reactor": {"hp": 24.0, "r": 16.0, "laser": false, "label": "REAKTOR"},
}
const TOWER_H := 56.0
const FLAK_RANGE := 650.0
const FLAK_RADIUS := 11.0
const FLAK_DAMAGE := 8.0

var planet: PlanetBody
var targets: Array[Dictionary] = []     ## {kind, pos, up, hp, alive, node, head, cool}
var bridges: Array[Transform3D] = []    ## broernes transform (planet-uafhængig, verden)
var bridge_size := Vector3.ZERO
var center := Vector3.ZERO
var entry := Vector3.ZERO
var reactor_idx := -1
var _root: Node3D
var _dome: MeshInstance3D
var _blink: Array[MeshInstance3D] = []
var _t := 0.0
var _armor_toast := 0.0
var _smoke: Array[Vector3] = []
var _chain: Array[Dictionary] = []      ## server: forsinkede kædeeksplosioner


func active() -> bool:
	return planet != null


func shielded() -> bool:
	for t in targets:
		if t["kind"] == "tower" and t["alive"]:
			return true
	return false


func count(kind: String, alive := true) -> int:
	var n := 0
	for t in targets:
		if t["kind"] == kind and t["alive"] == alive:
			n += 1
	return n


func total(kind: String) -> int:
	var n := 0
	for t in targets:
		if t["kind"] == kind:
			n += 1
	return n


# ---------------------------------------------------------------- opbygning

## Server: byg fæstningen på planeten og fortæl alle det.
func server_setup(planet_id: String) -> void:
	_cl_build.rpc(planet_id, [])


func server_clear() -> void:
	_cl_clear.rpc()


@rpc("authority", "call_local", "reliable")
func _cl_clear() -> void:
	if _root:
		_root.queue_free()
	_root = null
	planet = null
	targets.clear()
	bridges.clear()
	_blink.clear()
	_smoke.clear()
	_chain.clear()
	reactor_idx = -1


@rpc("authority", "call_local", "reliable")
func _cl_build(planet_id: String, dead: Array) -> void:
	_cl_clear()
	var p := W.universe.planet(planet_id)
	var f := {}
	for ff in p.features:
		if ff["type"] == "canyon":
			f = ff
			break
	if f.is_empty():
		return
	planet = p
	_root = Node3D.new()
	_root.name = "Fortress"
	_root.position = p.position
	add_child(_root)
	var a: Vector3 = f["a"]
	var b: Vector3 = f["b"]
	var n: Vector3 = f["n"]
	var w: float = f["width"]
	var depth: float = f["depth"]
	var at := func(t: float, s: float) -> Vector3:
		var d := a.slerp(b, t)
		return (d + n * (s / p.radius)).normalized()
	center = p.position + (at.call(0.5, 0.0) as Vector3) * (p.radius + depth)
	var ed: Vector3 = at.call(0.0, 0.0)
	entry = p.position + ed * (p.radius + depth + 90.0)
	# Luftskyts langs begge kanter
	var k := 0
	var t := 0.1
	while t < 0.93:
		_add_target("flak", at.call(t, (1.0 if k % 2 == 0 else -1.0) * w * 1.3))
		t += 0.075
		k += 1
	# Kontroltårne på kanterne
	for i in 3:
		_add_target("tower", at.call(0.3 + i * 0.24, (1.0 if i % 2 == 0 else -1.0) * w * 1.7))
	# Brændstoftanke på afsatserne
	var side := 1.0
	for tt in [0.2, 0.44, 0.66]:
		for dt in [0.0, 0.018]:
			_add_target("tank", at.call(tt + dt, side * w * 0.62))
		side = -side
	# Reaktoren for enden
	reactor_idx = targets.size()
	_add_target("reactor", at.call(0.965, 0.0))
	# Broer over kløften
	bridge_size = Vector3(w * 2.6, 7.0, 11.0)
	for tt in [0.26, 0.5, 0.74]:
		var d: Vector3 = at.call(tt, 0.0)
		var fl := p.position + d * p.surface_radius(d)
		var along := (a.slerp(b, tt + 0.01) - a.slerp(b, tt)).normalized()
		var xf := Transform3D(Basis.looking_at(along, d), fl + d * (depth * 0.6))
		bridges.append(xf)
	_build_visuals(f)
	for idx: int in dead:
		_kill_local(idx, false)


func _add_target(kind: String, d: Vector3) -> void:
	var p := planet
	var h := p.surface_radius(d)
	var pos := p.position + d * h
	targets.append({"kind": kind, "pos": pos, "up": d, "hp": float(KINDS[kind]["hp"]), "alive": true,
		"node": null, "head": null, "cool": randf_range(0.5, 2.0)})


func _build_visuals(f: Dictionary) -> void:
	var metal := K.hull(Color("4a3a5a"), K.TEX_PLATING, 0.5)
	var dark := K.hull(Color("2a2238"), K.TEX_PLATING, 0.5)
	var red := K.hull(Color("c0303a"), K.TEX_PANEL, 0.4)
	var stripes := K.stripes(0.5)
	for i in targets.size():
		var tg: Dictionary = targets[i]
		var g := Node3D.new()
		var up: Vector3 = tg["up"]
		var fwd := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		g.transform = Transform3D(Basis.looking_at(fwd, up), tg["pos"] - planet.position)
		_root.add_child(g)
		tg["node"] = g
		match str(tg["kind"]):
			"flak":
				K.add(g, K.cyl(3.6, 4.4, 2.0, 8), dark, Vector3(0, 1.0, 0))
				K.add(g, K.cyl(2.2, 2.8, 2.2, 8), metal, Vector3(0, 3.0, 0))
				var head := Node3D.new()
				head.position = Vector3(0, 4.6, 0)
				g.add_child(head)
				K.add(head, K.box(3.4, 2.0, 3.0), red, Vector3.ZERO)
				for s in [-0.8, 0.8]:
					K.add(head, K.cyl(0.25, 0.3, 4.4, 6), dark, Vector3(s, 0.3, -2.6), Vector3(-PI / 2, 0, 0))
				_blink.append(K.add(head, K.box(0.5, 0.5, 0.5), K.glow(Color("ff3b3b")), Vector3(0, 1.2, 0)))
				tg["head"] = head
			"tower":
				K.add(g, K.box(14.0, 4.0, 14.0), dark, Vector3(0, 2.0, 0))
				K.add(g, K.box(7.0, TOWER_H - 10.0, 7.0), metal, Vector3(0, (TOWER_H - 10.0) / 2.0 + 4.0, 0))
				K.add(g, K.box(7.2, 6.0, 7.2), K.windows(0.6), Vector3(0, TOWER_H - 12.0, 0))
				K.add(g, K.cyl(5.0, 6.5, 5.0, 8), red, Vector3(0, TOWER_H - 4.0, 0))
				K.add(g, K.cyl(0.3, 0.4, 12.0, 6), dark, Vector3(0, TOWER_H + 4.0, 0))
				K.add(g, K.torus(4.2, 0.4, 16, 4), K.glow(Color("ff4fd8")), Vector3(0, TOWER_H - 1.0, 0))
				_blink.append(K.add(g, K.box(1.2, 1.2, 1.2), K.glow(Color("ff3b3b")), Vector3(0, TOWER_H + 10.5, 0)))
				for s in [-1.0, 1.0]:
					K.add(g, K.box(1.0, TOWER_H * 0.7, 1.0), dark, Vector3(s * 4.5, TOWER_H * 0.35, s * 4.5))
			"tank":
				K.add(g, K.cyl(4.5, 4.5, 8.0, 10), K.hull(Color("e8b13a"), K.TEX_PANEL, 0.4), Vector3(0, 4.0, 0))
				K.add(g, K.cyl(4.6, 4.6, 1.2, 10), stripes, Vector3(0, 6.0, 0))
				K.add(g, K.sphere(4.5, 10, 4), K.hull(Color("e8b13a"), K.TEX_PANEL, 0.4), Vector3(0, 8.0, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
			"reactor":
				K.add(g, K.cyl(30.0, 32.0, 6.0, 14), dark, Vector3(0, 1.0, 0))
				K.add(g, K.cyl(14.0, 16.0, 6.0, 12), metal, Vector3(0, 7.0, 0))
				var core := K.add(g, K.cyl(9.0, 9.0, 18.0, 12), K.glow(Color("4dffe1")), Vector3(0, 18.0, 0))
				core.name = "Core"
				for y in [12.0, 19.0, 26.0]:
					K.add(g, K.torus(11.0, 1.0, 16, 4), red, Vector3(0, y, 0))
				for k2 in 4:
					var ang := k2 * PI / 2.0
					K.add(g, K.box(3.0, 26.0, 3.0), dark, Vector3(cos(ang) * 20.0, 13.0, sin(ang) * 20.0))
				_dome = MeshInstance3D.new()
				_dome.mesh = K.sphere(34.0, 16, 10)
				var dm := StandardMaterial3D.new()
				dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				dm.albedo_color = Color(0.4, 0.8, 1.0, 0.22)
				dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dm.cull_mode = BaseMaterial3D.CULL_DISABLED
				_dome.material_override = dm
				_dome.position = Vector3(0, 6.0, 0)
				_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				g.add_child(_dome)
		for c in g.get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Broerne
	for xf in bridges:
		var g := Node3D.new()
		g.transform = Transform3D(xf.basis, xf.origin - planet.position)
		_root.add_child(g)
		# Basis.looking_at(along, up): lokal -Z langs kløften, X på tværs
		K.add(g, K.box(bridge_size.x, bridge_size.y, bridge_size.z), metal, Vector3.ZERO)
		K.add(g, K.box(bridge_size.x, 1.0, 1.2), stripes, Vector3(0, -bridge_size.y / 2.0, bridge_size.z / 2.0))
		K.add(g, K.box(bridge_size.x, 1.0, 1.2), stripes, Vector3(0, -bridge_size.y / 2.0, -bridge_size.z / 2.0))
		for s in [-1.0, 1.0]:
			for x in range(-3, 4):
				_blink.append(K.add(g, K.box(0.8, 0.8, 0.8), K.glow(Color("ffd23f")), Vector3(x * bridge_size.x / 7.0, -bridge_size.y / 2.0 - 0.5, s * bridge_size.z / 2.0)))


# ---------------------------------------------------------------- træffere og skade

## Lokal laser: rammer skuddet et mål? Meldes til værten.
func hit_test(a: Vector3, b: Vector3, dmg: float) -> bool:
	if planet == null:
		return false
	var idx := _segment_target(a, b)
	if idx < 0:
		return false
	var tg: Dictionary = targets[idx]
	if not KINDS[tg["kind"]]["laser"] or (tg["kind"] == "reactor"):
		if _armor_toast <= 0.0:
			_armor_toast = 3.0
			if tg["kind"] == "reactor" and shielded():
				Game.toast.emit("Reaktoren er skjoldet – ødelæg kontroltårnene først")
			else:
				Game.toast.emit("Pansret! Brug bomber (B)")
		return true
	_srv_hit.rpc_id(1, idx, dmg)
	return true


## Har et missil ramt et af fæstningens mål eller en bro?
func missile_contact(a: Vector3, b: Vector3) -> bool:
	if planet == null:
		return false
	if _segment_target(a, b) >= 0:
		return true
	for xf in bridges:
		if _in_box(xf, bridge_size, b, 0.5):
			return true
	return false


## Har en faldende bombe ramt et tårn, en bro eller reaktoren?
func bomb_contact(a: Vector3, b: Vector3) -> bool:
	if planet == null:
		return false
	var idx := _segment_target(a, b)
	if idx >= 0 and targets[idx]["kind"] != "flak" and targets[idx]["kind"] != "tank":
		return true
	for xf in bridges:
		if _in_box(xf, bridge_size, b, 0.5):
			return true
	return false


func _segment_target(a: Vector3, b: Vector3) -> int:
	for i in targets.size():
		var tg: Dictionary = targets[i]
		if not tg["alive"]:
			continue
		var r: float = KINDS[tg["kind"]]["r"]
		var base: Vector3 = tg["pos"]
		if a.distance_to(base) > 200.0 and b.distance_to(base) > 200.0:
			continue
		var up: Vector3 = tg["up"]
		var h := 4.0
		match str(tg["kind"]):
			"tower": h = TOWER_H
			"reactor": h = 28.0
			"tank": h = 8.0
			"flak": h = 6.0
		for k in 5:
			var p := a.lerp(b, k / 4.0)
			var rel := p - base
			var y := rel.dot(up)
			if y < -1.0 or y > h + 1.0:
				continue
			if (rel - up * y).length() < r:
				return i
	return -1


@rpc("any_peer", "call_local", "reliable")
func _srv_hit(idx: int, dmg: float) -> void:
	if not multiplayer.is_server() or idx < 0 or idx >= targets.size():
		return
	_server_damage(idx, dmg)


## Server: bombe/kædeeksplosion – skade i et område.
func server_blast(pos: Vector3, radius: float, dmg: float, heavy := true) -> void:
	if planet == null:
		return
	for i in targets.size():
		var tg: Dictionary = targets[i]
		if not tg["alive"]:
			continue
		var base: Vector3 = tg["pos"]
		var up: Vector3 = tg["up"]
		var h := TOWER_H if tg["kind"] == "tower" else 10.0
		var y := clampf((pos - base).dot(up), 0.0, h)
		var d := maxf(0.0, pos.distance_to(base + up * y) - float(KINDS[tg["kind"]]["r"]))
		if d < radius:
			if tg["kind"] == "reactor" and shielded():
				continue
			if not heavy and not KINDS[tg["kind"]]["laser"]:
				continue      # missiler preller af på tårne og reaktor – brug bomber
			_server_damage(i, dmg * (1.0 - 0.7 * d / radius))


func _server_damage(idx: int, dmg: float) -> void:
	var tg: Dictionary = targets[idx]
	if not tg["alive"]:
		return
	if tg["kind"] == "reactor" and shielded():
		return
	tg["hp"] = float(tg["hp"]) - dmg
	if tg["hp"] <= 0.0:
		_cl_destroy.rpc(idx)
		server_target_destroyed.emit(idx, tg["kind"])
		if tg["kind"] == "tank":
			_chain.append({"t": 0.18, "pos": (tg["pos"] as Vector3) + (tg["up"] as Vector3) * 5.0, "r": 34.0, "dmg": 6.0})


@rpc("authority", "call_local", "reliable")
func _cl_destroy(idx: int) -> void:
	_kill_local(idx, true)


func _kill_local(idx: int, fx: bool) -> void:
	if idx < 0 or idx >= targets.size():
		return
	var tg: Dictionary = targets[idx]
	tg["alive"] = false
	var g: Node3D = tg["node"]
	var pos: Vector3 = tg["pos"]
	var up: Vector3 = tg["up"]
	_smoke.append(pos + up * 3.0)
	match str(tg["kind"]):
		"tower":
			if fx:
				W.bombs.big_explosion(pos + up * TOWER_H * 0.5, 1.4)
				var tw := create_tween()
				tw.tween_property(g, "rotation:x", g.rotation.x + 0.9, 2.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				tw.parallel().tween_property(g, "position", g.position - up * (TOWER_H * 0.6), 2.4).set_ease(Tween.EASE_IN)
				tw.tween_callback(func() -> void: g.visible = false)
			else:
				g.visible = false
			if fx:
				Game.toast.emit("Kontroltårn ødelagt!")
		"reactor":
			if fx:
				W.bombs.big_explosion(pos + up * 14.0, 3.0)
			g.visible = false
		"tank":
			if fx:
				W.bombs.big_explosion(pos + up * 5.0, 0.9)
			g.visible = false
		_:
			if fx:
				W.fx.explosion(pos + up * 4.0, true)
				W.fx.burst(pos + up * 4.0, 14, 30.0, [Color("ff7a3d"), Color("3a3048")], 1.6, 1.2)
				Sfx.play_at("eksplosion", pos, 0.0)
			g.visible = false
	# Ruiner
	if g and is_instance_valid(g) and tg["kind"] != "tower":
		var rubble := Node3D.new()
		rubble.transform = g.transform
		_root.add_child(rubble)
		var rr: float = KINDS[tg["kind"]]["r"]
		for k in 5:
			var b := K.add(rubble, K.box(rr * randf_range(0.3, 0.7), rr * randf_range(0.2, 0.4), rr * randf_range(0.3, 0.7)),
				K.flat(Color("2a2228")), Vector3(randf_range(-rr, rr) * 0.6, 0.6, randf_range(-rr, rr) * 0.6))
			b.rotation = Vector3(randf() * 0.5, randf() * TAU, randf() * 0.5)
	if _dome and idx != reactor_idx and not shielded():
		_dome.visible = false
		if fx:
			Game.toast.emit("Reaktorens skjold er nede – bomb den!")


# ---------------------------------------------------------------- flak

@rpc("authority", "call_local", "unreliable")
func _cl_flak(from: Vector3, burst: Vector3, peer: int) -> void:
	W.bolts.fire(from, (burst - from).normalized(), 520.0, Color("ff9f1c"), Bolts.Kind.REMOTE)
	await get_tree().create_timer(clampf(from.distance_to(burst) / 520.0, 0.05, 1.2)).timeout
	if planet == null:
		return
	W.fx.burst(burst, 10, 16.0, [Color("ff9f1c"), Color("ffd23f"), Color("3a3048"), Color("5a4a5a")], 2.4, 0.9)
	Sfx.play_at("eksplosion", burst, -10.0)
	var me := W.local_ship
	if me and is_instance_valid(me) and me.peer_id == peer and not me.dead and me.state == Ship.State.FLY:
		var d := me.position.distance_to(burst)
		if d < FLAK_RADIUS:
			me.take_damage(FLAK_DAMAGE * (1.0 - 0.6 * d / FLAK_RADIUS))


## Hvor synligt er skibet for luftskytset? 0 = nede i kløften, 1 = højt oppe.
func exposure(pos: Vector3) -> float:
	if planet == null:
		return 0.0
	return smoothstep(45.0, 115.0, planet.ground_altitude(pos))


## Er skibet tæt på fæstningen (til HUD-advarsler)?
func near(pos: Vector3, dist := 900.0) -> bool:
	return planet != null and pos.distance_to(center) < dist


@rpc("authority", "call_local", "reliable")
func cl_shock(pos: Vector3, radius: float, dmg: float) -> void:
	var me := W.local_ship
	if me and is_instance_valid(me) and not me.dead and me.state == Ship.State.FLY:
		var d := me.position.distance_to(pos)
		if d < radius:
			me.take_damage(dmg * (1.0 - d / radius))


# ---------------------------------------------------------------- kollision

## Kollision mellem skibet og tårne, broer og reaktoren. Returnerer ny position eller INF.
func collide(pos: Vector3) -> Vector3:
	if planet == null or pos.distance_to(center) > 1600.0:
		return Vector3.INF
	for xf in bridges:
		if _in_box(xf, bridge_size, pos, 1.5):
			var l := xf.affine_inverse() * pos
			# Skub ud lodret (over/under broen)
			l.y = (bridge_size.y / 2.0 + 2.0) * (1.0 if l.y >= 0.0 else -1.0)
			return xf * l
	for tg in targets:
		if not tg["alive"] or tg["kind"] == "flak" or tg["kind"] == "tank":
			continue
		var base: Vector3 = tg["pos"]
		var up: Vector3 = tg["up"]
		var h := TOWER_H if tg["kind"] == "tower" else 28.0
		var rel := pos - base
		var y := rel.dot(up)
		if y < 0.0 or y > h:
			continue
		var side := rel - up * y
		var r: float = float(KINDS[tg["kind"]]["r"]) + 1.5
		if side.length() < r:
			return base + up * y + side.normalized() * (r + 0.5)
	return Vector3.INF


func _in_box(xf: Transform3D, size: Vector3, p: Vector3, margin: float) -> bool:
	var l := xf.affine_inverse() * p
	return absf(l.x) < size.x / 2.0 + margin and absf(l.y) < size.y / 2.0 + margin and absf(l.z) < size.z / 2.0 + margin


# ---------------------------------------------------------------- markører til HUD

func markers(from: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if planet == null:
		return out
	for i in targets.size():
		var tg: Dictionary = targets[i]
		if not tg["alive"]:
			continue
		var p: Vector3 = tg["pos"]
		var d := from.distance_to(p)
		match str(tg["kind"]):
			"tower":
				out.append({"pos": p + (tg["up"] as Vector3) * TOWER_H, "label": "▼ TÅRN", "color": Color("ffd23f"), "d": d})
			"reactor":
				out.append({"pos": p + (tg["up"] as Vector3) * 30.0, "label": "REAKTOR" + (" (SKJOLD)" if shielded() else " ▼ BOMB"),
					"color": Color("ff4fd8"), "d": d})
			"flak":
				if d < 700.0:
					out.append({"pos": p + (tg["up"] as Vector3) * 6.0, "label": "✦", "color": Color("ff5a5a"), "d": d})
	return out


# ---------------------------------------------------------------- løkke

func _physics_process(delta: float) -> void:
	if planet == null:
		return
	_t += delta
	_armor_toast -= delta
	for i in _blink.size():
		if is_instance_valid(_blink[i]):
			_blink[i].visible = fmod(_t * 1.3 + i * 0.29, 1.0) < 0.6
	# Røg fra ruinerne
	if randf() < 0.5 and not _smoke.is_empty():
		var sp: Vector3 = _smoke.pick_random()
		var up := (sp - planet.position).normalized()
		W.fx.spawn(sp, up * randf_range(6, 12) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), Color("3a3048"), randf_range(2.0, 3.5), 2.5)
	# Reaktoren pulserer
	if reactor_idx >= 0 and targets[reactor_idx]["alive"]:
		var core: Node3D = (targets[reactor_idx]["node"] as Node3D).get_node_or_null("Core")
		if core:
			core.scale = Vector3(1.0 + 0.06 * sin(_t * 5.0), 1.0, 1.0 + 0.06 * sin(_t * 5.0))
	# Luftskytset drejer mod det lokale skib
	var me := W.local_ship
	if me and is_instance_valid(me):
		for tg in targets:
			if tg["kind"] == "flak" and tg["alive"] and tg["head"]:
				var head: Node3D = tg["head"]
				if me.position.distance_to(tg["pos"]) < FLAK_RANGE + 200.0:
					var to := me.position - head.global_position
					if to.length() > 1.0:
						head.global_basis = Basis.looking_at(to.normalized(), tg["up"])
	if W.is_server():
		_server_tick(delta)


func _server_tick(delta: float) -> void:
	# Kædeeksplosioner fra tanke
	var keep: Array[Dictionary] = []
	for c in _chain:
		c["t"] = float(c["t"]) - delta
		if c["t"] <= 0.0:
			server_blast(c["pos"], c["r"], c["dmg"])
		else:
			keep.append(c)
	_chain = keep
	# Luftskyts
	var ships := W.active_ships()
	for tg in targets:
		if tg["kind"] != "flak" or not tg["alive"]:
			continue
		tg["cool"] = float(tg["cool"]) - delta
		if tg["cool"] > 0.0:
			continue
		var best: Ship = null
		var bd := FLAK_RANGE
		var gun: Vector3 = (tg["pos"] as Vector3) + (tg["up"] as Vector3) * 5.0
		for s in ships:
			var d := s.position.distance_to(gun)
			if d < bd:
				bd = d
				best = s
		if best == null:
			tg["cool"] = 0.6
			continue
		var e := exposure(best.position)
		tg["cool"] = randf_range(0.9, 1.5) * lerpf(1.6, 1.0, e)
		var lead := best.position + best.forward() * best.speed * clampf(bd / 520.0, 0.05, 1.2)
		var spread := lerpf(55.0, 7.0, e)
		var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(spread * 0.3, spread)
		_cl_flak.rpc(gun, lead + off, best.peer_id)


func _ready() -> void:
	Game.player_joined.connect(func(id: int) -> void:
		if planet != null and W.is_server() and id != multiplayer.get_unique_id():
			var dead: Array = []
			for i in targets.size():
				if not targets[i]["alive"]:
					dead.append(i)
			_cl_build.rpc_id(id, planet.id, dead))
	Net.started.connect(_cl_clear)
