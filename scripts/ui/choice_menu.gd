class_name ChoiceMenu
extends CanvasLayer
## A small menu of choices over the game (buying, selling, giving): a title, a line of
## text, a list of buttons (each may be greyed out with a reason), and Leave. The game
## pauses while it's open. Works with mouse, keyboard and controller (Esc / B = Leave).

signal closed

## Each option: {"text": String, "enabled": bool, "action": Callable, "keep_open": bool}
var title: String = ""
var body: String = ""
var options: Array[Dictionary] = []
## False for story choices: there's no Leave button and Esc doesn't close it.
var cancellable: bool = true:
	set(v):
		cancellable = v
		if is_inside_tree():
			_build()

var _root: Control
var _box: VBoxContainer
var _body_label: Label
var _was_paused := false


static func open(tree: SceneTree, menu_title: String, text: String, opts: Array[Dictionary]) -> ChoiceMenu:
	var m := ChoiceMenu.new()
	m.title = menu_title
	m.body = text
	m.options = opts
	tree.root.add_child(m)
	return m


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("choice_menus")
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()


func _build() -> void:
	if _root:
		_root.queue_free()
	var o := UIKit.overlay(self, title, Vector2(520, 0))
	_root = o[0]
	_box = o[1]
	_body_label = UIKit.label(body, 18, UIKit.INK_DIM)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(460, 0)
	_box.add_child(_body_label)
	var first: Button = null
	for i in options.size():
		var opt := options[i]
		var b := UIKit.button(String(opt["text"]), 19)
		b.disabled = not bool(opt.get("enabled", true))
		b.pressed.connect(choose.bind(i))
		_box.add_child(b)
		if first == null and not b.disabled:
			first = b
	var leave: Button = null
	if cancellable:
		leave = UIKit.button("Leave", 19)
		leave.pressed.connect(close)
		_box.add_child(leave)
	var focus: Button = first if first else leave
	if focus:
		focus.grab_focus.call_deferred()


## Picks option `i` (also used by tests).
func choose(i: int) -> void:
	if i < 0 or i >= options.size() or not bool(options[i].get("enabled", true)):
		return
	var opt := options[i]
	(opt["action"] as Callable).call()
	if bool(opt.get("keep_open", false)):
		refresh()
	else:
		close()


## Rebuilds the options (their callables may recompute text and availability).
func refresh() -> void:
	var src: Variant = get_meta("rebuild", null)
	if src is Callable:
		options = (src as Callable).call()
	_build()


func close() -> void:
	get_tree().paused = _was_paused
	if not _was_paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if cancellable and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()
