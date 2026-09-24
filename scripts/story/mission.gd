class_name Mission
extends Node
## Base class for a story mission. A mission is a list of steps, each a coroutine
## (run_step), played in order. At the start of every step the game takes a checkpoint:
## if Harry is arrested, badly hurt or fails the step's own condition, the player can
## retry from there (Story.retry) or abandon the mission.
##
## Subclasses override step_count(), setup(from_step) (put the mission's people and props
## where they belong for the step it starts from) and run_step(i). Inside a step, use:
##   set_objective(text, target)      - the HUD objective and its marker (Vector3 / Node3D)
##   await until(func: condition)      - wait for something (false if the mission ended)
##   await wait(seconds)
##   await say([["Aldous", "line"], ...])       - conversation (controls locked)
##   bark("Pip", "line")               - a line said in passing
##   await cutscene([{shot}, ...])      - in-engine cutscene (see CutscenePlayer)
##   await choose(title, text, ["a", "b"])  - a choice; returns the index picked
##   spawn(node)                       - add a node that's removed when the mission ends
##   fail(reason) / complete()
## Missions only ever wait on their own tick, so a failed mission's coroutines simply stop.

signal ticked

var id: String = ""
var title: String = ""
var harry: Harry
var step: int = 0
var objective: String = ""
var objective_target: Variant = null
var finished := false
var failed := false
var fail_reason := ""

var _spawned: Array[Node] = []
var _start_step := 0
var _elapsed := 0.0


## How many steps the mission has.
func step_count() -> int:
	return 0


## Places the mission's people and props for a start (or restart) at step `from_step`.
func setup(_from_step: int) -> void:
	pass


## Plays step `i` (a coroutine).
func run_step(_i: int) -> void:
	pass


## Called once the mission is won, before Story records it (rewards, flags).
func on_complete() -> void:
	pass


func begin(from_step: int) -> void:
	_start_step = from_step
	step = from_step
	harry = get_tree().get_first_node_in_group("player") as Harry
	_run.call_deferred()


func _run() -> void:
	if harry == null:
		harry = get_tree().get_first_node_in_group("player") as Harry
	setup(_start_step)
	for i in range(_start_step, step_count()):
		step = i
		take_checkpoint()
		await run_step(i)
		if finished:
			return
	complete()


func _physics_process(delta: float) -> void:
	if finished:
		return
	_elapsed += delta
	if harry and (harry.is_dead() or harry.is_arrested()):
		fail("You were badly hurt." if harry.is_dead() else "Captain Crowe's men have taken you.")
		return
	ticked.emit()


# ---------------------------------------------------------------------------
# Scripting helpers
# ---------------------------------------------------------------------------
func set_objective(text: String, target: Variant = null) -> void:
	objective = text
	objective_target = target
	Story.bus().objective_changed.emit(text)


## World position of the objective marker (or Vector3.INF for none).
func objective_position() -> Vector3:
	if objective_target is Vector3:
		return objective_target
	if objective_target is Node3D and is_instance_valid(objective_target):
		return (objective_target as Node3D).global_position + Vector3.UP * 1.9
	return Vector3.INF


## Waits until `cond` returns true. Returns false if the mission ends first (or after
## `timeout` seconds, if given).
func until(cond: Callable, timeout: float = -1.0) -> bool:
	var t := 0.0
	while not finished:
		if cond.call():
			return true
		await ticked
		t += get_physics_process_delta_time()
		if timeout > 0.0 and t >= timeout:
			return false
	return false


func wait(seconds: float) -> void:
	var t := 0.0
	while not finished and t < seconds:
		await ticked
		t += get_physics_process_delta_time()


## A conversation. `lines` are [speaker, text] pairs; Harry can't move until it's over.
func say(lines: Array, lock: bool = true) -> void:
	var ui := StoryUI.find(get_tree())
	if harry and lock:
		harry.controls_locked = true
	ui.dialogue.play(lines)
	while not finished and ui.dialogue.is_playing():
		await ticked
	if harry and lock:
		harry.controls_locked = false


## A line said in passing (subtitled; doesn't stop the game).
func bark(speaker: String, text: String) -> void:
	StoryUI.find(get_tree()).dialogue.subtitle(speaker, text)


## Plays an in-engine cutscene (see CutscenePlayer for the shot format).
func cutscene(shots: Array) -> void:
	var ui := StoryUI.find(get_tree())
	if harry:
		harry.controls_locked = true
	ui.cutscene.play(shots)
	while not finished and ui.cutscene.is_playing():
		await ticked
	if harry:
		harry.controls_locked = false


## Offers a choice; returns the index of the option taken.
func choose(heading: String, text: String, options: Array) -> int:
	var picked := [-1]
	var opts: Array[Dictionary] = []
	for i in options.size():
		var idx := i
		opts.append({"text": options[i], "enabled": true, "action": func() -> void: picked[0] = idx})
	var menu := ChoiceMenu.open(get_tree(), heading, text, opts)
	menu.cancellable = false
	while not finished and picked[0] < 0:
		if not is_instance_valid(menu):
			menu = ChoiceMenu.open(get_tree(), heading, text, opts)
			menu.cancellable = false
		await ticked
	return picked[0]


## Adds a node to the scene for this mission; it's removed when the mission ends.
func spawn(node: Node, parent: Node = null) -> Node:
	(parent if parent else get_tree().current_scene).add_child(node)
	_spawned.append(node)
	return node


## Spawns a story character for this mission at `pos` (on the ground), facing `face_to`.
func npc(display: String, outfit: NPCBody.Outfit, height: float, pos: Vector3, face_to: Variant = null, pose: NPCBody.Pose = NPCBody.Pose.NORMAL) -> StoryNPC:
	var n := StoryNPC.new()
	n.name = display.replace(" ", "")
	n.display_name = display
	n.outfit = outfit
	n.body_height = height
	n.idle_pose = pose
	var at := ground(pos)
	if face_to is Vector3:
		n.rotation.y = atan2(-((face_to as Vector3).x - at.x), -((face_to as Vector3).z - at.z))
	spawn(n)
	n.global_position = at
	if face_to != null:
		n.face(face_to)
	return n


## `p` put on the ground (the hills' terrain height; in town, as given).
func ground(p: Vector3) -> Vector3:
	var s := get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	if s:
		return Vector3(p.x, s.height_at(p.x, p.z) + 0.05, p.z)
	return p


func harry_near(p: Vector3, radius: float) -> bool:
	return harry != null and harry.global_position.distance_to(p) <= radius


## How many things Harry carries for which `pred(item)` is true.
func count_items(pred: Callable) -> int:
	if harry == null:
		return 0
	return harry.inventory.items.filter(pred).size()


func fail(reason: String) -> void:
	if finished:
		return
	finished = true
	failed = true
	fail_reason = reason
	if harry:
		harry.controls_locked = false
	Story.on_failed(self, reason)


func complete() -> void:
	if finished:
		return
	finished = true
	if harry:
		harry.controls_locked = false
	objective = ""
	objective_target = null
	on_complete()
	cleanup()
	Story.on_completed(self)
	queue_free()


## Removes everything the mission spawned.
func cleanup() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			# Out of the tree at once, so a restarted mission can use the same names.
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.queue_free()
	_spawned.clear()


func _exit_tree() -> void:
	cleanup()


# ---------------------------------------------------------------------------
# Checkpoints
# ---------------------------------------------------------------------------
## Records Harry's state now, to restart this step from if he fails.
func take_checkpoint() -> void:
	if harry == null:
		return
	var saved := GameState.player
	GameState.capture(harry)
	Story.checkpoint = {
		"step": step,
		"position": harry.global_position,
		"yaw": harry.facing_yaw,
		"player": GameState.player.duplicate(true),
		"legend": Progress.legend,
		"notoriety": Progress.notoriety,
		"given": Progress.given_total,
	}
	GameState.player = saved


## Puts Harry back as he was at the checkpoint.
static func restore_snapshot(tree: SceneTree, cp: Dictionary) -> void:
	var h := tree.get_first_node_in_group("player") as Harry
	if h == null or cp.is_empty():
		return
	tree.paused = false
	if h.is_riding():
		h.dismount()
	h.respawn() # clears arrest/death and resets the guards
	var saved := GameState.player
	GameState.player = cp.get("player", {})
	GameState.restore(h)
	GameState.player = saved
	h.health = h.max_health
	h.health_changed.emit(h.health, h.max_health)
	h.global_position = cp.get("position", h.global_position)
	h.facing_yaw = float(cp.get("yaw", h.facing_yaw))
	h.velocity = Vector3.ZERO
	h.reset_physics_interpolation()
	h.controls_locked = false
	Progress.legend = float(cp.get("legend", Progress.legend))
	Progress.notoriety = float(cp.get("notoriety", Progress.notoriety))
	Progress.given_total = int(cp.get("given", Progress.given_total))
	tree.call_group("guards", "reset_after_player_respawn")
