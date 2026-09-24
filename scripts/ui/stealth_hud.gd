class_name StealthHUD
extends Control
## Stealth part of the HUD, drawn in code:
##  * detection chevrons around the screen centre pointing at each guard who is noticing
##    Harry, filling white -> amber -> red, with "?" when searching and "!" when chasing
##  * a small "light gem" (bottom left) showing how lit Harry is
##  * crosshair plus arrow type and count while aiming the longbow
##  * subtitles for what nearby guards say
## Everything fades out when there's nothing to show.

const INK := Color(0.93, 0.88, 0.76)
const AMBER := Color(0.95, 0.65, 0.2)
const RED := Color(0.85, 0.12, 0.08)

var player: Harry
var font: Font

var _subtitles: Array[Dictionary] = []
var _gem_alpha := 0.0
var _gem_value := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Stealth.bus().npc_spoke.connect(_on_spoke)


func _on_spoke(speaker: Node3D, line: String) -> void:
	if player == null or speaker == null:
		return
	if speaker.global_position.distance_to(player.global_position) > 30.0:
		return
	_subtitles.append({"text": line, "time": 3.5})
	if _subtitles.size() > 3:
		_subtitles.pop_front()


func _process(delta: float) -> void:
	for s in _subtitles:
		s["time"] = float(s["time"]) - delta
	_subtitles = _subtitles.filter(func(s: Dictionary) -> bool: return float(s["time"]) > 0.0)
	if player:
		var want_gem := 1.0 if (player.stealth.conspicuousness > 0.0 or player.is_crouching or player.is_aiming()) else 0.0
		_gem_alpha = move_toward(_gem_alpha, want_gem, delta * 2.0)
		_gem_value = lerpf(_gem_value, player.stealth.visibility, 1.0 - exp(-8.0 * delta))
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var center := size * 0.5
	_draw_detection(center)
	_draw_light_gem()
	if player.is_aiming():
		_draw_crosshair(center)
	_draw_subtitles()


func _draw_detection(center: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_fwd := -cam.global_basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length() < 0.01:
		return
	cam_fwd = cam_fwd.normalized()
	for node in get_tree().get_nodes_in_group("guards"):
		var g := node as Guard
		if g == null or g.state == Guard.State.UNCONSCIOUS:
			continue
		var level := g.awareness
		var searching := g.state in [Guard.State.INVESTIGATE, Guard.State.SEARCH]
		var chasing := g.state == Guard.State.CHASE
		if chasing:
			level = 1.0
		if level < 0.03 and not searching:
			continue
		var to_g := g.global_position - player.global_position
		to_g.y = 0.0
		if to_g.length() < 0.01:
			continue
		var angle := cam_fwd.signed_angle_to(to_g.normalized(), Vector3.UP)
		# Screen: up = straight ahead, clockwise = to the right.
		var dir := Vector2(sin(-angle), -cos(-angle))
		var radius := 120.0
		var tip := center + dir * (radius + 22.0)
		var base_c := center + dir * radius
		var side := Vector2(-dir.y, dir.x) * 16.0
		var col := INK.lerp(AMBER, clampf(level * 2.0, 0.0, 1.0)).lerp(RED, clampf(level * 2.0 - 1.0, 0.0, 1.0))
		col.a = 0.35 + 0.6 * clampf(level + (0.3 if searching else 0.0), 0.0, 1.0)
		var outline := PackedVector2Array([base_c - side, tip, base_c + side])
		draw_colored_polygon(PackedVector2Array([base_c - side * level, base_c + (tip - base_c) * level, base_c + side * level]), col)
		draw_polyline(outline, Color(col, 0.9), 2.0, true)
		if chasing or searching:
			var mark := "!" if chasing else "?"
			var p := tip + dir * 14.0 - Vector2(5, -8)
			draw_string(_font(), p, mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(col, 1.0))


func _draw_light_gem() -> void:
	if _gem_alpha <= 0.01:
		return
	var pos := Vector2(52, size.y - 110)
	var v := _gem_value
	var hidden := player.stealth.is_hidden()
	var fill := Color(0.08, 0.08, 0.1).lerp(Color(1.0, 0.85, 0.55), v)
	if hidden:
		fill = Color(0.05, 0.05, 0.07)
	draw_circle(pos, 14.0, Color(fill, _gem_alpha))
	draw_arc(pos, 15.0, 0.0, TAU, 32, Color(0.72, 0.56, 0.3, _gem_alpha), 1.5, true)
	if player.stealth.is_in_restricted_zone():
		draw_string(_font(), pos + Vector2(24, 6), "Trespassing", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(RED, _gem_alpha))
	elif hidden:
		draw_string(_font(), pos + Vector2(24, 6), "Hidden", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK, _gem_alpha))


func _draw_crosshair(center: Vector2) -> void:
	var c := player.combat
	var spread := lerpf(10.0, 3.0, c.draw)
	var col := Color(INK, 0.85)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(center + d * spread, center + d * (spread + 7.0), col, 1.5, true)
	draw_circle(center, 1.5, col)
	var label := "%s arrows: %d" % [c.arrow_kind.capitalize(), c.get_ammo(c.arrow_kind)]
	draw_string(_font(), center + Vector2(40, 60), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
	if c.draw > 0.0:
		draw_rect(Rect2(center + Vector2(40, 68), Vector2(90.0 * c.draw, 3)), Color(0.72, 0.56, 0.3, 0.9))


func _draw_subtitles() -> void:
	var y := size.y - 150.0
	for i in range(_subtitles.size() - 1, -1, -1):
		var s: Dictionary = _subtitles[i]
		var a := clampf(float(s["time"]), 0.0, 1.0)
		var text: String = s["text"]
		var w := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var p := Vector2(size.x * 0.5 - w * 0.5, y)
		draw_string(_font(), p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0, 0.8 * a))
		draw_string(_font(), p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(INK, a))
		y -= 28.0


func _font() -> Font:
	return font if font else ThemeDB.fallback_font
