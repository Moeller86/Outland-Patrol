class_name UiTheme
extends RefCounted
## Farver og Godot-tema i DOS/Terraria-stil: mørke paneler, kantede rammer,
## gule knapper med pink skygge og en skarp monospace-skrift uden kantudglatning.

const INK := Color("120a2e")
const PANEL := Color("1e1450")
const PANEL_2 := Color("2a1d6b")
const LINE := Color("4b3aa8")
const TEXT := Color("f4f0ff")
const MUTED := Color("a99ce0")
const PINK := Color("ff4f8b")
const CYAN := Color("2ec4d6")
const YELLOW := Color("ffd23f")
const GREEN := Color("6bdc4f")
const VIOLET := Color("c77dff")
const DANGER := Color("ff5a5a")


static func build() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "DejaVu Sans Mono", "Liberation Mono", "Monospace"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.font_weight = 700
	t.default_font = font
	t.default_font_size = 16

	t.set_stylebox("panel", "PanelContainer", _box(PANEL, LINE, 3, Vector2(6, 6)))
	t.set_stylebox("panel", "Panel", _box(PANEL, LINE, 3, Vector2(6, 6)))
	t.set_color("font_color", "Label", TEXT)

	t.set_stylebox("normal", "Button", _box(YELLOW, INK, 0, Vector2(4, 4), PINK, 12))
	t.set_stylebox("hover", "Button", _box(Color("ffe680"), INK, 0, Vector2(4, 4), PINK, 12))
	t.set_stylebox("pressed", "Button", _box(YELLOW, INK, 0, Vector2(2, 2), PINK, 12))
	t.set_stylebox("disabled", "Button", _box(PANEL_2, INK, 0, Vector2(4, 4), INK, 12))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), CYAN, 3, Vector2.ZERO))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", INK)
	t.set_color("font_disabled_color", "Button", MUTED)

	t.set_stylebox("normal", "LineEdit", _box(INK, LINE, 2, Vector2.ZERO, Color.TRANSPARENT, 8))
	t.set_stylebox("focus", "LineEdit", _box(INK, CYAN, 2, Vector2.ZERO, Color.TRANSPARENT, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", YELLOW)

	t.set_stylebox("background", "ProgressBar", _box(PANEL, LINE, 1, Vector2.ZERO))
	t.set_stylebox("fill", "ProgressBar", _box(CYAN, CYAN, 0, Vector2.ZERO))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 10)
	return t


static func _box(bg: Color, border: Color, border_w: int, shadow_off: Vector2,
		shadow: Color = INK, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false
	sb.shadow_color = shadow
	sb.shadow_size = 0 if shadow_off == Vector2.ZERO else 1
	sb.shadow_offset = shadow_off
	sb.set_content_margin_all(pad)
	return sb


## En lille overskrift i versaler (bruges som etiketter i HUD og menuer).
static func caption(text: String, color: Color = MUTED) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	return l


static func value(text: String, color: Color = TEXT, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l
