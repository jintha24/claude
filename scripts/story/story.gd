class_name Story
extends Node
## The story's progress (docs/STORY.md): which missions are done, the one being played,
## story flags (choices made, who has joined the Lantern Men) and the ending.
##
## Like Progress, it's a self-creating singleton: use the static functions and connect to
## Story.bus() signals. Missions are Mission nodes (scripts/story/act1/...), started by a
## MissionGiver in the world (or Story.start()), run as coroutines, and saved with the
## game once complete. A mission can't be saved half-way: it restarts from its last
## checkpoint if Harry fails, and from the beginning if the game is quit.

signal mission_started(id: String)
signal mission_completed(id: String)
signal mission_failed(id: String, reason: String)
signal objective_changed(text: String)
signal flag_changed(key: String)

## Every mission, in story order. "place" is where it's played ("london" / "hills").
const MISSIONS: Array[Dictionary] = [
	{"id": "cold_hearth", "number": 1, "act": 1, "title": "Cold Hearth", "place": "hills",
		"script": "res://scripts/story/act1/m1_cold_hearth.gd",
		"blurb": "The larder's bare and winter's coming. Old Aldous has a lesson or two left in him."},
	{"id": "crowded_pockets", "number": 2, "act": 1, "title": "Crowded Pockets", "place": "london",
		"script": "res://scripts/story/act1/m2_crowded_pockets.gd",
		"blurb": "Spitalfields market by day: every purse in London passes through it. Including yours."},
	{"id": "the_collector", "number": 3, "act": 1, "title": "The Collector", "place": "london",
		"script": "res://scripts/story/act1/m3_the_collector.gd",
		"blurb": "Ashcombe's rent man has taken a widow's last shillings."},
	{"id": "the_bridge", "number": 4, "act": 1, "title": "The Bridge", "place": "london",
		"script": "res://scripts/story/act1/m4_the_bridge.gd",
		"blurb": "One narrow footbridge over the Fleet ditch, and a very large man standing on it."},
	{"id": "bernards_kitchen", "number": 5, "act": 1, "title": "Father Bernard's Kitchen", "place": "london",
		"script": "res://scripts/story/act1/m5_bernards_kitchen.gd",
		"blurb": "Tom knows a priest who feeds the rookery, and asks no questions about where the money comes from."},
	{"id": "wanted", "number": 6, "act": 1, "title": "Wanted: The Hill Fox", "place": "london",
		"script": "res://scripts/story/act1/m6_wanted.gd",
		"blurb": "The newspapers have given you a name. Captain Crowe has given you a price."},
]
const ACT_TITLES := {1: "The Outlaw of the Hills", 2: "Steal from the Rich", 3: "The Price of a Legend", 4: "The Last Heist"}

static var completed: Array[String] = []
static var flags: Dictionary = {}
static var active: Mission = null
## The checkpoint the active mission restarts from if Harry fails.
static var checkpoint: Dictionary = {}
static var _bus: Story


static func bus() -> Story:
	if _bus == null or not is_instance_valid(_bus):
		_bus = Story.new()
		_bus.name = "Story"
		var tree := Engine.get_main_loop() as SceneTree
		tree.root.add_child.call_deferred(_bus)
	return _bus


static func reset() -> void:
	completed.clear()
	flags.clear()
	checkpoint = {}
	if active and is_instance_valid(active):
		active.queue_free()
	active = null


static func info(id: String) -> Dictionary:
	for m in MISSIONS:
		if m["id"] == id:
			return m
	return {}


static func is_done(id: String) -> bool:
	return id in completed


static func is_active() -> bool:
	return active != null and is_instance_valid(active) and not active.finished


## The next mission to play ({} once the Act is finished).
static func next_mission() -> Dictionary:
	for m in MISSIONS:
		if not is_done(m["id"]):
			return m
	return {}


## The act Harry is in (the next mission's; 1 after the last written mission's act ends).
static func act() -> int:
	var n := next_mission()
	return int(n["act"]) if not n.is_empty() else int(MISSIONS.back()["act"]) + 1


static func get_flag(key: String, default: Variant = false) -> Variant:
	return flags.get(key, default)


static func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value
	bus().flag_changed.emit(key)


## The Lantern Men who have joined (in joining order).
static func band() -> Array[String]:
	var out: Array[String] = []
	for k: String in flags:
		if k.begins_with("band_") and bool(flags[k]):
			out.append(k.substr(5))
	return out


static func has_band(member: String) -> bool:
	return bool(flags.get("band_" + member, false))


static func join_band(member: String) -> void:
	set_flag("band_" + member, true)


## "london" or "hills": where the current scene is.
static func place_of(tree: SceneTree) -> String:
	var scene := tree.current_scene
	if scene and scene.scene_file_path.contains("wilderness"):
		return "hills"
	return "london"


## Starts mission `id` (from checkpoint step `from_step`). Returns the Mission node.
static func start(tree: SceneTree, id: String, from_step: int = 0) -> Mission:
	var m := info(id)
	if m.is_empty() or is_active():
		return null
	var script := load(m["script"]) as GDScript
	var mission := script.new() as Mission
	mission.id = id
	mission.title = m["title"]
	mission.name = "Mission_" + id
	active = mission
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	parent.add_child(mission)
	mission.begin(from_step)
	bus().mission_started.emit(id)
	return mission


## Called by the mission when it's won.
static func on_completed(mission: Mission) -> void:
	if not mission.id in completed:
		completed.append(mission.id)
	checkpoint = {}
	if active == mission:
		active = null
	bus().mission_completed.emit(mission.id)


## Called by the mission when it's lost; it stays in the tree until retried or abandoned.
static func on_failed(mission: Mission, reason: String) -> void:
	bus().mission_failed.emit(mission.id, reason)


## Restarts the failed (or active) mission from its last checkpoint.
static func retry(tree: SceneTree) -> Mission:
	if active == null or not is_instance_valid(active):
		return null
	var id := active.id
	var cp := checkpoint.duplicate(true)
	active.cleanup()
	active.queue_free()
	active = null
	var step := int(cp.get("step", 0))
	Mission.restore_snapshot(tree, cp)
	var m := start(tree, id, step)
	return m


## Gives up on the active mission (it can be started again from its giver).
static func abandon() -> void:
	if active and is_instance_valid(active):
		active.cleanup()
		active.queue_free()
	active = null
	checkpoint = {}


## The ending the story is heading for: the Ledger choice (made in Act 3) and the Legend.
static func ending() -> Dictionary:
	var choice: String = get_flag("ledger_choice", "")
	var high := Progress.legend >= 60.0
	match choice:
		"keep":
			return {"id": "outlaw_king", "title": "The Outlaw King", "text": "Harry keeps the Iron Ledger and bleeds the rich with it. One by one the Lantern Men walk away."}
		"burn":
			return {"id": "the_ghost", "title": "The Ghost", "text": "The Ledger burns; every last sovereign of Ashcombe's gold goes to the slums, and the Hill Fox is never seen again." + (" In St Giles, Pip opens a school." if high else "")}
	return {"id": "the_legend", "title": "The Legend", "text": "The Ledger reaches the Royal Commission. Ashcombe and Crowe are taken; Harry refuses the pardon and goes home to the hills." + (" In St Giles, Pip opens a school." if high else " London's poor barely remember his name.")}


static func to_dict() -> Dictionary:
	return {"completed": completed.duplicate(), "flags": flags.duplicate(true)}


static func from_dict(d: Dictionary) -> void:
	reset()
	for id in d.get("completed", []):
		completed.append(String(id))
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
