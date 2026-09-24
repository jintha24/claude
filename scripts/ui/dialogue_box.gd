class_name DialogueBox
extends Control
## Conversation subtitles for the story: the speaker's name and their line in a panel at
## the bottom of the screen, typed out. E, Enter or a click shows the whole line,
## then moves on; otherwise each line moves on by itself once it's had time to be read.
## Also shows one-off lines said in passing (subtitle()).

signal finished

const INK := Color(0.93, 0.88, 0.76)
const GOLD := Color(0.86, 0.68, 0.36)
const CHARS_PER_SECOND := 48.0

var _lines: Array = []
var _i := -1
var _shown := 0.0
var _hold := 0.0
var _passing: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Plays `lines` ([speaker, text] pairs) one after another.
func play(lines: Array) -> void:
	_lines = lines.duplicate()
	_i = -1
	_next()


func is_playing() -> bool:
	return _i >= 0 and _i < _lines.size()


## The line being said now (speaker, text), or [] (for tests).
func current_line() -> Array:
	return _lines[_i] if is_playing() else []


## Shows everything, or moves to the next line if it's all shown.
func advance() -> void:
	if not is_playing():
		return
	var text: String = _lines[_i][1]
	if _shown < text.length():
		_shown = text.length()
	else:
		_next()


## A line said in passing (doesn't need to be read to carry on).
func subtitle(speaker: String, text: String) -> void:
	_passing.append({"speaker": speaker, "text": text, "time": 2.5 + text.length() * 0.045})
	if _passing.size() > 2:
		_passing.pop_front()


func _next() -> void:
	_i += 1
	_shown = 0.0
	if _i >= _lines.size():
		_i = -1
		_lines.clear()
		finished.emit()
		return
	var text: String = _lines[_i][1]
	_hold = 1.4 + text.length() * 0.05


func _process(delta: float) -> void:
	for p in _passing:
		p["time"] = float(p["time"]) - delta
	_passing = _passing.filter(func(p: Dictionary) -> bool: return float(p["time"]) > 0.0)
	if is_playing():
		var text: String = _lines[_i][1]
		if _shown < text.length():
			_shown = minf(_shown + CHARS_PER_SECOND * delta, text.length())
		else:
			_hold -= delta
			if _hold <= 0.0:
				_next()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_playing() or get_tree().paused:
		return
	var pressed := event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if pressed:
		get_viewport().set_input_as_handled()
		advance()


func _draw() -> void:
	var font := UIKit.font()
	var w := minf(size.x - 80.0, 900.0)
	var y := size.y - 70.0
	if is_playing():
		var speaker: String = _lines[_i][0]
		var text: String = String(_lines[_i][1]).substr(0, int(_shown))
		var h := 108.0
		var rect := Rect2(size.x * 0.5 - w * 0.5, size.y - h - 36.0, w, h)
		draw_rect(rect, Color(0.04, 0.035, 0.03, 0.82))
		draw_rect(rect, Color(GOLD, 0.6), false, 1.5)
		if speaker != "":
			draw_string(font, rect.position + Vector2(22, 32), speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, GOLD)
		draw_multiline_string(font, rect.position + Vector2(22, 60), text, HORIZONTAL_ALIGNMENT_LEFT, w - 44.0, 21, 3, INK)
		if _shown >= String(_lines[_i][1]).length():
			draw_string(font, rect.end - Vector2(34, 12), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(GOLD, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)))
		y = rect.position.y - 16.0
	for i in range(_passing.size() - 1, -1, -1):
		var p := _passing[i]
		var a := clampf(float(p["time"]), 0.0, 1.0)
		var line := "%s: %s" % [p["speaker"], p["text"]] if String(p["speaker"]) != "" else String(p["text"])
		var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var pos := Vector2(size.x * 0.5 - tw * 0.5, y - 150.0 if not is_playing() else y)
		draw_string(font, pos + Vector2(1, 1), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0, 0, 0, 0.8 * a))
		draw_string(font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(INK, a))
		y -= 26.0
