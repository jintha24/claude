extends SceneTree
## Shared helpers for the automated gameplay tests. Each test script extends this file,
## overrides run_tests(), and is run headless:
##   godot --headless --path . --script res://tests/test_movement.gd
## The process exits with code 0 when every check passed, 1 otherwise.

var harry: Harry
var main: Node
var passed := 0
## Movement/parkour tests remove the constables so nobody arrests Harry mid-test.
var keep_guards := false
var failed := 0
var _errors_before := 0


## A test file that stalls (e.g. after a script error) fails instead of hanging forever.
var watchdog_seconds := 900.0


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > watchdog_seconds * 1000.0:
		print("FAIL  watchdog: %s took longer than %d s" % [get_script().resource_path.get_file(), int(watchdog_seconds)])
		quit(1)
	return false


func _initialize() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_boot.call_deferred()


## Override to load a different scene or tweak it before it enters the tree.
func make_scene() -> Node:
	return load("res://scenes/main/main.tscn").instantiate()


## Tests run at a fixed hour with the clock stopped, unless they say otherwise.
var start_hour := 12.0
var freeze_clock := true


func _boot() -> void:
	GameClock.minutes = start_hour * 60.0
	GameClock.paused = freeze_clock
	main = make_scene()
	root.add_child(main)
	current_scene = main
	if not keep_guards:
		for g in get_nodes_in_group_safe("guards"):
			g.free()
	await wait(5)
	harry = main.get_node_or_null("Harry") as Harry
	await run_tests()
	print("")
	print("RESULT %s: %d passed, %d failed" % [get_script().resource_path.get_file(), passed, failed])
	quit(1 if failed > 0 else 0)


func run_tests() -> void:
	pass


func get_nodes_in_group_safe(group: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in root.find_children("*", "", true, false):
		if n.is_in_group(group):
			out.append(n)
	return out


func wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func release_all() -> void:
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_"):
			Input.action_release(a)


func press_for(action: String, frames: int) -> void:
	Input.action_press(action)
	await wait(frames)
	Input.action_release(action)


## Teleports Harry, resets his state and lets him settle for a few frames.
func tp(pos: Vector3, yaw: float = 0.0, settle: int = 20) -> void:
	release_all()
	if harry.is_dead() or harry.is_arrested():
		harry.respawn()
	harry.parkour.cancel()
	harry.combat.cancel()
	harry.set_crouched(false)
	harry.health = harry.max_health
	harry.stealth.crime_timer = 0.0
	harry.global_position = pos
	harry.velocity = Vector3.ZERO
	harry.facing_yaw = yaw
	harry.set_state(Harry.State.FALL)
	harry.reset_physics_interpolation()
	await wait(settle)


func state_name() -> String:
	return Harry.State.keys()[harry.state]


func describe() -> String:
	return "%s pos=%s hp=%.0f" % [state_name(), harry.global_position.snapped(Vector3.ONE * 0.01), harry.health]


func check(name: String, ok: bool, info: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("%s  %s  | %s | %s" % ["PASS" if ok else "FAIL", name, info, describe() if harry else ""])


## Waits until `cond` returns true or `max_frames` pass. Returns whether it became true.
func wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await wait(1)
	return cond.call()
