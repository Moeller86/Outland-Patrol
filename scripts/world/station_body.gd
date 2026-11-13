class_name StationBody
extends Node3D
## En rumstation. Man docker ved at flyve hen til dokken langsomt og trykke L,
## ligesom ved landing på en planet.
##
## To udseender, begge bygget med ModelKit:
##  handelsstation – spindel med vinduesbælter, roterende ring med boligmoduler,
##                   dokring, solpaneler og containerlager (Kepler Station)
##  Concord-base    – Bastion Kepler: dæk i lag, oplyst hangar, kommandotårn med radar,
##                   dokarme og moduler, der dukker op, når gruppen åbner dem.

const K = preload("res://scripts/world/model_kit.gd")
const TURRET_RANGE := 380.0
const TURRET_INTERVAL := 1.1
const TURRET_DAMAGE := 1.5

var data: Dictionary
var id: String
var system_id: String
var display_name: String
var dock_dir: Vector3      ## Fra stationens centrum ud mod dokken
var dock_pos: Vector3      ## Dokkens position (verdenskoordinater)
var is_base := false
## Flyvende base (dreadnought): parkerer ved hvert stop i `stops` og hopper videre
var mobile := false
var stops: Array[Vector3] = []
var stop_idx := 0
var park_time := 150.0
var _park_t := 0.0
var _origin := Vector3.ZERO
signal relocated
const DREAD_HALF := Vector3(72.0, 16.0, 22.0)   ## kollisionskasse (lokalt)
var collide_radius := 24.0
## Concord-basens åbne hangar (lokale koordinater i _body: +Z ud mod dokken)
const HANGAR_Z := 30.0                ## hangarens midte
const HANGAR_FRONT := 46.0            ## den åbne front
const HANGAR_BACK := 14.5
const HANGAR_HALF_W := 21.0
const HANGAR_FLOOR := -7.0
const HANGAR_CEIL := 9.0
const PAD_COUNT := 4

var _ring: Node3D
var _radar: Node3D
var _body: Node3D
var _modules: Dictionary = {}      ## modul-id -> Node3D
var _turret_heads: Array[Node3D] = []
var _turret_tips: Array[Vector3] = []
var _turret_t := 0.0
var _lights: Array[MeshInstance3D] = []


func setup(d: Dictionary, system_origin: Vector3) -> void:
	data = d
	id = d["id"]
	system_id = d["system"]
	display_name = d["name"]
	name = "Station_" + id
	position = d["world_pos"]
	is_base = d.get("base", false)
	mobile = d.get("mobile", false)
	_origin = system_origin
	if mobile:
		for sp in d.get("stops", []):
			stops.append(system_origin + Game.vec(sp))
		park_time = float(d.get("park", 150.0))
	collide_radius = 30.0 if is_base else (18.0 if d.get("plot", false) else 24.0)
	dock_dir = (system_origin - position).normalized()
	if dock_dir.length() < 0.5:
		dock_dir = Vector3.BACK
	dock_pos = position + dock_dir * 32.0
	if mobile:
		collide_radius = 0.0
		dock_pos = position + dock_dir * (DREAD_HALF.z + 14.0)
	if is_base:
		# Hangarens midte (man flyver ind i hangaren for at lande på sin plads)
		dock_pos = position + dock_dir * HANGAR_Z


func _ready() -> void:
	# Lokal +Z peger ud mod dokken.
	_body = Node3D.new()
	_body.name = "Body"
	_body.basis = Basis.looking_at(-dock_dir, Vector3.UP if absf(dock_dir.y) < 0.95 else Vector3.RIGHT)
	add_child(_body)
	if mobile:
		_build_dreadnought()
		Game.player_joined.connect(func(id: int) -> void:
			if multiplayer.is_server() and id != multiplayer.get_unique_id():
				_cl_jump.rpc_id(id, stop_idx, false))
		Net.started.connect(func() -> void:
			_park_t = 0.0
			_relocate(0, false))
	elif is_base:
		_build_base()
		Game.world_changed.connect(_update_modules)
		_update_modules()
	elif data.get("plot", false):
		_build_plot_frame()
	else:
		_build_trade_station()
	# Saml de faste dele i få masker (færre tegnekald); lys, moduler og drejende dele beholdes
	var keep: Array = []
	keep.append_array(_lights)
	keep.append_array(_turret_heads)
	keep.append_array(_modules.values())
	if _ring:
		keep.append(_ring)
	if _radar:
		keep.append(_radar)
	K.merge(_body, keep)


# ---------------------------------------------------------------- flyvende base

func _mobile_tick(delta: float) -> void:
	if stops.size() < 2:
		return
	_park_t += delta
	if not W.is_server():
		return
	if _park_t >= park_time:
		_park_t = 0.0
		_cl_jump.rpc((stop_idx + 1) % stops.size(), true)


## Sekunder til næste hop (kun værten ved det præcist; klienterne får et skøn).
func time_to_jump() -> float:
	return maxf(0.0, park_time - _park_t)


@rpc("authority", "call_local", "reliable")
func _cl_jump(idx: int, fx: bool) -> void:
	_park_t = 0.0
	_relocate(idx, fx)


func _relocate(idx: int, fx: bool) -> void:
	if stops.is_empty():
		return
	var old := position
	stop_idx = idx % stops.size()
	var pos := stops[stop_idx]
	var to_origin := (_origin - pos).normalized()
	if to_origin.length() < 0.5:
		to_origin = Vector3.BACK
	position = pos
	dock_dir = to_origin
	dock_pos = position + dock_dir * (DREAD_HALF.z + 14.0)
	if _body:
		_body.basis = Basis.looking_at(-dock_dir, Vector3.UP if absf(dock_dir.y) < 0.95 else Vector3.RIGHT)
	reset_physics_interpolation()
	if Game.locations.has(id):
		Game.locations[id]["world_pos"] = position
	if fx and W.fx:
		for p in [old, position]:
			for k in 6:
				W.fx.explosion(p + Vector3(randf_range(-60, 60), randf_range(-15, 15), randf_range(-20, 20)), false)
			W.fx.burst(p, 60, 120.0, [Color("9fe2ff"), Color.WHITE, Color("4d8bff")], 3.0, 1.4)
		Sfx.play_at("hop", position, 4.0)
	# Skibe, der ligger i hangaren, følger med
	var me := W.local_ship
	if me and is_instance_valid(me) and me.state == Ship.State.LANDED and me.docked_at == id:
		me.dock_at(id, me.slot)
	if fx:
		Game.toast.emit("%s er hoppet videre i systemet" % display_name)
	relocated.emit()


## Kollision med dreadnoughten (orienteret kasse). Returnerer ny position eller INF.
func collide_mobile(p: Vector3, r := 2.5) -> Vector3:
	var xf := _body_xf()
	var l := xf.affine_inverse() * p
	var h := DREAD_HALF + Vector3.ONE * r
	if absf(l.x) >= h.x or absf(l.y) >= h.y or absf(l.z) >= h.z:
		return Vector3.INF
	var px := h.x - absf(l.x)
	var py := h.y - absf(l.y)
	var pz := h.z - absf(l.z)
	if px <= py and px <= pz:
		l.x = signf(l.x) * (h.x + 0.2)
	elif py <= pz:
		l.y = signf(l.y) * (h.y + 0.2)
	else:
		l.z = signf(l.z) * (h.z + 0.2)
	return xf * l


## CNS Vogteren: lang, kantet slagskibsskrog (langs lokal X), med en stor sidehangar
## mod dokken (+Z), kanontårne, bro og seks store motorer agter.
func _build_dreadnought() -> void:
	var b := _body
	var hull := K.hull(Color("8a90b8"), K.TEX_PLATING, 0.12)
	var white := K.hull(C_WHITE, K.TEX_PANEL, 0.12)
	var blue := K.hull(C_BLUE, K.TEX_PANEL, 0.15)
	var dark := K.hull(Color("3a3f5a"), K.TEX_PLATING, 0.15)
	var darker := K.flat(C_DARK)
	var gold := K.hull(C_GOLD, K.TEX_PLATING, 0.2)
	var win := K.windows(0.2)
	var L := DREAD_HALF.x
	# Skrog: hovedblok, næsekile (mod -X) og agterblok
	K.add(b, K.box(L * 1.5, 22.0, 38.0), hull, Vector3(-L * 0.1, 0, 0))
	K.add(b, K.wedge(38.0, L * 0.6, 22.0), white, Vector3(-L * 0.85 - L * 0.3 + 6.0, 0, 0), Vector3(0, 0, PI / 2))
	K.add(b, K.box(L * 0.45, 28.0, 42.0), dark, Vector3(L * 0.75, 0, 0))
	K.add(b, K.box(L * 1.5, 3.0, 38.4), win, Vector3(-L * 0.1, 4.0, 0))
	K.add(b, K.box(L * 1.6, 2.0, 40.0), blue, Vector3(-L * 0.1, -9.0, 0))
	K.add(b, K.box(L * 1.0, 1.4, 38.6), K.stripes(0.2), Vector3(-L * 0.2, -11.4, 0))
	# Overbygning og bro
	K.add(b, K.box(40.0, 10.0, 20.0), white, Vector3(L * 0.35, 16.0, 0))
	K.add(b, K.box(20.0, 8.0, 16.0), blue, Vector3(L * 0.45, 25.0, 0))
	K.add(b, K.box(20.4, 2.0, 16.4), K.glow(Color("4dffe1")), Vector3(L * 0.45, 26.5, 0))
	K.add(b, K.cyl(0.6, 0.9, 18.0, 6), K.flat(Color("d9d2ff")), Vector3(L * 0.5, 38.0, 4.0))
	_lights.append(K.add(b, K.box(2.0, 2.0, 2.0), K.glow(Color("ff3b3b")), Vector3(L * 0.5, 47.5, 4.0)))
	_radar = Node3D.new()
	_radar.position = Vector3(L * 0.3, 30.0, -4.0)
	b.add_child(_radar)
	K.add(_radar, K.cyl(5.0, 1.6, 1.0, 12), K.flat(Color("d9d2ff")), Vector3(0, 2.0, 0), Vector3(0.9, 0, 0))
	# Kanontårne på ryggen
	for k in 5:
		var x := -L * 0.9 + k * 16.0
		K.add(b, K.cyl(4.0, 4.6, 2.4, 10), dark, Vector3(x, 12.2, 0))
		for s in [-1.0, 1.0]:
			K.add(b, K.cyl(0.5, 0.6, 9.0, 6), darker, Vector3(x - 5.0, 13.0, s * 1.4), Vector3(0, 0, PI / 2))
	K.greebles(b, 61, Vector3(-L * 0.1, 11.2, 0), Vector2(L * 1.3, 30.0), Vector3.UP, 26, dark, 2.4)
	K.greebles(b, 62, Vector3(-L * 0.1, -12.2, 0), Vector2(L * 1.3, 30.0), Vector3.DOWN, 18, dark, 2.6)
	# Sidehangar mod dokken (+Z): mørk åbning, oplyst gulv og blinkende indflyvningslys
	K.add(b, K.box(46.0, 16.0, 1.0), K.stripes(0.3), Vector3(-6.0, -1.0, 19.3))
	K.add(b, K.box(42.0, 13.0, 1.4), darker, Vector3(-6.0, -1.5, 19.4))
	K.add(b, K.box(40.0, 0.6, 10.0), K.hull(Color("9fb4e8"), K.TEX_PLATING, 0.4), Vector3(-6.0, -7.5, 15.0))
	for i in 8:
		_lights.append(K.add(b, K.box(1.0, 0.5, 1.0), K.glow(Color("4dffe1")), Vector3(-24.0 + i * 5.2, -7.0, 20.4)))
	for k in 6:
		_lights.append(K.add(b, K.box(1.4, 1.4, 1.4), K.glow(Color("4d8bff")), Vector3(-6.0, -8.0, 24.0 + k * 4.0)))
	# Concord-emblem på siden
	K.add(b, K.torus(7.0, 1.6, 16, 4), gold, Vector3(-L * 0.75, 2.0, 19.2), Vector3(PI / 2, 0, 0))
	K.add(b, K.box(1.8, 9.0, 0.8), gold, Vector3(-L * 0.75, 2.0, 19.4))
	# Navn på skroget
	for s in [-1.0, 1.0]:
		var lbl := Label3D.new()
		lbl.text = "CNS VOGTEREN"
		lbl.font_size = 220
		lbl.pixel_size = 0.025
		lbl.modulate = Color("e8e6ff")
		lbl.outline_size = 10
		lbl.position = Vector3(L * 0.5, -3.0, s * 19.4)
		lbl.rotation = Vector3(0, 0 if s > 0 else PI, 0)
		b.add_child(lbl)
	# Motorer agter (+X)
	for y in [-7.0, 7.0]:
		for z in [-13.0, 0.0, 13.0]:
			K.add(b, K.cyl(5.0, 5.6, 6.0, 10), darker, Vector3(L + 2.0, y, z), Vector3(0, 0, -PI / 2))
			K.add(b, K.cyl(4.4, 4.4, 0.4, 10), K.glow(Color("4dd0ff")), Vector3(L + 5.2, y, z), Vector3(0, 0, -PI / 2))
	# Navigationslys langs skroget
	for k in 10:
		_lights.append(K.add(b, K.box(1.0, 1.0, 1.0), K.glow(Color("ffd23f")), Vector3(-L + k * 15.0, 11.5, 19.0)))
		_lights.append(K.add(b, K.box(1.0, 1.0, 1.0), K.glow(Color("ffd23f")), Vector3(-L + k * 15.0, 11.5, -19.0)))


func _process(delta: float) -> void:
	if _ring:
		_ring.rotate_object_local(Vector3.BACK, delta * 0.12)
	if _radar:
		_radar.rotate_object_local(Vector3.UP, delta * 0.8)
	if not _lights.is_empty():
		var on := (Time.get_ticks_msec() / 500) % 2 == 0
		for i in _lights.size():
			_lights[i].visible = on == (i % 2 == 0)


func _physics_process(delta: float) -> void:
	if mobile:
		_mobile_tick(delta)
		return
	if not is_base or not Game.module_unlocked("turrets") or W.pirates == null:
		return
	# Tårnhovederne drejer mod nærmeste pirat (på alle maskiner, kun visuelt).
	var nearest := W.pirates.nearest_visible(global_position, TURRET_RANGE)
	if nearest != Vector3.INF:
		for h in _turret_heads:
			var dir := nearest - h.global_position
			if dir.length() > 1.0:
				h.global_basis = h.global_basis.slerp(Basis.looking_at(dir.normalized(), Vector3.UP), minf(1.0, delta * 4.0))
	if not W.is_server():
		return
	_turret_t -= delta
	if _turret_t > 0.0:
		return
	_turret_t = TURRET_INTERVAL
	var target := W.pirates.server_nearest(global_position, TURRET_RANGE)
	if target < 0:
		return
	var tip: Vector3 = _turret_tips.pick_random()
	var tpos: Vector3 = W.pirates.position_of(target)
	W.pirates.server_damage(target, TURRET_DAMAGE)
	_cl_turret_shot.rpc(tip, tpos)


@rpc("authority", "call_local", "unreliable")
func _cl_turret_shot(from: Vector3, to: Vector3) -> void:
	W.bolts.fire(from, (to - from).normalized(), 320.0, Color("4d8bff"), Bolts.Kind.REMOTE)
	Sfx.play_at("taarn", from, -3.0)


# ---------------------------------------------------------------- handelsstation

func _build_trade_station() -> void:
	var b := _body
	var white := K.hull(Color("d9d2ff"))
	var violet := K.hull(Color("7b4dff"))
	var metal := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4)
	var cyan := K.hull(Color("2ec4d6"), K.TEX_PLATING, 0.4)
	var along := Vector3(PI / 2, 0, 0)   # cylinder langs Z, toppen mod +Z (dokken)
	# Spindel med vinduesbælter
	K.add(b, K.cyl(6, 8, 46, 12), white, Vector3.ZERO, along)
	for z in [-8.0, 4.0, 14.0]:
		K.add(b, K.cyl(7.6 - z * 0.04, 7.6 - z * 0.04, 2.0, 12), K.windows(0.6), Vector3(0, 0, z), along)
	K.add(b, K.cyl(12, 12, 10, 12), violet, Vector3(0, 0, -14), along)
	K.add(b, K.cyl(12.2, 12.2, 1.5, 12), K.windows(0.6), Vector3(0, 0, -14), along)
	K.add(b, K.cyl(4, 9, 6, 12), metal, Vector3(0, 0, -25), along)
	K.greebles(b, 5, Vector3(0, 12, -14), Vector2(10, 8), Vector3.UP, 6, metal, 1.2)
	# Dokring med striber og lys
	K.add(b, K.torus(8.0, 2.6, 16, 6), K.stripes(0.5), Vector3(0, 0, 25), along)
	for i in 8:
		var a := i / 8.0 * TAU
		_lights.append(K.add(b, K.box(1, 1, 1), K.glow(Color("4dffe1")), Vector3(cos(a) * 9.6, sin(a) * 9.6, 26.2)))
	# Roterende ring med boligmoduler og eger
	_ring = Node3D.new()
	b.add_child(_ring)
	K.add(_ring, K.torus(30, 4.5, 24, 6), K.hull(Color("ff7a59"), K.TEX_PLATING, 0.4), Vector3(0, 0, 4), along)
	for i in 8:
		var a := i / 8.0 * TAU
		var p := Vector3(cos(a) * 30, sin(a) * 30, 4)
		var hab := K.add(_ring, K.box(9, 6, 7), white, p)
		hab.rotation = Vector3(0, 0, a)
		var win := K.add(_ring, K.box(9.2, 1.8, 7.2), K.windows(0.7), p)
		win.rotation = Vector3(0, 0, a)
	for i in 4:
		K.add(_ring, K.box(1.6, 60, 1.6), metal, Vector3(0, 0, 4), Vector3(0, 0, i * PI / 4))
	# Solpaneler og containerlager
	for s in [-1.0, 1.0]:
		K.add(b, K.box(14, 1.2, 1.2), metal, Vector3(s * 13, 0, -18))
		K.add(b, K.box(22, 0.5, 12), cyan, Vector3(s * 31, 0, -18))
		for k in 3:
			K.add(b, K.box(22.2, 0.6, 0.4), K.flat(Color("1a5f8a")), Vector3(s * 31, 0, -22 + k * 4))
	var cols := [Color("ff9e3d"), Color("4dd0ff"), Color("6bdc4f"), Color("ffd23f")]
	for k in 6:
		K.add(b, K.box(4, 4, 6), K.hull(cols[k % 4], K.TEX_PLATING, 0.6), Vector3(-6 + (k % 3) * 6, -10 - (k / 3) * 4.4, -6))
	K.add(b, K.box(20, 1, 8), metal, Vector3(0, -7.6, -6))
	K.add(b, K.cyl(0.2, 0.3, 14, 4), K.flat(Color("d9d2ff")), Vector3(4, 10, -26))
	_lights.append(K.add(b, K.box(1.2, 1.2, 1.2), K.glow(Color("ff3b3b")), Vector3(4, 17.4, -26)))


# ---------------------------------------------------------------- byggegrund i rummet

## En tom byggegrund i rummet: fire bøjer med lys og en lille dokring. Selve basen
## bygges af PlayerBases, når gruppen har købt grunden.
func _build_plot_frame() -> void:
	var b := _body
	var yellow := K.hull(C_GOLD, K.TEX_PLATING, 0.5)
	K.add(b, K.torus(6.0, 1.6, 14, 4), K.stripes(0.5), Vector3(0, 0, 22), Vector3(PI / 2, 0, 0))
	for i in 4:
		var a := i / 4.0 * TAU + PI / 4
		var p := Vector3(cos(a) * 30.0, sin(a) * 30.0, 0)
		K.add(b, K.cyl(1.2, 1.2, 4.0, 8), yellow, p, Vector3(PI / 2, 0, 0))
		_lights.append(K.add(b, K.box(1.0, 1.0, 1.0), K.glow(Color("6bdc4f")), p + Vector3(0, 0, 2.6)))
	K.add(b, K.box(0.6, 0.6, 22.0), K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4), Vector3(0, 0, 11))


# ---------------------------------------------------------------- Concord-base

const C_WHITE := Color("e6ecff")
const C_BLUE := Color("2e6bd6")
const C_DARK := Color("1a1028")
const C_GOLD := Color("ffd23f")


## Hangarpladsernes placering (lokalt i _body). Plads 0–3.
static func pad_local(slot: int) -> Vector3:
	var i := clampi(slot, 0, PAD_COUNT - 1)
	return Vector3(-13.5 + i * 9.0, HANGAR_FLOOR + 0.6, HANGAR_Z - 2.0)


## Verdensposition og retning for en hangarplads.
func pad_world(slot: int) -> Vector3:
	return _body_xf() * pad_local(slot)


func _body_xf() -> Transform3D:
	return Transform3D(Basis.looking_at(-dock_dir, Vector3.UP if absf(dock_dir.y) < 0.95 else Vector3.RIGHT), position)


## Concord-basen: kollision med kasser, så man kan flyve ind i den åbne hangar.
## Returnerer en ny position (skubbet ud) eller INF.
func collide_point(p: Vector3, r := 2.5) -> Vector3:
	var xf := _body_xf()
	var l := xf.affine_inverse() * p
	# Inde i hangaren: gulv, loft og vægge
	if l.z > HANGAR_BACK and l.z < HANGAR_FRONT + 1.0 and absf(l.x) < HANGAR_HALF_W + 2.0 and l.y > HANGAR_FLOOR - 3.0 and l.y < HANGAR_CEIL + 3.0:
		var inside := absf(l.x) < HANGAR_HALF_W - r and l.y > HANGAR_FLOOR + r and l.y < HANGAR_CEIL - r and l.z < HANGAR_FRONT + 1.0
		if inside:
			return Vector3.INF
		# I væggen/gulvet/loftet: skub tilbage ind i hangaren (eller ud foran)
		var q := l
		if l.z > HANGAR_FRONT - 1.0 and (absf(l.x) >= HANGAR_HALF_W - r or l.y <= HANGAR_FLOOR + r or l.y >= HANGAR_CEIL - r):
			q.z = HANGAR_FRONT + r + 1.0     # ramte kanten af åbningen udefra
		else:
			q.x = clampf(l.x, -HANGAR_HALF_W + r + 0.2, HANGAR_HALF_W - r - 0.2)
			q.y = clampf(l.y, HANGAR_FLOOR + r + 0.2, HANGAR_CEIL - r - 0.2)
			q.z = maxf(l.z, HANGAR_BACK + r + 0.2)
		return xf * q
	# Selve basen (kasse) og kommandotårnet
	var boxes := [[Vector3(0, -1, -6), Vector3(20, 11, 21)], [Vector3(0, 18, -18), Vector3(7.5, 10, 7.5)],
		[Vector3(0, -1, 4), Vector3(36, 3, 4)], [Vector3(0, 0, -20), Vector3(47, 2, 8)]]
	for bx in boxes:
		var c: Vector3 = bx[0]
		var h: Vector3 = (bx[1] as Vector3) + Vector3.ONE * r
		var d := l - c
		if absf(d.x) < h.x and absf(d.y) < h.y and absf(d.z) < h.z:
			# Skub ud langs den akse, hvor vi er tættest på kanten
			var px := h.x - absf(d.x)
			var py := h.y - absf(d.y)
			var pz := h.z - absf(d.z)
			var q := l
			if px <= py and px <= pz:
				q.x = c.x + signf(d.x) * (h.x + 0.2)
			elif py <= pz:
				q.y = c.y + signf(d.y) * (h.y + 0.2)
			else:
				q.z = c.z + signf(d.z) * (h.z + 0.2)
			return xf * q
	return Vector3.INF


## Den åbne hangar foran basen med fire nummererede pladser.
func _build_hangar() -> void:
	var b := _body
	var white := K.hull(C_WHITE)
	var blue := K.hull(C_BLUE)
	var metal := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4)
	var floor_m := K.hull(Color("3a3f5a"), K.TEX_PLATING, 0.25)
	var len := HANGAR_FRONT - HANGAR_BACK
	var cz := (HANGAR_FRONT + HANGAR_BACK) / 2.0
	var w := HANGAR_HALF_W * 2.0
	K.add(b, K.box(w + 2.0, 1.4, len), floor_m, Vector3(0, HANGAR_FLOOR - 0.7, cz))
	K.add(b, K.box(w + 2.0, 1.6, len), white, Vector3(0, HANGAR_CEIL + 0.8, cz))
	K.add(b, K.box(w + 2.2, 0.8, len + 0.2), K.windows(0.5), Vector3(0, HANGAR_CEIL + 2.0, cz))
	for s in [-1.0, 1.0]:
		K.add(b, K.box(1.6, HANGAR_CEIL - HANGAR_FLOOR, len), blue, Vector3(s * (HANGAR_HALF_W + 0.8), (HANGAR_CEIL + HANGAR_FLOOR) / 2.0, cz))
		# Bjælker og lysstriber langs væggene
		for k in 5:
			var z := HANGAR_BACK + 2.0 + k * (len - 4.0) / 4.0
			K.add(b, K.box(0.8, HANGAR_CEIL - HANGAR_FLOOR, 1.0), metal, Vector3(s * (HANGAR_HALF_W - 0.2), (HANGAR_CEIL + HANGAR_FLOOR) / 2.0, z))
		K.add(b, K.box(0.3, 0.4, len - 2.0), K.glow(Color("4dffe1")), Vector3(s * (HANGAR_HALF_W - 0.7), HANGAR_CEIL - 1.2, cz))
		# Front: kraftig ramme med advarselsstriber
		K.add(b, K.box(2.4, HANGAR_CEIL - HANGAR_FLOOR + 3.0, 2.4), K.stripes(0.45), Vector3(s * (HANGAR_HALF_W + 1.2), (HANGAR_CEIL + HANGAR_FLOOR) / 2.0, HANGAR_FRONT))
		_lights.append(K.add(b, K.box(0.8, 0.8, 0.8), K.glow(Color("ff3b3b") if s < 0 else Color("4dff6a")), Vector3(s * (HANGAR_HALF_W + 1.2), HANGAR_CEIL + 2.4, HANGAR_FRONT + 1.3)))
	K.add(b, K.box(w + 5.0, 2.4, 2.4), K.stripes(0.45), Vector3(0, HANGAR_CEIL + 1.2, HANGAR_FRONT))
	K.add(b, K.box(w + 5.0, 1.2, 2.6), K.stripes(0.45), Vector3(0, HANGAR_FLOOR - 0.6, HANGAR_FRONT))
	# Loftslamper
	for k in 4:
		for x in [-10.0, 0.0, 10.0]:
			K.add(b, K.box(3.0, 0.3, 1.0), K.glow(Color("fff3b0")), Vector3(x, HANGAR_CEIL - 0.1, HANGAR_BACK + 4.0 + k * 8.0))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("fff3d0")
	lamp.light_energy = 2.0
	lamp.omni_range = 40.0
	lamp.position = Vector3(0, HANGAR_CEIL - 2.0, HANGAR_Z)
	b.add_child(lamp)
	# Kraftfelt i åbningen (kun pynt)
	var field := MeshInstance3D.new()
	field.mesh = K.box(w, HANGAR_CEIL - HANGAR_FLOOR, 0.05)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.albedo_color = Color(0.3, 0.8, 1.0, 0.08)
	field.material_override = fm
	field.position = Vector3(0, (HANGAR_CEIL + HANGAR_FLOOR) / 2.0, HANGAR_FRONT - 0.5)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(field)
	# Pladser 1–4 med farvet ring, nummer og indflyvningslys
	var pad_cols := [Color("ff4f8b"), Color("4dd0ff"), Color("6bdc4f"), Color("ffd23f")]
	for i in PAD_COUNT:
		var p := pad_local(i)
		K.add(b, K.cyl(3.6, 3.6, 0.2, 16), K.hull(Color("2a2e48"), K.TEX_PLATING, 0.4), p + Vector3(0, -0.55, 0))
		K.add(b, K.torus(3.4, 0.25, 20, 4), K.glow(pad_cols[i]), p + Vector3(0, -0.4, 0))
		for k in 3:
			_lights.append(K.add(b, K.box(0.6, 0.2, 0.6), K.glow(pad_cols[i]), p + Vector3(0, -0.45, 5.0 + k * 2.4)))
		var num := Label3D.new()
		num.text = str(i + 1)
		num.font_size = 160
		num.pixel_size = 0.02
		num.modulate = pad_cols[i]
		num.outline_size = 12
		num.rotation = Vector3(-PI / 2, 0, 0)
		num.position = p + Vector3(0, -0.35, -4.6)
		b.add_child(num)
		var sign := Label3D.new()
		sign.text = "PLADS %d" % (i + 1)
		sign.font_size = 72
		sign.pixel_size = 0.02
		sign.modulate = pad_cols[i]
		sign.outline_size = 8
		sign.position = Vector3(p.x, HANGAR_CEIL - 2.6, HANGAR_BACK + 0.9)
		b.add_child(sign)
	# Kasser, slanger og et værksted langs bagvæggen
	var crate_cols := [Color("ff9e3d"), Color("4dd0ff"), Color("c77dff")]
	for k in 6:
		var x := -18.0 + k * 7.2
		K.add(b, K.box(2.2, 2.0, 2.2), K.hull(crate_cols[k % 3], K.TEX_PLATING, 0.6), Vector3(x, HANGAR_FLOOR + 1.0, HANGAR_BACK + 2.0))
	K.add(b, K.box(6.0, 4.0, 2.0), metal, Vector3(-17.0, HANGAR_FLOOR + 2.0, HANGAR_Z + 6.0))
	K.add(b, K.box(5.0, 1.0, 0.2), K.glow(Color("4dff6a")), Vector3(-17.0, HANGAR_FLOOR + 3.0, HANGAR_Z + 4.95))


func _build_base() -> void:
	var b := _body
	var white := K.hull(C_WHITE)
	var blue := K.hull(C_BLUE)
	var navy := K.hull(Color("1f3f8a"), K.TEX_PLATING, 0.35)
	var metal := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4)
	var gold := K.hull(C_GOLD, K.TEX_PLATING, 0.5)
	var dark := K.flat(C_DARK)
	var win := K.windows(0.5)

	# Dæk i lag: blå underdæk, hvidt hoveddæk med vinduesbælte, øvre dæk
	K.add(b, K.box(38, 5, 44), navy, Vector3(0, -8, -6))
	K.add(b, K.box(34, 10, 40), white, Vector3(0, -1, -6))
	K.add(b, K.box(34.2, 2.2, 40.2), win, Vector3(0, 1.4, -6))
	K.add(b, K.box(36, 1.2, 42), blue, Vector3(0, 4.6, -6))
	K.add(b, K.box(24, 4, 30), white, Vector3(0, 7, -10))
	K.add(b, K.box(24.2, 1.4, 30.2), win, Vector3(0, 7.4, -10))
	K.add(b, K.wedge(36, 3, 6, 0.0), white, Vector3(0, -1, -27.5), Vector3(PI / 2, 0, 0))
	K.greebles(b, 41, Vector3(0, 9, -10), Vector2(20, 26), Vector3.UP, 14, metal, 1.4)
	K.greebles(b, 42, Vector3(0, -10.5, -6), Vector2(30, 36), Vector3.DOWN, 10, metal, 1.6)

	_build_hangar()
	# Hangar i fronten (+Z): ramme med striber, mørk bugt, oplyst gulv og porte
	K.add(b, K.box(22, 12, 1.0), K.stripes(0.45), Vector3(0, -1.5, 14.3))
	K.add(b, K.box(19, 9.5, 1.4), dark, Vector3(0, -1.6, 14.4))
	K.add(b, K.box(17, 0.4, 8), K.hull(Color("9fb4e8"), K.TEX_PLATING, 0.6), Vector3(0, -6.0, 10.5))
	for i in 6:
		_lights.append(K.add(b, K.box(0.6, 0.3, 0.6), K.glow(Color("4dffe1")), Vector3(-7.5 + i * 3.0, -5.7, 14.6)))
	for s in [-1.0, 1.0]:
		K.add(b, K.box(1.4, 12, 3), blue, Vector3(s * 11.6, -1.5, 14))
		K.add(b, K.box(0.4, 0.4, 0.4), K.glow(Color("ff3b3b") if s < 0 else Color("4dff6a")), Vector3(s * 11.6, 4.8, 15.6))
	K.add(b, K.box(24, 1.6, 3.4), gold, Vector3(0, 5.3, 14))

	# Kommandotårn med vindueskrans, skrå top, radar og antenner
	K.add(b, K.box(11, 12, 11), blue, Vector3(0, 15, -18))
	K.add(b, K.box(13, 3, 13), white, Vector3(0, 22, -18))
	K.add(b, K.box(13.2, 1.6, 13.2), K.glow(Color("4dffe1")), Vector3(0, 22.2, -18))
	K.add(b, K.wedge(13, 3, 13), blue, Vector3(0, 25, -18))
	_radar = Node3D.new()
	_radar.position = Vector3(-4, 27, -18)
	b.add_child(_radar)
	K.add(_radar, K.cyl(0.4, 0.6, 3, 6), metal, Vector3(0, 1.5, 0))
	K.add(_radar, K.cyl(3.0, 1.0, 0.6, 10), K.flat(Color("d9d2ff")), Vector3(0, 3.6, 0.6), Vector3(0.9, 0, 0))
	K.add(b, K.cyl(0.25, 0.4, 14, 4), K.flat(Color("d9d2ff")), Vector3(3.5, 31, -20))
	_lights.append(K.add(b, K.box(1.2, 1.2, 1.2), K.glow(Color("ff3b3b")), Vector3(3.5, 38.4, -20)))
	K.add(b, K.cyl(0.15, 0.25, 8, 4), K.flat(Color("d9d2ff")), Vector3(1, 29, -15))
	# Concord-emblem
	K.add(b, K.torus(4.2, 1.2, 14, 4), gold, Vector3(0, 15, -12.4), Vector3(PI / 2, 0, 0))
	K.add(b, K.box(1.2, 5.4, 0.6), gold, Vector3(0, 15, -12.2))

	# Dokarme med pods og solpaneler
	for s in [-1.0, 1.0]:
		K.add(b, K.box(14, 3, 3), metal, Vector3(s * 24, -1, 4))
		K.add(b, K.cyl(3, 3, 6, 10), white, Vector3(s * 32, -1, 4), Vector3(PI / 2, 0, 0))
		K.add(b, K.cyl(3.1, 3.1, 1.6, 10), win, Vector3(s * 32, -1, 4), Vector3(PI / 2, 0, 0))
		K.add(b, K.torus(2.6, 0.8, 10, 4), K.stripes(0.6), Vector3(s * 32, -1, 7.2), Vector3(PI / 2, 0, 0))
		_lights.append(K.add(b, K.box(0.6, 0.6, 0.6), K.glow(Color("ffd23f")), Vector3(s * 35.4, -1, 4)))
		K.add(b, K.box(10, 1, 2), metal, Vector3(s * 22, 0, -20))
		K.add(b, K.box(20, 0.5, 14), K.hull(Color("2ec4d6"), K.TEX_PLATING, 0.35), Vector3(s * 36, 0, -20))
		for k in 4:
			K.add(b, K.box(20.2, 0.6, 0.35), K.flat(Color("1a5f8a")), Vector3(s * 36, 0, -26 + k * 4))

	# --- Moduler (skjules, til de er åbnet)
	var armory := _module("armory")
	for s in [-1.0, 1.0]:
		K.add(armory, K.box(7, 7, 14), K.hull(Color("ff7a59"), K.TEX_PANEL, 0.4), Vector3(s * 21, -5, -4))
		K.add(armory, K.box(7.2, 1.2, 14.2), K.stripes(0.5), Vector3(s * 21, -1.4, -4))
		for k in 4:
			K.add(armory, K.cyl(0.5, 0.5, 4, 6), metal, Vector3(s * 24.8, -5, -9 + k * 3.4), Vector3(PI / 2, 0, 0))
			K.add(armory, K.wedge(1.0, 1.2, 1.0), K.hull(Color("ff3b3b"), K.TEX_PLATING, 0.6), Vector3(s * 24.8, -5, -11.4 + k * 3.4), Vector3(-PI / 2, 0, 0))

	var shield := _module("shield_gen")
	K.add(shield, K.cyl(3, 4.5, 4, 10), white, Vector3(6, 11.5, 2))
	K.add(shield, K.torus(3.6, 0.8, 12, 4), K.glow(Color("4dffe1")), Vector3(6, 13.8, 2))
	var core := K.add(shield, K.sphere(2.4, 10, 6), K.glow(Color("9ff2ff")), Vector3(6, 15.4, 2))
	core.scale = Vector3(1, 0.7, 1)
	for k in 3:
		var a := k / 3.0 * TAU
		K.add(shield, K.cyl(0.25, 0.25, 6, 4), metal, Vector3(6 + cos(a) * 3.6, 16, 2 + sin(a) * 3.6), Vector3(0, 0, 0))
	var bubble := MeshInstance3D.new()
	bubble.mesh = K.sphere(48.0, 24, 12)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(0.3, 0.9, 1.0, 0.06)
	bubble.material_override = bm
	bubble.position = Vector3(0, 2, -6)
	shield.add_child(bubble)

	var cargo := _module("cargo_bay")
	K.add(cargo, K.box(34, 1.2, 12), metal, Vector3(0, -11.2, -16))
	var cols := [Color("ff9e3d"), Color("6bdc4f"), Color("4dd0ff"), Color("c77dff")]
	for k in 8:
		K.add(cargo, K.box(6, 5, 7), K.hull(cols[k % 4], K.TEX_PLATING, 0.6), Vector3(-12.6 + (k % 4) * 8.4, -14.4 - (k / 4) * 5.2, -16))
	K.add(cargo, K.box(1.2, 14, 1.2), gold, Vector3(15.5, -15, -16))
	K.add(cargo, K.box(1.2, 1.2, 12), gold, Vector3(15.5, -8.6, -16))

	var turrets := _module("turrets")
	for c: Vector3 in [Vector3(-15, 9.6, 10), Vector3(15, 9.6, 10), Vector3(-15, 9.6, -24), Vector3(15, 9.6, -24)]:
		K.add(turrets, K.cyl(2.0, 2.6, 1.6, 10), metal, c)
		var head := Node3D.new()
		head.position = c + Vector3(0, 1.8, 0)
		turrets.add_child(head)
		K.add(head, K.box(3.0, 1.8, 3.0), blue, Vector3.ZERO)
		K.add(head, K.wedge(3.0, 0.9, 3.0), white, Vector3(0, 1.35, 0))
		for s in [-0.6, 0.6]:
			K.add(head, K.cyl(0.22, 0.28, 3.6, 6), K.flat(Color("3a3f5a")), Vector3(s, 0.1, -3.0), Vector3(-PI / 2, 0, 0))
		_turret_heads.append(head)
		_turret_tips.append(_body.transform * (c + Vector3(0, 2, -5)) + position)

	var yard := _module("shipyard")
	for s in [-1.0, 1.0]:
		K.add(yard, K.box(2, 2, 36), gold, Vector3(s * 13, 0, -46))
		for k in 3:
			K.add(yard, K.box(2, 18, 2), gold, Vector3(s * 13, 8, -32 - k * 14))
	for k in 3:
		K.add(yard, K.box(28, 2, 2), gold, Vector3(0, 17, -32 - k * 14))
	K.add(yard, K.box(5, 3, 16), K.hull(Color("d9d2ff")), Vector3(0, 0, -48))
	K.add(yard, K.wedge(5, 4, 3), K.hull(Color("d9d2ff")), Vector3(0, 0, -58), Vector3(-PI / 2, 0, 0))
	K.add(yard, K.box(14, 0.4, 4), K.hull(Color("ff4f8b"), K.TEX_PLATING, 0.6), Vector3(0, 0, -45))
	for k in 4:
		_lights.append(K.add(yard, K.box(0.8, 0.8, 0.8), K.glow(Color("ffd23f")), Vector3(-12 + k * 8, 18.4, -46)))


func _module(module_id: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Module_" + module_id
	n.visible = false
	_body.add_child(n)
	_modules[module_id] = n
	return n


func _update_modules() -> void:
	for module_id: String in _modules:
		(_modules[module_id] as Node3D).visible = Game.module_unlocked(module_id)
