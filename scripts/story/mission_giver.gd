class_name MissionGiver
extends Interactable
## Where a mission begins: a character to talk to (E), or a place that starts it when
## Harry walks in (auto_radius > 0: Pip in the market, the bridge). Only the next mission
## in the story is offered, and only at its hours; the HUD marks it with a gold diamond.

@export var mission_id: String = ""
## Text after "[E] " (e.g. "Talk to Aldous").
@export var prompt_text: String = "Begin"
## Starts on its own when Harry comes within this many metres (0 = talk to start).
@export var auto_radius: float = 0.0
## Offered between these hours (x..y, may wrap past midnight); (-1, -1) = any time.
@export var hours: Vector2 = Vector2(-1, -1)

## The character offering the mission, if any (shown only while it's on offer).
var npc: StoryNPC
var _harry: Harry


func _ready() -> void:
	interact_range = 2.4
	add_to_group("mission_givers")


func mission_title() -> String:
	return String(Story.info(mission_id).get("title", ""))


func is_available() -> bool:
	if Story.is_active() or Story.next_mission().get("id", "") != mission_id:
		return false
	return in_hours()


func in_hours() -> bool:
	if hours.x < 0.0:
		return true
	var h := GameClock.hours()
	return (h >= hours.x and h < hours.y) if hours.x <= hours.y else (h >= hours.x or h < hours.y)


func marker_position() -> Vector3:
	if npc and is_instance_valid(npc):
		return npc.global_position + Vector3.UP * 2.3
	return global_position + Vector3.UP * 2.0


func get_interact_point() -> Vector3:
	if npc and is_instance_valid(npc):
		return npc.global_position + Vector3.UP * 1.4
	return global_position + Vector3.UP * 1.2


func get_prompt(_h: Harry) -> String:
	if auto_radius > 0.0 or not is_available():
		return ""
	return "%s  (%s)" % [prompt_text, mission_title()]


func interact(_h: Harry) -> void:
	begin()


func begin() -> Mission:
	if not is_available():
		return null
	return Story.start(get_tree(), mission_id)


func _physics_process(_delta: float) -> void:
	var available := is_available()
	if npc and is_instance_valid(npc):
		npc.visible = available
		npc.process_mode = Node.PROCESS_MODE_INHERIT if available else Node.PROCESS_MODE_DISABLED
		npc.collision_layer = NPCCharacter.LAYER_NPC if available else 0
	if auto_radius <= 0.0 or not available:
		return
	if _harry == null or not is_instance_valid(_harry):
		_harry = get_tree().get_first_node_in_group("player") as Harry
		return
	if _harry.global_position.distance_to(global_position) > auto_radius:
		return
	if _harry.is_dead() or _harry.is_arrested() or _harry.is_riding() or _harry.is_climbing():
		return
	for g in get_tree().get_nodes_in_group("guards"):
		if (g as Guard).state == Guard.State.CHASE:
			return # not while he's being chased
	begin()
