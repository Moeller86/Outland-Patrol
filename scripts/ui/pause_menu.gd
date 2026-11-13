class_name PauseMenu
extends Control
## ESC-menuen: fortsæt, genstart missionen, indstillinger, taster, start forfra,
## til startskærmen og afslut. Solo sættes spillet på pause; i co-op kører det videre.

signal resumed

var main: Node                     ## main.gd (kaldes for indstillinger og genstart)
var _pages: Dictionary = {}
var _page := ""
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _waiting_action := ""          ## handling, der venter på en ny tast
var _key_buttons: Dictionary = {}
var _note: Label
var _restart_btn: Button
var _save_btn: Button
var _test_btn: Button
var _test_check: CheckButton
var _new_pilot_btn: Button
var _coop_label: Label
var _confirm_text: Label
var _confirm_fn: Callable

# Indstillinger
var _fullscreen: CheckButton
var _pixel: OptionButton
var _dither: OptionButton
var _sens: HSlider
var _sens_label: Label
var _invert: CheckButton
var _cockpit: CheckButton
var _music: CheckButton
var _music_vol: HSlider
var _sfx: CheckButton
var _sfx_vol: HSlider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 10)
	panel.add_child(holder)
	_pages["main"] = _build_main()
	_pages["settings"] = _build_settings()
	_pages["keys"] = _build_keys()
	_pages["confirm"] = _build_confirm()
	_pages["test"] = _build_test()
	for p: Control in _pages.values():
		holder.add_child(p)
	_note = UiTheme.value("", UiTheme.YELLOW, 14)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(_note)


# ---------------------------------------------------------------- åbn/luk

func open() -> void:
	if visible:
		return
	_prev_mouse = Input.mouse_mode
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.is_online:
		get_tree().paused = true
	_show("main")
	Sfx.play("klik", -2.0, 0.0)


func close() -> void:
	if not visible:
		return
	_waiting_action = ""
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _prev_mouse
	resumed.emit()


func _show(page: String) -> void:
	_page = page
	for k: String in _pages:
		(_pages[k] as Control).visible = k == page
	_note.text = ""
	match page:
		"main":
			var can_restart: bool = W.missions != null and W.missions.active and multiplayer.is_server()
			_restart_btn.disabled = not can_restart
			_restart_btn.text = "GENSTART MISSIONEN" + ("" if can_restart else "  (ingen mission)")
			_new_pilot_btn.disabled = Net.is_online
			_coop_label.visible = Net.is_online
			_test_btn.visible = Game.test_mode
		"settings":
			_sync_settings()
		"keys":
			_refresh_keys()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	if _waiting_action != "":
		get_viewport().set_input_as_handled()
		if key == KEY_ESCAPE:
			_waiting_action = ""
			_refresh_keys()
			return
		var lost := Game.rebind(_waiting_action, key)
		var name := _action_name(_waiting_action)
		_waiting_action = ""
		_refresh_keys()
		main.save_settings()
		_note.text = "%s: %s" % [name, OS.get_keycode_string(key)]
		if lost != "":
			_note.text += "  ·  (fjernet fra \"%s\")" % _action_name(lost)
		return
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _page == "main":
			close()
		else:
			_show("main")


# ---------------------------------------------------------------- hovedside

func _build_main() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiTheme.caption("Concord Patrol · Pause"))
	v.add_child(UiTheme.value("MENU", UiTheme.YELLOW, 30))
	_coop_label = UiTheme.caption("Co-op: spillet kører videre for de andre piloter, mens menuen er åben", UiTheme.CYAN)
	v.add_child(_coop_label)
	_button(v, "FORTSÆT  ▶", close)
	_restart_btn = _button(v, "GENSTART MISSIONEN", func():
		close()
		main.restart_mission())
	_save_btn = _button(v, "GEM SPILLET  (F6)", func():
		if main.save_game():
			_note.text = "Spillet er gemt kl. %s · det gemmes også automatisk, når noget ændrer sig" % main.last_saved
		else:
			_note.text = "Kun værten kan gemme – dit fremskridt gemmes hos værten")
	_test_btn = _button(v, "TESTVÆRKTØJER  ⚙", func(): _show("test"))
	_button(v, "INDSTILLINGER", func(): _show("settings"))
	_button(v, "TASTER OG STYRING", func(): _show("keys"))
	_new_pilot_btn = _button(v, "START FORFRA SOM NY PILOT", func():
		_ask("Start forfra som ny pilot \"%s\"? Kreditter, rang, skibe og opgraderinger for denne pilot slettes. Andre piloter og dine baser bevares." % Net.local_name,
			func():
				close()
				main.restart_as_new_pilot()))
	_button(v, "TIL STARTSKÆRMEN", func():
		_ask("Tilbage til startskærmen? Dit spil gemmes.", func():
			close()
			main.to_title()))
	_button(v, "AFSLUT SPILLET", func():
		_ask("Afslut Outland Patrol? Dit spil gemmes.", func():
			Game.server_save()
			get_tree().quit()))
	return v


func _build_confirm() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(UiTheme.caption("Er du sikker?"))
	_confirm_text = UiTheme.value("", UiTheme.TEXT, 16)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(560, 0)
	v.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var yes := Button.new()
	yes.text = "JA"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func():
		if _confirm_fn.is_valid():
			_confirm_fn.call())
	row.add_child(yes)
	var no := Button.new()
	no.text = "NEJ, TILBAGE"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func(): _show("main"))
	row.add_child(no)
	return v


func _ask(text: String, fn: Callable) -> void:
	_confirm_text.text = text
	_confirm_fn = fn
	_show("confirm")


# ---------------------------------------------------------------- indstillinger

func _build_settings() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UiTheme.value("INDSTILLINGER", UiTheme.YELLOW, 26))
	v.add_child(UiTheme.caption("Grafik"))
	var g := _grid(v)
	_fullscreen = _check(g, "Fuldskærm (F11)", func(on: bool): main.set_fullscreen(on))
	_pixel = _option(g, "Pixelstørrelse (F2)", main.PIXEL_PRESETS.map(func(p): return p["name"]), func(i: int): main.set_pixel_mode(i))
	_dither = _option(g, "Dithering (F3)", main.DITHER_PRESETS.map(func(p): return p["name"]), func(i: int): main.set_dither_mode(i))
	v.add_child(UiTheme.caption("Styring og kamera"))
	g = _grid(v)
	g.add_child(_label("Musens følsomhed (+/−)"))
	var sr := HBoxContainer.new()
	_sens = HSlider.new()
	_sens.min_value = 0.5
	_sens.max_value = 2.0
	_sens.step = 0.05
	_sens.custom_minimum_size = Vector2(220, 0)
	_sens_label = UiTheme.value("", UiTheme.CYAN, 14)
	_sens.value_changed.connect(func(x: float):
		Game.mouse_sensitivity = x
		_sens_label.text = "%d %%" % roundi(x * 100.0)
		main.save_settings())
	sr.add_child(_sens)
	sr.add_child(_sens_label)
	g.add_child(sr)
	_invert = _check(g, "Inverter musens op/ned", func(on: bool):
		Game.invert_y = on
		main.save_settings())
	_test_check = _check(g, "Testtilstand (alle skibe, testværktøjer)", func(on: bool):
		Game.test_mode = on
		main.save_settings()
		_note.text = "Testtilstand %s – skibsvalget på startskærmen skifter ved næste start" % ("slået til" if on else "slået fra"))
	_cockpit = _check(g, "Cockpitvisning (V)", func(on: bool):
		if main.camera.first_person != on:
			main.camera.set_first_person(on)
		main.save_settings())
	v.add_child(UiTheme.caption("Lyd"))
	g = _grid(v)
	_music = _check(g, "Musik (F4)", func(on: bool):
		Sfx.set_music(on)
		main.save_settings())
	_music_vol = _slider(g, "Musikkens lydstyrke", func(x: float): main.set_volume("Musik", x))
	_sfx = _check(g, "Lydeffekter (F5)", func(on: bool):
		Sfx.set_sfx(on)
		main.save_settings())
	_sfx_vol = _slider(g, "Effekternes lydstyrke", func(x: float): main.set_volume("Effekter", x))
	_button(v, "◀ TILBAGE", func(): _show("main"))
	return v


func _sync_settings() -> void:
	_fullscreen.set_pressed_no_signal(main.fullscreen)
	_pixel.select(main.pixel_mode)
	_dither.select(main.dither_mode)
	_sens.set_value_no_signal(Game.mouse_sensitivity)
	_sens_label.text = "%d %%" % roundi(Game.mouse_sensitivity * 100.0)
	_invert.set_pressed_no_signal(Game.invert_y)
	_test_check.set_pressed_no_signal(Game.test_mode)
	_cockpit.set_pressed_no_signal(main.camera.first_person)
	_music.set_pressed_no_signal(Sfx.music_on)
	_sfx.set_pressed_no_signal(Sfx.sfx_on)
	_music_vol.set_value_no_signal(main.get_volume("Musik"))
	_sfx_vol.set_value_no_signal(main.get_volume("Effekter"))


# ---------------------------------------------------------------- testværktøjer

func _build_test() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UiTheme.value("TESTVÆRKTØJER", UiTheme.YELLOW, 26))
	v.add_child(UiTheme.caption("Kun til test, mens spillet bygges · slås fra under Indstillinger"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var tools := [
		["FYLD ALT OP  (missiler, bomber, flares, skrog)", func(): _fill_all()],
		["ALLE OPGRADERINGER PÅ MAX", func(): Game.request_test("upgrades")],
		["+10.000 KREDIT", func(): Game.request_test("credits")],
		["+500 XP (RANG)", func(): Game.request_test("rank")],
		["ALLE SKIBE I HANGAREN", func(): Game.request_test("all_ships")],
		["LÅS BASEMODULER OP", func(): Game.request_test("unlock_base")],
		["ALLE VÅBEN OG GADGETS PÅ LAGERET", func(): Game.request_test("parts")],
	]
	for t: Array in tools:
		var b := Button.new()
		b.text = t[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(t[1])
		g.add_child(b)
	v.add_child(UiTheme.caption("Skift skib med det samme"))
	var sg := GridContainer.new()
	sg.columns = 4
	sg.add_theme_constant_override("h_separation", 6)
	sg.add_theme_constant_override("v_separation", 6)
	v.add_child(sg)
	for cls: String in Game.ship_data["order"]:
		var b := Button.new()
		b.text = str(Game.ship_data["classes"][cls]["name"]).replace("Frontier-", "").get_slice("-", 0).to_upper()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c := cls
		b.pressed.connect(func():
			Game.request_test("ship", c)
			_note.text = "Skifter til %s" % Game.ship_data["classes"][c]["name"])
		sg.add_child(b)
	v.add_child(UiTheme.caption("Send pirater ud tæt på dig (i rummet)"))
	var pg := GridContainer.new()
	pg.columns = 4
	pg.add_theme_constant_override("h_separation", 6)
	pg.add_theme_constant_override("v_separation", 6)
	v.add_child(pg)
	var pir := [["BLANDET BØLGE", "bolge"], ["☠ KAPTAJN", "kaptajn"]]
	for t: String in ["rover", "jaeger", "kanonbaad", "missilbaad", "skygge"]:
		pir.append([str(Pirates.TYPES[t]["name"]).to_upper(), t])
	for e: Array in pir:
		var b := Button.new()
		b.text = e[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var what: String = e[1]
		b.pressed.connect(func():
			Game.request_test("pirates", what)
			_note.text = "Pirater på vej …")
		pg.add_child(b)
	_button(v, "◀ TILBAGE", func(): _show("main"))
	return v


## Fyld missiler (hos værten), bomber og flares (lokalt) og reparér skibet.
func _fill_all() -> void:
	Game.request_test("ammo")
	if W.bombs:
		W.bombs.ammo = Bombs.ISSUED
	if W.missiles:
		W.missiles.flare_cool = 0.0
	var s: Ship = main.local_ship
	if s and is_instance_valid(s) and not s.dead:
		s.hull = 100.0
		s.shield = s.shield_max
	_note.text = "Fyldt op: missiler, %d bomber, flares klar, skrog og skjold fulde" % Bombs.ISSUED


# ---------------------------------------------------------------- taster

func _build_keys() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UiTheme.value("TASTER OG STYRING", UiTheme.YELLOW, 26))
	v.add_child(UiTheme.caption("Klik på en tast og tryk den nye · ESC fortryder"))
	# Alle handlinger i to spalter, så de kan ses uden at rulle
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	inner.add_child(g)
	for pair: Array in Game.ACTION_NAMES:
		var action: String = pair[0]
		var l := _label(pair[1])
		l.custom_minimum_size = Vector2(215, 0)
		g.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(190, 0)
		b.pressed.connect(func():
			_waiting_action = action
			_refresh_keys())
		g.add_child(b)
		_key_buttons[action] = b
	inner.add_child(UiTheme.caption("Mus og faste taster"))
	var fixed := GridContainer.new()
	fixed.columns = 4
	fixed.add_theme_constant_override("h_separation", 16)
	inner.add_child(fixed)
	for pair in [["Mus", "Styr skibet · kanonerne følger markøren"], ["Venstre museknap", "Skyd"],
			["Højre museknap (hold)", "Rul med musen"], ["Højre museknap (kort klik)", "Lås mål"], ["Midterste museknap", "Missil"],
			["Musehjul", "Zoom · helt ind = cockpit"], ["ESC", "Denne menu"], ["F2 / F3", "Pixelstørrelse / dithering"],
			["F4 / F5", "Musik / lydeffekter"], ["F11", "Fuldskærm"], ["F7", "Markører: alle / færre / kun mål"], ["F6", "Gem spillet"], ["F9", "Vis ydelse (FPS og hak)"], ["+ / −", "Musens følsomhed"]]:
		var a := _label(pair[0])
		a.add_theme_color_override("font_color", UiTheme.CYAN)
		a.custom_minimum_size = Vector2(190, 0)
		fixed.add_child(a)
		var d := _label(pair[1])
		d.custom_minimum_size = Vector2(230, 0)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fixed.add_child(d)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var back := Button.new()
	back.text = "◀ TILBAGE"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): _show("main"))
	row.add_child(back)
	var reset := Button.new()
	reset.text = "STANDARDTASTER"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		Game.reset_keys()
		main.save_settings()
		_refresh_keys()
		_note.text = "Alle taster er sat tilbage til standard")
	row.add_child(reset)
	return v


func _refresh_keys() -> void:
	for action: String in _key_buttons:
		var b: Button = _key_buttons[action]
		if action == _waiting_action:
			b.text = "» TRYK EN TAST «"
		else:
			var names: Array[String] = []
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey:
					names.append(OS.get_keycode_string((ev as InputEventKey).physical_keycode))
			b.text = " / ".join(names) if not names.is_empty() else "–"


func _action_name(action: String) -> String:
	for pair: Array in Game.ACTION_NAMES:
		if pair[0] == action:
			return pair[1]
	return action


# ---------------------------------------------------------------- små byggeklodser

func _button(parent: Control, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _grid(parent: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 6)
	parent.add_child(g)
	return g


func _label(text: String) -> Label:
	var l := UiTheme.value(text, UiTheme.TEXT, 15)
	l.custom_minimum_size = Vector2(250, 0)
	return l


func _check(g: GridContainer, text: String, fn: Callable) -> CheckButton:
	g.add_child(_label(text))
	var c := CheckButton.new()
	c.toggled.connect(fn)
	g.add_child(c)
	return c


func _option(g: GridContainer, text: String, items: Array, fn: Callable) -> OptionButton:
	g.add_child(_label(text))
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.item_selected.connect(fn)
	g.add_child(o)
	return o


func _slider(g: GridContainer, text: String, fn: Callable) -> HSlider:
	g.add_child(_label(text))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(220, 0)
	s.value_changed.connect(fn)
	g.add_child(s)
	return s
