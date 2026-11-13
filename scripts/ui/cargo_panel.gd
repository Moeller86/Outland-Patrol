class_name CargoPanel
extends Control
## Lastrummet (I): se lasten og smid varer ud under flyvning. De udsmidte kasser
## driver bag skibet og kan samles op igen (af andre med det samme, af én selv
## efter et par sekunder). Skibet flyver ligeud, mens panelet er åbent.

signal closed

var ship: Ship
var _list: VBoxContainer
var _head: Label
var _bar: ProgressBar


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -470
	panel.offset_right = -30
	panel.offset_top = -170
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UiTheme.caption("Lastrum"))
	_head = UiTheme.value("", UiTheme.YELLOW, 20)
	v.add_child(_head)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 12)
	v.add_child(_bar)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)
	v.add_child(UiTheme.caption("Udsmidt last driver bag skibet og kan samles op igen", UiTheme.MUTED))
	var close_btn := Button.new()
	close_btn.text = "LUK"
	close_btn.pressed.connect(close)
	v.add_child(close_btn)
	Game.wallet_changed.connect(func():
		if visible:
			_refresh())


func open(s: Ship) -> void:
	ship = s
	visible = true
	_refresh()
	Sfx.play("klik", -2.0, 0.0)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var cargo: Dictionary = Game.wallet.get("cargo", {})
	var total := Game.cargo_total(cargo)
	var cap := int(Game.wallet.get("cargo_max", 1))
	_head.text = "%d / %d  %s" % [total, cap, "· FULDT" if total >= cap else ""]
	_bar.max_value = cap
	_bar.value = total
	if total == 0:
		_list.add_child(UiTheme.value("Lastrummet er tomt", UiTheme.MUTED, 15))
		return
	var can_drop := ship != null and is_instance_valid(ship) and ship.state == Ship.State.FLY and not ship.dead
	for good: String in cargo:
		var n := int(cargo[good])
		if n <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var name := UiTheme.value("%s  ×%d" % [Game.good_name(good), n], Game.col(Game.goods[good].get("color", "ffffff")), 16)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		for spec in [[1, "SMID 1"], [0, "SMID ALLE"]]:
			var b := Button.new()
			b.text = spec[1]
			b.disabled = not can_drop
			var amount: int = spec[0]
			b.pressed.connect(func():
				Game.request_jettison(good, amount)
				Sfx.play("afgang", -8.0, 0.1))
			row.add_child(b)
	if not can_drop:
		_list.add_child(UiTheme.caption("Kan kun smides ud under flyvning", UiTheme.MUTED))
