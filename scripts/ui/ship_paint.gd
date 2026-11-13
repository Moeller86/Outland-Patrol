class_name ShipPaint
extends HBoxContainer
## Hangaren: tilpas dit skib. Lakfarve, striber/accent, motorens glød, flammefarve,
## lakmønster og skibets navn. Ændringer gemmes med det samme og ses af alle i co-op.

const PAINTS := ["ff4f8b", "e94f64", "ff7a3d", "ffd23f", "6bdc4f", "2ec4d6", "4d8bff", "8a5cff",
	"c77dff", "e8e6ff", "6a6f8a", "2a2440"]
const ACCENTS := ["ffd23f", "ff9e3d", "ff4f8b", "4dffe1", "6bdc4f", "4d8bff", "e8e6ff", "23203a"]
const ENGINES := ["4dffe1", "4dd0ff", "6bdc4f", "ff4fd8", "ffd23f", "ff3b3b", "c77dff", "ffffff"]
const FLAMES := ["ff9e3d", "ffd23f", "4dd0ff", "ff4fd8", "6bdc4f", "ffffff"]

var _preview_root: Node3D
var _model: ShipModel
var _look: Dictionary = {}
var _name_edit: LineEdit
var _pattern_btns: Dictionary = {}
var _rows: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	# Forhåndsvisning
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(240, 170)
	svc.stretch = true
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	svc.add_child(sv)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 7.0, 15.0)
	cam.fov = 45.0
	sv.add_child(cam)
	cam.look_at(Vector3(0, 0, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.3
	sv.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("9a96c0")
	env.environment.ambient_light_energy = 0.7
	sv.add_child(env)
	_preview_root = Node3D.new()
	_preview_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sv.add_child(_preview_root)
	# Valg
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	v.add_child(UiTheme.caption("Hangaren · tilpas dit skib (ses af alle i co-op)"))
	_swatches(v, "paint", "Lak", PAINTS)
	_swatches(v, "accent", "Striber og detaljer", ACCENTS)
	_swatches(v, "engine", "Motorens glød og lys", ENGINES)
	_swatches(v, "flame", "Flammer", FLAMES)
	v.add_child(UiTheme.value("Lakmønster", UiTheme.TEXT, 14))
	var pr := HBoxContainer.new()
	v.add_child(pr)
	for key: String in ShipModel.PATTERNS:
		var b := Button.new()
		b.text = ShipModel.PATTERN_NAMES[key]
		b.toggle_mode = true
		b.pressed.connect(func(): _choose("pattern", key))
		pr.add_child(b)
		_pattern_btns[key] = b
	v.add_child(UiTheme.value("Skibets navn", UiTheme.TEXT, 14))
	var nr := HBoxContainer.new()
	v.add_child(nr)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "fx Nattens Gnist"
	_name_edit.custom_minimum_size = Vector2(240, 0)
	_name_edit.text_submitted.connect(func(t: String): _choose("ship_name", t))
	nr.add_child(_name_edit)
	var save := Button.new()
	save.text = "GEM NAVN"
	save.pressed.connect(func(): _choose("ship_name", _name_edit.text))
	nr.add_child(save)
	var reset := Button.new()
	reset.text = "STANDARDFARVER"
	reset.pressed.connect(func():
		_look = {}
		Game.request_look(_look)
		_rebuild())
	v.add_child(reset)
	Game.look_changed.connect(func(id: int, l: Dictionary):
		if id == multiplayer.get_unique_id():
			_look = l.duplicate()
			_rebuild())
	Game.ship_class_changed.connect(func(id: int, _c: String):
		if id == multiplayer.get_unique_id():
			_rebuild())


func refresh() -> void:
	_look = Game.local_look().duplicate()
	_name_edit.text = str(_look.get("ship_name", ""))
	_rebuild()


func _swatches(parent: VBoxContainer, key: String, label: String, cols: Array) -> void:
	parent.add_child(UiTheme.value(label, UiTheme.TEXT, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var btns: Array = []
	for c: String in cols:
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 26)
		b.toggle_mode = true
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c)
		sb.border_color = Color("23203a")
		sb.set_border_width_all(2)
		var sel := sb.duplicate() as StyleBoxFlat
		sel.border_color = Color.WHITE
		sel.set_border_width_all(4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sel)
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_stylebox_override("focus", sel)
		b.set_meta("col", c)
		b.pressed.connect(func(): _choose(key, c))
		row.add_child(b)
		btns.append(b)
	_rows[key] = btns


func _choose(key: String, value: String) -> void:
	_look[key] = value
	Game.request_look(_look)
	Sfx.play("klik", -4.0, 0.0)
	_rebuild()


func _rebuild() -> void:
	if _preview_root == null:
		return
	for c in _preview_root.get_children():
		c.queue_free()
	_model = ShipModel.new()
	var ship := W.local_ship
	_model.ship_class = Game.local_class()
	_model.paint = ship.paint if ship and is_instance_valid(ship) else Color("ff4f8b")
	_model.apply_look(_look)
	_model.thrust = 0.8
	var big: bool = _model.ship_class in ["krydser", "fregat", "fragter"]
	_model.scale = Vector3.ONE * (0.55 if big else 0.9)
	_preview_root.add_child(_model)
	# Markér de valgte farver
	for key: String in _rows:
		var cur := str(_look.get(key, ""))
		for b: Button in _rows[key]:
			b.set_pressed_no_signal(str(b.get_meta("col")) == cur)
	var pat := str(_look.get("pattern", "panel"))
	for k: String in _pattern_btns:
		(_pattern_btns[k] as Button).set_pressed_no_signal(k == pat)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _preview_root == null:
		return
	_t += delta
	_preview_root.rotation = Vector3(0, _t * 0.5, 0)
