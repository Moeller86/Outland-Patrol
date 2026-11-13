class_name SiteMenu
extends Control
## Menuen, når man er landet ved et fund på en planet (vrag, ruin, kapsel, piratlejr):
## en lille pixelscene, beskrivelse, én handling og "LET".

signal launch_requested

var site_id := ""

var _art: TextureRect
var _kind: Label
var _title: Label
var _desc: Label
var _result: Label
var _action: Button
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
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_kind = UiTheme.caption("")
	v.add_child(_kind)
	_title = UiTheme.value("", UiTheme.YELLOW, 24)
	v.add_child(_title)
	_art = TextureRect.new()
	_art.custom_minimum_size = Vector2(576, 324)
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	v.add_child(_art)
	_desc = UiTheme.value("", UiTheme.TEXT, 15)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(576, 0)
	v.add_child(_desc)
	_result = UiTheme.value("", UiTheme.CYAN, 15)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(576, 0)
	v.add_child(_result)
	var row := HBoxContainer.new()
	v.add_child(row)
	_action = Button.new()
	_action.pressed.connect(_on_action)
	row.add_child(_action)
	_launch = Button.new()
	_launch.text = "ENTER  LET"
	_launch.pressed.connect(func(): launch_requested.emit())
	row.add_child(_launch)
	W.sites.action_result.connect(_on_result)
	W.sites.known_changed.connect(func(): if visible: _refresh())


func open(id: String) -> void:
	site_id = id
	var s := W.sites.get_site(id)
	if s.is_empty():
		return
	var kind: Dictionary = Sites.KINDS[s["kind"]]
	var planet := W.universe.planet(s["planet"])
	_kind.text = ("Missionsfund · " if s["mission"] != "" else "Fund · ") + str(kind["title"]).to_upper() + " · " + planet.display_name.to_upper()
	_title.text = str(s["name"])
	_desc.text = str(kind["desc"])
	if s["mission"] != "":
		_desc.text = "Vraget af %s. Nødsenderen blinker stadig, og fartskriveren – den sorte boks – sidder i førerkabinen." % str(s["name"]).trim_prefix("Vraget af ")
	_art.texture = SiteArt.texture_for(s, planet.data)
	_result.text = ""
	visible = true
	_refresh()


func close() -> void:
	visible = false
	site_id = ""


func _refresh() -> void:
	var act := W.sites.action_for(site_id)
	_action.text = str(act["label"])
	_action.disabled = not act["enabled"]
	if not act["enabled"] and _result.text == "":
		_result.text = str(act["note"])
	if act["enabled"]:
		_action.grab_focus()
	else:
		_launch.grab_focus()


func _on_action() -> void:
	W.sites.request_action(site_id)
	_action.disabled = true


func _on_result(id: String, text: String) -> void:
	if id != site_id or not visible:
		return
	_result.text = text
	_refresh()
	_result.text = text


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("launch"):
		get_viewport().set_input_as_handled()
		launch_requested.emit()
