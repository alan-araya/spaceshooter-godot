class_name UiKit
extends RefCounted
## Tema e helpers de interface (metal escuro com rebites, destaque âmbar). Tudo em código
## para ser fácil trocar por um Theme .tres depois.

const AMBER := Color("ffc94a")
const TEXT := Color("f2ead8")
const DIM := Color("9a958a")
const PANEL := Color(0.09, 0.09, 0.11, 0.92)
const METAL := Color("2c3038")
const METAL_HI := Color("4a505b")

static var _theme: Theme


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	var normal := _box(METAL, METAL_HI, 2)
	var hover := _box(Color("3a3f49"), AMBER, 2)
	var pressed := _box(Color("22252b"), AMBER, 2)
	var disabled := _box(Color("1d1f24"), Color("33363d"), 2)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBox = normal
		match st:
			"hover", "focus":
				sb = hover
			"pressed":
				sb = pressed
			"disabled":
				sb = disabled
		t.set_stylebox(st, "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", AMBER)
	t.set_color("font_focus_color", "Button", AMBER)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", Color("5c5a55"))
	t.set_font_size("font_size", "Button", 20)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, METAL_HI, 2, 14))
	_theme = t
	return t


static func _box(bg: Color, border: Color, bw: int, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = margin + 8
	sb.content_margin_right = margin + 8
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	return sb


static func label(text: String, size: int = 18, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func button(text: String, cb: Callable, min_w: int = 360) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): Sfx.play("ui_move"))
	return b


static func full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
