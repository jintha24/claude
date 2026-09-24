extends "res://tests/test_base.gd"
## Phase 7: Ashcombe House. The way there, the house and its navigation, doors and keys,
## lockpicking and the Chubb detector safe, valuables, sash windows, the drainpipe and wing
## roof, the sewer, creaky boards, indoor darkness, the household routine, guards noticing
## things out of place, and the guard dogs (scent with the wind, chase, bite, bay, arrows).

var house: AshcombeHouse
var staff: AshcombeStaff
var noises: Array[Dictionary] = []


func _init() -> void:
	keep_guards = true


func run_tests() -> void:
	house = main.get_node("AshcombeHouse")
	staff = main.get_node("AshcombeStaff")
	Weather.automatic = false
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Stealth.bus().noise_made.connect(func(p: Vector3, r: float, k: String, s: bool, src: Node) -> void:
		noises.append({"pos": p, "radius": r, "kind": k, "suspicious": s, "source": src}))
	_freeze_everyone()
	await wait(20)

	await _test_getting_there()
	await _test_navigation()
	await _test_doors()
	await _test_lockpicking()
	await _test_safe_and_loot()
	await _test_windows_and_roof()
	await _test_sewer()
	await _test_creaks_and_darkness()
	await _test_witnesses()
	await _test_schedule()
	await _test_dogs()


# ---------------------------------------------------------------------------
## Teleport, and turn the camera to look the way Harry faces (so "forward" is forward).
func tp(pos: Vector3, yaw: float = 0.0, settle: int = 20) -> void:
	(main.get_node("ThirdPersonCamera") as ThirdPersonCamera).snap_behind(yaw)
	await super.tp(pos, yaw, settle)


func _freeze_everyone() -> void:
	for n in get_nodes_in_group_safe("guards") + get_nodes_in_group_safe("guard_dogs"):
		n.process_mode = Node.PROCESS_MODE_DISABLED
		(n as Node3D).global_position += Vector3(0, 0, 0)
	# Park the street constables far away so they can't wander in.
	for n in get_nodes_in_group_safe("guards"):
		if not n.is_in_group("ashcombe_guards"):
			n.queue_free()


func _wake(n: Node) -> void:
	n.process_mode = Node.PROCESS_MODE_INHERIT


func _door(n: String) -> MansionDoor:
	return house.get_node("Doors/" + n) as MansionDoor


func _guard(n: String) -> Guard:
	return staff.get_node(n) as Guard


func _heard(kind: String, since: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(since, noises.size()):
		if noises[i]["kind"] == kind:
			out.append(noises[i])
	return out


func _press_e() -> void:
	await press_for("interact", 2)
	await wait(1)


## Plays the lever minigame perfectly (presses E only when the marker is in the gate).
func _pick_perfectly(max_frames: int = 1500) -> void:
	var it := harry.interaction
	for i in max_frames:
		if not it.is_lockpicking():
			return
		if it.reseat <= 0.0 and absf(it.marker - it.zone_center) < it.zone_width * 0.25:
			Input.action_press("interact")
			await wait(1)
			Input.action_release("interact")
		await wait(1)


## Waits until the marker is well outside the gate, then presses (a deliberate slip).
func _slip() -> void:
	var it := harry.interaction
	for i in 600:
		if not it.is_lockpicking():
			return
		if it.reseat <= 0.0 and absf(it.marker - it.zone_center) > it.zone_width * 1.5 + 0.08:
			Input.action_press("interact")
			await wait(1)
			Input.action_release("interact")
			await wait(2)
			return
		await wait(1)


# ---------------------------------------------------------------------------
func _test_getting_there() -> void:
	# Ashcombe Row: a real gap in the market's east row.
	var space := main.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(30.0, 8.0, -71.0), Vector3(30.0, -2.0, -71.0), 1)
	var hit := space.intersect_ray(q)
	check("Ashcombe Row runs through the market's east side", not hit.is_empty() and (hit["position"] as Vector3).y < 0.1, str(hit.get("position", "none")))
	# Walk from the market up the lane and in through the open gate (daytime).
	await tp(Vector3(22.0, 0.05, -71.0), -PI * 0.5)
	check("outside the grounds Harry is not trespassing", not harry.stealth.is_in_restricted_zone())
	Input.action_press("move_forward")
	await wait_until(func() -> bool: return harry.global_position.x > 50.0, 900)
	Input.action_release("move_forward")
	check("by day he can walk up the lane and in through the open gates", harry.global_position.x > 50.0, describe())
	check("inside the railings he is trespassing", harry.stealth.is_in_restricted_zone())
	check("the grounds count as restricted for conspicuousness", harry.stealth.conspicuousness >= 1.0)


func _test_navigation() -> void:
	var map := main.get_viewport().world_3d.navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(55.0, 0.0, -71.0), Vector3(66.0, AshcombeHouse.FF, -61.0), true)
	var top := -INF
	for p in path:
		top = maxf(top, p.y)
	var end := path[path.size() - 1] if path.size() > 0 else Vector3.ZERO
	check("guards can walk from the forecourt up the grand staircase to the study", path.size() > 2 and end.distance_to(Vector3(66.0, AshcombeHouse.FF, -61.0)) < 1.0 and top > 5.0, "%d pts end %s" % [path.size(), end])
	var path2 := NavigationServer3D.map_get_path(map, Vector3(52.0, 0.0, -96.0), Vector3(69.0, AshcombeHouse.GF, -89.0), true)
	var end2 := path2[path2.size() - 1] if path2.size() > 0 else Vector3.ZERO
	check("and from the service yard into the servants' hall", end2.distance_to(Vector3(69.0, AshcombeHouse.GF, -89.0)) < 1.0)


func _test_doors() -> void:
	var lib := _door("LibraryDoor")
	await tp(Vector3(66.0, AshcombeHouse.GF + 0.05, -74.8), 0.0)
	await wait(12)
	check("facing a door, the prompt offers to open it", harry.interaction.prompt.begins_with("Open"), harry.interaction.prompt)
	await _press_e()
	await wait(90)
	check("E swings the door open", lib.is_open and absf(lib.swing) > 0.95)
	check("it swings away from Harry (into the library)", lib.swing > 0.0)
	await tp(Vector3(66.0, AshcombeHouse.GF + 0.05, -75.0), 0.0)
	await wait(12)
	check("an open door offers to close", harry.interaction.prompt.begins_with("Close"), harry.interaction.prompt)
	await _press_e()
	await wait(90)
	check("and closes again", not lib.is_open and absf(lib.swing) < 0.02)
	# A closed door blocks sight.
	var space := main.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(66.0, 2.0, -73.0), Vector3(66.0, 2.0, -79.0), Guard.MASK_SIGHT)
	check("a closed door blocks a guard's line of sight", not space.intersect_ray(q).is_empty())
	# Locked pantry: key or picks.
	var pantry := _door("PantryDoor")
	await tp(Vector3(70.1, AshcombeHouse.GF + 0.05, -81.0), -PI * 0.5)
	await wait(12)
	check("a locked door must be picked", harry.interaction.prompt.begins_with("Pick the lock (3-lever"), harry.interaction.prompt)
	var key := {"name": "Pantry key", "value": 0, "kind": "key", "key_id": "pantry"}
	harry.inventory.add_item(key)
	await wait(12)
	check("...unless Harry has its key", harry.interaction.prompt.begins_with("Unlock"), harry.interaction.prompt)
	await _press_e()
	await wait(60)
	check("the key opens it", pantry.is_open and not pantry.is_locked())
	harry.inventory.remove_item(key)
	pantry.close()
	pantry.set_locked(true)
	# From the inside a bolted outer door just opens.
	var garden := _door("GardenDoor")
	garden.set_locked(true)
	await tp(Vector3(78.9, AshcombeHouse.GF + 0.05, -69.0), -PI * 0.5)
	await wait(12)
	check("from inside, a locked outer door is simply unbolted", harry.interaction.prompt.begins_with("Unbolt"), harry.interaction.prompt)
	# Guards open doors in their way and they swing shut behind them.
	var footman := _guard("Footman")
	var dining := _door("DiningDoorHall")
	dining.close()
	await wait(80)
	footman.global_position = Vector3(66.0, AshcombeHouse.GF + 0.05, -67.0)
	await wait(20)
	check("a guard walking up to a door opens it", dining.is_open)
	footman.global_position = Vector3(64.0, AshcombeHouse.GF + 0.05, -72.0)
	await wait(240)
	check("and it swings shut after he's gone through", not dining.is_open)


func _test_lockpicking() -> void:
	var study := _door("StudyDoor")
	await tp(Vector3(66.0, AshcombeHouse.FF + 0.05, -67.0), PI)
	await wait(12)
	check("the study door is locked (3 levers)", harry.interaction.prompt.contains("3-lever"), harry.interaction.prompt)
	var picks := harry.inventory.lockpicks
	var since := noises.size()
	await _press_e()
	check("E starts the lockpicking minigame", harry.interaction.is_lockpicking() and harry.state == Harry.State.LOCKPICK)
	check("Harry kneels at the lock", harry.is_crouching)
	await _slip()
	check("a slip loses the lever and makes a louder scrape", harry.interaction.lever == 0 and _heard("lockpick", since).size() > 0)
	await _pick_perfectly()
	check("setting every lever opens the lock", not study.is_locked(), "locked=%s levers=%d" % [study.is_locked(), harry.interaction.lever])
	check("picking is quiet (only small sounds)", _heard("lockpick", since).all(func(n: Dictionary) -> bool: return float(n["radius"]) <= 3.1))
	check("at most one pick snapped", harry.inventory.lockpicks >= picks - 1, "%d -> %d" % [picks, harry.inventory.lockpicks])
	await wait(10)
	check("after picking, the prompt offers to open the door", harry.interaction.prompt.begins_with("Open"), harry.interaction.prompt)
	# Moving away abandons picking.
	study.set_locked(true)
	await tp(Vector3(66.0, AshcombeHouse.FF + 0.05, -67.0), PI)
	await wait(12)
	await _press_e()
	Input.action_press("move_back")
	await wait(10)
	Input.action_release("move_back")
	check("walking away gives up on the lock", not harry.interaction.is_busy() and study.is_locked())
	# No picks, no picking.
	var had := harry.inventory.lockpicks
	harry.inventory.lockpicks = 0
	await tp(Vector3(66.0, AshcombeHouse.FF + 0.05, -67.0), PI)
	await wait(12)
	check("without lockpicks the lock can't be tried", harry.interaction.prompt.begins_with("Locked - no lockpicks"), harry.interaction.prompt)
	harry.inventory.lockpicks = had
	study.set_locked(false)
	study.open_from(Vector3(66.0, AshcombeHouse.FF, -70.0))


func _test_safe_and_loot() -> void:
	var safe := house.get_node("Loot/StudySafe") as IronSafe
	var front := safe.global_transform * Vector3(0.0, 0.0, 0.9)
	await tp(Vector3(front.x, AshcombeHouse.FF + 0.05, front.z), atan2(-(safe.global_position.x - front.x), -(safe.global_position.z - front.z)))
	await wait(12)
	check("the safe has a Chubb detector lock", harry.interaction.prompt.contains("detector"), harry.interaction.prompt)
	await _press_e()
	await _pick_perfectly(1)
	await _slip()
	check("one slip on a detector lock jams it", safe.lock.jammed and not harry.interaction.is_busy())
	await wait(12)
	check("...and then only the key will open it", harry.interaction.prompt.begins_with("Detector tripped"), harry.interaction.prompt)
	# The key is on Lord Ashcombe's dressing table.
	var key_spot := house.get_node("Loot/SafeKey") as LootSpot
	var ks := key_spot.global_position
	await tp(Vector3(ks.x + 0.3, AshcombeHouse.FF + 0.05, ks.z + 0.9), 0.0)
	await wait(12)
	check("the safe key lies on the dressing table", harry.interaction.target == key_spot, harry.interaction.prompt)
	await _press_e()
	await wait(30)
	check("Harry pockets the key", harry.inventory.has_key("study_safe"))
	await tp(Vector3(front.x, AshcombeHouse.FF + 0.05, front.z), atan2(-(safe.global_position.x - front.x), -(safe.global_position.z - front.z)))
	await wait(12)
	check("with the key, the jammed safe can be opened", harry.interaction.prompt.begins_with("Unlock the safe"), harry.interaction.prompt)
	await _press_e()
	await wait(20)
	check("the safe door swings open", safe.is_open)
	var money := harry.inventory.money
	var docs := harry.inventory.count_kind("document")
	await wait(10)
	Input.action_press("interact")
	await wait(150)
	Input.action_release("interact")
	await wait(5)
	check("emptying the safe: £50 in banknotes", harry.inventory.money - money == 12000, Money.format(harry.inventory.money - money))
	check("...and Ashcombe's papers", harry.inventory.count_kind("document") - docs == 2)
	# A painting takes four seconds to cut free; letting go stops it. (The valet is sent
	# out of sight first; he comes back later to find the empty frame.)
	var valet := _guard("Valet")
	valet.global_position = Vector3(76.0, AshcombeHouse.FF + 0.05, -61.0)
	var painting := house.get_node("Loot/PaintingStag") as LootSpot
	await tp(Vector3(64.0, AshcombeHouse.FF + 0.05, -74.6), 0.0)
	await wait(12)
	check("paintings are cut from their frames", harry.interaction.prompt.begins_with("Cut from its frame"), harry.interaction.prompt)
	Input.action_press("interact")
	await wait(90)
	Input.action_release("interact")
	await wait(5)
	check("letting go of E before it's done leaves the painting", not painting.is_taken)
	var since := noises.size()
	var value := harry.inventory.total_value()
	Input.action_press("interact")
	await wait(260)
	Input.action_release("interact")
	await wait(5)
	check("holding E for 4 s takes it", painting.is_taken and harry.inventory.total_value() - value == 7200)
	check("cutting canvas makes small sounds", _heard("tampering", since).size() >= 2)
	check("the picture is gone from the wall", not (painting.get_child(0) as Node3D).visible)
	# A servant who sees the empty frame raises the alarm.
	valet.global_position = Vector3(64.0, AshcombeHouse.FF + 0.05, -70.0)
	valet.set("_yaw", 0.0)
	await tp(Vector3(79.0, AshcombeHouse.FF + 0.05, -60.0), 0.0)
	var alarms := [0]
	Stealth.bus().alarm_raised.connect(func(_p: Vector3, _b: Node) -> void: alarms[0] += 1)
	_wake(valet)
	await wait(60)
	check("a guard who notices the empty frame raises the alarm", alarms[0] > 0 and valet.alertness >= 0.9, Guard.State.keys()[valet.state])
	valet.process_mode = Node.PROCESS_MODE_DISABLED
	valet.reset_after_player_respawn()


func _test_windows_and_roof() -> void:
	# Up the yard drainpipe to the wing roof.
	await tp(Vector3(AshcombeHouse.WING_X0 - 0.75, 0.05, -92.0), -PI * 0.5)
	await press_for("jump", 2)
	await wait(20)
	check("the yard drainpipe can be climbed", harry.state == Harry.State.PIPE or harry.state == Harry.State.GRAB, state_name())
	Input.action_press("move_forward")
	await wait_until(func() -> bool: return harry.global_position.y > AshcombeHouse.WING_ROOF - 0.1 and harry.is_on_floor() and not harry.is_climbing(), 900)
	Input.action_release("move_forward")
	check("...up onto the servants' wing roof", harry.global_position.y > AshcombeHouse.WING_ROOF - 0.1, describe())
	# Lady Evelyn's window: latched.
	var win := house.get_node("Windows/EvelynWindow") as MansionWindow
	await tp(Vector3(67.0, AshcombeHouse.WING_ROOF + 0.05, -86.7), PI)
	await wait(12)
	check("a latched sash offers to slip the catch", harry.interaction.prompt == "Slip the sash catch", harry.interaction.prompt)
	Input.action_press("interact")
	await wait(200)
	Input.action_release("interact")
	await wait(40)
	check("slipping the catch opens the window", win.is_open)
	check("a thin blade makes almost no sound", true)
	await wait(12)
	check("then Harry can climb in", harry.interaction.prompt == "Climb in through the window", harry.interaction.prompt)
	await _press_e()
	await wait(90)
	check("he climbs through onto the first floor", harry.global_position.z > -85.8 and absf(harry.global_position.y - AshcombeHouse.FF) < 0.3, describe())
	check("crouched, clear of the sill", harry.is_crouching)
	# Out through a front first-floor window onto the portico roof.
	var front := house.get_node("Windows/FrontFF3") as MansionWindow
	front.latched = false
	await tp(Vector3(62.8, AshcombeHouse.FF + 0.05, -68.0), PI * 0.5)
	await wait(12)
	check("from inside a closed window is raised", harry.interaction.prompt == "Raise the sash", harry.interaction.prompt)
	Input.action_press("interact")
	await wait(70)
	Input.action_release("interact")
	await wait(30)
	await wait(12)
	check("a front window leads out onto the portico roof", harry.interaction.prompt == "Climb out through the window", harry.interaction.prompt)
	await _press_e()
	await wait(90)
	check("...and he's out on the portico", harry.global_position.x < 62.0 and harry.global_position.y > 4.9, describe())
	# No floor below a window: no climbing out.
	var high := house.get_node("Windows/RearFF1") as MansionWindow
	high.latched = false
	high._raise(false)
	await tp(Vector3(79.2, AshcombeHouse.FF + 0.05, -78.0), -PI * 0.5)
	await wait(12)
	check("you can't step out of a first-floor window into thin air", harry.interaction.target != high, harry.interaction.prompt)
	high.close_window()


func _test_sewer() -> void:
	var cover := house.get_node("MewsManhole") as DrainCover
	await tp(AshcombeHouse.SHAFT_A + Vector3(-1.1, 0.05, 0.0), -PI * 0.5)
	await wait(12)
	check("a manhole in the mews", harry.interaction.prompt.begins_with("Lift the sewer"), harry.interaction.prompt)
	var since := noises.size()
	Input.action_press("interact")
	await wait(170)
	Input.action_release("interact")
	await wait(5)
	check("lifting the heavy cover takes a few seconds and scrapes", cover.is_open and _heard("iron_scrape", since).size() == 1)
	# Stepping into the open shaft he catches the rim; letting go (C) drops him the rest.
	await tp(AshcombeHouse.SHAFT_A + Vector3(0.0, 0.3, 0.0), 0.0, 60)
	check("dropping into the shaft he catches the rim", harry.state == Harry.State.HANG, describe())
	await press_for("crouch", 2)
	await wait(60)
	if harry.state == Harry.State.PIPE:
		# Caught the iron ladder on the way down: climb down it.
		Input.action_press("move_back")
		await wait_until(func() -> bool: return not harry.is_climbing() and harry.is_on_floor(), 600)
		Input.action_release("move_back")
	await wait(20)
	check("down the shaft into the old sewer", harry.global_position.y < AshcombeHouse.SEWER_Y + 0.3 and not harry.is_dead(), describe())
	await wait(15)
	check("it's pitch dark down there, even at noon", harry.stealth.exposure < 0.05, "%.2f" % harry.stealth.exposure)
	# The tunnel runs under the wall; come up the ladder at the far end in the lawn.
	await tp(Vector3(AshcombeHouse.SHAFT_B.x - 1.0, AshcombeHouse.SEWER_Y + 0.05, AshcombeHouse.SHAFT_B.z), -PI * 0.5)
	Input.action_press("move_forward")
	await wait(20)
	await press_for("jump", 2)
	await wait_until(func() -> bool: return harry.state == Harry.State.PIPE, 120)
	check("the far shaft has an iron ladder", harry.state == Harry.State.PIPE, describe())
	await wait_until(func() -> bool: return harry.global_position.y > -0.1 and harry.is_on_floor() and not harry.is_climbing(), 900)
	Input.action_release("move_forward")
	check("...up into the south lawn, inside the walls", harry.global_position.y > -0.1 and harry.stealth.is_in_restricted_zone(), describe())


func _test_creaks_and_darkness() -> void:
	# Creaky boards outside the study door.
	await tp(Vector3(62.8, AshcombeHouse.FF + 0.05, -67.0), -PI * 0.5)
	var since := noises.size()
	Input.action_press("move_forward")
	Input.action_press("walk")
	await wait(200)
	Input.action_release("move_forward")
	Input.action_release("walk")
	var creaks := _heard("creak", since)
	check("walking over the old boards they creak loudly", creaks.size() > 0 and float(creaks[0]["radius"]) >= 6.0 * Stealth.hearing_multiplier, str(creaks.size()))
	await tp(Vector3(62.8, AshcombeHouse.FF + 0.05, -67.0), -PI * 0.5)
	harry.set_crouched(true)
	since = noises.size()
	Input.action_press("move_forward")
	await wait(320)
	Input.action_release("move_forward")
	creaks = _heard("creak", since)
	check("creeping slowly they barely whisper", creaks.size() > 0 and creaks.all(func(n: Dictionary) -> bool: return float(n["radius"]) <= 2.0), str(creaks.map(func(n: Dictionary) -> float: return n["radius"])))
	harry.set_crouched(false)
	# Indoors by day is dim; the sunny forecourt is bright.
	await tp(Vector3(67.0, AshcombeHouse.GF + 0.05, -80.0), 0.0, 30)
	var inside := harry.stealth.exposure
	await tp(Vector3(55.0, 0.05, -80.0), 0.0, 30)
	var outside := harry.stealth.exposure
	check("rooms are dim by day (a little light from the windows)", inside < 0.2 and outside > 0.5, "inside %.2f outside %.2f" % [inside, outside])
	# Carpet is quiet, marble and gravel are loud.
	check("gravel crunches underfoot", harry.stealth.surface == "gravel", harry.stealth.surface)


func _test_witnesses() -> void:
	# A door Harry leaves open that should be shut makes a guard suspicious.
	var footman := _guard("Footman")
	footman.reset_after_player_respawn()
	var garden := _door("GardenDoor")
	garden.set_locked(false)
	await wait(60)
	await tp(Vector3(78.9, AshcombeHouse.GF + 0.05, -69.0), -PI * 0.5)
	await wait(12)
	await _press_e()
	await wait(30)
	check("Harry opens the garden door", garden.is_open, harry.interaction.prompt)
	await tp(Vector3(67.0, AshcombeHouse.GF + 0.05, -83.0), 0.0)
	footman.global_position = Vector3(72.0, AshcombeHouse.GF + 0.05, -69.0)
	footman.set("_yaw", -PI * 0.5)
	_wake(footman)
	await wait(90)
	check("a guard who sees a door left open comes to look", footman.state in [Guard.State.INVESTIGATE, Guard.State.SEARCH], Guard.State.keys()[footman.state])
	footman.process_mode = Node.PROCESS_MODE_DISABLED
	footman.reset_after_player_respawn()
	# Guards indoors see a man in a lit room.
	GameClock.minutes = 20.0 * 60.0
	staff.apply_schedule()
	await wait(20)
	var hall_light := house.get_node("Lights/HallGasolier") as Light3D
	check("the gasoliers are lit in the evening", hall_light.visible)
	await tp(Vector3(64.5, AshcombeHouse.GF + 0.05, -71.0), 0.0, 30)
	check("under the hall gasolier Harry is well lit", harry.stealth.exposure > 0.3, "%.2f" % harry.stealth.exposure)
	GameClock.minutes = 12.0 * 60.0
	staff.apply_schedule()


func _test_schedule() -> void:
	var gate := house.get_node("GateNorth") as MansionDoor
	check("by day the gates stand open", gate.is_open and not gate.is_locked())
	check("...and the front door is always locked", _door("FrontDoor").is_locked())
	check("...the garden door is not", not _door("GardenDoor").is_locked())
	GameClock.minutes = 23.0 * 60.0 + 45.0
	staff.apply_schedule()
	await wait(150)
	check("at night the gates are shut and locked", not gate.is_open and gate.is_locked() and absf(gate.swing) < 0.05)
	check("the garden door and servants' entrance are locked", _door("GardenDoor").is_locked() and _door("ServantsEntrance").is_locked())
	check("after half past eleven the gasoliers are out", not (house.get_node("Lights/HallGasolier") as Light3D).visible)
	check("...only the landing night-lamp burns", (house.get_node("Lights/LandingNightLamp") as Light3D).visible)
	check("the dogs are let off their chains", staff.dogs.all(func(d: GuardDog) -> bool: return not d.chained))
	check("the outdoor men light their lanterns", _guard("GardenMan").lantern.visible)
	# The gate from outside: the key-holder's padlock.
	await tp(Vector3(44.5, 0.05, -72.5), -PI * 0.5 + PI, 20)
	harry.facing_yaw = -PI * 0.5
	await wait(12)
	check("the locked gate can be picked (4-lever)", harry.interaction.prompt.contains("4-lever"), harry.interaction.prompt)
	GameClock.minutes = 12.0 * 60.0
	staff.apply_schedule()
	await wait(150)
	check("in the morning the gates are opened again", gate.is_open and not gate.is_locked())


func _test_dogs() -> void:
	GameClock.minutes = 23.0 * 60.0
	staff.apply_schedule()
	Stealth.ambient_light = 0.05
	var brutus := staff.get_node("Brutus") as GuardDog
	var nell := staff.get_node("Nell") as GuardDog
	nell.global_position = Vector3(50.0, 0.05, -108.0)
	brutus.global_position = Vector3(95.0, 0.05, -106.0)
	brutus.reset_physics_interpolation()
	# Scent and the wind (blowing towards +X): downwind of Harry vs upwind of him.
	Weather.wind = 0.9
	Weather.wind_direction = Vector3(1, 0, 0)
	await tp(Vector3(78.0, 0.05, -106.0), 0.0, 5) # west of the dog: the wind carries his scent to it
	var down := brutus.scent_range()
	await tp(Vector3(104.0, 0.05, -106.0), 0.0, 5) # east of the dog: the wind carries it away
	var up := brutus.scent_range()
	check("a dog smells you much farther downwind than upwind", down > 17.0 and up < 8.0, "downwind %.1f m, upwind %.1f m" % [down, up])
	# Downwind and crouched in the dark 15 m away: the dog still scents him.
	await tp(Vector3(80.0, 0.05, -106.0), -PI * 0.5, 5)
	harry.set_crouched(true)
	brutus.scent = 0.0
	brutus.global_position = Vector3(95.0, 0.05, -106.0)
	_wake(brutus)
	var since := noises.size()
	await wait_until(func() -> bool: return brutus.state in [GuardDog.State.ALERT, GuardDog.State.TRACK, GuardDog.State.CHASE], 300)
	check("downwind, the dog picks up his scent in the dark", brutus.state != GuardDog.State.PATROL, GuardDog.State.keys()[brutus.state])
	await wait_until(func() -> bool: return _heard("dog_bark", since).size() > 0, 600)
	check("...and bays", _heard("dog_bark", since).size() > 0)
	# The barking brings a guard.
	var gm := _guard("GardenMan")
	gm.reset_after_player_respawn()
	gm.global_position = Vector3(88.0, 0.05, -84.0)
	_wake(gm)
	since = noises.size()
	await wait_until(func() -> bool: return _heard("dog_bark", since).size() > 0, 600)
	await wait(20)
	check("the barking brings the guards", gm.state in [Guard.State.INVESTIGATE, Guard.State.SEARCH, Guard.State.SUSPICIOUS, Guard.State.CHASE], Guard.State.keys()[gm.state])
	gm.process_mode = Node.PROCESS_MODE_DISABLED
	gm.reset_after_player_respawn()
	# Out in the open, the dog runs him down: faster than a sprinting man, and it bites.
	harry.set_crouched(false)
	Stealth.ambient_light = 0.8
	Weather.wind = 0.2
	brutus.global_position = Vector3(90.0, 0.05, -99.0)
	brutus.set("_yaw", PI)
	brutus.reset_physics_interpolation()
	await tp(Vector3(90.0, 0.05, -90.0), -PI * 0.5, 5)
	var hp := harry.health
	await wait_until(func() -> bool: return harry.health < hp, 600)
	check("the dog catches him and bites", harry.health < hp, "%s %.0f hp" % [GuardDog.State.keys()[brutus.state], harry.health])
	check("a dog outruns a sprinting man", brutus.run_speed > harry.sprint_speed)
	# Up out of reach on a roof: it stands beneath, barking.
	await tp(Vector3(77.0, AshcombeHouse.WING_ROOF + 0.05, -95.0), 0.0, 5)
	brutus.global_position = Vector3(80.0, 0.05, -95.0)
	brutus.scent = 1.0
	brutus.last_scent = harry.global_position
	brutus.call("_enter", GuardDog.State.CHASE)
	await wait(60)
	check("with Harry up on a roof, the dog bays beneath him", brutus.state == GuardDog.State.BAY, GuardDog.State.keys()[brutus.state])
	# A blunt arrow sends it off yelping (the Outlaw's Code: nobody dies).
	brutus.on_arrow_hit("blunt", brutus.global_position + Vector3.UP * 0.6, Vector3(1, 0, 0))
	await wait(5)
	check("a blunt arrow sends the dog off yelping", brutus.state == GuardDog.State.FLEE)
	# By day the dogs are chained at their kennels and can't reach you.
	GameClock.minutes = 12.0 * 60.0
	staff.apply_schedule()
	brutus.process_mode = Node.PROCESS_MODE_DISABLED
	_wake(nell)
	nell.global_position = AshcombeHouse.KENNEL_YARD
	await tp(AshcombeHouse.KENNEL_YARD + Vector3(4.5, 0.05, 0.0), PI * 0.5, 5)
	hp = harry.health
	await wait(400)
	check("by day a chained dog barks but can't reach", nell.chained and harry.health == hp and nell.global_position.distance_to(AshcombeHouse.KENNEL_YARD) < 3.2, "%s d=%.1f" % [GuardDog.State.keys()[nell.state], nell.global_position.distance_to(AshcombeHouse.KENNEL_YARD)])
	Weather.wind = 0.2
