extends "res://tests/test_base.gd"
## Phase 9 (the hills): fishing from the jetty (cast, bite, strike, playing the fish,
## snapping the line, letting it throw the hook, missing the bite, the evening rise) and
## improving the camp.

var streamer: WorldStreamer


func make_scene() -> Node:
	return load("res://scenes/wilderness/hills.tscn").instantiate()


func tp(pos: Vector3, yaw: float = 0.0, settle: int = 20) -> void:
	(main.get_node("ThirdPersonCamera") as ThirdPersonCamera).snap_behind(yaw)
	await super.tp(pos, yaw, settle)


func run_tests() -> void:
	streamer = main.get_node("Streamer")
	Weather.automatic = false
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Progress.reset()
	(main.get_node("Animals") as AnimalSpawner).deer_herds = 0
	(main.get_node("Animals") as AnimalSpawner).rabbits = 0
	await _test_fishing()
	await _test_camp()


func _to_jetty() -> FishingSpot:
	var jetty := main.get_node("Jetty") as FishingSpot
	var d := jetty.cast_dir
	streamer.prime(jetty.global_position)
	await tp(jetty.global_position - d * 0.9 + Vector3.UP * 0.1, atan2(-d.x, -d.z), 30)
	await wait(12)
	return jetty


## Casts (hold E ~1 s) and waits for the bite. `quick` cuts the wait short (the first cast
## waits naturally; the later ones only test what happens after the bite).
func _cast_and_wait(quick: bool = true) -> bool:
	await press_for("interact", 2)
	await wait(2)
	Input.action_press("interact")
	await wait(60)
	Input.action_release("interact")
	var s := harry.interaction.fishing
	if s == null:
		return false
	if quick and s.phase == FishingSession.Phase.WAIT:
		s.set("_wait", minf(float(s.get("_wait")), 1.5))
	return await wait_until(func() -> bool: return s.phase == FishingSession.Phase.BITE, 2400)


func _test_fishing() -> void:
	GameClock.minutes = 6.5 * 60.0 # the morning feed
	var jetty := await _to_jetty()
	check("an anglers' jetty runs out over the lake", jetty != null and streamer.generator.water_depth(jetty.global_position.x, jetty.global_position.z) > 0.3 and harry.is_on_floor(), describe())
	check("standing on it: 'Fish from the jetty'", harry.interaction.prompt == "Fish from the jetty", harry.interaction.prompt)
	check("bites come sooner at dawn than at noon", FishingSession.bite_factor() < 1.0)
	var got_bite := await _cast_and_wait(false)
	var s := harry.interaction.fishing
	if s == null:
		check("cast out, and a fish bites", false, describe())
		return
	check("cast out, and a fish bites", got_bite and s.power > 0.1, "phase %s" % FishingSession.Phase.keys()[s.phase])
	check("the float bobs out on the water", jetty.float_mesh.visible)
	await press_for("interact", 2)
	check("strike: hooked!", s.phase == FishingSession.Phase.FIGHT)
	# Play it: reel while the tension's low, give line when it's high.
	var n := harry.inventory.items.size()
	for i in 3000:
		if s.phase != FishingSession.Phase.FIGHT:
			break
		if s.tension < 0.55:
			Input.action_press("interact")
		elif s.tension > 0.68:
			Input.action_release("interact")
		await wait(1)
	Input.action_release("interact")
	check("played carefully, the fish is landed", s.phase == FishingSession.Phase.LANDED, s.message)
	check("...and goes in his bag", harry.inventory.items.size() == n + 1 and harry.inventory.items[n].get("fish", "") != "", str(harry.inventory.items.back()))
	check("fishing ends and he can move again", not harry.interaction.is_busy())
	# Hauling on it without letting up snaps the line.
	await wait(12)
	got_bite = await _cast_and_wait()
	s = harry.interaction.fishing
	await press_for("interact", 2)
	Input.action_press("interact")
	await wait_until(func() -> bool: return s.is_over(), 900)
	Input.action_release("interact")
	check("reeling without let-up snaps the line", s.phase == FishingSession.Phase.LOST and s.message.contains("snaps"), s.message)
	# Never reeling: slack line, it throws the hook.
	await wait(12)
	got_bite = await _cast_and_wait()
	s = harry.interaction.fishing
	await press_for("interact", 2)
	await wait_until(func() -> bool: return s.is_over(), 900)
	check("slack line: it throws the hook", s.phase == FishingSession.Phase.LOST and s.message.contains("threw the hook"), s.message)
	# Too slow to strike.
	await wait(12)
	got_bite = await _cast_and_wait()
	s = harry.interaction.fishing
	await wait(90)
	check("too slow to strike: the fish takes the bait and goes", s.phase == FishingSession.Phase.WAIT and s.message.contains("Too slow"), s.message)
	Input.action_press("move_back")
	await wait(10)
	Input.action_release("move_back")
	check("walking away puts the rod down", not harry.interaction.is_busy() and not jetty.float_mesh.visible)
	# Species and prices.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pike_seen := false
	for i in 200:
		var t := FishingSession.new(rng)
		t.power = 1.0
		t.call("_choose_fish")
		if t.fish[0] == "Pike":
			pike_seen = true
	check("long casts reach the pike in deep water", pike_seen)


func _test_camp() -> void:
	var cave := main.get_node("Cave") as StreamedScene
	var clearing := Vector3(-120.0, streamer.height_at(-120.0, 96.0) + 0.05, 96.0)
	streamer.prime(clearing)
	await tp(clearing, 0.0, 20)
	await wait_until(func() -> bool: return cave.is_loaded(), 600)
	var hideout := cave.instance as CaveHideout
	var plans := hideout.get_node("CampPlans") as ShopCounter
	check("plans for the camp hang by the fire", plans != null and plans.kind == "camp")
	harry.inventory.money = 5000
	check("the paddock", Upgrades.buy(harry, "camp_paddock"))
	check("...lets Cinder get his wind back twice as fast", is_equal_approx((main.get_node("Cinder") as Horse).recover_seconds, 12.5))
	check("bunks and a stove", Upgrades.buy(harry, "camp_bunks"))
	await wait(3)
	check("the camp visibly grows", hideout.get_node("Improvements").get_child_count() > 0)
	harry.inventory.lockpicks = 1
	(hideout.get_node("Bed") as CampBed).sleep(harry)
	check("with the lads about, sleeping restores his picks", harry.inventory.lockpicks >= 6)
	check("sleeping at camp autosaves", SaveGame.exists(0))
	check("the smokehouse doubles what game fetches", Upgrades.buy(harry, "camp_smokehouse") and Upgrades.fence_price({"value": 100, "kind": "provision"}) == 160)
