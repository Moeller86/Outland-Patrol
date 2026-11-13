class_name ShipManager
extends Control
## Rumskibsmanageren (U): overblik over skibet med et 3D-billede, hvor hver plads
## (våben, skjold, motor, gadgets) står i en kasse med en streg ind til sin plads på
## skibet. Viser Mk-niveau, lageret og lasten. I en hangar (station eller egen base med
## hangar) kan man trække dele mellem pladserne og lageret, installere fra lageret og
## – hos en udstyrsforhandler – købe nye dele i Mk I–III.

signal closed

const BW := 200.0
const BH := 62.0
const SLOT_COL := {"vaaben": Color("ff4f8b"), "skjold": Color("2ec4d6"), "motor": Color("ff9e3d"), "gadget": Color("6bdc4f")}

var ship: Ship
var loc_id := ""
var _sel: Array = ["vaaben", 0]
var _stage: Control
var _lines: LineLayer
var _sv: SubViewport
var _cam: Camera3D
var _turn: Node3D
var _model: Node3D
var _model_cls := ""
var _center := Vector3.ZERO
var _extent := Vector3.ONE
var _boxes: Array[SlotBox] = []
var _left: VBoxContainer
var _right: VBoxContainer
var _title: Label
var _status: Label
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	add_to_group("ship_manager")
	var bg := ColorRect.new()
	bg.color = Color(UiTheme.INK, 0.985)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	_title = UiTheme.value("", UiTheme.YELLOW, 22)
	head.add_child(_title)
	_status = UiTheme.value("", UiTheme.CYAN, 14)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	_status.custom_minimum_size = Vector2(100, 0)
	head.add_child(_status)
	var close_btn := Button.new()
	close_btn.text = "LUK (U)"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	v.add_child(body)
	# Venstre: skibets tal og den valgte del
	var lp := PanelContainer.new()
	lp.custom_minimum_size = Vector2(270, 0)
	body.add_child(lp)
	var ls := ScrollContainer.new()
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(ls)
	_left = VBoxContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.add_theme_constant_override("separation", 6)
	ls.add_child(_left)
	# Midten: skibet
	_stage = Control.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	body.add_child(_stage)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(svc)
	_sv = SubViewport.new()
	_sv.own_world_3d = true
	_sv.transparent_bg = true
	svc.add_child(_sv)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_sv.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.3
	_sv.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("9a96c0")
	env.environment.ambient_light_energy = 0.75
	_sv.add_child(env)
	_turn = Node3D.new()
	_turn.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sv.add_child(_turn)
	_lines = LineLayer.new()
	_lines.manager = self
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_lines)
	# Højre: installér, lager og last
	var rp := PanelContainer.new()
	rp.custom_minimum_size = Vector2(390, 0)
	body.add_child(rp)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(rs)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 6)
	rs.add_child(_right)

	Game.fit_changed.connect(func(): if visible: _refresh())
	Game.wallet_changed.connect(func(): if visible: _refresh())


# ---------------------------------------------------------------- åbn / luk

func open(s: Ship, at_loc := "") -> void:
	ship = s
	loc_id = at_loc
	visible = true
	_refresh()
	Sfx.play("klik", -2.0, 0.0)


## Fra stationsmenuens Udstyr-fane eller basens hangar.
func open_here(at_loc: String) -> void:
	open(W.local_ship, at_loc)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Må man ændre udstyret lige nu? (landet i en hangar)
func editable() -> bool:
	if ship == null or not is_instance_valid(ship) or ship.state != Ship.State.LANDED or loc_id == "":
		return false
	return Game.can_refit(loc_id) or Game.test_mode


## Kan man købe nye dele her?
func can_shop() -> bool:
	return editable() and (Game.has_outfitter(loc_id) or Game.test_mode)


# ---------------------------------------------------------------- opbygning

func _refresh() -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var cls := ship.ship_class
	var cdata: Dictionary = Game.ship_data["classes"][cls]
	var nm := str(ship.look.get("name", "")) if ship.look.has("name") else ""
	_title.text = "RUMSKIBSMANAGER · %s%s" % [cdata["name"], (" «%s»" % nm) if nm != "" else ""]
	if editable():
		_status.text = "Hangar: %s · træk dele mellem pladser og lager" % _loc_name()
	else:
		_status.text = "Kun overblik – land i en hangar for at flytte og installere udstyr"
	if _model_cls != cls + JSON.stringify(ship.look):
		_build_model()
	_build_boxes()
	_build_left()
	_build_right()


func _loc_name() -> String:
	var loc: Dictionary = Game.locations.get(loc_id, {})
	return str(loc.get("name", loc_id))


func _build_model() -> void:
	if _model:
		_model.queue_free()
	var m := ShipModel.new()
	m.paint = ship.paint
	m.ship_class = ship.ship_class
	m.apply_look(ship.look)
	_turn.add_child(m)
	_model = m
	_model_cls = ship.ship_class + JSON.stringify(ship.look)
	# Skibets størrelse (til kamera og streger)
	var aabb := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var gi := mi as MeshInstance3D
		var bb: AABB = (m.global_transform.affine_inverse() * gi.global_transform) * gi.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	if first:
		aabb = AABB(Vector3(-4, -1, -5), Vector3(8, 2, 10))
	_center = aabb.get_center()
	_extent = aabb.size * 0.5
	var r := maxf(_extent.x, _extent.z) * 1.15
	_cam.position = _center + Vector3(0, r * 2.1, r * 3.0)
	_cam.look_at(_center)


func _build_boxes() -> void:
	for b in _boxes:
		b.queue_free()
	_boxes.clear()
	var f := Game.fit_for(ship.ship_class)
	for slot: String in Game.equipment["slots"]:
		var vals: Array = f[slot] if f[slot] is Array else [f[slot]]
		for k in vals.size():
			var b := SlotBox.new()
			b.manager = self
			b.slot = slot
			b.idx = k
			b.item_id = str(vals[k])
			b.multi = vals.size() > 1 or slot == "gadget"
			if slot == "vaaben":
				b.group = int((f["grupper"] as Array)[k])
			b.size = Vector2(BW, BH)
			_stage.add_child(b)
			_boxes.append(b)


func _process(delta: float) -> void:
	if not visible or _model == null:
		return
	_t += delta
	_turn.rotation.y = sin(_t * 0.4) * 0.35
	_layout()
	_lines.queue_redraw()


## Placér kasserne rundt om skibet: våben i siderne (efter hvilken side kanonen sidder
## på), skjoldet øverst, motor og gadgets nederst.
func _layout() -> void:
	var s := _stage.size
	var guns: Array = ship.handling.get("guns", Ship.GUNS)
	var left: Array[SlotBox] = []
	var right: Array[SlotBox] = []
	var bottom: Array[SlotBox] = []
	for b in _boxes:
		b.anchor3d = _anchor_for(b, guns)
		match b.slot:
			"vaaben":
				if b.anchor3d.x < -0.01 or (absf(b.anchor3d.x) <= 0.01 and left.size() <= right.size()):
					left.append(b)
				else:
					right.append(b)
			"skjold":
				b.position = Vector2(s.x / 2.0 - BW / 2.0, 6)
			_:
				bottom.append(b)
	var gap := 12.0
	for col in [left, right]:
		var h: float = col.size() * (BH + gap) - gap
		var y0: float = s.y * 0.45 - h / 2.0
		for i in col.size():
			col[i].position = Vector2(6 if col == left else s.x - BW - 6, y0 + i * (BH + gap))
	var bw := minf(BW, (s.x - 12 - gap * (bottom.size() - 1)) / maxf(1.0, bottom.size()))
	var total := bottom.size() * (bw + gap) - gap
	for i in bottom.size():
		bottom[i].size = Vector2(bw, BH)
		bottom[i].position = Vector2(s.x / 2.0 - total / 2.0 + i * (bw + gap), s.y - BH - 6)


func _anchor_for(b: SlotBox, guns: Array) -> Vector3:
	match b.slot:
		"vaaben":
			if guns.is_empty():
				return _center
			var ga = guns[b.idx % guns.size()]
			return Vector3(ga[0], ga[1], ga[2]) if ga is Array else (ga as Vector3)
		"skjold":
			return _center + Vector3(0, _extent.y * 0.8, -_extent.z * 0.1)
		"motor":
			return _center + Vector3(0, 0, _extent.z * 0.9)
		_:
			var n := maxi(1, Game.slot_count(ship.ship_class, "gadget"))
			var u := (b.idx + 0.5) / n - 0.5
			return _center + Vector3(u * _extent.x * 0.9, _extent.y * 0.6, _extent.z * 0.25)


## Skærmpunkt (i scenens koordinater) for et punkt på skibet.
func screen_of(p: Vector3) -> Vector2:
	return _cam.unproject_position(_turn.global_transform * p)


func select(slot: String, idx: int) -> void:
	_sel = [slot, idx]
	_refresh()


func is_selected(b: SlotBox) -> bool:
	return b.slot == _sel[0] and b.idx == _sel[1]


# ---------------------------------------------------------------- venstre panel

func _build_left() -> void:
	for c in _left.get_children():
		c.queue_free()
	var h := ship.handling
	var cls := ship.ship_class
	var cdata: Dictionary = Game.ship_data["classes"][cls]
	_left.add_child(UiTheme.caption(str(cdata.get("role", "")), UiTheme.PINK))
	_left.add_child(UiTheme.value(str(cdata["name"]), UiTheme.YELLOW, 18))
	_stat("Topfart", "%d m/s" % int(ship.max_speed()))
	_stat("Drejning", "%d %%" % int(float(h.get("turn", 1.0)) / float(cdata.get("turn", h.get("turn", 1.0))) * 100.0) if cdata.has("turn") else "–")
	_stat("Skjold", "%d" % int(ship.shield_max) + (" · %d lag" % int(h["layers"]) if h.has("layers") else ""))
	_stat("Skrog", "%d %%" % int(ship.hull))
	_stat("Panser", "%d %% skade" % int(float(h.get("armor", 1.0)) * 100.0))
	_stat("Last", "%d / %d" % [Game.cargo_total(Game.wallet.get("cargo", {})), int(Game.wallet.get("cargo_max", 0))])
	_stat("Pladser", "%d våben · %d gadgets · %d kanoner" % [Game.slot_count(cls, "vaaben"), Game.slot_count(cls, "gadget"), (h.get("guns", []) as Array).size()])
	_left.add_child(HSeparator.new())
	# Den valgte plads
	var f := Game.fit_for(cls)
	var sel_slot: String = _sel[0]
	var sel_idx: int = _sel[1]
	if not f.has(sel_slot):
		return
	var vals: Array = f[sel_slot] if f[sel_slot] is Array else [f[sel_slot]]
	if sel_idx >= vals.size():
		sel_idx = 0
		_sel[1] = 0
	var cur := str(vals[sel_idx])
	_left.add_child(UiTheme.caption(_slot_title(sel_slot, sel_idx), SLOT_COL.get(sel_slot, UiTheme.MUTED)))
	var it := Game.part(cur)
	if it.is_empty():
		_left.add_child(UiTheme.value("– tom plads –", UiTheme.MUTED, 16))
		_left.add_child(_wrap(UiTheme.value("Træk en del hertil fra lageret, eller vælg en til højre.", UiTheme.MUTED, 13)))
	else:
		_left.add_child(UiTheme.value(str(it["name"]), UiTheme.TEXT, 17))
		_left.add_child(_wrap(UiTheme.value(str(it["desc"]), UiTheme.MUTED, 13)))
		for line in part_lines(it):
			_left.add_child(UiTheme.value("· " + line, UiTheme.TEXT, 13))
	if sel_slot == "vaaben" and cur != "":
		var grp := int((f["grupper"] as Array)[sel_idx])
		var gb := Button.new()
		gb.text = "SEKUNDÆR · højreklik" if grp == 1 else "PRIMÆR · venstreklik"
		gb.tooltip_text = "Skift våbengruppe (kan gøres overalt)"
		gb.pressed.connect(func(): Game.request_weapon_group(sel_idx, 1 - grp))
		_left.add_child(gb)
	if editable() and cur != "" and int(it.get("price", 0)) > 0:
		var ub := Button.new()
		ub.text = "AFMONTÉR → LAGER"
		ub.pressed.connect(func(): Game.request_unequip(loc_id, sel_slot, sel_idx))
		_left.add_child(ub)


func _stat(label: String, val: String) -> void:
	var r := HBoxContainer.new()
	var a := UiTheme.value(label, UiTheme.MUTED, 13)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(a)
	r.add_child(UiTheme.value(val, UiTheme.TEXT, 13))
	_left.add_child(r)


static func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(240, 0)
	return l


func _slot_title(slot: String, idx: int) -> String:
	var t := str(Game.equipment["slots"][slot])
	if slot in Game.equipment["multi"]:
		t += " %d" % (idx + 1)
	return t


## Talværdier for en del (til panelet og kasserne).
static func part_lines(it: Dictionary) -> Array[String]:
	var out: Array[String] = []
	match str(it.get("slot", "")):
		"vaaben":
			if it.get("beam", false):
				out.append("Stråle · %d m · %.1f skade/s" % [int(it.get("beam_range", 240)), float(it.get("dps", 7.0))])
				out.append("Varm efter %.1f s" % float(it.get("heat_time", 3.0)))
			else:
				out.append("Skade pr. skud %.2f×" % float(it.get("dmg_mult", 1.0)))
				out.append("Ladetid %.2f×" % float(it.get("cd_mult", 1.0)))
				if int(it.get("bolts", 1)) > 1:
					out.append("%d skud ad gangen" % int(it["bolts"]))
				if int(it.get("salvo", 1)) > 1:
					out.append("Salve på %d" % int(it["salvo"]))
			var eff := {1: "Ion: lammer og slår skjolde ned", 2: "Flak: nærhedsrør og sprængning", 3: "Krystal: går gennem skjolde"}
			if eff.has(int(it.get("effect", 0))):
				out.append(eff[int(it["effect"])])
		"skjold":
			out.append("Skjold %d %%" % int(float(it.get("shield_mult", 1.0)) * 100.0))
			out.append("Opladning %d %%" % int(float(it.get("regen_mult", 1.0)) * 100.0))
			if it.has("layers"):
				out.append("%d lag" % int(it["layers"]))
		"motor":
			out.append("Topfart %d %%" % int(float(it.get("speed_mult", 1.0)) * 100.0))
			out.append("Drejning %d %%" % int(float(it.get("turn_mult", 1.0)) * 100.0))
		"gadget":
			out.append("Aktiv" if it.get("active", false) else "Passiv")
			if it.has("cooldown"):
				out.append("Genopladning %d s" % int(round(float(it["cooldown"]))))
			if it.has("duration"):
				out.append("Varighed %d s" % int(round(float(it["duration"]))))
			if it.has("radius"):
				out.append("Rækkevidde %d m" % int(it["radius"]))
			if float(it.get("power", 1.0)) > 1.0:
				out.append("Styrke %d %%" % int(float(it["power"]) * 100.0))
	return out


# ---------------------------------------------------------------- højre panel

func _build_right() -> void:
	for c in _right.get_children():
		c.queue_free()
	var f := Game.fit_for(ship.ship_class)
	var sel_slot: String = _sel[0]
	var sel_idx: int = _sel[1]
	var stash: Dictionary = Game.parts
	var credits := int(Game.wallet.get("credits", 0))
	if editable():
		var vals: Array = f[sel_slot] if f[sel_slot] is Array else [f[sel_slot]]
		var cur := str(vals[mini(sel_idx, vals.size() - 1)])
		_right.add_child(UiTheme.value("Installér i %s" % _slot_title(sel_slot, sel_idx), UiTheme.YELLOW, 16))
		var any := false
		for pid: String in stash:
			var it := Game.part(pid)
			if it.is_empty() or it["slot"] != sel_slot:
				continue
			any = true
			var row := DragRow.new()
			row.manager = self
			row.item_id = pid
			row.add_child(_name_label("%s  (%d på lager)" % [it["name"], int(stash[pid])], 14))
			var b := Button.new()
			b.text = "INSTALLÉR"
			b.pressed.connect(func(): Game.request_equip(loc_id, pid, sel_idx))
			row.add_child(b)
			_right.add_child(row)
		# Standarddelene (Mk I) er gratis og kan altid installeres i en hangar
		if not can_shop():
			for base: String in Game.equipment["items"]:
				var bi: Dictionary = Game.equipment["items"][base]
				if bi["slot"] == sel_slot and int(bi.get("price", 0)) == 0 and base != cur:
					any = true
					var row := HBoxContainer.new()
					row.add_child(_name_label("%s · gratis" % Game.part(base)["name"], 14))
					var b := Button.new()
					b.text = "INSTALLÉR"
					b.pressed.connect(func(): Game.request_equip(loc_id, base, sel_idx))
					row.add_child(b)
					_right.add_child(row)
		if not any:
			_right.add_child(UiTheme.caption("Intet af den slags på lageret"))
		if can_shop():
			_right.add_child(UiTheme.caption("Forhandler · køb og montér", UiTheme.PINK))
			for base: String in Game.equipment["items"]:
				var bi: Dictionary = Game.equipment["items"][base]
				if bi["slot"] != sel_slot:
					continue
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 4)
				var nl := _name_label(str(bi["name"]), 13)
				nl.custom_minimum_size = Vector2(110, 0)
				nl.tooltip_text = str(bi["desc"])
				nl.mouse_filter = Control.MOUSE_FILTER_PASS
				row.add_child(nl)
				for mk in range(1, Game.MK_MAX + 1):
					var pid := Game.part_id(base, mk)
					var it := Game.part(pid)
					var b := Button.new()
					var price := int(it["price"])
					b.text = "%s %s" % [Game.MK_NAMES[mk].replace("Mk ", ""), ("✔" if pid == cur else (str(price) if price > 0 else "gratis"))]
					b.custom_minimum_size = Vector2(76, 0)
					b.add_theme_font_size_override("font_size", 11)
					b.add_theme_stylebox_override("normal", _small_box(UiTheme.YELLOW))
					b.add_theme_stylebox_override("hover", _small_box(Color("ffe680")))
					b.add_theme_stylebox_override("pressed", _small_box(UiTheme.YELLOW))
					b.add_theme_stylebox_override("disabled", _small_box(UiTheme.PANEL_2))
					var locked := not Game.mk_allowed(mk) and not Game.test_mode
					b.disabled = pid == cur or locked or credits < price
					b.tooltip_text = "%s · %d cr%s\n%s" % [it["name"], price, ("\nKræver rang %s" % Game.mission_data["ranks"][Game.MK_RANK[mk]]["name"]) if locked else "", "\n".join(part_lines(it))]
					b.pressed.connect(func(): Game.request_equip(loc_id, pid, sel_idx))
					row.add_child(b)
				_right.add_child(row)
	# Lager (træk hertil for at afmontere)
	var zone := DropZone.new()
	zone.manager = self
	var zv := VBoxContainer.new()
	zv.add_theme_constant_override("separation", 4)
	zone.add_child(zv)
	_right.add_child(zone)
	var n := 0
	for k: String in stash:
		n += int(stash[k])
	zv.add_child(UiTheme.value("Lager · %d dele" % n, UiTheme.YELLOW, 16))
	zv.add_child(UiTheme.caption("Følger piloten · træk en plads hertil for at afmontere" if editable() else "Følger piloten"))
	for pid: String in stash:
		var it := Game.part(pid)
		if it.is_empty():
			continue
		var row := DragRow.new()
		row.manager = self
		row.item_id = pid
		var dot := ColorRect.new()
		dot.color = SLOT_COL.get(it["slot"], UiTheme.MUTED)
		dot.custom_minimum_size = Vector2(6, 18)
		dot.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(dot)
		row.add_child(_name_label("%d × %s" % [int(stash[pid]), it["name"]], 13))
		if can_shop():
			var sb := Button.new()
			sb.text = "SÆLG %d" % (int(it["price"]) / 2)
			sb.pressed.connect(func(): Game.request_sell_part(loc_id, pid))
			row.add_child(sb)
		zv.add_child(row)
	if n == 0:
		zv.add_child(UiTheme.value("Tomt", UiTheme.MUTED, 13))
	# Last
	_right.add_child(HSeparator.new())
	var cargo: Dictionary = Game.wallet.get("cargo", {})
	_right.add_child(UiTheme.value("Last · %d / %d" % [Game.cargo_total(cargo), int(Game.wallet.get("cargo_max", 0))], UiTheme.YELLOW, 16))
	if cargo.is_empty():
		_right.add_child(UiTheme.value("Lastrummet er tomt", UiTheme.MUTED, 13))
	for good: String in cargo:
		var g: Dictionary = Game.goods.get(good, {})
		_right.add_child(UiTheme.value("%d × %s" % [int(cargo[good]), g.get("name", good)], UiTheme.TEXT, 13))
	# Lange tekster brydes, så panelet holder sin bredde
	for l in _right.find_children("*", "Label", true, false):
		if not (l as Label).clip_text:
			(l as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


static func _small_box(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


static func _name_label(text: String, size: int) -> Label:
	var l := UiTheme.value(text, UiTheme.TEXT, size)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


# ---------------------------------------------------------------- træk og slip

func can_drop_on_slot(b: SlotBox, data: Variant) -> bool:
	if not editable() or not (data is Dictionary):
		return false
	var d: Dictionary = data
	if d.get("kind", "") == "stash":
		return str(Game.part(str(d["id"])).get("slot", "")) == b.slot
	if d.get("kind", "") == "slot":
		return d["slot"] == b.slot and int(d["idx"]) != b.idx and b.slot in Game.equipment["multi"]
	return false


func drop_on_slot(b: SlotBox, data: Dictionary) -> void:
	if data.get("kind", "") == "stash":
		Game.request_equip(loc_id, str(data["id"]), b.idx)
	elif data.get("kind", "") == "slot":
		Game.request_move(loc_id, b.slot, int(data["idx"]), b.idx)
	_sel = [b.slot, b.idx]


func drop_on_stash(data: Dictionary) -> void:
	if data.get("kind", "") == "slot":
		Game.request_unequip(loc_id, str(data["slot"]), int(data["idx"]))


## En plads på skibet: kasse med pladsens navn, delen og dens Mk.
class SlotBox extends Control:
	var manager: ShipManager
	var slot := ""
	var idx := 0
	var item_id := ""
	var multi := false
	var group := 0
	var anchor3d := Vector3.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			manager.select(slot, idx)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if not manager.editable() or item_id == "":
			return null
		if int(Game.part(item_id).get("price", 0)) == 0 and not (slot in Game.equipment["multi"]):
			return null     # standardskjold og -motor kan ikke tages af
		var l := UiTheme.value(str(Game.part(item_id).get("name", "")), UiTheme.YELLOW, 15)
		set_drag_preview(l)
		return {"kind": "slot", "slot": slot, "idx": idx, "id": item_id}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return manager.can_drop_on_slot(self, data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		manager.drop_on_slot(self, data)

	func _draw() -> void:
		var font := get_theme_default_font()
		var col: Color = ShipManager.SLOT_COL.get(slot, UiTheme.MUTED)
		var sel := manager.is_selected(self)
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.PANEL, 0.92))
		draw_rect(Rect2(Vector2.ZERO, Vector2(5, size.y)), col)
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.YELLOW if sel else Color(col, 0.6), false, 3.0 if sel else 1.5)
		var title := str(Game.equipment["slots"][slot]).to_upper()
		if multi:
			title += " %d" % (idx + 1)
		if slot == "vaaben" and item_id != "":
			title += "  · " + ("S" if group == 1 else "P")
		var it := Game.part(item_id)
		if slot == "gadget" and it.get("active", false):
			title += "  [%s]" % Game.key_name("gadget_%d" % (idx + 1))
		draw_string(font, Vector2(12, 16), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, 11, col)
		if it.is_empty():
			draw_string(font, Vector2(12, 38), "– tom –", HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 15, UiTheme.MUTED)
			return
		draw_string(font, Vector2(12, 38), str(it["base_name"]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 15, UiTheme.TEXT)
		# Mk-mærke
		var mk := int(it.get("mk", 1))
		var badge := Rect2(size.x - 46, 5, 40, 16)
		draw_rect(badge, [UiTheme.MUTED, UiTheme.MUTED, UiTheme.CYAN, UiTheme.YELLOW][mk])
		draw_string(font, badge.position + Vector2(0, 12), Game.MK_NAMES[mk].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 10, UiTheme.INK)
		var lines := ShipManager.part_lines(it)
		if not lines.is_empty():
			draw_string(font, Vector2(12, 55), lines[0], HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 10, UiTheme.MUTED)

	func _process(_d: float) -> void:
		queue_redraw()


## Streger fra kasserne ind til pladserne på skibet.
class LineLayer extends Control:
	var manager: ShipManager

	func _draw() -> void:
		for b in manager._boxes:
			var p := manager.screen_of(b.anchor3d)
			var r := Rect2(b.position, b.size)
			var from := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
			var col: Color = ShipManager.SLOT_COL.get(b.slot, UiTheme.MUTED)
			var sel := manager.is_selected(b)
			draw_line(from, p, Color(UiTheme.INK, 0.8), 4.0 if sel else 3.0)
			draw_line(from, p, Color(col, 1.0 if sel else 0.75), 2.0 if sel else 1.5)
			draw_circle(p, 5.0 if sel else 4.0, UiTheme.INK)
			draw_circle(p, 3.5 if sel else 2.5, col)


## En linje på lageret, der kan trækkes over på en plads.
class DragRow extends HBoxContainer:
	var manager: ShipManager
	var item_id := ""

	func _get_drag_data(_at: Vector2) -> Variant:
		if not manager.editable():
			return null
		set_drag_preview(UiTheme.value(str(Game.part(item_id).get("name", "")), UiTheme.YELLOW, 15))
		return {"kind": "stash", "id": item_id}


## Lageret som mål: træk en plads hertil for at afmontere.
class DropZone extends PanelContainer:
	var manager: ShipManager

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return manager.editable() and data is Dictionary and data.get("kind", "") == "slot"

	func _drop_data(_at: Vector2, data: Variant) -> void:
		manager.drop_on_stash(data)
