class_name CommPanel
extends Control
## Opkald (H): samtale med et civilt skib. Viser skibets hus og navn, hvad det siger,
## og de svar, man kan give. Skibet flyver ligeud, mens panelet er åbent.

signal closed

var _npc := -1
var _portrait: ColorRect
var _letter: Label
var _name: Label
var _house: Label
var _text: Label
var _opts: VBoxContainer
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -300
	panel.offset_bottom = -40
	add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	_portrait = ColorRect.new()
	_portrait.custom_minimum_size = Vector2(96, 96)
	h.add_child(_portrait)
	_letter = UiTheme.value("", Color("1a1430"), 48)
	_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.add_child(_letter)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	h.add_child(v)
	v.add_child(UiTheme.caption("Opkald · åben kanal"))
	_name = UiTheme.value("", UiTheme.YELLOW, 17)
	v.add_child(_name)
	_house = UiTheme.value("", UiTheme.MUTED, 12)
	v.add_child(_house)
	_text = UiTheme.value("", UiTheme.TEXT, 15)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(400, 0)
	v.add_child(_text)
	_opts = VBoxContainer.new()
	_opts.add_theme_constant_override("separation", 4)
	v.add_child(_opts)
	W.traffic.hail_received.connect(_on_hail)
	W.traffic.hail_reply.connect(_on_reply)


func _on_hail(i: int, nm: String, house: String, text: String, options: Array) -> void:
	_npc = i
	var col := Game.col(Traffic.HOUSES.get(house, {}).get("color", "b8b4d8"))
	_portrait.color = col
	_letter.text = str(Traffic.HOUSES.get(house, {}).get("name", "?")).left(1)
	_name.text = nm
	_house.text = "Hus %s" % Traffic.HOUSES.get(house, {}).get("name", "") if house != "fri" else "Uafhængig"
	_text.text = "“%s”" % text
	for c in _opts.get_children():
		c.queue_free()
	for o: Dictionary in options:
		var b := Button.new()
		b.text = "▸ " + str(o["label"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var oid: String = o["id"]
		b.pressed.connect(func():
			if oid == "bye":
				close()
			else:
				W.traffic.request_choice(_npc, oid))
		_opts.add_child(b)
	visible = true
	Sfx.play("besked", -3.0, 0.0)
	closed_by_user = false


var closed_by_user := false


func _on_reply(text: String) -> void:
	if not visible:
		return
	_text.text = "“%s”" % text
	for c in _opts.get_children():
		c.queue_free()
	var b := Button.new()
	b.text = "▸ Luk kanalen"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(close)
	_opts.add_child(b)


func close() -> void:
	if not visible:
		return
	visible = false
	closed_by_user = true
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	# Luk, hvis skibet flyver for langt væk
	var me := W.local_ship
	if _npc >= 0 and me and is_instance_valid(me) and (not W.traffic.is_alive(_npc) or me.position.distance_to(W.traffic.position_of(_npc)) > Traffic.HAIL_RANGE * 2.5):
		Game.toast.emit("Forbindelsen blev afbrudt")
		close()
