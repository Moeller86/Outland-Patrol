class_name TitleScreen
extends Control
## Startskærm: pilotnavn, og valg mellem solo, at være vært (host) eller at joine en ven.

signal solo_pressed(pilot: String)
signal host_pressed(pilot: String, port: int)
signal join_pressed(pilot: String, address: String, port: int)
## Testknap: start solo direkte i en mission (skabelonens id).
signal test_mission_pressed(pilot: String, template_id: String)

var _name: LineEdit
var _address: LineEdit
var _port: LineEdit
var _status: Label
var _ship_btns: Dictionary = {}
var _ship_name: Label
var _ship_desc: Label
var _ship_bars: VBoxContainer
var _preview_root: Node3D
var _preview_model: ShipModel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var title := UiTheme.value("OUTLAND PATROL", UiTheme.YELLOW, 40)
	title.add_theme_color_override("font_shadow_color", UiTheme.PINK)
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	v.add_child(title)
	var sub := UiTheme.value("Concord Patrol · the Reach. Tag korte missioner på 5–15 minutter, forsvar Concords planeter, og stig i rang. Alene eller op til 4 piloter i co-op.", UiTheme.CYAN, 16)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)

	v.add_child(UiTheme.caption("Pilotnavn"))
	_name = LineEdit.new()
	_name.text = "Pilot"
	_name.max_length = 16
	v.add_child(_name)
	_build_ship_picker(v)

	var solo := Button.new()
	solo.text = "SPIL ALENE  ▶"
	solo.pressed.connect(func(): solo_pressed.emit(_pilot()))
	v.add_child(solo)

	v.add_child(UiTheme.caption("Test – start direkte i en angrebsmission"))
	var trow := HBoxContainer.new()
	v.add_child(trow)
	for t in [["assault_frosta", "ISFÆSTNINGEN"], ["assault_korvus", "RAVNEKLØFTEN"]]:
		var tb := Button.new()
		tb.text = "▶ " + t[1]
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tid: String = t[0]
		tb.pressed.connect(func(): test_mission_pressed.emit(_pilot(), tid))
		trow.add_child(tb)

	v.add_child(UiTheme.caption("Co-op"))
	var row := HBoxContainer.new()
	v.add_child(row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Værtens IP"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_address)
	_port = LineEdit.new()
	_port.text = str(Net.DEFAULT_PORT)
	_port.custom_minimum_size = Vector2(90, 0)
	row.add_child(_port)
	var btns := HBoxContainer.new()
	v.add_child(btns)
	var host := Button.new()
	host.text = "HOST CO-OP"
	host.pressed.connect(func(): host_pressed.emit(_pilot(), int(_port.text)))
	btns.add_child(host)
	var join := Button.new()
	join.text = "JOIN VEN"
	join.pressed.connect(func(): join_pressed.emit(_pilot(), _address.text.strip_edges(), int(_port.text)))
	btns.add_child(join)

	_status = UiTheme.value("", UiTheme.MUTED, 14)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)

	var keys := UiTheme.value("MUS styr · KLIK/SPACE primære våben · HØJREKLIK/CTRL sekundære våben · W/S fart · SHIFT afterburner · X cruise · A/D sidelæns · Q/E rul · R lås nærmeste fjende · T næste mål · C scan · G/midterklik missil · B bombe · F flares · M kort · L land/dock · ENTER afgang · F2 pixelstørrelse · F3 dithering · F4 musik · F5 lyd · +/- styrefølsomhed · HJUL zoom · V cockpit · I lastrum · F6 gem · ESC menu · F11 fuldskærm", UiTheme.MUTED, 11)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(keys)
	var goal := UiTheme.value("Du starter i hangaren på Bastion Kepler, Concord Patrols hovedkvarter. Vælg en mission på tavlen, og tryk ENTER for at lette.", UiTheme.GREEN, 13)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(goal)


## Valg af startskib med en lille 3D-forhåndsvisning, der drejer rundt.
func _build_ship_picker(v: VBoxContainer) -> void:
	v.add_child(UiTheme.caption("TEST: vælg frit mellem alle skibe" if Game.test_mode else "Startskib (nye piloter – kendte piloter flyver videre i deres eget)"))
	var row := GridContainer.new()
	row.columns = 6
	v.add_child(row)
	for cls: String in (Game.ship_data["order"] if Game.test_mode else Game.ship_data.get("start", Game.ship_data["order"])):
		var b := Button.new()
		b.text = str(Game.ship_data["classes"][cls]["name"]).replace("Frontier-", "").get_slice("-", 0).to_upper()
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _select_ship(cls))
		row.add_child(b)
		_ship_btns[cls] = b
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 14)
	v.add_child(info)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(260, 120)
	svc.stretch = true
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	info.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	svc.add_child(sv)
	_preview_root = Node3D.new()
	_preview_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sv.add_child(_preview_root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5.5, 13.0)
	cam.fov = 45.0
	sv.add_child(cam)
	cam.look_at(Vector3(0, 0, 0.5), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, 0.6, 0)
	sv.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("8a8fd6")
	env.environment.ambient_light_energy = 0.7
	sv.add_child(env)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	info.add_child(text)
	_ship_name = UiTheme.value("", UiTheme.YELLOW, 16)
	text.add_child(_ship_name)
	_ship_desc = UiTheme.value("", UiTheme.TEXT, 13)
	_ship_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ship_desc.custom_minimum_size = Vector2(360, 0)
	text.add_child(_ship_desc)
	_ship_bars = VBoxContainer.new()
	_ship_bars.add_theme_constant_override("separation", 2)
	text.add_child(_ship_bars)
	_select_ship(Net.chosen_ship)


func _select_ship(cls: String) -> void:
	Net.chosen_ship = cls
	var d: Dictionary = Game.ship_data["classes"][cls]
	for k: String in _ship_btns:
		var b := _ship_btns[k] as Button
		b.button_pressed = k == cls
		var base := str(Game.ship_data["classes"][k]["name"]).get_slice("-", 0).to_upper()
		b.text = ("▶ " + base + " ◀") if k == cls else base
	_ship_name.text = "%s · %s" % [d["name"], d["role"]]
	_ship_desc.text = str(d["desc"])
	for c in _ship_bars.get_children():
		c.queue_free()
	for b: Array in ShipStats.bars(d):
		var h := HBoxContainer.new()
		_ship_bars.add_child(h)
		var cap := UiTheme.caption(b[0])
		cap.custom_minimum_size = Vector2(90, 0)
		h.add_child(cap)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(200, 7)
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.value = clampf(b[1], 0.05, 1.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
	if _preview_model:
		_preview_model.queue_free()
	_preview_model = ShipModel.new()
	_preview_model.ship_class = cls
	_preview_model.thrust = 0.6
	_preview_root.add_child(_preview_model)


func _process(delta: float) -> void:
	if visible and _preview_root:
		_preview_root.rotate_y(delta * 0.7)


func _pilot() -> String:
	var n := _name.text.strip_edges()
	return n if n != "" else "Pilot"


func set_status(msg: String) -> void:
	_status.text = msg
