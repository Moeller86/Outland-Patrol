class_name StarMap
extends Control
## Kortet (M). To visninger:
##  SYSTEM  – systemet set ovenfra: planeter, stationer, Concord-basen, trade lanes,
##            jump gates, asteroidebælter, fragtskibe, pirater, piloter og missionens mål.
##  GALAKSE – alle systemer og jump gates imellem dem.
##
## Klik på noget (eller et tomt sted) for at sætte en markering. Markeringen vises
## som gul markør i HUD'en, også i andre systemer (så peger den på den rigtige gate).
## Højreklik fjerner markeringen. Hjul zoomer, træk flytter. TAB skifter visning.

signal closed

const PAD := 28.0
const PICK_RADIUS := 16.0

var ship: Ship
var mode := "system"            ## "system" eller "galaxy"
var view_sys := "kepler"

var _zoom := 1.0
var _pan := Vector2.ZERO        ## Forskydning i verdensmeter (x, z)
var _drag_from := Vector2.INF
var _dragged := false
var _hover: Dictionary = {}
var _font: Font
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = get_theme_default_font()


func open() -> void:
	visible = true
	mode = "system"
	if ship and is_instance_valid(ship):
		view_sys = W.universe.system_at(ship.position)
	_zoom = 1.0
	_pan = Vector2.ZERO
	_hover = {}
	Sfx.play("kort", -4.0, 0.0)
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_ESCAPE, KEY_M:
				close()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				_switch_mode("galaxy" if mode == "system" else "system")
				get_viewport().set_input_as_handled()


func _switch_mode(m: String) -> void:
	mode = m
	_zoom = 1.0
	_pan = Vector2.ZERO
	Sfx.play("klik", -2.0, 0.0)


# ---------------------------------------------------------------- mus

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and mode == "system":
			_zoom_at(mb.position, 1.2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and mode == "system":
			_zoom_at(mb.position, 1.0 / 1.2)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = mb.position
				_dragged = false
				if _tab_rect("system").has_point(mb.position):
					_switch_mode("system")
					_drag_from = Vector2.INF
				elif _tab_rect("galaxy").has_point(mb.position):
					_switch_mode("galaxy")
					_drag_from = Vector2.INF
			else:
				if _drag_from != Vector2.INF and not _dragged:
					_click(mb.position)
				_drag_from = Vector2.INF
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not W.waypoint.is_empty():
				W.waypoint = {}
				Sfx.play("lock_tabt", -4.0, 0.0)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_from != Vector2.INF and mode == "system" and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if mm.position.distance_to(_drag_from) > 5.0:
				_dragged = true
			if _dragged:
				_pan -= mm.relative / _scale()
		_hover = _pick(mm.position)
		accept_event()


func _zoom_at(screen: Vector2, k: float) -> void:
	var before := _to_world(screen)
	_zoom = clampf(_zoom * k, 0.6, 12.0)
	var after := _to_world(screen)
	_pan += before - after


func _click(pos: Vector2) -> void:
	var hit := _pick(pos)
	if mode == "galaxy":
		if not hit.is_empty():
			view_sys = hit["system"]
			_switch_mode("system")
		return
	if not _map_rect().has_point(pos):
		return
	if hit.is_empty():
		var w := _to_world(pos)
		var origin: Vector3 = W.universe.origins[view_sys]
		W.waypoint = {"pos": Vector3(w.x, origin.y, w.y), "label": "MARKERING", "system": view_sys}
	else:
		W.waypoint = {"pos": hit["pos"], "label": str(hit["label"]).to_upper(), "system": view_sys}
	Sfx.play("markering", -4.0, 0.0)


# ---------------------------------------------------------------- geometri

func _map_rect() -> Rect2:
	return Rect2(Vector2(PAD, PAD + 52.0), (size - Vector2(PAD * 2.0 + 230.0, PAD * 2.0 + 90.0)).max(Vector2(200, 150)))


func _tab_rect(m: String) -> Rect2:
	var x := PAD + (0.0 if m == "system" else 130.0)
	return Rect2(Vector2(x, PAD + 6.0), Vector2(120, 30))


## Det område (x, z), systemets ting fylder, relativt til systemets origo.
func _bounds() -> Rect2:
	var origin: Vector3 = W.universe.origins[view_sys]
	var b := Rect2(Vector2(-200, -200), Vector2(400, 400))
	for p in W.universe.planets:
		if p.system_id == view_sys:
			var c := _xz(p.position - origin)
			var r := p.radius + p.atmo_top
			b = b.merge(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	for s in W.universe.stations:
		if s.system_id == view_sys:
			b = b.expand(_xz(s.position - origin))
	for gid: String in W.universe.gates:
		var g: Dictionary = W.universe.gates[gid]
		if g["system"] == view_sys:
			b = b.expand(_xz((g["pos"] as Vector3) - origin))
	return b.grow(120.0)


func _scale() -> float:
	var r := _map_rect()
	var b := _bounds()
	return maxf(0.0001, minf(r.size.x / b.size.x, r.size.y / b.size.y) * _zoom)


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Verdenspunktet (x, z), der ligger midt i kortet.
func _focus() -> Vector2:
	return _xz(W.universe.origins[view_sys]) + _bounds().get_center() + _pan


func _to_screen(world: Vector3) -> Vector2:
	return _map_rect().get_center() + (_xz(world) - _focus()) * _scale()


func _to_world(screen: Vector2) -> Vector2:
	return (screen - _map_rect().get_center()) / _scale() + _focus()


## Det klikbare objekt nærmest musen: {label, pos, system, kind}
func _pick(pos: Vector2) -> Dictionary:
	var best := {}
	var bd := PICK_RADIUS
	if mode == "galaxy":
		for sys_id: String in Game.systems:
			var d := pos.distance_to(_galaxy_pos(sys_id))
			if d < 40.0 and d < bd + 30.0:
				bd = d - 30.0
				best = {"label": Game.systems[sys_id]["name"], "system": sys_id, "kind": "system", "pos": W.universe.origins[sys_id]}
		return best
	for o: Dictionary in _objects():
		var sp := _to_screen(o["pos"])
		var d := pos.distance_to(sp) - float(o.get("r", 0.0))
		if d < bd:
			bd = d
			best = o
	return best


## Faste ting i systemet, som kan markeres.
func _objects() -> Array:
	var out := []
	for p in W.universe.planets:
		if p.system_id == view_sys:
			out.append({"label": p.display_name, "pos": p.pad_top, "kind": "planet", "system": view_sys,
				"r": maxf(6.0, p.radius * _scale()), "body": p})
			for op in p.pads.slice(1):
				out.append({"label": str(op["name"]), "pos": op["top"], "kind": "outpost", "system": view_sys})
	for s in W.universe.stations:
		if s.system_id == view_sys:
			out.append({"label": s.display_name, "pos": s.dock_pos, "kind": "base" if s.is_base else "station", "system": view_sys})
	for gid: String in W.universe.gates:
		var g: Dictionary = W.universe.gates[gid]
		if g["system"] == view_sys:
			var dest: String = W.universe.gates[g["to"]]["system"]
			out.append({"label": "Jump gate → %s" % Game.systems[dest]["name"], "pos": g["pos"], "kind": "gate", "system": view_sys})
	if W.sites:
		for s in W.sites.known_in(view_sys):
			out.append({"label": "%s%s" % [s["name"], " (tom)" if s["looted"] else ""], "pos": s["land"], "kind": "site", "system": view_sys})
	return out


func _galaxy_pos(sys_id: String) -> Vector2:
	# Systemerne placeres efter deres origo, skaleret ind i kortet.
	var r := _map_rect()
	var pts := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id: String in Game.systems:
		var v := _xz(W.universe.origins[id])
		pts[id] = v
		lo = lo.min(v)
		hi = hi.max(v)
	var span := (hi - lo)
	var c := (lo + hi) / 2.0
	var k := minf(r.size.x * 0.6 / maxf(span.x, 1.0), r.size.y * 0.6 / maxf(span.y, 1.0))
	if span.x < 1.0 and span.y < 1.0:
		k = 1.0
	return r.get_center() + ((pts[sys_id] as Vector2) - c) * k


# ---------------------------------------------------------------- tegning

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.INK)
	var r := _map_rect()
	draw_rect(r, UiTheme.PANEL.darkened(0.45))
	if mode == "system":
		_draw_grid(r)
		_draw_system()
	else:
		_draw_galaxy()
	# Maskér det, der stikker ud over kortet (ved zoom), og tegn rammen ovenpå
	draw_rect(Rect2(0, 0, size.x, r.position.y), UiTheme.INK)
	draw_rect(Rect2(0, r.end.y, size.x, size.y - r.end.y), UiTheme.INK)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), UiTheme.INK)
	draw_rect(Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y), UiTheme.INK)
	# Faner
	for m: String in ["system", "galaxy"]:
		var tr := _tab_rect(m)
		var on := mode == m
		draw_rect(tr, UiTheme.YELLOW if on else UiTheme.PANEL_2)
		draw_rect(tr, UiTheme.INK if on else UiTheme.LINE, false, 2.0)
		_text(tr.position + Vector2(12, 21), "SYSTEM" if m == "system" else "GALAKSE", UiTheme.INK if on else UiTheme.MUTED, 14)
	var title := "KORT · %s" % str(Game.systems[view_sys]["name"]).to_upper() if mode == "system" else "KORT · THE REACH"
	_text(Vector2(PAD + 270.0, PAD + 28.0), title, UiTheme.TEXT, 20)
	draw_rect(r, UiTheme.LINE, false, 2.0)
	_draw_legend(Vector2(r.end.x + 18.0, r.position.y))
	var help := "KLIK: SÆT MARKERING   HØJREKLIK: FJERN   HJUL: ZOOM   TRÆK: FLYT   TAB: SYSTEM/GALAKSE   M/ESC: LUK" if mode == "system" \
		else "KLIK PÅ ET SYSTEM FOR AT SE DET   TAB: SYSTEM/GALAKSE   M/ESC: LUK"
	_text(Vector2(PAD, size.y - PAD), help, UiTheme.MUTED, 12)
	# Hover-info
	if not _hover.is_empty():
		var info := str(_hover["label"])
		if mode == "system" and ship and is_instance_valid(ship) and W.universe.system_at(ship.position) == view_sys:
			info += " · " + Hud._dist(ship.position.distance_to(_hover["pos"]))
		info += "  (klik for at markere)" if mode == "system" else "  (klik for at åbne)"
		var mp := get_local_mouse_position() + Vector2(16, -8)
		var w := _font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16.0
		mp.x = minf(mp.x, size.x - w - 4.0)
		draw_rect(Rect2(mp - Vector2(0, 16), Vector2(w, 24)), UiTheme.PANEL_2)
		draw_rect(Rect2(mp - Vector2(0, 16), Vector2(w, 24)), UiTheme.PINK, false, 2.0)
		_text(mp + Vector2(8, 1), info, UiTheme.TEXT, 13)


func _draw_grid(r: Rect2) -> void:
	if _scale() <= 0.0:
		return
	var step := 250.0
	while step * _scale() < 40.0 and step < 1.0e6:
		step *= 2.0
	var w0 := _to_world(r.position)
	var w1 := _to_world(r.end)
	var col := Color(UiTheme.LINE, 0.35)
	var x := floorf(w0.x / step) * step
	while x <= w1.x:
		var sx := r.get_center().x + (x - _focus().x) * _scale()
		if sx >= r.position.x and sx <= r.end.x:
			draw_line(Vector2(sx, r.position.y), Vector2(sx, r.end.y), col, 1.0)
		x += step
	var z := floorf(w0.y / step) * step
	while z <= w1.y:
		var sy := r.get_center().y + (z - _focus().y) * _scale()
		if sy >= r.position.y and sy <= r.end.y:
			draw_line(Vector2(r.position.x, sy), Vector2(r.end.x, sy), col, 1.0)
		z += step
	_text(r.position + Vector2(8, r.size.y - 8), "Gitter: %s" % Hud._dist(step), UiTheme.MUTED, 11)


func _in_map(p: Vector2, margin := 0.0) -> bool:
	return _map_rect().grow(margin).has_point(p)


func _draw_system() -> void:
	var sc := _scale()
	var origin: Vector3 = W.universe.origins[view_sys]
	var sys: Dictionary = Game.systems[view_sys]
	# Asteroidebælter: prikker i et fast mønster
	for f: Dictionary in sys.get("asteroids", []):
		var center := origin + Game.vec(f["center"])
		var spread := Game.vec(f["spread"])
		var rng := RandomNumberGenerator.new()
		rng.seed = int(f["seed"])
		var colors: Array = f["colors"]
		for k in 70:
			var p := center + Vector3(rng.randf_range(-1, 1) * spread.x, 0, rng.randf_range(-1, 1) * spread.z)
			var sp := _to_screen(p)
			if _in_map(sp):
				draw_rect(Rect2(sp - Vector2(1.5, 1.5), Vector2(3, 3)), Color(Game.col(colors[k % colors.size()]), 0.7))
		var cs := _to_screen(center)
		if _in_map(cs):
			_text(cs + Vector2(-40, -spread.z * sc - 6), "ASTEROIDER (%s)" % str(f["kind"]).to_upper(), Color(UiTheme.MUTED, 0.8), 11)
	# Trade lanes
	for l in W.universe.lanes:
		if l["system"] != view_sys:
			continue
		var a := _to_screen(l["a"])
		var b := _to_screen(l["b"])
		draw_dashed_line(a, b, Color(UiTheme.YELLOW, 0.7), 2.0, 8.0)
		for e: Vector2 in [a, b]:
			draw_arc(e, 5.0, 0.0, TAU, 10, UiTheme.YELLOW, 2.0)
	# Planeter
	for p in W.universe.planets:
		if p.system_id != view_sys:
			continue
		var c := _to_screen(p.position)
		var pr := maxf(6.0, p.radius * sc)
		var col := Game.col(p.data.get("atmo", "ffffff"))
		draw_circle(c, pr, col.darkened(0.35))
		draw_circle(c, pr * 0.82, col.darkened(0.15))
		draw_arc(c, pr, 0.0, TAU, 32, col, 2.0)
		# Atmosfære
		draw_arc(c, (p.radius + p.atmo_top) * sc, 0.0, TAU, 32, Color(col, 0.35), 1.0)
		var pad := _to_screen(p.pad_top)
		draw_rect(Rect2(pad - Vector2(3, 3), Vector2(6, 6)), UiTheme.PINK)
		for op in p.pads.slice(1):
			var oc := _to_screen(op["top"])
			var ocol := Color("6bdc4f") if op["style"] == "plot" else Color("ffb36b")
			draw_rect(Rect2(oc - Vector2(3, 3), Vector2(6, 6)), ocol)
			if _zoom > 1.6:
				_label(oc + Vector2(0, 14.0), str(op["name"]).to_upper(), ocol, 11)
		_label(c + Vector2(0, pr + 16.0), p.display_name.to_upper(), UiTheme.PINK, 13)
		if W.weather and W.weather.level.get(p.id, 0.0) > 0.3:
			var wt: Dictionary = Weather.TYPES[W.weather.type_of(p.id)]
			_label(c + Vector2(0, pr + 30.0), "⚠ " + str(wt["name"]), Game.col(wt["color"]), 11)
	# Stationer og basen
	for s in W.universe.stations:
		if s.system_id != view_sys:
			continue
		var c := _to_screen(s.position)
		if s.is_base:
			var pts := PackedVector2Array([c + Vector2(0, -10), c + Vector2(9, -5), c + Vector2(7, 7), c + Vector2(0, 11), c + Vector2(-7, 7), c + Vector2(-9, -5)])
			draw_colored_polygon(pts, Color("2e6bd6"))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color("e6ecff"), 2.0)
			_label(c + Vector2(0, 26), s.display_name.to_upper(), Color("6fa8ff"), 13)
		else:
			draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), UiTheme.CYAN)
			draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), Color.WHITE, false, 2.0)
			_label(c + Vector2(0, 24), s.display_name.to_upper(), UiTheme.CYAN, 13)
	# Jump gates
	for gid: String in W.universe.gates:
		var g: Dictionary = W.universe.gates[gid]
		if g["system"] != view_sys:
			continue
		var c := _to_screen(g["pos"])
		draw_arc(c, 9.0, 0.0, TAU, 14, UiTheme.VIOLET, 3.0)
		draw_circle(c, 4.0, Color(UiTheme.VIOLET, 0.5))
		_label(c + Vector2(0, 24), str(g["label"]), UiTheme.VIOLET, 12)
	# Fund, man har scannet
	if W.sites:
		for s in W.sites.known_in(view_sys):
			var c := _to_screen(s["pos"])
			var col := Game.col(Sites.KINDS[s["kind"]]["color"])
			if s["looted"]:
				col = Color(col, 0.35)
			draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), UiTheme.INK)
			draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), col)
	# Fragtskibe
	if W.freighters:
		for fp in W.freighters.positions_in(view_sys):
			var c := _to_screen(fp)
			if _in_map(c):
				draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), UiTheme.GREEN)
	# Mission
	var ms := W.missions
	if ms and ms.active and ms.client.get("system", "") == view_sys:
		var pulse := 10.0 + sin(_t * 5.0) * 3.0
		var esc: Dictionary = ms.client.get("escort", {})
		if not esc.is_empty() and esc.get("alive", false):
			var c := _to_screen(esc["pos"])
			draw_arc(c, pulse, 0.0, TAU, 16, UiTheme.GREEN, 2.0)
			_label(c + Vector2(0, -16), str(esc["name"]).to_upper(), UiTheme.GREEN, 12)
		elif ms.client.get("has_target", false):
			var c := _to_screen(ms.client["target"])
			draw_arc(c, pulse, 0.0, TAU, 16, UiTheme.GREEN, 2.0)
			_label(c + Vector2(0, -16), "MISSIONSMÅL", UiTheme.GREEN, 12)
	# Concord-patruljer
	if W.patrols:
		for pp in W.patrols.positions_in(view_sys):
			var c := _to_screen(pp)
			if _in_map(c):
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(5, 4), c + Vector2(-5, 4)]), Color("6fa8ff"))
	# Pirater
	if W.pirates:
		for pp in W.pirates.positions_in(view_sys):
			var c := _to_screen(pp)
			if _in_map(c):
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 4), c + Vector2(-5, 4)]), UiTheme.DANGER)
	# Markering
	var wp: Dictionary = W.waypoint
	if not wp.is_empty() and wp["system"] == view_sys:
		var c := _to_screen(wp["pos"])
		if ship and is_instance_valid(ship) and W.universe.system_at(ship.position) == view_sys:
			draw_dashed_line(_to_screen(ship.position), c, Color(UiTheme.TEXT, 0.45), 1.0, 3.0)
		var d := 8.0 + sin(_t * 4.0) * 1.5
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), UiTheme.YELLOW)
		draw_polyline(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0), c + Vector2(0, -d)]), UiTheme.INK, 2.0)
		if wp["label"] == "MARKERING":
			_label(c + Vector2(0, -16), str(wp["label"]), UiTheme.YELLOW, 12)
	# Piloter (andre først, så ens eget skib ligger øverst)
	for id: int in W.ships:
		var s: Ship = W.ships[id]
		if not is_instance_valid(s) or s.dead or W.universe.system_at(s.position) != view_sys:
			continue
		if s == ship:
			continue
		_draw_ship(s, 7.0)
	if ship and is_instance_valid(ship) and W.universe.system_at(ship.position) == view_sys:
		_draw_ship(ship, 10.0)
		var c := _to_screen(ship.position)
		draw_arc(c, 16.0 + fmod(_t * 18.0, 14.0), 0.0, TAU, 20, Color(UiTheme.TEXT, 1.0 - fmod(_t * 18.0, 14.0) / 14.0), 1.5)
	elif ship and is_instance_valid(ship):
		var g := W.gate_towards(view_sys, W.universe.system_at(ship.position))
		if not g.is_empty():
			_label(_to_screen(g["pos"]) + Vector2(0, -16), "DU ER I %s" % str(Game.systems[W.universe.system_at(ship.position)]["name"]).to_upper(), UiTheme.TEXT, 12)


func _draw_ship(s: Ship, sz: float) -> void:
	var c := _to_screen(s.position)
	var f := _xz(s.forward())
	f = f.normalized() if f.length() > 0.05 else Vector2.UP
	var side := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([c + f * sz, c - f * sz * 0.6 + side * sz * 0.65, c - f * sz * 0.3, c - f * sz * 0.6 - side * sz * 0.65])
	draw_colored_polygon(pts, s.paint)
	draw_polyline(pts + PackedVector2Array([pts[0]]), UiTheme.INK if s != ship else Color.WHITE, 2.0)
	_label(c + Vector2(0, sz + 14.0), s.display_name if s != ship else "DIG", Color.WHITE if s == ship else s.paint, 12)


func _draw_galaxy() -> void:
	var here := W.universe.system_at(ship.position) if ship and is_instance_valid(ship) else ""
	# Forbindelser
	for gid: String in W.universe.gates:
		var g: Dictionary = W.universe.gates[gid]
		var a := _galaxy_pos(g["system"])
		var b := _galaxy_pos(W.universe.gates[g["to"]]["system"])
		draw_dashed_line(a, b, Color(UiTheme.VIOLET, 0.8), 3.0, 10.0)
	for sys_id: String in Game.systems:
		var sys: Dictionary = Game.systems[sys_id]
		var c := _galaxy_pos(sys_id)
		var col := Game.col(sys["sun"])
		var hover: bool = not _hover.is_empty() and _hover.get("system", "") == sys_id
		draw_circle(c, 34.0, Color(col, 0.12))
		draw_circle(c, 18.0 + (3.0 if hover else 0.0), col)
		draw_arc(c, 24.0, 0.0, TAU, 24, Color(col, 0.7), 2.0)
		# Planeterne som små prikker i kredsløb
		var n := 0
		for p in W.universe.planets:
			if p.system_id == sys_id:
				var a := n * 2.1 + _t * 0.3
				draw_circle(c + Vector2(cos(a), sin(a)) * (38.0 + n * 9.0), 4.0, Game.col(p.data.get("atmo", "ffffff")))
				n += 1
		_label(c + Vector2(0, 74), str(sys["name"]).to_upper(), UiTheme.TEXT, 16)
		var info := "%d planeter" % n
		if W.universe.home_base(sys_id):
			info += " · Concord-base"
		_label(c + Vector2(0, 92), info, UiTheme.MUTED, 12)
		if sys_id == here:
			_label(c + Vector2(0, -50), "▼ DU ER HER", UiTheme.YELLOW, 13)
		if not W.waypoint.is_empty() and W.waypoint["system"] == sys_id:
			_label(c + Vector2(0, -66 if sys_id == here else -50), "◆ " + str(W.waypoint["label"]), UiTheme.YELLOW, 12)
		var ms := W.missions
		if ms and ms.active and ms.client.get("system", "") == sys_id:
			_label(c + Vector2(0, 108), "MISSION: " + str(ms.client.get("name", "")).to_upper(), UiTheme.GREEN, 12)


func _draw_legend(pos: Vector2) -> void:
	var rows := [
		["planet", UiTheme.PINK, "Planet / by"],
		["base", Color("6fa8ff"), "Concord-base"],
		["outpost", Color("ffb36b"), "Mine / koloni / forpost"],
		["outpost", Color("6bdc4f"), "Byggegrund / egen base"],
		["station", UiTheme.CYAN, "Station"],
		["gate", UiTheme.VIOLET, "Jump gate"],
		["lane", UiTheme.YELLOW, "Trade lane"],
		["freighter", UiTheme.GREEN, "Fragtskib"],
		["pirate", UiTheme.DANGER, "Pirat"],
		["patrol", Color("6fa8ff"), "Concord-patrulje"],
		["site", Color("ff9e3d"), "Fund (scannet)"],
		["wp", UiTheme.YELLOW, "Markering"],
		["mission", UiTheme.GREEN, "Missionsmål"],
	]
	_text(pos + Vector2(0, 12), "SIGNATURFORKLARING", UiTheme.MUTED, 12)
	var y := pos.y + 36.0
	for row: Array in rows:
		var c := Vector2(pos.x + 10.0, y)
		var col: Color = row[1]
		match row[0]:
			"planet": draw_circle(c, 7.0, col.darkened(0.2))
			"base": draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, -4), c + Vector2(5, 6), c + Vector2(0, 8), c + Vector2(-5, 6), c + Vector2(-7, -4)]), Color("2e6bd6"))
			"station": draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), col)
			"outpost": draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), col)
			"gate": draw_arc(c, 7.0, 0.0, TAU, 12, col, 3.0)
			"lane": draw_dashed_line(c - Vector2(9, 0), c + Vector2(9, 0), col, 2.0, 4.0)
			"freighter": draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), col)
			"site":
				draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), UiTheme.INK)
				draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), col)
			"pirate", "patrol": draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 4), c + Vector2(-5, 4)]), col)
			"wp": draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)]), col)
			"mission": draw_arc(c, 7.0, 0.0, TAU, 12, col, 2.0)
		_text(Vector2(pos.x + 28.0, y + 5.0), row[2], UiTheme.TEXT, 13)
		y += 26.0
	if not W.waypoint.is_empty():
		y += 10.0
		_text(Vector2(pos.x, y), "MARKERING:", UiTheme.MUTED, 12)
		_text(Vector2(pos.x, y + 18.0), str(W.waypoint["label"]), UiTheme.YELLOW, 13)
		_text(Vector2(pos.x, y + 34.0), str(Game.systems[W.waypoint["system"]]["name"]), UiTheme.MUTED, 12)


func _text(pos: Vector2, text: String, col: Color, fs: int) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, UiTheme.INK)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _label(center: Vector2, text: String, col: Color, fs: int) -> void:
	if not _in_map(center, 40.0) and mode == "system":
		return
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(Vector2(roundf(center.x - w / 2.0), roundf(center.y)), text, col, fs)
