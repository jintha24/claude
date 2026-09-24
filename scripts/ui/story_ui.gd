class_name StoryUI
extends CanvasLayer
## The story's screen layer: the mission HUD, the dialogue box and the cutscene player,
## plus what happens when a mission ends (a banner when it's won; when it's lost, a
## choice to retry from the last checkpoint or abandon it).

var hud: MissionHUD
var dialogue: DialogueBox
var cutscene: CutscenePlayer

static var _pending: StoryUI

var _fail_timer := -1.0
var _fail_reason := ""


## The StoryUI in the current scene (made if there isn't one yet).
static func find(tree: SceneTree) -> StoryUI:
	var ui := tree.get_first_node_in_group("story_ui") as StoryUI
	if ui == null and is_instance_valid(_pending) and not _pending.is_inside_tree():
		return _pending
	if ui == null:
		ui = StoryUI.new()
		_pending = ui
		var parent: Node = tree.current_scene if tree.current_scene else tree.root
		if parent.is_node_ready():
			parent.add_child(ui)
		else:
			parent.add_child.call_deferred(ui) # the scene is still being set up
	return ui


func _init() -> void:
	name = "StoryUI"
	layer = 5
	add_to_group("story_ui")
	hud = MissionHUD.new()
	hud.name = "MissionHUD"
	add_child(hud)
	cutscene = CutscenePlayer.new()
	cutscene.name = "Cutscene"
	add_child(cutscene)
	dialogue = DialogueBox.new()
	dialogue.name = "Dialogue"
	add_child(dialogue)
	cutscene.setup(dialogue)


func _ready() -> void:
	Story.bus().mission_started.connect(_on_started)
	Story.bus().mission_completed.connect(_on_completed)
	Story.bus().mission_failed.connect(_on_failed)


func _on_started(id: String) -> void:
	var m := Story.info(id)
	var first_of_act := true
	for other in Story.MISSIONS:
		if int(other["act"]) == int(m["act"]) and int(other["number"]) < int(m["number"]):
			first_of_act = false
	if first_of_act and Story.checkpoint.get("step", 0) == 0:
		hud.banner("Act %s: %s" % [_act_word(int(m["act"])), Story.ACT_TITLES.get(int(m["act"]), "")], m["title"], 4.5)
	else:
		hud.banner(m["title"], m.get("blurb", ""), 4.0)


func _on_completed(id: String) -> void:
	var m := Story.info(id)
	var n := Story.next_mission()
	if n.is_empty() or int(n["act"]) != int(m["act"]):
		hud.banner("End of Act %s" % _act_word(int(m["act"])), Story.ACT_TITLES.get(int(m["act"]), ""), 6.0)
	else:
		hud.banner("Mission complete", m["title"], 4.0)


func _on_failed(_id: String, reason: String) -> void:
	_fail_reason = reason
	_fail_timer = 1.6


func _process(delta: float) -> void:
	if _fail_timer >= 0.0:
		_fail_timer -= delta
		if _fail_timer < 0.0:
			_offer_retry()


func _offer_retry() -> void:
	if Story.active == null or not is_instance_valid(Story.active):
		return
	var tree := get_tree()
	var menu := ChoiceMenu.open(tree, "Mission failed", "%s\n\n%s" % [Story.active.title, _fail_reason], [
		{"text": "Retry from the last checkpoint", "enabled": true, "action": func() -> void: Story.retry(tree)},
		{"text": "Abandon the mission", "enabled": true, "action": func() -> void: Story.abandon()},
	])
	menu.cancellable = false


static func _act_word(n: int) -> String:
	return ["Zero", "One", "Two", "Three", "Four", "Five"][clampi(n, 0, 5)]
