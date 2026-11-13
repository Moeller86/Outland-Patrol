class_name Debrief
extends Control
## Debriefing efter en mission: resultat, løn, erfaring, rang og en knap til at fortsætte.

signal closed

var _head: Label
var _name: Label
var _reason: Label
var _rows: GridContainer
var _rank: Label
var _bar: ProgressBar
var _rankup: Label
var _base: Label
var _ok: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UiTheme.caption("Concord Patrol · Debriefing"))
	_head = UiTheme.value("", UiTheme.GREEN, 30)
	v.add_child(_head)
	_name = UiTheme.value("", UiTheme.YELLOW, 18)
	v.add_child(_name)
	_reason = UiTheme.value("", UiTheme.CYAN, 15)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.custom_minimum_size = Vector2(520, 0)
	v.add_child(_reason)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 24)
	_rows.add_theme_constant_override("v_separation", 6)
	v.add_child(_rows)
	_rank = UiTheme.value("", UiTheme.TEXT, 16)
	v.add_child(_rank)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(520, 12)
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.YELLOW
	_bar.add_theme_stylebox_override("fill", fill)
	v.add_child(_bar)
	_rankup = UiTheme.value("", UiTheme.PINK, 18)
	v.add_child(_rankup)
	_base = UiTheme.value("", UiTheme.CYAN, 15)
	_base.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_base)
	_ok = Button.new()
	_ok.text = "ENTER  FORTSÆT"
	_ok.pressed.connect(_close)
	v.add_child(_ok)


func show_result(r: Dictionary) -> void:
	var ok: bool = r["success"]
	_head.text = "MISSION FULDFØRT" if ok else "MISSION MISLYKKEDES"
	_head.add_theme_color_override("font_color", UiTheme.GREEN if ok else UiTheme.DANGER)
	_name.text = str(r["name"])
	_reason.text = str(r["reason"])
	for c in _rows.get_children():
		c.queue_free()
	var rows := [
		["Løn", "+%d cr" % int(r["credits"])],
		["Erfaring", "+%d xp" % int(r["xp"])],
		["Pirater nedkæmpet", str(int(r["kills"]))],
		["Tid", "%d:%02d" % [int(r["minutes"]), int(fmod(float(r["minutes"]) * 60.0, 60.0))]],
	]
	for row: Array in rows:
		_rows.add_child(UiTheme.caption(row[0]))
		_rows.add_child(UiTheme.value(row[1], UiTheme.YELLOW))
	var xp := int(r["xp_after"])
	var idx := Game.rank_index(xp)
	var next := Game.next_rank_xp(xp)
	var cur := int(Game.mission_data["ranks"][idx]["xp"])
	if next > 0:
		_rank.text = "Rang: %s   ·   %d / %d xp til %s" % [Game.rank_name(xp), xp, next, Game.mission_data["ranks"][idx + 1]["name"]]
		_bar.max_value = next - cur
		_bar.value = xp - cur
	else:
		_rank.text = "Rang: %s   ·   %d xp (højeste rang)" % [Game.rank_name(xp), xp]
		_bar.max_value = 1
		_bar.value = 1
	var promoted := Game.rank_index(int(r["xp_before"])) < idx
	_rankup.text = "FORFREMMET TIL %s!" % Game.rank_name(xp).to_upper() if promoted else ""
	_rankup.visible = promoted
	if promoted:
		get_tree().create_timer(1.4).timeout.connect(func(): Sfx.play("rang", -3.0, 0.0))
	var unlocked := str(r.get("unlocked", ""))
	if unlocked != "":
		_base.text = "BASTION KEPLER UDVIDET: %s er klar." % unlocked
	elif r["success"]:
		var nxt := Game.next_module()
		_base.text = "%s: %d fuldførte missioner%s" % [Game.base_data["name"], int(r.get("base_level", 0)),
			("" if nxt.is_empty() else ", %s om %d" % [nxt["name"], int(nxt["missions"]) - int(r.get("base_level", 0))])]
	else:
		_base.text = ""
	_base.visible = _base.text != ""
	visible = true
	_ok.grab_focus()


func _close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("launch"):
		get_viewport().set_input_as_handled()
		_close()
