class_name Weather
extends Node3D
## Vejr og farer på planeterne (kun nede i atmosfæren):
##  sandstorm – Sahra: tæt sandtåge, vindstød der skubber skibet, scanner og lock-on
##              har kort rækkevidde, og fjerne markører forsvinder.
##  lightning – Viridia: tordenvejr med regn og mørk himmel. Lynet slår ned nær skibene;
##              jorden lyser og knitrer et sekund før, så man kan nå at flytte sig.
##  lava      – Ignis: vulkanudbrud, hvor lavabomber skydes op og falder ned omkring en.
##              Havet af lava er altid farligt: flyver man lavt over det, bliver skibet kogt.
##
## Værten bestemmer, hvornår der er uvejr på hver planet, og hvor lyn og lavabomber
## kommer. Hver maskine tegner effekterne selv og tjekker skade på sit eget skib.

const TYPES := {
	"sandstorm": {"name": "SANDSTORM", "warn": "⚠ SANDSTORM · scanner og lock-on forstyrret", "color": "e0a85a"},
	"lightning": {"name": "TORDENVEJR", "warn": "⚠ TORDENVEJR · pas på lynnedslag", "color": "9fb4ff"},
	"lava": {"name": "VULKANUDBRUD", "warn": "⚠ VULKANUDBRUD · lavabomber", "color": "ff7a3d"},
}
const CALM_TIME := Vector2(45.0, 100.0)
const STORM_TIME := Vector2(40.0, 70.0)
const FIRST_STORM := Vector2(15.0, 45.0)
const RAMP := 1.0 / 6.0          ## intensitet pr. sekund, når uvejret kommer/går

const STRIKE_WARN := 1.1         ## sekunder fra knitren til nedslag
const STRIKE_RADIUS := 18.0
const STRIKE_DAMAGE := 24.0
const BOMB_GRAVITY := 30.0
const BOMB_HIT := 5.0
const BOMB_BLAST := 14.0
const HEAT_ALT := 28.0           ## lavere end dette over lavahavet koger skibet
const HEAT_DPS := 7.0

const STREAKS := 520
const BOX := Vector3(48.0, 32.0, 48.0)

var active: Dictionary = {}       ## planet-id -> bool (synkroniseret)
var level: Dictionary = {}        ## planet-id -> 0..1 (lokalt, glidende)
var flash := 0.0                  ## lynglimt 0..1 (til himmel og lys)
var heat := false                 ## eget skib er over lavahavet lige nu
var auto := true                  ## server: skift selv mellem uvejr og stille (tests slår det fra)

var _timer: Dictionary = {}       ## server: planet-id -> sekunder til næste skift
var _spawn_t: Dictionary = {}     ## server: planet-id -> sekunder til næste lyn/bombe
var _strikes: Array[Dictionary] = []
var _bombs: Array[Dictionary] = []
var _heat_fx := 0.0

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _pos := PackedVector3Array()
var _bolt: Node3D
var _bolt_segs: Array[MeshInstance3D] = []
var _bolt_t := 0.0
var _flash_light: OmniLight3D
var _bomb_nodes: Array[MeshInstance3D] = []


func _ready() -> void:
	for p in W.universe.planets:
		if p.data.has("weather"):
			active[p.id] = false
			level[p.id] = 0.0
	_build_streaks()
	_build_bolt()
	for k in 12:
		var b := MeshInstance3D.new()
		b.mesh = ModelKit.sphere(1.6, 8, 5)
		b.material_override = ModelKit.glow(Color("ff7a3d"))
		b.visible = false
		add_child(b)
		_bomb_nodes.append(b)
	Game.player_joined.connect(_on_player_joined)
	Net.started.connect(_on_net_started)


func _on_net_started() -> void:
	for id: String in active:
		active[id] = false
		level[id] = 0.0
		_timer[id] = randf_range(FIRST_STORM.x, FIRST_STORM.y)
		_spawn_t[id] = 2.0
	_strikes.clear()
	_bombs.clear()


func type_of(planet_id: String) -> String:
	var p := W.universe.planet(planet_id)
	return str(p.data["weather"]["type"]) if p and p.data.has("weather") else ""


# ---------------------------------------------------------------- forespørgsler

## Vejret, som det mærkes et sted: {type, k (0..1), planet}. k er 0 uden for atmosfæren.
func effect_at(pos: Vector3) -> Dictionary:
	var p := W.universe.nearest_planet(pos)
	if p == null or not level.has(p.id):
		return {"type": "", "k": 0.0, "planet": null}
	var inside := smoothstep(p.atmo_top * 1.15, p.atmo_top * 0.8, p.altitude(pos))
	return {"type": type_of(p.id), "k": float(level[p.id]) * inside, "planet": p}


## Scannerens rækkevidde ganges med dette (sandstorm: kort rækkevidde).
func scan_mul(pos: Vector3) -> float:
	var e := effect_at(pos)
	return lerpf(1.0, 0.3, e["k"]) if e["type"] == "sandstorm" else 1.0


func lock_mul(pos: Vector3) -> float:
	var e := effect_at(pos)
	return lerpf(1.0, 0.33, e["k"]) if e["type"] == "sandstorm" else 1.0


## Hvor langt væk HUD-markører for pirater kan ses (INF uden storm).
func radar_range(pos: Vector3) -> float:
	var e := effect_at(pos)
	return lerpf(5000.0, 350.0, e["k"]) if e["type"] == "sandstorm" and e["k"] > 0.05 else INF


## Vindens skub (m/s) i en sandstorm.
func wind_at(pos: Vector3) -> Vector3:
	var e := effect_at(pos)
	if e["type"] != "sandstorm" or e["k"] <= 0.0:
		return Vector3.ZERO
	var p: PlanetBody = e["planet"]
	var up := (pos - p.position).normalized()
	var t := Time.get_ticks_msec() / 1000.0
	var dir := p.tangent.rotated(up, sin(t * 0.07) * 0.8)
	dir = (dir - up * dir.dot(up)).normalized()
	var gust := 0.6 + 0.4 * sin(t * 1.3) * sin(t * 0.47 + 1.0)
	return dir * 9.0 * gust * float(e["k"])


## Er et punkt over Ignis' lavahav (og lavt nok til at blive kogt)?
func over_lava(pos: Vector3) -> bool:
	var p := W.universe.nearest_planet(pos)
	if p == null:
		return false
	if p.in_crater(pos):
		return true
	if type_of(p.id) != "lava":
		return false
	var d := (pos - p.position).normalized()
	return p.height_at(d) <= 0.5 and p.ground_altitude(pos) < HEAT_ALT


# ---------------------------------------------------------------- server

func _physics_process(delta: float) -> void:
	if W.is_server():
		_server_tick(delta)
	_tick_local(delta)


func _server_tick(delta: float) -> void:
	for id: String in active:
		if not _timer.has(id):
			_timer[id] = randf_range(FIRST_STORM.x, FIRST_STORM.y)
			_spawn_t[id] = 2.0
		if auto:
			_timer[id] -= delta
		if auto and _timer[id] <= 0.0:
			var on: bool = not active[id]
			_timer[id] = randf_range(STORM_TIME.x, STORM_TIME.y) if on else randf_range(CALM_TIME.x, CALM_TIME.y)
			_cl_set.rpc(id, on)
		if not active[id] or level.get(id, 0.0) < 0.5:
			continue
		var kind := type_of(id)
		if kind != "lightning" and kind != "lava":
			continue
		_spawn_t[id] -= delta
		if _spawn_t[id] > 0.0:
			continue
		var p := W.universe.planet(id)
		var in_atmo: Array[Ship] = []
		for s in W.active_ships():
			if W.universe.nearest_planet(s.position) == p and p.altitude(s.position) < p.atmo_top:
				in_atmo.append(s)
		if in_atmo.is_empty():
			_spawn_t[id] = 1.0
			continue
		var target: Ship = in_atmo.pick_random()
		if kind == "lightning":
			_spawn_t[id] = randf_range(1.2, 2.8) / sqrt(float(in_atmo.size()))
			var r := randf_range(0.0, 20.0) if randf() < 0.3 else randf_range(25.0, 110.0)
			_cl_strike.rpc(id, _ground_near(p, target.position, r))
		else:
			_spawn_t[id] = randf_range(0.8, 1.8) / sqrt(float(in_atmo.size()))
			var origin := _ground_near(p, target.position, randf_range(150.0, 280.0))
			var up := (origin - p.position).normalized()
			var vy := randf_range(55.0, 80.0)
			var t_flight := 2.0 * vy / BOMB_GRAVITY
			var aim := _ground_near(p, target.position + target.forward() * target.speed * t_flight * 0.5, randf_range(0.0, 40.0))
			var horiz := aim - origin
			horiz -= up * horiz.dot(up)
			var vel := up * vy + horiz / t_flight * randf_range(0.8, 1.1)
			_cl_bomb.rpc(id, origin, vel)


func _ground_near(p: PlanetBody, pos: Vector3, r: float) -> Vector3:
	var up := (pos - p.position).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized().rotated(up, randf() * TAU)
	var d := (up * p.radius + side * r).normalized()
	return p.position + d * p.fine_surface_radius(d)


## Server (og tests): tænd/sluk vejret på en planet med det samme.
func server_set(planet_id: String, on: bool, instant := false) -> void:
	_timer[planet_id] = randf_range(STORM_TIME.x, STORM_TIME.y) if on else randf_range(CALM_TIME.x, CALM_TIME.y)
	_cl_set.rpc(planet_id, on)
	if instant:
		level[planet_id] = 1.0 if on else 0.0


@rpc("authority", "call_local", "reliable")
func _cl_set(planet_id: String, on: bool) -> void:
	active[planet_id] = on
	var me := W.local_ship
	if on and me and is_instance_valid(me) and W.universe.nearest_planet(me.position).id == planet_id \
			and W.universe.nearest_planet(me.position).altitude(me.position) < W.universe.nearest_planet(me.position).atmo_top * 3.0:
		Game.toast.emit("%s på %s!" % [str(TYPES[type_of(planet_id)]["name"]).capitalize(), W.universe.planet(planet_id).display_name])


@rpc("authority", "call_local", "reliable")
func _cl_strike(planet_id: String, ground: Vector3) -> void:
	var p := W.universe.planet(planet_id)
	var up := (ground - p.position).normalized()
	_strikes.append({"pos": ground, "up": up, "t": 0.0, "hit": false})
	Sfx.play_at("knitren", ground, 0.0, 0.05)


@rpc("authority", "call_local", "reliable")
func _cl_bomb(planet_id: String, origin: Vector3, vel: Vector3) -> void:
	var p := W.universe.planet(planet_id)
	_bombs.append({"pos": origin, "vel": vel, "center": p.position, "planet": p, "t": 0.0})
	Sfx.play_at("lava", origin, 2.0)
	W.fx.burst(origin, 14, 18.0, [Color("ff4f1f"), Color("ffd23f"), Color("3a2a3a")], 1.6, 1.0)


func _on_player_joined(id: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	for pid: String in active:
		if active[pid]:
			_cl_set.rpc_id(id, pid, true)


# ---------------------------------------------------------------- lokalt: skade og effekter

func _tick_local(delta: float) -> void:
	for id: String in level:
		level[id] = move_toward(level[id], 1.0 if active[id] else 0.0, RAMP * delta)
	var me := W.local_ship
	var mine := me != null and is_instance_valid(me) and not me.dead and me.state == Ship.State.FLY
	flash = maxf(0.0, flash - delta * 3.0)

	# Lynnedslag: knitren, så nedslag
	for s in _strikes.duplicate():
		s["t"] = float(s["t"]) + delta
		var ground: Vector3 = s["pos"]
		var up: Vector3 = s["up"]
		if not s["hit"]:
			if randf() < 0.6:
				W.fx.spawn(ground + up * randf_range(0.5, 6.0) + Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)),
					up * randf_range(4, 12), Color("cfe0ff") if randf() < 0.5 else Color("6f8bff"), 0.7, 0.35)
			if s["t"] >= STRIKE_WARN:
				s["hit"] = true
				_show_bolt(ground, up)
				W.fx.burst(ground, 24, 30.0, [Color.WHITE, Color("cfe0ff"), Color("ffd23f")], 1.4, 0.8)
				Sfx.play_at("torden", ground, 6.0, 0.08)
				if mine and Bolts.seg_dist(ground, ground + up * 400.0, me.position) < STRIKE_RADIUS:
					me.take_damage(STRIKE_DAMAGE)
					Game.toast.emit("Ramt af lynet!")
				if me and is_instance_valid(me) and me.position.distance_to(ground) < 600.0:
					flash = 1.0
		elif s["t"] > STRIKE_WARN + 0.5:
			_strikes.erase(s)

	# Lavabomber: kasteparabler mod planetens centrum
	var i := 0
	for b in _bombs.duplicate():
		var p: PlanetBody = b["planet"]
		var pos: Vector3 = b["pos"]
		var up := (pos - p.position).normalized()
		b["vel"] = (b["vel"] as Vector3) - up * BOMB_GRAVITY * delta
		pos += (b["vel"] as Vector3) * delta
		b["pos"] = pos
		b["t"] = float(b["t"]) + delta
		if randf() < 0.8:
			W.fx.spawn(pos, Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)),
				[Color("ff4f1f"), Color("ffd23f"), Color("5a3a4a")][randi() % 3], randf_range(0.8, 1.6), 0.6)
		var boom := false
		if mine and pos.distance_to(me.position) < BOMB_HIT:
			me.take_damage(18.0)
			boom = true
		elif float(b["t"]) > 0.5 and p.ground_altitude(pos) <= 0.0:
			boom = true
			if mine and pos.distance_to(me.position) < BOMB_BLAST:
				me.take_damage(10.0)
		if boom or float(b["t"]) > 12.0:
			W.fx.explosion(pos, false)
			Sfx.play_at("eksplosion", pos, 0.0)
			_bombs.erase(b)
	for n in _bomb_nodes:
		n.visible = false
	for b in _bombs:
		if i < _bomb_nodes.size():
			_bomb_nodes[i].visible = true
			_bomb_nodes[i].position = b["pos"]
			i += 1

	# Varme over lavahavet (altid på Ignis)
	heat = mine and over_lava(me.position)
	if heat:
		me.environment_damage(HEAT_DPS * delta)
		_heat_fx -= delta
		if _heat_fx <= 0.0:
			_heat_fx = 0.7
			me.damaged.emit(true)
		if randf() < 0.5:
			W.fx.spawn(me.position + Vector3(randf_range(-3, 3), -2.0, randf_range(-3, 3)), me.global_basis.y * 6.0,
				Color("ff7a3d"), 0.6, 0.4)

	# Lydkulisse
	var cam := get_viewport().get_camera_3d()
	var e := effect_at(cam.global_position) if cam else {"type": "", "k": 0.0}
	Sfx.set_ambient("vind", e["k"] if e["type"] == "sandstorm" else 0.0)
	Sfx.set_ambient("regn", e["k"] * 0.8 if e["type"] == "lightning" else 0.0)
	Sfx.set_ambient("varme", 1.0 if heat else 0.0)


func _process(delta: float) -> void:
	_update_streaks(delta)
	if _bolt_t > 0.0:
		_bolt_t -= delta
		_bolt.visible = _bolt_t > 0.0 and int(_bolt_t * 30.0) % 3 != 0
		_flash_light.light_energy = maxf(0.0, _bolt_t) * 20.0
		_flash_light.visible = _bolt_t > 0.0


# ---------------------------------------------------------------- lyn (grafik)

func _build_bolt() -> void:
	_bolt = Node3D.new()
	_bolt.visible = false
	add_child(_bolt)
	var mat := ModelKit.glow(Color("eef3ff"))
	for k in 10:
		var seg := MeshInstance3D.new()
		seg.mesh = ModelKit.box(1.4, 1.0, 1.4)
		seg.material_override = mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bolt.add_child(seg)
		_bolt_segs.append(seg)
	_flash_light = OmniLight3D.new()
	_flash_light.omni_range = 450.0
	_flash_light.light_color = Color("cfe0ff")
	_flash_light.visible = false
	add_child(_flash_light)


## Et takket lyn fra skyerne ned til jorden.
func _show_bolt(ground: Vector3, up: Vector3) -> void:
	var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	var side2 := up.cross(side)
	var top := ground + up * 320.0
	var prev := top
	var n := _bolt_segs.size()
	for k in n:
		var t := float(k + 1) / n
		var next := top.lerp(ground, t)
		if k < n - 1:
			next += side * randf_range(-14, 14) + side2 * randf_range(-14, 14)
		var seg := _bolt_segs[k]
		var mid := (prev + next) / 2.0
		var dir := next - prev
		var b := Basis(Quaternion(Vector3.UP, dir.normalized()))
		seg.transform = Transform3D(b * Basis.from_scale(Vector3(1.0, dir.length(), 1.0)), mid)
		prev = next
	_bolt.visible = true
	_bolt_t = 0.35
	_flash_light.position = ground + up * 60.0


# ---------------------------------------------------------------- regn, sand og aske

func _build_streaks() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 1.0, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	box.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = box
	_mm.instance_count = STREAKS
	_mm.visible_instance_count = 0
	_pos.resize(STREAKS)
	for k in STREAKS:
		_pos[k] = Vector3(randf_range(-1, 1) * BOX.x, randf_range(-1, 1) * BOX.y, randf_range(-1, 1) * BOX.z)
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 16384.0
	add_child(_mmi)


## Partikler i en kasse omkring kameraet, der vrides med, når kameraet flytter sig.
func _update_streaks(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var e := effect_at(cam.global_position)
	var k: float = e["k"]
	if k < 0.02:
		_mm.visible_instance_count = 0
		return
	var p: PlanetBody = e["planet"]
	var c := cam.global_position
	var up := (c - p.position).normalized()
	var right := up.cross(Vector3.FORWARD if absf(up.z) < 0.95 else Vector3.RIGHT).normalized()
	var fwd := right.cross(up)
	var frame := Basis(right, up, fwd)
	var vel: Vector3
	var col: Color
	var length := 1.0
	var thick := 1.0
	match e["type"]:
		"lightning":
			vel = -up * 75.0 + right * 6.0
			col = Color(0.8, 0.88, 1.0, 0.7)
			length = 6.0
			thick = 2.2
		"sandstorm":
			vel = wind_at(c) * 6.0 + up * sin(Time.get_ticks_msec() / 300.0) * 3.0
			col = Color(1.0, 0.86, 0.6, 0.7)
			length = 2.0
			thick = 5.5
		_:
			vel = -up * 6.0 + right * 2.0
			col = Color(0.3, 0.26, 0.28, 0.9)
			length = 1.5
			thick = 5.0
	var n := int(STREAKS * k)
	_mm.visible_instance_count = n
	var vdir := vel.normalized() if vel.length() > 0.01 else -up
	var b := Basis(Quaternion(Vector3.UP, vdir)) * Basis.from_scale(Vector3(thick, length, thick))
	var inv := frame.inverse()
	for i in n:
		var wp: Vector3 = _pos[i] + vel * delta
		# Hold partiklen i kassen omkring kameraet (i planetens lokale akser)
		var rel := inv * (wp - c)
		rel.x = wrapf(rel.x, -BOX.x, BOX.x)
		rel.y = wrapf(rel.y, -BOX.y, BOX.y)
		rel.z = wrapf(rel.z, -BOX.z, BOX.z)
		wp = c + frame * rel
		_pos[i] = wp
		_mm.set_instance_transform(i, Transform3D(b, wp))
		_mm.set_instance_color(i, col)
