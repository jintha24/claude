class_name SaveLoadMenu
extends CanvasLayer
## The save / load screen: the autosave (load only) and five slots, each showing the date
## saved, the place, Harry's purse and the time played.

signal closed

var saving := false
var _root: Control


static func open(tree: SceneTree, save_mode: bool) -> SaveLoadMenu:
	var m := SaveLoadMenu.new()
	m.saving = save_mode
	tree.root.add_child(m)
	return m


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	if _root:
		_root.queue_free()
	var o := UIKit.overlay(self, "Save Game" if saving else "Load Game", Vector2(760, 0))
	_root = o[0]
	var box: VBoxContainer = o[1]
	var first: Button = null
	for slot in range(0 if not saving else 1, SaveGame.SLOTS + 1):
		var h := HBoxContainer.new()
		var name_text := "Autosave" if slot == 0 else "Slot %d" % slot
		var b := UIKit.button("%s:  %s" % [name_text, SaveGame.describe(slot)], 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not saving and not SaveGame.exists(slot)
		b.pressed.connect(_pick.bind(slot))
		h.add_child(b)
		if slot > 0 and SaveGame.exists(slot):
			var del := UIKit.button("Delete", 16)
			del.pressed.connect(func() -> void:
				SaveGame.delete(slot)
				_build())
			h.add_child(del)
		box.add_child(h)
		if first == null and not b.disabled:
			first = b
	var back := UIKit.button("Back", 20)
	back.pressed.connect(close)
	box.add_child(back)
	(first if first else back).grab_focus.call_deferred()


func _pick(slot: int) -> void:
	if saving:
		if SaveGame.save(get_tree(), slot):
			Progress.bus().note.emit("Game saved.")
		elif Story.is_active():
			Progress.bus().note.emit("You can't save during a mission.")
		else:
			Progress.bus().note.emit("The game couldn't be saved.")
		_build()
	else:
		close()
		for m in get_tree().root.get_children():
			if m is PauseMenu:
				(m as PauseMenu).queue_free()
		SaveGame.load_game(get_tree(), slot)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
