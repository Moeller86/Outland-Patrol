class_name Missiles
extends Node3D
## Målsøgende missiler, flares og missilforsvar.
##
## Spillerens missiler (R / midterste museknap) kræver et låst mål. Skytten simulerer
## sit eget missil og melder træf til værten (med dusør); de andre ser en kopi.
## Nogle pirater har missiler. Værten affyrer dem mod en spiller; det skib, der er
## målet, afgør selv, om det bliver ramt, narret af flares (F) eller skudt ned af
## missilforsvaret (opgradering), og fortæller de andre det.

const SPEED0 := 110.0
const SPEED_MAX := 200.0
const ACCEL := 120.0
const TURN := 3.0               ## rad/s
const LIFE := 7.0
const HIT_RADIUS := 5.0
const PLAYER_DAMAGE := 6.0      ## skade på en pirat (nok til at sprænge den)
const PIRATE_DAMAGE := 16.0     ## skade på en spiller
const MAX_AMMO := 8
const FIRE_COOLDOWN := 0.6
const BLAST_RADIUS := 16.0      ## missilets sprængradius (bomben: 42 m)
const BLAST_DAMAGE := 5.0
const MISSILE_BLAST := 0.45     ## eksplosionens størrelse i forhold til en bombe
const FLARE_COOLDOWN := 5.0
const FLARE_CHANCE := 0.75
const PD_RANGE := 150.0
const PD_INTERVAL := 0.5
const PD_CHANCE := 0.45

var _m: Dictionary = {}          ## missil-id -> {pos, dir, speed, life, kind, target, mine, node}
var _flares: Array[Dictionary] = []
var _next := 1
var fire_cool := 0.0
var flare_cool := 0.0
var _pd_t := 0.0
var _warn_t := 0.0


func incoming() -> int:
	## Antal piratmissiler, der er låst på eget skib.
	var me := W.local_ship
	var n := 0
	for id: int in _m:
		var m: Dictionary = _m[id]
		if m["kind"] == "pirate" and me and m["target"] == me.peer_id:
			n += 1
	return n


# ---------------------------------------------------------------- spillerens missiler

## Affyr et missil. Med et låst mål styrer det selv efter målet; uden lås flyver
## det ligeud, hvor kanonerne sigter, og sprænger ved første træf (pirat, mål,
## jorden eller vandet). Returnerer en fejltekst eller "".
func fire_player(ship: Ship) -> String:
	if fire_cool > 0.0:
		return "busy"
	if int(Game.wallet.get("missiles", 0)) <= 0:
		return "Ingen missiler – køb flere på en base eller station"
	fire_cool = FIRE_COOLDOWN
	var id := multiplayer.get_unique_id() * 10000 + _next
	_next += 1
	var from := ship.global_transform * Vector3(0, -0.9, -2.0)
	var target := ship.lock_target if ship.is_locked() else -1
	var dir := ship.aim_dir.normalized() if target < 0 and ship.aim_dir.length() > 0.5 else (ship.forward() + ship.global_basis.y * -0.05).normalized()
	_spawn(id, from, dir, ship.speed, "player", target, true)
	Game.wallet["missiles"] = int(Game.wallet["missiles"]) - 1
	Game.wallet_changed.emit()
	Game.request_spend_missile()
	Sfx.play("lava", -6.0, 0.1)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_cl_copy.rpc(id, from, dir, ship.speed, target)
	return ""


@rpc("any_peer", "call_remote", "reliable")
func _cl_copy(id: int, from: Vector3, dir: Vector3, spd: float, target: int) -> void:
	_spawn(id, from, dir, spd, "player", target, false)
	Sfx.play_at("lava", from, -4.0)


# ---------------------------------------------------------------- piraternes missiler

## Server: en pirat skyder et missil mod en spillers skib.
func server_pirate_fire(from: Vector3, dir: Vector3, target_peer: int) -> void:
	var id := _next
	_next += 1
	_cl_pirate.rpc(-id, from, dir, target_peer)


@rpc("authority", "call_local", "reliable")
func _cl_pirate(id: int, from: Vector3, dir: Vector3, target_peer: int) -> void:
	var me := W.local_ship
	var mine := me != null and me.peer_id == target_peer
	_spawn(id, from, dir, 60.0, "pirate", target_peer, mine)
	Sfx.play_at("lava", from, -2.0)
	if mine:
		Game.toast.emit("⚠ Missil låst på dig! Tryk F for flares")


## Ramte et spillermissil en pirat? Det låste mål først, ellers enhver pirat på vejen.
func _pirate_hit(from: Vector3, to: Vector3, target: int) -> int:
	if target >= 0 and W.pirates.is_active(target) and Bolts.seg_dist(from, to, W.pirates.position_of(target)) < HIT_RADIUS:
		return target
	for i in Pirates.POOL:
		if W.pirates.is_active(i) and Bolts.seg_dist(from, to, W.pirates.position_of(i)) < HIT_RADIUS:
			return i
	return -1


## Server: et spillermissil er sprængt – mindre områdeskade end en bombe.
@rpc("any_peer", "call_local", "reliable")
func _srv_impact(id: int, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if W.assault:
		W.assault.server_blast(pos, BLAST_RADIUS, BLAST_DAMAGE, false)
	for i in Pirates.POOL:
		if W.pirates.is_active(i) and W.pirates.position_of(i).distance_to(pos) < BLAST_RADIUS:
			W.pirates.server_damage(i, 2.0)
	_cl_boom.rpc(id, pos, true)


## Fjern et missil hos alle (ramt, narret eller skudt ned).
@rpc("any_peer", "call_local", "reliable")
func _cl_boom(id: int, pos: Vector3, big: bool) -> void:
	if _m.has(id):
		(_m[id]["node"] as Node3D).queue_free()
		_m.erase(id)
	if big and W.bombs:
		W.bombs.big_explosion(pos, MISSILE_BLAST)
	else:
		W.fx.explosion(pos, big)
		Sfx.play_at("eksplosion", pos, -2.0 if big else -6.0)


@rpc("any_peer", "call_local", "reliable")
func _cl_decoy(id: int, flare_pos: Vector3) -> void:
	if _m.has(id):
		_m[id]["decoy"] = flare_pos
		_m[id]["life"] = minf(float(_m[id]["life"]), 1.2)


# ---------------------------------------------------------------- flares og missilforsvar

func fire_flares(ship: Ship) -> String:
	if flare_cool > 0.0:
		return "Flares lader op …"
	flare_cool = FLARE_COOLDOWN
	var back := -ship.forward()
	var pos := ship.position + back * 4.0
	_cl_flares(pos, back * 18.0)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_cl_flares.rpc(pos, back * 18.0)
	# Hvert missil på vej mod os bliver måske narret
	var flare_at := pos + back * 25.0
	for id: int in _m.keys():
		var m: Dictionary = _m[id]
		if m["kind"] == "pirate" and m["target"] == ship.peer_id and not m.has("decoy") \
				and (m["pos"] as Vector3).distance_to(ship.position) < 500.0 and randf() < FLARE_CHANCE:
			_cl_decoy.rpc(id, flare_at)
	Sfx.play("knitren", -6.0, 0.1)
	return ""


@rpc("any_peer", "call_remote", "unreliable")
func _cl_flares(pos: Vector3, vel: Vector3) -> void:
	for k in 4:
		var v := vel + Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		_flares.append({"pos": pos, "vel": v, "life": 3.0})


# ---------------------------------------------------------------- simulation

func _spawn(id: int, from: Vector3, dir: Vector3, spd: float, kind: String, target: int, mine: bool) -> void:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = ModelKit.cyl(0.22, 0.22, 2.0, 6)
	body.material_override = ModelKit.hull(Color("e6ecff") if kind == "player" else Color("3a2350"))
	body.rotation = Vector3(-PI / 2, 0, 0)
	n.add_child(body)
	var tip := MeshInstance3D.new()
	tip.mesh = ModelKit.cyl(0.0, 0.22, 0.6, 6)
	tip.material_override = ModelKit.glow(Color("ff3b3b") if kind == "player" else Color("7dff4d"))
	tip.rotation = Vector3(-PI / 2, 0, 0)
	tip.position = Vector3(0, 0, -1.3)
	n.add_child(tip)
	add_child(n)
	_m[id] = {"pos": from, "dir": dir.normalized(), "speed": maxf(SPEED0, spd + 30.0), "life": LIFE,
		"kind": kind, "target": target, "mine": mine, "node": n}


func _target_pos(m: Dictionary) -> Vector3:
	if m.has("decoy"):
		return m["decoy"]
	if m["kind"] == "player":
		if W.pirates and W.pirates.is_active(m["target"]):
			var tp := W.pirates.position_of(m["target"])
			var tv := W.pirates.velocity_of(m["target"])
			return tp + tv * clampf((m["pos"] as Vector3).distance_to(tp) / float(m["speed"]), 0.0, 1.5)
		return Vector3.INF
	var s: Ship = W.ships.get(m["target"])
	if s and is_instance_valid(s) and not s.dead and s.state == Ship.State.FLY and not s.cloaked:
		return s.position + s.forward() * s.speed * clampf((m["pos"] as Vector3).distance_to(s.position) / float(m["speed"]), 0.0, 1.0)
	return Vector3.INF


func _physics_process(delta: float) -> void:
	fire_cool = maxf(0.0, fire_cool - delta)
	flare_cool = maxf(0.0, flare_cool - delta)
	var me := W.local_ship
	for id: int in _m.keys():
		if not _m.has(id):
			continue
		var m: Dictionary = _m[id]
		m["life"] = float(m["life"]) - delta
		m["speed"] = minf(SPEED_MAX, float(m["speed"]) + ACCEL * delta)
		var tp := _target_pos(m)
		var dir: Vector3 = m["dir"]
		if tp != Vector3.INF:
			var want := (tp - (m["pos"] as Vector3)).normalized()
			var ang := dir.angle_to(want)
			if ang > 0.0001:
				dir = dir.slerp(want, minf(1.0, TURN * delta / ang)).normalized()
		m["dir"] = dir
		var from: Vector3 = m["pos"]
		var to := from + dir * float(m["speed"]) * delta
		m["pos"] = to
		var n: Node3D = m["node"]
		n.position = to
		if dir.length() > 0.5:
			n.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
		# Røgspor
		W.fx.spawn(from, -dir * 4.0 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)),
			Color("8a8fb0") if randf() < 0.7 else Color("ffd23f"), 0.7, 0.7)
		# Træf og udløb (kun den maskine, der "ejer" afgørelsen)
		if not m["mine"]:
			if m["life"] <= -1.0:   # sikkerhed, hvis beskeden om at fjerne det aldrig kom
				n.queue_free()
				_m.erase(id)
			continue
		if m.has("decoy") and to.distance_to(m["decoy"]) < 6.0 or m["life"] <= 0.0:
			_cl_boom.rpc(id, to, false)
			continue
		if m["kind"] == "player":
			var victim := _pirate_hit(from, to, int(m["target"]))
			var pl := W.universe.nearest_planet(to)
			if victim >= 0:
				W.pirates._srv_hit.rpc_id(1, victim, PLAYER_DAMAGE)
				_srv_impact.rpc_id(1, id, to)
			elif pl.ground_altitude(to) < 0.5:
				var dn := (to - pl.position).normalized()
				_srv_impact.rpc_id(1, id, pl.position + dn * (pl.fine_surface_radius(dn) + 0.5))
			elif W.assault and W.assault.missile_contact(from, to):
				_srv_impact.rpc_id(1, id, to)
			elif W.asteroids and W.asteroids.collide(to, 1.0):
				_srv_impact.rpc_id(1, id, to)
		elif me and not m.has("decoy") and Bolts.seg_dist(from, to, me.position) < HIT_RADIUS:
			me.take_damage(PIRATE_DAMAGE)
			Game.toast.emit("Ramt af et missil!")
			_cl_boom.rpc(id, to, true)
	_point_defense(delta)
	_update_flares(delta)
	# Advarselsbip, mens et missil jager os
	_warn_t -= delta
	if incoming() > 0 and _warn_t <= 0.0:
		_warn_t = 0.45
		Sfx.play("laaser", -6.0, 0.0)


## Forsvarsdrone (gadget): skyd det nærmeste piratmissil, der jager os, ned. Returnerer true ved skud.
func drone_intercept(from: Vector3, range_m: float) -> bool:
	var best := 0
	var bd := range_m
	for id: int in _m:
		var m: Dictionary = _m[id]
		if m["kind"] == "pirate" and m["mine"]:
			var d := (m["pos"] as Vector3).distance_to(from)
			if d < bd:
				bd = d
				best = id
	if best == 0:
		return false
	var mp: Vector3 = _m[best]["pos"]
	W.bolts.fire(from, (mp - from).normalized(), 600.0, Color("4dd0ff"), Bolts.Kind.REMOTE)
	Sfx.play("drone", -6.0)
	_cl_boom.rpc(best, mp, false)
	Game.toast.emit("Forsvarsdronen skød et missil ned")
	return true


## Missilforsvar (opgradering): skyder af og til et indkommende missil ned.
func _point_defense(delta: float) -> void:
	var me := W.local_ship
	if me == null or not is_instance_valid(me) or me.dead or Game.upgrade_level("missile_defense") <= 0:
		return
	_pd_t -= delta
	if _pd_t > 0.0:
		return
	var best := 0
	var found := false
	var bd := PD_RANGE
	for id: int in _m:
		var m: Dictionary = _m[id]
		if m["kind"] == "pirate" and m["mine"]:
			var d := (m["pos"] as Vector3).distance_to(me.position)
			if d < bd:
				bd = d
				best = id
				found = true
	if not found:
		return
	_pd_t = PD_INTERVAL
	var mp: Vector3 = _m[best]["pos"]
	W.bolts.fire(me.position + me.global_basis.y * 1.5, (mp - me.position).normalized(), 500.0, Color("9fe2ff"), Bolts.Kind.REMOTE)
	Sfx.play("taarn", -8.0, 0.1)
	if randf() < PD_CHANCE:
		_cl_boom.rpc(best, mp, false)
		Game.toast.emit("Missilforsvar: missil skudt ned")


func _update_flares(delta: float) -> void:
	for f in _flares.duplicate():
		f["life"] = float(f["life"]) - delta
		f["vel"] = (f["vel"] as Vector3) * (1.0 - delta * 0.8)
		f["pos"] = (f["pos"] as Vector3) + (f["vel"] as Vector3) * delta
		W.fx.spawn(f["pos"], Vector3.ZERO, Color("fff3b0") if randf() < 0.5 else Color("ff9e3d"), 1.4, 0.25)
		if f["life"] <= 0.0:
			_flares.erase(f)
