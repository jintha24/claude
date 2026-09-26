extends SceneTree
## A long unattended play session, to shake out bugs, glitches and crashes that the
## focused tests don't reach:
##   godot --headless --path . --script res://tools/soak_test.gd 2>&1 | tee soak.log
## It plays the hills (running about, the camp and villages through the day and night,
## riding Cinder, shooting at game), takes the road to London, criss-crosses the old
## streets and the city in all weathers and hours, starts street incidents, saves and
## loads, and travels back. Throughout it watches for Harry falling out of the world,
## nodes piling up, memory creeping up and long stalls, and prints a report. Engine
## errors show in the log as "ERROR:"; the report counts them.


var _problems: Array[String] = []
var _t0 := 0
var _worst_frame := 0.0
var _worst_where := ""
var _last_tick := 0
var _where := ""
var _baseline_nodes := 0
var _baseline_mem := 0


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last_tick > 0:
		var ms := (now - _last_tick) / 1000.0
		if ms > _worst_frame:
			_worst_frame = ms
			_worst_where = _where
	_last_tick = now
	return false


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	SaveGame.new_game()
	Weather.automatic = true
	await _hills(true)
	await _to_london()
	await _london()
	await _save_and_load()
	await _to_hills()
	await _hills(false)
	_report()


# ---------------------------------------------------------------------------
func _scene() -> Node:
	return current_scene


func _harry() -> Harry:
	return current_scene.get_node_or_null("Harry") as Harry if current_scene else null


func frames(n: int) -> void:
	for i in n:
		await process_frame
		_check_player()


func _check_player() -> void:
	var h := _harry()
	if h == null or not is_instance_valid(h):
		return
	var p := h.global_position
	if p.y < -40.0 or not p.is_finite():
		_problem("Harry fell out of the world at %s (%s)" % [p, _where])
		h.respawn()


func _problem(what: String) -> void:
	if not _problems.has(what):
		_problems.append(what)
	print("SOAK PROBLEM: ", what)


func _go(where: String, p: Vector3) -> void:
	_where = where
	var h := _harry()
	if h == null:
		return
	var streamer := current_scene.get_node_or_null("Streamer") as WorldStreamer
	if streamer:
		p.y = streamer.height_at(p.x, p.z) + 1.0
		streamer.prime(p)
	var city := current_scene.get_node_or_null("City") as CityStreamer
	if city:
		city.prime(p)
	h.global_position = p
	h.velocity = Vector3.ZERO
	h.reset_physics_interpolation()
	await frames(30)


## Runs about: forward with turns, sprints and jumps, for `n` frames.
func _run_about(n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = n
	Input.action_press("move_forward")
	for i in n:
		if i % 90 == 0:
			for a in ["move_left", "move_right", "sprint", "jump"]:
				Input.action_release(a)
			var r := rng.randf()
			Input.action_press("move_left" if r < 0.3 else ("move_right" if r < 0.6 else "sprint"))
			if rng.randf() < 0.3:
				Input.action_press("jump")
		await frames(1)
	for a in ["move_forward", "move_left", "move_right", "sprint", "jump"]:
		Input.action_release(a)


func _hour(h: float) -> void:
	GameClock.advance(fposmod(h * 60.0 - GameClock.minutes, 1440.0))
	await frames(20)


func _wait_for_scene(fragment: String) -> bool:
	for i in 3000:
		await process_frame
		if current_scene and current_scene.scene_file_path.contains(fragment) and _harry() != null:
			await frames(60)
			return true
	_problem("never arrived in %s" % fragment)
	return false


func _checkpoint(label: String) -> void:
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mem := int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576
	print("SOAK %6.1fs %-28s nodes %6d orphans %4d memory %5d MB  worst frame %.0f ms (%s)" % [
		(Time.get_ticks_msec() - _t0) / 1000.0, label, nodes, orphans, mem, _worst_frame, _worst_where])
	if orphans > 200:
		_problem("%d orphan nodes at %s (leak)" % [orphans, label])
	if label.begins_with("hills") and _baseline_nodes == 0:
		_baseline_nodes = nodes
		_baseline_mem = mem


# ---------------------------------------------------------------------------
func _hills(first: bool) -> void:
	if first:
		change_scene_to_file("res://scenes/wilderness/hills.tscn")
		if not await _wait_for_scene("wilderness"):
			return
	var gen := (current_scene.get_node("Streamer") as WorldStreamer).generator
	_checkpoint("hills: arrived")
	for h: float in [6.0, 9.0, 13.0, 18.5, 22.0, 2.0]:
		await _hour(h)
		await _go("the camp at %d:00" % int(h), Vector3(-130.0, 0.0, 96.0))
		await _run_about(240)
	for v: Array in TerrainGenerator.VILLAGES:
		var c: Vector2 = v[1]
		await _go("in %s" % v[0], Vector3(c.x, 0.0, c.y))
		await _run_about(300)
	# Riding Cinder along the road.
	await _go("the London road", Vector3(560.0, 0.0, 470.0))
	var cinder := current_scene.get_node_or_null("Cinder") as Node3D
	var h := _harry()
	if cinder and h:
		cinder.global_position = h.global_position + Vector3(2.0, 0.5, 0.0)
		await frames(10)
		h.try_mount()
		await _run_about(600)
		if h.is_riding():
			Input.action_press("mount_horse")
			await frames(3)
			Input.action_release("mount_horse")
	# Shooting at whatever's about.
	for i in 6:
		Input.action_press("fire")
		await frames(12)
		Input.action_release("fire")
		await frames(20)
	# Up on the far edges of the map.
	for p: Vector2 in [Vector2(-1990, -1990), Vector2(1990, -1990), Vector2(-1990, 1990), Vector2(2000, 610)]:
		await _go("the edge of the hills %s" % p, Vector3(p.x, 0.0, p.y))
		await _run_about(200)
	_checkpoint("hills: done")


func _to_london() -> void:
	_where = "travelling to London"
	var post := current_scene.get_node_or_null("ToLondon")
	if post == null:
		_problem("no road to London")
		return
	post.call("travel")
	await _wait_for_scene("main")
	_checkpoint("london: arrived")


func _london() -> void:
	var enc := current_scene.get_node_or_null("Encounters") as Encounters
	var spots: Array[Vector3] = [
		Vector3(0, 0.3, -60), Vector3(-45, 0.3, -8), Vector3(20, 0.3, 30), Vector3(325, 0.3, -110),
		Vector3(-430, 0.3, 200), Vector3(-900, 0.3, 470), Vector3(600, 0.3, 300), Vector3(115, 0.3, 560),
		Vector3(-300, 0.3, -700), Vector3(1200, 0.3, -1200), Vector3(-1500, 0.3, 1500), Vector3(40, 0.3, 900),
	]
	var hours: Array[float] = [7.5, 11.0, 13.0, 17.5, 20.0, 23.0, 3.0, 9.0]
	var kinds := [Weather.Kind.CLEAR, Weather.Kind.CLOUDY, Weather.Kind.LIGHT_RAIN, Weather.Kind.STORM, Weather.Kind.FOG, Weather.Kind.SNOW]
	for i in spots.size():
		await _hour(hours[i % hours.size()])
		Weather.set_weather(kinds[i % kinds.size()], true)
		await _go("London %s" % spots[i], spots[i])
		if enc and i % 3 == 0:
			enc.start_random()
		await _run_about(360)
		if i % 4 == 3:
			_checkpoint("london: %d spots" % (i + 1))
	Weather.set_weather(Weather.Kind.CLEAR, true)
	_checkpoint("london: done")


func _save_and_load() -> void:
	_where = "saving and loading"
	if not SaveGame.save(self, 3):
		_problem("couldn't save")
		return
	await frames(10)
	if not SaveGame.load_game(self, 3):
		_problem("couldn't load the save")
		return
	await _wait_for_scene("main")
	await frames(120)
	SaveGame.delete(3)
	_checkpoint("london: after load")


func _to_hills() -> void:
	_where = "travelling to the hills"
	await _go("the Hills road", Vector3(-81.0, 0.3, 70.0))
	var post: Node = null
	for n in current_scene.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("travel_point.gd") and String(n.get("destination_scene")).contains("wilderness"):
			post = n
			break
	if post == null:
		_problem("no road back to the hills")
		return
	post.call("travel")
	await _wait_for_scene("wilderness")
	_checkpoint("hills: back")


func _report() -> void:
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var mem := int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576
	if _baseline_nodes > 0 and nodes > _baseline_nodes * 1.5 + 2000:
		_problem("nodes piled up in the hills: %d at the start, %d at the end" % [_baseline_nodes, nodes])
	if _baseline_mem > 0 and mem > _baseline_mem * 1.6 + 300:
		_problem("memory crept up: %d MB at the start, %d MB at the end" % [_baseline_mem, mem])
	print("")
	print("SOAK REPORT: %.0f s of play, worst frame %.0f ms (%s)" % [(Time.get_ticks_msec() - _t0) / 1000.0, _worst_frame, _worst_where])
	for p in _problems:
		print("SOAK PROBLEM: ", p)
	print("SOAK %s" % ("OK" if _problems.is_empty() else "FOUND %d PROBLEMS" % _problems.size()))
	quit(0 if _problems.is_empty() else 1)
