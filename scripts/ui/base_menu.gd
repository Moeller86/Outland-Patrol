class_name BaseMenu
extends Control
## Menuen ved en byggegrund / gruppens egen base: køb grunden, byg moduler, hent
## varer fra lageret, reparer og brug hangaren. Alt går gennem værten (W.bases.request).

signal launch_requested

var plot_id := ""

var _title: Label
var _sub: Label
var _status: Label
var _art: TextureRect
var _left_info: Label
var _left_box: VBoxContainer
var _right: VBoxContainer
var _launch: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(940, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UiTheme.value("", UiTheme.YELLOW, 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_sub = UiTheme.caption("")
	head.add_child(_sub)
	_status = UiTheme.value("", UiTheme.CYAN, 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	_left_box = VBoxContainer.new()
	row.add_child(_left_box)
	_art = TextureRect.new()
	_art.custom_minimum_size = Vector2(384, 216)
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_left_box.add_child(_art)
	_left_info = UiTheme.value("", UiTheme.TEXT, 14)
	_left_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_info.custom_minimum_size = Vector2(384, 0)
	_left_box.add_child(_left_info)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 420)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 6)
	scroll.add_child(_right)
	var mgr := Button.new()
	mgr.text = "RUMSKIBSMANAGER (U) · flyt og installér udstyr fra lageret"
	mgr.pressed.connect(func(): get_tree().call_group("ship_manager", "open_here", plot_id))
	v.add_child(mgr)
	_launch = Button.new()
	_launch.text = "ENTER  AFGANG ▲"
	_launch.pressed.connect(func(): launch_requested.emit())
	v.add_child(_launch)
	Game.world_changed.connect(func(): if visible: _refresh())
	Game.wallet_changed.connect(func(): if visible: _refresh())


func open(id: String) -> void:
	plot_id = id
	visible = true
	_refresh()
	_launch.grab_focus()


func close() -> void:
	visible = false
	plot_id = ""


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("launch"):
		get_viewport().set_input_as_handled()
		launch_requested.emit()


func _btn(text: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.pressed.connect(cb)
	return b


func _refresh() -> void:
	if plot_id == "":
		return
	var B := W.bases
	var plot := Game.plot_data(plot_id)
	var st := Game.base_state(plot_id)
	var res: String = plot["resource"]
	var res_name := Game.good_name(res).to_lower()
	var w: Dictionary = Game.wallet
	var credits := int(w["credits"])
	var owned: bool = st.get("owned", false)
	var where := ""
	if plot["kind"] == "ground":
		where = W.universe.planet(plot["planet"]).display_name
	else:
		where = str(Game.systems[plot["system"]]["name"]) + " · i rummet"
	_title.text = ("GRUPPENS BASE · " if owned else "") + str(plot["name"]).to_upper()
	_sub.text = where.to_upper()
	_art.texture = _make_art(plot, st)
	for c in _right.get_children():
		c.queue_free()
	if not owned:
		_status.text = "Byggegrunden er til salg. Basen bliver fælles for hele gruppen."
		_left_info.text = "Råstof her: %s\nUdvinding giver %s, mens I spiller – også når I er andre steder i universet." % [res_name, res_name]
		_right.add_child(UiTheme.caption("Byggegrund", UiTheme.PINK))
		_right.add_child(UiTheme.value("Køb grunden og byg en base med udvinding, lager, forsvarstårne, skjold og hangar. Pirater vil af og til prøve at plyndre den.", UiTheme.TEXT, 14))
		_right.get_child(_right.get_child_count() - 1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_right.add_child(_btn("KØB BYGGEGRUNDEN · %d cr" % int(plot["price"]), credits >= int(plot["price"]),
			func(): B.request("buy", plot_id)))
		_right.add_child(UiTheme.value("Du har %d cr." % credits, UiTheme.MUTED, 13))
		return
	var hp := float(st.get("hp", 0.0))
	var hpm := B.hp_max(plot_id)
	var status := "Modstand %d/%d" % [int(hp), int(hpm)]
	if hp <= 0.0:
		status += "  ·  UDE AF DRIFT – reparer basen"
	elif B.raid_active(plot_id):
		status += "  ·  ⚠ UNDER ANGREB!"
	_status.text = status
	_status.add_theme_color_override("font_color", UiTheme.DANGER if hp <= 0.0 or B.raid_active(plot_id) else UiTheme.CYAN)
	var stored := int(st.get("storage", 0))
	_left_info.text = "Lager: %d/%d %s\nUdvinding: %d %s i minuttet\nDu har %d cr · lastrum %d/%d" % [stored, B.storage_cap(plot_id), res_name,
		B.production_per_min(plot_id), res_name, credits, Game.cargo_total(w["cargo"]), int(w["cargo_max"])]
	# Lager og tjenester
	_right.add_child(UiTheme.caption("Lager og tjenester", UiTheme.PINK))
	var h := HBoxContainer.new()
	_right.add_child(h)
	h.add_child(_btn("Tag 5 %s" % res_name, stored > 0, func(): B.request("take", plot_id, "5")))
	h.add_child(_btn("Tag alt", stored > 0, func(): B.request("take", plot_id, "all")))
	if hp < hpm:
		_right.add_child(_btn("Reparer basen · %d cr" % int(ceil(hpm - hp)), credits > 0, func(): B.request("repair_base", plot_id)))
	if B.level(plot_id, "hangar") > 0:
		var h2 := HBoxContainer.new()
		_right.add_child(h2)
		h2.add_child(_btn("Reparer skibet · gratis", W.local_ship != null and W.local_ship.hull < 100.0, func(): B.request("repair_ship", plot_id)))
		var have := int(w.get("missiles", 0))
		h2.add_child(_btn("Fyld missiler (%d/%d)" % [have, Game.missile_max()], have < Game.missile_max() and credits >= 15,
			func(): B.request("missiles", plot_id)))
	# Hangar: skift mellem sine egne skibe
	if B.level(plot_id, "hangar") > 0:
		var my_ships: Array = Game.owned_ships()
		_right.add_child(UiTheme.caption("Hangar · dine skibe (%d/%d pladser)" % [my_ships.size(), Game.ship_slots()], UiTheme.PINK))
		var grid := GridContainer.new()
		grid.columns = 2
		_right.add_child(grid)
		for cls: String in my_ships:
			var nm: String = Game.ship_data["classes"][cls]["name"]
			var cur := cls == Game.local_class()
			grid.add_child(_btn(("▶ " if cur else "") + nm, not cur, func(): Game.request_ship(plot_id, cls)))
	# Moduler
	_right.add_child(UiTheme.caption("Moduler", UiTheme.PINK))
	for m: Dictionary in Game.bases_data["modules"]:
		var mid: String = m["id"]
		var lvl := B.level(plot_id, mid)
		var mx := int(m["max"])
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation", 2)
		_right.add_child(line)
		var lv := "" if lvl == 0 else ("  ·  %d/%d" % [lvl, mx])
		line.add_child(UiTheme.value("%s%s" % [m["name"], lv], UiTheme.YELLOW if lvl > 0 else UiTheme.TEXT, 15))
		var d := UiTheme.value(str(m["desc"]), UiTheme.MUTED, 12)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(d)
		if lvl >= mx:
			continue
		var cost := B.module_cost(plot_id, mid)
		var goods: Dictionary = cost["goods"]
		var parts := ["%d cr" % int(cost["credits"])]
		var ok := credits >= int(cost["credits"])
		for g: String in goods:
			var have_g := int(w["cargo"].get(g, 0))
			parts.append("%d %s (%d)" % [int(goods[g]), Game.good_name(g).to_lower(), have_g])
			ok = ok and have_g >= int(goods[g])
		line.add_child(_btn(("BYG" if lvl == 0 else "UDBYG") + " · " + " + ".join(parts), ok, func(): B.request("build", plot_id, mid)))


## Pixelscene af basen: planetens landskab (eller rummet) og de byggede moduler.
func _make_art(plot: Dictionary, st: Dictionary) -> ImageTexture:
	var img := Image.create(192, 108, false, Image.FORMAT_RGBA8)
	var mods: Dictionary = st.get("modules", {})
	if plot["kind"] == "ground":
		SceneArt._landscape(img, Game.locations[plot["planet"]])
	else:
		SceneArt._r(img, 0, 0, 192, 108, Color("120a2e"))
		for i in 60:
			img.set_pixel((i * 37) % 192, (i * 23) % 108, [Color.WHITE, Color("9fe2ff"), Color("ff9ed2")][i % 3])
	if not st.get("owned", false):
		for x in [20, 70, 120, 170]:
			SceneArt._r(img, x, 70, 2, 12, Color("ffd23f"))
			SceneArt._r(img, x - 1, 68, 4, 3, Color("6bdc4f"))
		return ImageTexture.create_from_image(img)
	var x := 8
	for k in int(mods.get("udvinding", 0)):
		for y in range(40, 80, 5):
			SceneArt._r(img, x, y, 12, 1, Color("ffd23f"))
		SceneArt._r(img, x, 40, 1, 40, Color("ffd23f"))
		SceneArt._r(img, x + 11, 40, 1, 40, Color("ffd23f"))
		SceneArt._r(img, x + 5, 34, 2, 6, Color("ff3b3b"))
		x += 18
	for k in int(mods.get("lager", 0)):
		SceneArt._r(img, x, 56, 8, 24, Color("e6ecff"))
		SceneArt._r(img, x + 10, 56, 8, 24, Color("e6ecff"))
		SceneArt._r(img, x, 64, 18, 2, Color("ffd23f"))
		x += 22
	if int(mods.get("hangar", 0)) > 0:
		SceneArt._r(img, x, 58, 30, 22, Color("2e6bd6"))
		SceneArt._r(img, x + 8, 66, 14, 14, Color("1a1028"))
		x += 34
	if int(mods.get("skjold", 0)) > 0:
		for a in 40:
			var t := a / 40.0 * PI
			img.set_pixel(clampi(96 + int(cos(t) * 90.0), 0, 191), clampi(82 - int(sin(t) * 60.0), 0, 107), Color("9ff2ff"))
	for k in int(mods.get("taarn", 0)):
		SceneArt._r(img, 150 + k * 10, 66, 6, 14, Color("5a5f8a"))
		SceneArt._r(img, 149 + k * 10, 62, 8, 4, Color("6bdc4f"))
	SceneArt._pad_and_ship(img, 84)
	return ImageTexture.create_from_image(img)
