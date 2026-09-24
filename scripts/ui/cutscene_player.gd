class_name CutscenePlayer
extends Control
## In-engine cutscenes: a sequence of camera shots with letterbox bars and dialogue.
## Each shot is a Dictionary:
##   "from": Vector3      camera position at the start of the shot
##   "look": Vector3      what it looks at
##   "to": Vector3        (optional) camera position at the end (a slow dolly)
##   "look_to": Vector3   (optional) look target at the end (a pan)
##   "time": float        (optional) seconds; by default as long as its lines take
##   "lines": Array       (optional) [speaker, text] pairs said during the shot
##   "fov": float         (optional) degrees, default 50
##   "card": String       (optional) a title card instead of a camera shot ("Act One")
## E / click moves the dialogue on; Space skips the rest of the cutscene.

signal finished

const BAR := 0.11

var _shots: Array = []
var _i := -1
var _t := 0.0
var _cam: Camera3D
var _prev_cam: Camera3D
var _dialogue: DialogueBox
var _bars := 0.0
var _card := ""


func setup(dialogue: DialogueBox) -> void:
	_dialogue = dialogue


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play(shots: Array) -> void:
	_shots = shots.duplicate()
	_prev_cam = get_viewport().get_camera_3d()
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.name = "CutsceneCamera"
		var scene := get_tree().current_scene
		(scene if scene else get_tree().root).add_child(_cam)
	_i = -1
	_next_shot()


func is_playing() -> bool:
	return _i >= 0


func skip() -> void:
	if is_playing():
		_dialogue.play([])
		_end()


func _next_shot() -> void:
	_i += 1
	_t = 0.0
	if _i >= _shots.size():
		_end()
		return
	var s: Dictionary = _shots[_i]
	_card = String(s.get("card", ""))
	if _card == "":
		_cam.fov = float(s.get("fov", 50.0))
		_frame(s, 0.0)
		_cam.make_current()
	var lines: Array = s.get("lines", [])
	if not lines.is_empty():
		_dialogue.play(lines)


func _frame(s: Dictionary, k: float) -> void:
	var from: Vector3 = s["from"]
	var to: Vector3 = s.get("to", from)
	var look: Vector3 = s["look"]
	var look_to: Vector3 = s.get("look_to", look)
	var e := smoothstep(0.0, 1.0, k)
	var p := from.lerp(to, e)
	var l := look.lerp(look_to, e)
	if p.distance_to(l) > 0.01:
		_cam.global_transform = Transform3D(Basis.IDENTITY, p).looking_at(l, Vector3.UP)


func _shot_length(s: Dictionary) -> float:
	return float(s.get("time", 2.5))


func _end() -> void:
	_i = -1
	_card = ""
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if _cam and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	finished.emit()


func _process(delta: float) -> void:
	_bars = move_toward(_bars, 1.0 if is_playing() else 0.0, delta * 3.0)
	if is_playing():
		var s: Dictionary = _shots[_i]
		_t += delta
		var length := _shot_length(s)
		if _card == "":
			_frame(s, clampf(_t / maxf(length, 0.01), 0.0, 1.0))
		# A shot lasts its time and at least until its lines have been said.
		if _t >= length and not _dialogue.is_playing():
			_next_shot()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if is_playing() and not get_tree().paused and event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		skip()


func _draw() -> void:
	if _bars <= 0.0:
		return
	var h := size.y * BAR * _bars
	draw_rect(Rect2(0, 0, size.x, h), Color.BLACK)
	draw_rect(Rect2(0, size.y - h, size.x, h), Color.BLACK)
	if _card != "":
		var font := UIKit.font()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.018, 0.015, clampf(_t * 2.0, 0.0, 1.0) * 0.96))
		var lines := _card.split("\n")
		var y := size.y * 0.5 - (lines.size() - 1) * 26.0
		for i in lines.size():
			var fs := 40 if i == 0 else 24
			var col := Color(0.86, 0.68, 0.36) if i == 0 else Color(0.93, 0.88, 0.76)
			var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(size.x * 0.5 - w * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, clampf(_t * 1.5, 0.0, 1.0)))
			y += 52.0
	if is_playing():
		draw_string(UIKit.font(), Vector2(size.x - 170.0, size.y - h * 0.4), "Space: skip", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.45))
