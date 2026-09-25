extends "res://tests/test_base.gd"
## Phase 4: the market square, crowds, pickpocketing, loot, money and reactions.

var market: MarketSquare


func _init() -> void:
	keep_guards = true


func run_tests() -> void:
	market = main.get_node("MarketSquare")
	await wait(30)

	# --- The square and its crowd ------------------------------------------------
	var stalls := market.find_children("Stall_*", "StaticBody3D", false, false)
	var traders := get_tree_civilians().filter(func(c: Civilian) -> bool: return c.is_merchant)
	var shoppers := get_tree_civilians().filter(func(c: Civilian) -> bool: return not c.is_merchant)
	check("16 market stalls", stalls.size() == 16)
	check("a trader at every stall", traders.size() == 16)
	check("at least 30 shoppers", shoppers.size() >= 30)
	check("a constable walks the square", get_nodes_in_group_safe("guards").any(func(g: Node) -> bool: return g.name == "ConstableDunn"))
	for g in get_nodes_in_group_safe("guards"):
		g.free() # keep the pickpocketing checks deterministic; guards are added back below
	var start := {}
	for c in shoppers:
		start[c] = (c as Node3D).global_position
	await wait(900)
	var moved := 0
	var still_out := 0
	for c in shoppers:
		if not is_instance_valid(c):
			moved += 1 # finished their errand and went indoors
			continue
		still_out += 1
		if (c as Node3D).global_position.distance_to(start[c]) > 2.0:
			moved += 1
	check("shoppers wander and browse", moved >= shoppers.size() * 0.8, "%d/%d moved" % [moved, shoppers.size()])
	var all := get_tree_civilians()
	var min_d := INF
	for i in all.size():
		for j in range(i + 1, all.size()):
			min_d = minf(min_d, all[i].global_position.distance_to(all[j].global_position))
	check("crowd avoidance: nobody walks through anybody", min_d > 0.45, "closest %.2f m" % min_d)

	# --- Money and loot tables --------------------------------------------------------
	check("money: 0d", Money.format(0) == "0d")
	check("money: 7s 3d", Money.format(87) == "7s 3d")
	check("money: £2 4s 6d", Money.format(2 * 240 + 4 * 12 + 6) == "£2 4s 6d")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rich_ok := true
	var poor_ok := true
	for i in 50:
		var g := LootTable.roll("gentleman", rng)
		rich_ok = rich_ok and g.any(func(it: Dictionary) -> bool: return it["kind"] == "coins")
		for it in LootTable.roll("worker", rng):
			if it["kind"] == "coins" and int(it["value"]) > 30:
				poor_ok = false
	check("a gentleman always carries coin", rich_ok)
	check("a working man carries only pennies", poor_ok)

	# --- Pickpocketing a trader ---------------------------------------------------
	var trader: Civilian = traders[0]
	await wait_until(func() -> bool: return trader.state == Civilian.State.TEND_STALL and trader.global_position.distance_to(trader.stall_point) < 0.7, 300)
	await wait(30)
	var f := trader.get_facing_dir()
	await tp(trader.global_position + f * 0.9, atan2(f.x, f.z)) # in front, facing him
	await wait(5)
	# (Another shopper with his back to Harry may be fair game: it's this trader who isn't.)
	check("no pickpocket prompt from the front", harry.thievery.prompt_target != trader and not trader.can_be_pickpocketed_from(harry.global_position))
	await tp(trader.global_position - f * 0.85, atan2(-f.x, -f.z)) # behind, facing his back
	await wait(5)
	check("pickpocket prompt from behind", harry.thievery.prompt_target == trader)
	var money_before := harry.inventory.money
	var ok := await pickpocket(true)
	check("successful pickpocket of a trader", ok and trader.robbed and harry.inventory.money > money_before, "purse %s" % Money.format(harry.inventory.money))
	await wait(10)
	check("pockets can't be picked twice", not trader.can_be_pickpocketed_from(harry.global_position))

	# --- A gentleman: two stages, valuables --------------------------------------
	var gent := spawn_still_person("gentleman", Vector3(0, 0.05, -64.0), 0.0)
	await wait(20)
	await tp(gent.global_position + Vector3(0, 0, 0.85), 0.0)
	await wait(5)
	var coins_before := harry.inventory.money
	var items_before := harry.inventory.items.size()
	harry.thievery.try_start()
	check("a gentleman takes two careful moves", harry.thievery.stages == 2)
	harry.thievery.cancel()
	harry.set_state(Harry.State.IDLE)
	gent.suspicion = 0.0
	await wait(5)
	ok = await pickpocket(true)
	var gained_items := harry.inventory.items.size() - items_before
	check("robbing a gentleman", ok and harry.inventory.money > coins_before and gent.robbed, "+%d items" % gained_items)

	# --- Failure: shout, crime, the constable comes --------------------------------
	var worker := spawn_still_person("worker", Vector3(3, 0.05, -70.0), 0.0)
	var dunn := Guard.new()
	dunn.name = "TestConstable"
	dunn.position = Vector3(3.0, 0.0, -58.0)
	dunn.rotation.y = 0.0 # facing north (-Z), towards the worker
	main.add_child(dunn)
	var gawker := spawn_still_person("lady", Vector3(6, 0.05, -70.0), PI * 0.5)
	await wait(30)
	await tp(worker.global_position + Vector3(0, 0, 0.85), 0.0)
	await wait(5)
	ok = await pickpocket(false)
	await wait(5)
	check("fumbled attempt: the victim shouts 'Thief!'", not ok and worker.state == Civilian.State.SHOUT and worker.wary)
	check("fumble counts as a crime", harry.stealth.crime_timer > 0.0)
	var chased := await wait_until(func() -> bool: return dunn.state == Guard.State.CHASE, 120)
	check("the constable gives chase", chased)
	check("bystanders turn to gawk", gawker.state == Civilian.State.GAWK or gawker.state == Civilian.State.FLEE)
	dunn.free()
	await wait(2)

	# --- Crowds help ---------------------------------------------------------------
	var lone := spawn_still_person("worker", Vector3(-4, 0.05, -71.0), 0.0)
	await wait(10)
	await tp(lone.global_position + Vector3(0, 0, 0.85), 0.0)
	await wait(5)
	harry.thievery.try_start()
	var w_alone := harry.thievery.zone_width
	harry.thievery.cancel()
	harry.set_state(Harry.State.IDLE)
	lone.suspicion = 0.0
	for k in 3:
		spawn_still_person("worker", lone.global_position + Vector3(1.2 * cos(k * 2.0), 0, 1.2 * sin(k * 2.0) - 0.6), 0.0)
	await wait(15)
	await tp(lone.global_position + Vector3(0, 0, 0.85), 0.0)
	await wait(5)
	harry.thievery.try_start()
	var w_crowd := harry.thievery.zone_width
	harry.thievery.cancel()
	harry.set_state(Harry.State.IDLE)
	check("a crowd widens the sweet spot", w_crowd > w_alone * 1.2, "%.2f vs %.2f" % [w_crowd, w_alone])
	await wait(15)
	check("standing in a crowd lowers visibility", harry.stealth.crowd_cover >= 2)

	# --- Level of detail --------------------------------------------------------
	await tp(Vector3(0, 0.05, 38.0), 0.0)
	await wait(60)
	var far := 0
	for c in get_tree_civilians():
		if c.lod_level == 2:
			far += 1
	check("distant townsfolk switch to low detail", far > 20, "%d far" % far)


func get_tree_civilians() -> Array:
	return get_nodes_in_group_safe("civilians").filter(func(c: Node) -> bool: return is_instance_valid(c) and not c.is_queued_for_deletion())


func spawn_still_person(victim_class: String, pos: Vector3, yaw: float) -> Civilian:
	var c := Civilian.new()
	c.name = "Test_" + victim_class
	c.is_merchant = true # stands still at its "stall point"
	c.outfit = {"gentleman": NPCBody.Outfit.GENTLEMAN, "lady": NPCBody.Outfit.LADY}.get(victim_class, NPCBody.Outfit.WORKER)
	c.position = pos
	c.rotation.y = yaw
	c.stall_point = pos
	c.stall_look = pos + Vector3(-sin(yaw), 0, -cos(yaw)) * 3.0
	main.add_child(c)
	c.victim_class = victim_class
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	c.pockets = LootTable.roll(victim_class, rng)
	c._cry_timer = 9999.0
	return c


## Runs the timing mini-game, pressing E inside (or deliberately outside) the sweet spot.
func pickpocket(succeed: bool) -> bool:
	if not harry.thievery.try_start():
		return false
	var result := [false, false]
	var cb := func(success: bool, _loot: Array) -> void:
		result[0] = true
		result[1] = success
	harry.thievery.attempt_finished.connect(cb, CONNECT_ONE_SHOT)
	for i in 600:
		await wait(1)
		if result[0]:
			break
		var th := harry.thievery
		if th.victim == null:
			continue
		var inside := absf(th.marker - th.zone_center) <= th.zone_width * 0.35
		var outside := absf(th.marker - th.zone_center) > th.zone_width * 0.5 + 0.08
		if (succeed and inside) or (not succeed and outside):
			await press_for("interact", 1)
	return result[1]
