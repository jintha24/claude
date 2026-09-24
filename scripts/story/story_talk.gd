class_name StoryTalk
extends Interactable
## "Talk to Pip": a line from someone Harry knows (a different one each time).

var speaker: String = ""
var lines: Array = []
var npc: StoryNPC
var enabled: bool = true
var _i := -1


func _ready() -> void:
	interact_range = 2.4


func get_interact_point() -> Vector3:
	return (npc.global_position if npc and is_instance_valid(npc) else global_position) + Vector3.UP * 1.4


func get_prompt(_h: Harry) -> String:
	if not enabled or lines.is_empty() or Story.is_active():
		return ""
	return "Talk to %s" % speaker


func interact(_h: Harry) -> void:
	_i = (_i + 1) % lines.size()
	StoryUI.find(get_tree()).dialogue.play([[speaker, lines[_i]]])
	if npc and is_instance_valid(npc):
		npc.face(_h)
