class_name PauseMenu
extends CanvasLayer
## Esc: the pause menu. Resume, Save, Load, Settings, Quit to the title, Quit to desktop.

const TITLE_SCENE := "res://scenes/ui/main_menu.tscn"

var _root: Control


static func open(tree: SceneTree) -> PauseMenu:
	var m := PauseMenu.new()
	tree.root.add_child(m)
	return m


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var o := UIKit.overlay(self, "The Thief of London", Vector2(380, 0))
	_root = o[0]
	var box: VBoxContainer = o[1]
	var sub := UIKit.label("~ Paused ~", 18, UIKit.BRASS)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var entries := [
		["Resume", resume],
		["Save Game", func() -> void: _sub(SaveLoadMenu.open(get_tree(), true))],
		["Load Game", func() -> void: _sub(SaveLoadMenu.open(get_tree(), false))],
		["Settings", func() -> void: _sub(SettingsMenu.open(get_tree()))],
		["Quit to Title", quit_to_title],
		["Quit to Desktop", func() -> void: get_tree().quit()],
	]
	var first: Button = null
	for e: Array in entries:
		var b := UIKit.button(e[0])
		b.pressed.connect(e[1])
		box.add_child(b)
		if first == null:
			first = b
	first.grab_focus.call_deferred()


func _sub(menu: CanvasLayer) -> void:
	_root.visible = false
	menu.tree_exited.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			_root.visible = true
			(_root.find_children("*", "Button", true, false)[0] as Button).grab_focus())


func resume() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()


func quit_to_title() -> void:
	get_tree().paused = false
	queue_free()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume()
