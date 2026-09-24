class_name GameHUD
extends CanvasLayer
## Minimal immersive HUD for Phase 1:
##  * health bar that only appears when Harry is hurt, then fades away
##  * red vignette flash on damage, fade to black on death
##  * F3 debug overlay (FPS, state, speed, fall height) for tuning
##  * Esc pause menu (Resume / Quit)
## The full Victorian HUD, menus and settings arrive in Phase 9.

@export var player_path: NodePath

const INK := Color(0.93, 0.88, 0.76)
const PANEL := Color(0.07, 0.06, 0.05, 0.88)
const BRASS := Color(0.72, 0.56, 0.3)

var _player: Harry
var _font: SystemFont
var _debug_label: Label
var _health_root: Control
var _health_fill: ColorRect
var _health_alpha := 0.0
var _health_show_timer := 0.0
var _damage_flash: ColorRect
var _death_fade: ColorRect
var _death_label: Label
var _pause_root: Control
var _last_fall := 0.0
var _last_health := 100.0
var _flash := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"])
	_build_health()
	_build_overlays()
	_build_debug()
	_build_pause_menu()
	if not player_path.is_empty():
		_player = get_node(player_path) as Harry
	if _player:
		_player.health_changed.connect(_on_health_changed)
		_player.died.connect(_on_died)
		_player.respawned.connect(_on_respawned)
		_player.landed.connect(func(h: float) -> void: _last_fall = h)
		_last_health = _player.max_health


func _build_health() -> void:
	_health_root = Control.new()
	_health_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_root.offset_left = 40.0
	_health_root.offset_top = -70.0
	_health_root.offset_right = 304.0
	_health_root.offset_bottom = -54.0
	_health_root.modulate.a = 0.0
	add_child(_health_root)
	var frame := ColorRect.new()
	frame.color = Color(0, 0, 0, 0.55)
	frame.size = Vector2(264, 16)
	_health_root.add_child(frame)
	var border := ReferenceRect.new()
	border.border_color = BRASS
	border.border_width = 1.5
	border.editor_only = false
	border.size = Vector2(264, 16)
	_health_root.add_child(border)
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.55, 0.1, 0.08)
	_health_fill.position = Vector2(2, 2)
	_health_fill.size = Vector2(260, 12)
	_health_root.add_child(_health_fill)


func _build_overlays() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(0.45, 0.0, 0.0, smoothstep(0.25, 0.75, d) * strength);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_damage_flash.material = mat
	add_child(_damage_flash)

	_death_fade = ColorRect.new()
	_death_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_fade.color = Color(0, 0, 0, 0)
	add_child(_death_fade)
	_death_label = _make_label("", 44)
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_label.modulate.a = 0.0
	add_child(_death_label)


func _build_debug() -> void:
	_debug_label = _make_label("", 16)
	_debug_label.position = Vector2(16, 12)
	_debug_label.visible = false
	_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug_label.add_theme_constant_override("outline_size", 4)
	add_child(_debug_label)


func _build_pause_menu() -> void:
	_pause_root = Control.new()
	_pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.visible = false
	add_child(_pause_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	_pause_root.add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BRASS
	style.set_border_width_all(2)
	style.set_content_margin_all(36)
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(340, 0)
	panel.add_child(box)
	var title := _make_label("The Thief of London", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _make_label("~ Paused ~", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = BRASS
	box.add_child(sub)
	box.add_child(HSeparator.new())
	var resume := _make_button("Resume")
	resume.pressed.connect(_set_paused.bind(false))
	box.add_child(resume)
	var quit := _make_button("Quit to Desktop")
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", BRASS)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.11, 0.09) if state != "hover" else Color(0.2, 0.16, 0.12)
		sb.border_color = BRASS if state != "normal" else Color(0.35, 0.28, 0.18)
		sb.set_border_width_all(1)
		b.add_theme_stylebox_override(state, sb)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_overlay"):
		_debug_label.visible = not _debug_label.visible
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not get_tree().paused:
		# Clicking back into the window re-captures the mouse (e.g. after Alt+Tab).
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	_pause_root.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED
	if p:
		(_pause_root.find_children("*", "Button", true, false)[0] as Button).grab_focus()


func _process(delta: float) -> void:
	# Health bar fades in when hurt and out again a few seconds after.
	_health_show_timer = maxf(_health_show_timer - delta, 0.0)
	var want := 1.0 if _health_show_timer > 0.0 or (_player and _player.health < _player.max_health * 0.35) else 0.0
	_health_alpha = move_toward(_health_alpha, want, delta * 2.0)
	_health_root.modulate.a = _health_alpha
	_flash = move_toward(_flash, 0.0, delta * 1.2)
	(_damage_flash.material as ShaderMaterial).set_shader_parameter("strength", _flash)

	if _debug_label.visible and _player:
		_debug_label.text = "FPS %d\nState: %s\nSpeed: %.2f m/s\nHealth: %.0f\nLast fall: %.2f m\nPosition: %s" % [
			Engine.get_frames_per_second(),
			Harry.State.keys()[_player.state],
			_player.get_horizontal_speed(),
			_player.health,
			_last_fall,
			str(_player.global_position.snapped(Vector3.ONE * 0.01)),
		]


func _on_health_changed(health: float, max_health: float) -> void:
	_health_fill.size.x = 260.0 * health / max_health
	if health < _last_health - 0.5:
		_health_show_timer = 4.0
		_flash = clampf((_last_health - health) / 40.0, 0.35, 1.0)
	_last_health = health


func _on_died() -> void:
	_death_label.text = "Harry has fallen..."
	var tw := create_tween()
	tw.tween_property(_death_fade, "color:a", 1.0, 2.0).set_delay(0.6)
	tw.parallel().tween_property(_death_label, "modulate:a", 1.0, 1.2).set_delay(1.2)


func _on_respawned() -> void:
	var tw := create_tween()
	tw.tween_property(_death_label, "modulate:a", 0.0, 0.4)
	tw.tween_property(_death_fade, "color:a", 0.0, 1.2)
