class_name UIKit
extends RefCounted
## The game's Victorian look for menus and panels: Georgia-style serif type, ink on dark
## walnut, brass rules. Every menu builds its controls through these helpers so they all
## match (and work with mouse, keyboard and controller).

const INK := Color(0.93, 0.88, 0.76)
const INK_DIM := Color(0.93, 0.88, 0.76, 0.6)
const PANEL := Color(0.07, 0.06, 0.05, 0.92)
const BRASS := Color(0.72, 0.56, 0.3)
const RED := Color(0.8, 0.2, 0.15)
const GOOD := Color(0.45, 0.7, 0.35)

static var _font: SystemFont


static func font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"])
	return _font


static func label(text: String, size: int = 20, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", BRASS)
	b.add_theme_color_override("font_focus_color", BRASS)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.47, 0.4))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.11, 0.09) if state != "hover" else Color(0.2, 0.16, 0.12)
		sb.border_color = BRASS if state in ["hover", "focus", "pressed"] else Color(0.35, 0.28, 0.18)
		sb.set_border_width_all(1)
		sb.set_content_margin_all(6)
		b.add_theme_stylebox_override(state, sb)
	return b


static func panel(min_size: Vector2 = Vector2(420, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BRASS
	style.set_border_width_all(2)
	style.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", style)
	p.custom_minimum_size = min_size
	return p


## A full-screen layer: dimmed backdrop with a centred panel. Returns [root, vbox].
static func overlay(parent: Node, title: String, min_size: Vector2 = Vector2(460, 0)) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var p := panel(min_size)
	center.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	p.add_child(box)
	if title != "":
		var t := label(title, 30)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(t)
		var rule := ColorRect.new()
		rule.color = BRASS
		rule.custom_minimum_size = Vector2(0, 1)
		box.add_child(rule)
	return [root, box]


static func slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 24)
	return s


## A label on the left and a control on the right.
static func row(text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(text, 18)
	l.custom_minimum_size = Vector2(240, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h
