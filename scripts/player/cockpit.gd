class_name Cockpit
extends Node3D
## Cockpittet i førstepersonsvisning (inspireret af 90'ernes rumsimulatorer).
## Hænger på kameraet (lokal -Z er fremad), så det aldrig ryster i forhold til billedet.
##
## Instrumenterne er små SubViewports i pixelopløsning, der tegnes på skærme i 3D:
##   – to runde scannere: forreste og bageste halvkugle (pirater, patruljer, piloter,
##     stationer og markering)
##   – målskærmen i midten: hologram af det låste mål, der vender som målet, med
##     afstand og skade; uden mål vises ens eget skib
##   – en bjælke foroven med skjold, låse-/missillampe og skrog
##   – gashåndtag/fart til venstre, tre søjler (motor, scanner, flares) til højre
##   – et lille digitalur: missionens nedtælling eller tiden i systemet

const K = preload("res://scripts/world/model_kit.gd")
const D := 0.9            ## Afstand fra øjet til instrumentbrættet
const SCOPE_RANGE := 2500.0
const DASH_SCALE := 0.7     ## Instrumentbrættets størrelse (1 = fylder ca. 40 % af billedet)

const C_BG := Color("0b0918")
const C_AMBER := Color("ff9f1c")
const C_RED := Color("ff3b3b")
const C_GREEN := Color("4dff6a")
const C_CYAN := Color("4dd0ff")
const C_PINK := Color("ff4fd8")
const C_YELLOW := Color("ffd23f")
const C_DIM := Color("3a3459")

var ship_class := ""
var paint := Color("e94f64")
var ship: Ship

var _views: Array[SubViewport] = []
var _painters: Array[Control] = []
var _holo_root: Node3D
var _holo_model: Node3D
var _holo_kind := ""
var _holo_mat: ShaderMaterial
var _blinkers: Array[MeshInstance3D] = []
var _font: Font
var _t := 0.0
var _clock := 0.0


class Painter extends Control:
	var fn: Callable

	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)


func _ready() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DejaVu Sans Mono", "Courier New", "Liberation Mono", "Monospace"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.font_weight = 700
	_font = f
	visibility_changed.connect(_on_visibility)


func _on_visibility() -> void:
	for v in _views:
		v.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


func build(cls: String, col: Color) -> void:
	if cls == ship_class and col == paint and get_child_count() > 0:
		return
	ship_class = cls
	paint = col
	for c in get_children():
		c.queue_free()
	_views.clear()
	_painters.clear()
	_blinkers.clear()
	_holo_model = null
	_holo_kind = ""
	var frame := _mat(Color("3a3656"))
	var frame_hi := _mat(Color("5a5680"))
	var frame2 := _mat(paint.darkened(0.3))
	var dash := _mat(Color("24213a"))
	var panel := _mat(Color("4a4f72"))
	var dark := _mat(Color("15132a"))
	_build_frame(cls, frame, frame_hi, frame2)
	# Instrumentbrættet samles i én knude, der skaleres ned mod billedets bundkant,
	# så der er godt udsyn (DASH_SCALE af den oprindelige størrelse).
	var board := Node3D.new()
	board.name = "Dash"
	var pivot := Vector3(0, -0.66, -D)
	board.transform = Transform3D(Basis().scaled(Vector3.ONE * DASH_SCALE), pivot - pivot * DASH_SCALE + Vector3(0, -0.015, 0))
	add_child(board)

	# ---- Konsollen i midten (trapezformet, hælder lidt bagover)
	var top := -0.21
	var console := Node3D.new()
	console.position = Vector3(0, 0, -D)
	console.rotation.x = -0.12
	board.add_child(console)
	_box_in(console, Vector3(0.84, 0.46, 0.06), Vector3(0, top - 0.21, 0.0), dash)
	_box_in(console, Vector3(0.84, 0.03, 0.08), Vector3(0, top + 0.02, 0.0), frame2)
	for s in [-1.0, 1.0]:
		var side := _box_in(console, Vector3(0.05, 0.5, 0.1), Vector3(s * 0.44, top - 0.2, 0.01), frame_hi)
		side.rotation.z = s * 0.12
	# Bjælken foroven: skjold · lås · skrog
	_screen_in(console, Vector3(0, top - 0.035, 0.035), Vector2(0.74, 0.06), Vector2i(148, 12), _draw_strip)
	# Målskærmen
	var cmd_v := _screen_in(console, Vector3(0, top - 0.21, 0.035), Vector2(0.4, 0.26), Vector2i(120, 78), _draw_cmd, true)
	_make_holo(cmd_v)
	_box_in(console, Vector3(0.44, 0.3, 0.02), Vector3(0, top - 0.21, 0.022), dark)
	# Gashåndtag/fart (venstre) og søjler (højre)
	_screen_in(console, Vector3(-0.31, top - 0.2, 0.035), Vector2(0.12, 0.24), Vector2i(24, 48), _draw_throttle)
	_screen_in(console, Vector3(0.31, top - 0.2, 0.035), Vector2(0.12, 0.24), Vector2i(24, 48), _draw_columns)
	# Digitalur nederst til højre
	_screen_in(console, Vector3(0.3, top - 0.345, 0.035), Vector2(0.14, 0.05), Vector2i(28, 10), _draw_clock)
	_screen_in(console, Vector3(-0.3, top - 0.345, 0.035), Vector2(0.14, 0.05), Vector2i(28, 10), _draw_class)

	# ---- Sidekonsoller med de runde scannere
	for s in [-1.0, 1.0]:
		var sc := Node3D.new()
		sc.position = Vector3(s * 0.66, top - 0.12, -D + 0.06)
		sc.rotation = Vector3(-0.15, -s * 0.38, 0)
		board.add_child(sc)
		_box_in(sc, Vector3(0.36, 0.36, 0.05), Vector3(0, -0.02, -0.02), dash)
		var bez := MeshInstance3D.new()
		bez.mesh = K.torus(0.15, 0.022, 20, 4)
		bez.material_override = frame_hi
		bez.rotation.x = PI / 2
		bez.position = Vector3(0, 0, 0.012)
		sc.add_child(bez)
		_screen_in(sc, Vector3(0, 0, 0.01), Vector2(0.3, 0.3), Vector2i(64, 64),
			_draw_front_scope if s < 0 else _draw_rear_scope)
		# Etiketlampe under scanneren
		_blinkers.append(_box_in(sc, Vector3(0.05, 0.018, 0.01), Vector3(0, -0.17, 0.015), K.glow(C_GREEN if s < 0 else C_AMBER)))

	# ---- Sidevægge med knapper, rør og blinkende lamper
	for s in [-1.0, 1.0]:
		var wall := Node3D.new()
		wall.position = Vector3(s * 1.0, -0.5, -0.55)
		wall.rotation = Vector3(0, -s * 0.9, s * 0.35)
		board.add_child(wall)
		_box_in(wall, Vector3(0.7, 0.4, 0.05), Vector3.ZERO, panel)
		_box_in(wall, Vector3(0.72, 0.03, 0.07), Vector3(0, 0.2, 0.0), frame2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 41 if s < 0 else 77
		var cols := [C_GREEN, C_AMBER, C_RED, C_CYAN, C_YELLOW]
		for row in 3:
			for c in 5:
				var lamp := _box_in(wall, Vector3(0.035, 0.025, 0.02),
					Vector3(-0.22 + c * 0.07, 0.11 - row * 0.06, 0.035), K.glow(cols[rng.randi() % cols.size()]))
				_blinkers.append(lamp)
		for k in 3:
			var knob := MeshInstance3D.new()
			knob.mesh = K.cyl(0.025, 0.03, 0.04, 8)
			knob.material_override = frame_hi
			knob.rotation.x = PI / 2
			knob.position = Vector3(0.18 + k * 0.0, -0.09 - k * 0.0, 0.04) + Vector3(-0.08 * k, 0, 0)
			wall.add_child(knob)
		# Rør langs væggen
		var pipe := MeshInstance3D.new()
		pipe.mesh = K.cyl(0.018, 0.018, 0.75, 6)
		pipe.material_override = frame_hi
		pipe.rotation.z = PI / 2
		pipe.position = Vector3(0, -0.16, 0.04)
		wall.add_child(pipe)
	# Gulv/næse under konsollen
	_box_in(board, Vector3(2.4, 0.08, 0.9), Vector3(0, -0.72, -0.55), dark)

	# Svagt lys i cockpittet, så rammen kan ses, også på skyggesiden af en planet
	var light := OmniLight3D.new()
	light.light_color = Color("9fb4ff")
	light.light_energy = 0.8
	light.omni_range = 3.0
	light.position = Vector3(0, 0.2, -0.3)
	add_child(light)
	_on_visibility()


func _build_frame(cls: String, frame: Material, frame_hi: Material, frame2: Material) -> void:
	match cls:
		"bison":
			# Firkantet fragter-rude med midterstiver og tyk ramme
			_bar(Vector3(-1.08, -0.4, -D), Vector3(-0.98, 0.72, -D), 0.11, frame)
			_bar(Vector3(1.08, -0.4, -D), Vector3(0.98, 0.72, -D), 0.11, frame)
			_bar(Vector3(-1.2, 0.62, -D), Vector3(1.2, 0.62, -D), 0.12, frame2)
			_bar(Vector3(0, 0.62, -D), Vector3(0, 0.3, -D), 0.05, frame)
			_bar(Vector3(-1.2, -0.32, -D), Vector3(-0.92, -0.32, -D), 0.05, frame)
			_bar(Vector3(1.2, -0.32, -D), Vector3(0.92, -0.32, -D), 0.05, frame)
		"albatros":
			# Bred panoramarude med to lodrette stivere
			_bar(Vector3(-1.15, -0.35, -D), Vector3(-1.0, 0.7, -D), 0.09, frame)
			_bar(Vector3(1.15, -0.35, -D), Vector3(1.0, 0.7, -D), 0.09, frame)
			_bar(Vector3(-0.5, -0.36, -D * 1.05), Vector3(-0.46, 0.66, -D * 1.05), 0.03, frame)
			_bar(Vector3(0.5, -0.36, -D * 1.05), Vector3(0.46, 0.66, -D * 1.05), 0.03, frame)
			_bar(Vector3(-1.2, 0.58, -D), Vector3(1.2, 0.58, -D), 0.09, frame2)
		"hveps":
			# Boblekuppel: buede stivere, der mødes over hovedet
			for s in [-1.0, 1.0]:
				var pts := [Vector3(s * 1.1, -0.35, -D), Vector3(s * 0.95, 0.15, -D), Vector3(s * 0.62, 0.5, -D),
					Vector3(s * 0.2, 0.68, -D), Vector3(0, 0.7, -D)]
				for i in pts.size() - 1:
					_bar(pts[i], pts[i + 1], 0.05, frame)
			_bar(Vector3(0, 0.7, -D), Vector3(0, 0.7, 0.2), 0.05, frame2)
		_:
			# Falk: to kraftige skrå søjler, der løber op mod hjørnerne, med paneler på
			for s in [-1.0, 1.0]:
				var a := Vector3(s * 0.6, -0.36, -D)
				var b := Vector3(s * 1.55, 0.72, -D * 0.9)
				_bar(a, b, 0.07, frame)
				_bar(a + Vector3(s * 0.07, -0.04, 0.03), b + Vector3(s * 0.07, -0.04, 0.03), 0.04, frame_hi)
				# Greebles langs søjlen
				for k in 4:
					var p := a.lerp(b, 0.15 + k * 0.2) + Vector3(0, 0, 0.06)
					_box_in(self, Vector3(0.05, 0.03, 0.03), p, frame2 if k % 2 else frame_hi)
				_bar(Vector3(s * 0.62, -0.37, -D), Vector3(s * 0.4, -0.4, -D), 0.05, frame)


# ---------------------------------------------------------------- opdatering

func update_from(s: Ship, delta: float) -> void:
	ship = s
	_t += delta
	_clock += delta
	for i in _blinkers.size():
		_blinkers[i].visible = fmod(_t * (0.5 + float(i % 7) * 0.17) + float(i) * 0.37, 1.0) < 0.72
	for p in _painters:
		p.queue_redraw()
	_update_holo(delta)


# ---------------------------------------------------------------- tegning af skærmene

func _text(c: CanvasItem, pos: Vector2, s: String, col: Color, size := 8) -> void:
	c.draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _segments(c: CanvasItem, r: Rect2, frac: float, n: int, on: Color, rtl := false) -> void:
	var w := r.size.x / n
	for i in n:
		var k := (n - 1 - i) if rtl else i
		var lit := float(i) < frac * n - 0.01
		c.draw_rect(Rect2(r.position.x + k * w + 1, r.position.y, w - 1, r.size.y), on if lit else C_DIM)


func _draw_strip(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), C_BG)
	if ship == null:
		return
	var sh := clampf(ship.shield / maxf(ship.shield_max, 1.0), 0.0, 1.0)
	var hu := clampf(ship.hull / 100.0, 0.0, 1.0)
	_segments(c, Rect2(4, 3, 56, 6), sh, 12, C_CYAN, true)
	_segments(c, Rect2(88, 3, 56, 6), hu, 12, C_GREEN if hu > 0.3 else C_RED)
	# Låse-/missillampe i midten
	var col := C_DIM
	if W.missiles and W.missiles.incoming() > 0:
		col = C_RED if fmod(_t, 0.4) < 0.2 else C_DIM
	elif ship.is_locked():
		col = C_GREEN
	elif ship.lock_target >= 0:
		col = C_YELLOW if fmod(_t, 0.3) < 0.15 else C_DIM
	c.draw_circle(Vector2(74, 6), 4.0, col)
	c.draw_arc(Vector2(74, 6), 5.0, 0.0, TAU, 12, C_DIM, 1.0)
	c.draw_rect(Rect2(64, 5, 3, 2), C_AMBER)
	c.draw_rect(Rect2(81, 5, 3, 2), C_AMBER)


func _draw_throttle(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), C_BG)
	if ship == null:
		return
	var n := 10
	for i in n:
		var y := 36 - i * 3.3
		var lit := float(i) < ship.throttle * n
		c.draw_rect(Rect2(4, y, 8, 2), C_AMBER if lit else C_DIM)
	var sp := clampf(ship.speed / maxf(ship.max_speed() + ship.boost_speed(), 1.0), 0.0, 1.0)
	c.draw_rect(Rect2(14, 38 - sp * 34.0, 6, 2), C_YELLOW if ship.cruise != 2 else C_CYAN)
	_text(c, Vector2(1, 46), "%3d" % mini(999, int(ship.speed)), C_GREEN, 8)


func _draw_columns(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), C_BG)
	if ship == null:
		return
	var thrust := clampf(ship.speed / maxf(ship.max_speed(), 1.0), 0.0, 1.0)
	var scan := 1.0 - (clampf(W.sites.scan_cool / Sites.SCAN_COOLDOWN, 0.0, 1.0) if W.sites else 0.0)
	var flare := 1.0 - (clampf(W.missiles.flare_cool / Missiles.FLARE_COOLDOWN, 0.0, 1.0) if W.missiles else 0.0)
	var vals := [thrust, scan, flare]
	var cols := [C_CYAN if ship.cruise == 2 else C_AMBER, C_GREEN, C_PINK]
	var labels := ["M", "C", "F"]
	for i in 3:
		var x := 2 + i * 7
		var h := 34.0 * float(vals[i])
		c.draw_rect(Rect2(x, 4, 5, 34), C_DIM)
		c.draw_rect(Rect2(x, 38 - h, 5, h), cols[i])
		_text(c, Vector2(x, 47), labels[i], C_DIM.lightened(0.5), 7)


func _draw_clock(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), C_BG)
	var t := _clock
	var col := C_CYAN
	if W.missions and W.missions.active and float(W.missions.client.get("timer", -1.0)) > 0.0:
		t = float(W.missions.client["timer"])
		col = C_RED if t < 30.0 else C_YELLOW
	_text(c, Vector2(1, 9), "%02d:%02d" % [int(t) / 60 % 100, int(t) % 60], col, 8)


func _draw_class(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), C_BG)
	var m := int(Game.wallet.get("missiles", 0))
	if W.bombs and W.bombs.ammo > 0:
		_text(c, Vector2(1, 9), "B:%d" % W.bombs.ammo, C_YELLOW, 8)
	else:
		_text(c, Vector2(1, 9), "M:%d" % m, C_AMBER if m > 0 else C_RED, 8)


func _draw_front_scope(c: Control) -> void:
	_draw_scope(c, true)


func _draw_rear_scope(c: Control) -> void:
	_draw_scope(c, false)


func _draw_scope(c: Control, front: bool) -> void:
	var ctr := c.size / 2.0
	var r := c.size.x / 2.0 - 2.0
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 1))
	c.draw_circle(ctr, r, Color("071a3a"))
	c.draw_arc(ctr, r, 0.0, TAU, 32, Color("2e6bd6"), 1.0)
	c.draw_arc(ctr, r * 0.5, 0.0, TAU, 24, Color("173a7a"), 1.0)
	c.draw_line(ctr - Vector2(r, 0), ctr + Vector2(r, 0), Color("173a7a"))
	c.draw_line(ctr - Vector2(0, r), ctr + Vector2(0, r), Color("173a7a"))
	_text(c, Vector2(3, 9), "F" if front else "B", Color("4d8bff"), 8)
	if ship == null:
		return
	var inv := ship.global_transform.affine_inverse()
	var sys_id := ship.universe.system_at(ship.position)
	var plot := func(world: Vector3, col: Color, size: float, far_ok: bool) -> void:
		var l: Vector3 = inv * world
		var d := l.length()
		if d < 1.0 or (d > SCOPE_RANGE and not far_ok):
			return
		var ahead := -l.z
		if (ahead >= 0.0) != front:
			return
		var off := Vector2(l.x, -l.y)
		var ang := acos(clampf(absf(ahead) / d, 0.0, 1.0))   # 0 = lige for/bag
		var v := off.normalized() * (ang / (PI / 2.0)) * r if off.length() > 0.001 else Vector2.ZERO
		if not front:
			v.x = -v.x
		c.draw_rect(Rect2(ctr + v - Vector2(size, size) / 2.0, Vector2(size, size)), col)
	for st in ship.universe.stations:
		if st.system_id == sys_id:
			plot.call(st.position, Color.WHITE, 3.0, true)
	if not W.waypoint.is_empty() and W.waypoint.get("system", "") == sys_id:
		if fmod(_t, 0.6) < 0.4:
			plot.call(W.waypoint["pos"], C_YELLOW, 3.0, true)
	if W.patrols:
		for p in W.patrols.positions_in(sys_id):
			plot.call(p, C_CYAN, 2.0, false)
	if W.traffic:
		for p in W.traffic.positions_in(sys_id):
			plot.call(p, Color("b8b4d8"), 2.0, false)
	for s in W.active_ships():
		if s != ship:
			plot.call(s.position, C_GREEN, 2.0, false)
	if W.pirates:
		for i in Pirates.POOL:
			if W.pirates.is_active(i) and W.pirates.system_of(i) == sys_id:
				var locked := i == ship.lock_target
				plot.call(W.pirates.position_of(i), C_YELLOW if locked else C_PINK, 3.0 if locked else 2.0, false)


func _draw_cmd(c: Control) -> void:
	# Tegnes oven på hologrammet
	if ship == null:
		return
	c.draw_rect(Rect2(0, 0, c.size.x, 11), Color(0, 0, 0, 0.55))
	c.draw_rect(Rect2(0, c.size.y - 11, c.size.x, 11), Color(0, 0, 0, 0.55))
	var i := ship.lock_target
	if i >= 0 and W.pirates and W.pirates.is_active(i):
		var d := ship.position.distance_to(W.pirates.position_of(i))
		var hp := W.pirates.hp_fraction(i)
		_text(c, Vector2(3, 9), "MÅL: " + W.pirates.display_name(i).to_upper(), C_RED if W.pirates.type_of(i) == "kaptajn" else C_AMBER, 8)
		_text(c, Vector2(c.size.x - 34, 9), "LÅST" if ship.is_locked() else "LÅSER", C_GREEN if ship.is_locked() else C_YELLOW, 8)
		_text(c, Vector2(3, c.size.y - 2), "AFST %.2f km" % (d / 1000.0), C_AMBER, 8)
		var dmg := "OK" if hp > 0.66 else ("SKADET" if hp > 0.33 else "KRITISK")
		_text(c, Vector2(c.size.x - 6 - dmg.length() * 5, c.size.y - 2), dmg, C_GREEN if hp > 0.66 else (C_YELLOW if hp > 0.33 else C_RED), 8)
	else:
		_text(c, Vector2(3, 9), "INTET MÅL · " + Game.key_name("target_nearest"), C_DIM.lightened(0.4), 8)
		var hu := clampf(ship.hull / 100.0, 0.0, 1.0)
		var st := "SKROG %d%%" % int(hu * 100.0)
		_text(c, Vector2(3, c.size.y - 2), st, C_GREEN if hu > 0.5 else C_RED, 8)
	# Hjørnebeslag
	var cc := C_AMBER.darkened(0.3)
	for p in [Vector2(1, 12), Vector2(c.size.x - 6, 12), Vector2(1, c.size.y - 17), Vector2(c.size.x - 6, c.size.y - 17)]:
		c.draw_rect(Rect2(p, Vector2(5, 1)), cc)
		c.draw_rect(Rect2(p + Vector2(0 if p.x < 10 else 4, 0 if p.y < 20 else -4), Vector2(1, 5)), cc)


# ---------------------------------------------------------------- hologram

func _make_holo(v: SubViewport) -> void:
	v.own_world_3d = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = C_BG
	var we := WorldEnvironment.new()
	we.environment = env
	v.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.2, 8.5)
	cam.fov = 40.0
	v.add_child(cam)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	_holo_root = Node3D.new()
	v.add_child(_holo_root)
	_holo_mat = ShaderMaterial.new()
	_holo_mat.shader = load("res://shaders/hologram.gdshader")
	# Gitterring under modellen
	var ring := MeshInstance3D.new()
	ring.mesh = K.torus(3.0, 0.04, 24, 4)
	ring.material_override = K.glow(Color("173a7a"))
	ring.position = Vector3(0, -1.6, 0)
	v.add_child(ring)


func _update_holo(delta: float) -> void:
	if _holo_root == null or ship == null:
		return
	var i := ship.lock_target
	var target := i >= 0 and W.pirates and W.pirates.is_active(i)
	var kind := ("pirat:" + W.pirates.type_of(i)) if target else "eget:" + ship.ship_class
	if kind != _holo_kind:
		_holo_kind = kind
		if _holo_model:
			_holo_model.queue_free()
		if target:
			_holo_model = ShipModels.pirate_of(W.pirates.type_of(i))
		else:
			var m := ShipModel.new()
			m.ship_class = ship.ship_class
			m.paint = ship.paint
			_holo_model = m
		_holo_root.add_child(_holo_model)
		_apply_holo(_holo_model)
		# Skaler modellen, så den fylder skærmen uanset skibstype
		var box := _aabb(_holo_model, Transform3D.IDENTITY)
		var ext := maxf(box.size.x, maxf(box.size.y, box.size.z))
		_holo_model.scale = Vector3.ONE * (7.5 / maxf(ext, 0.1))
		_holo_model.position = -box.get_center() * _holo_model.scale.x
	if target:
		# Målet vender, som vi ser det fra vores skib
		var tb := (W.pirates._p[i]["node"] as Node3D).global_basis
		_holo_root.basis = (ship.global_basis.inverse() * tb).orthonormalized()
		_holo_mat.set_shader_parameter("tint", C_AMBER)
	else:
		_holo_root.basis = Basis(Vector3.UP, _t * 0.6) * Basis(Vector3.RIGHT, 0.35)
		_holo_mat.set_shader_parameter("tint", C_CYAN if ship.hull > 50.0 else C_RED)


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for ch in n.get_children():
		if ch is MeshInstance3D or ch.get_child_count() > 0:
			var b := _aabb(ch, t)
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b)
				first = false
	return out


func _apply_holo(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = _holo_mat
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is GPUParticles3D or n is CPUParticles3D or n is Light3D:
		(n as Node3D).visible = false
	for ch in n.get_children():
		_apply_holo(ch)


# ---------------------------------------------------------------- byggeklodser

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	m.metallic = 0.2
	return m


func _box_in(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = K.box(size.x, size.y, size.z)
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


## En skærm: en flade med en SubViewport som tekstur. `fn` tegner indholdet.
func _screen_in(parent: Node3D, pos: Vector3, size: Vector2, px: Vector2i, fn: Callable, three_d := false) -> SubViewport:
	var v := SubViewport.new()
	v.size = px
	v.transparent_bg = false
	v.disable_3d = not three_d
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	v.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(v)
	var p := Painter.new()
	p.fn = fn
	p.size = Vector2(px)
	v.add_child(p)
	_views.append(v)
	_painters.append(p)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = v.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material_override = m
	q.position = pos
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(q)
	return v


## En stiver (firkantet bjælke) fra a til b.
func _bar(a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var m := MeshInstance3D.new()
	m.mesh = K.box(thick, thick, a.distance_to(b))
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK
	m.transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	add_child(m)
