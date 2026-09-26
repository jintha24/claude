extends "res://tests/test_base.gd"
## Realistic people and their daily routines: every townsperson is a resident with a home,
## a trade and a day (DailyRoutine, Population); the rookery's beggars and soup queue keep
## hours; the generated human bodies are driven by the pose rig (CharacterLook, CharacterRig).

var population: Population


func run_tests() -> void:
	population = main.get_node("Population")
	await wait_until(func() -> bool: return not population.residents.is_empty(), 900)
	_test_roster()
	await _test_day()
	await _test_one_life()
	await _test_sunday()
	await _test_rookery()
	await _test_bodies()


func _test_roster() -> void:
	var rs := population.residents
	var jobs := {}
	for r in rs:
		jobs[r.job] = jobs.get(r.job, 0) + 1
	check("the town has a roster of residents", rs.size() >= 100, "%d: %s" % [rs.size(), str(jobs)])
	check("every resident has a home to go to", rs.all(func(r: DailyRoutine) -> bool: return r.home != null and is_instance_valid(r.home)))
	check("a costermonger for every stall", jobs.get("costermonger", 0) == 16 and rs.filter(func(r: DailyRoutine) -> bool: return r.stall >= 0).size() == 16)
	check("clerks, housewives, gentlemen, labourers, pensioners and rookery folk", ["clerk", "housewife", "gentleman", "labourer", "pensioner", "rookery"].all(func(j: String) -> bool: return jobs.get(j, 0) > 0), str(jobs))
	check("workers have a workplace", rs.filter(func(r: DailyRoutine) -> bool: return r.job in ["clerk", "gentleman", "labourer"]).all(func(r: DailyRoutine) -> bool: return r.work != null))
	# Everyone sleeps at home and the routine is the same every week.
	var asleep := rs.all(func(r: DailyRoutine) -> bool: return r.activity_at(3.5, 5) == DailyRoutine.HOME)
	check("at half past three in the morning everyone is in bed", asleep)
	var again := DailyRoutine.create(rs[20].id, rs[20].job, RandomNumberGenerator.new())
	check("a routine reads as a timetable", rs[20].describe(5).contains(":"), rs[20].describe(5))
	check("the same person keeps the same face", again.look_seed == rs[20].look_seed)
	var clerk: DailyRoutine = rs.filter(func(r: DailyRoutine) -> bool: return r.job == "clerk")[0]
	check("a clerk is at work mid-morning on a weekday", clerk.activity_at(10.0, 5) == DailyRoutine.WORK, clerk.describe(5))
	var coster: DailyRoutine = rs.filter(func(r: DailyRoutine) -> bool: return r.job == "costermonger")[0]
	check("a costermonger keeps her stall all day", coster.activity_at(12.0, 5) == DailyRoutine.STALL and coster.activity_at(19.0, 5) != DailyRoutine.STALL)
	var labourer: DailyRoutine = rs.filter(func(r: DailyRoutine) -> bool: return r.job == "labourer")[0]
	check("labourers work a half day on Saturday", labourer.activity_at(15.0, 0) != DailyRoutine.WORK and labourer.activity_at(15.0, 5) == DailyRoutine.WORK)
	var drinkers := rs.filter(func(r: DailyRoutine) -> bool: return r.activity_at(21.5, 5) == DailyRoutine.PUB)
	check("some spend Thursday evening in the pub", drinkers.size() >= 5 and drinkers.size() < rs.size() / 2, "%d" % drinkers.size())
	var saturday := rs.filter(func(r: DailyRoutine) -> bool: return r.activity_at(21.5, 0) == DailyRoutine.PUB)
	check("more of them on a Saturday night", saturday.size() > drinkers.size(), "%d vs %d" % [saturday.size(), drinkers.size()])


func _test_day() -> void:
	await set_hour(12.0)
	await wait(10)
	var out := population.get_children().filter(func(c: Node) -> bool: return c is Civilian)
	var with_home := out.filter(func(c: Node) -> bool: return population.resident_of(c as Civilian) != null)
	check("everyone out at noon is a resident", out.size() > 30 and with_home.size() == out.size(), "%d of %d" % [with_home.size(), out.size()])
	check("noon: shoppers in the market, traders at the stalls, rookery folk about", population.count("shopper") >= 25 and population.traders.size() == 16 and population.count("rookery") > 0,
		"%d shoppers, %d rookery" % [population.count("shopper"), population.count("rookery")])
	# Out-of-doors people are exactly those whose routine says so.
	var wd := Population.weekday()
	var right := with_home.all(func(c: Node) -> bool:
		var r := population.resident_of(c as Civilian)
		return r.is_outdoor(r.activity) or r.activity in [DailyRoutine.ERRAND, DailyRoutine.MARKET, DailyRoutine.HOME, DailyRoutine.WORK, DailyRoutine.PUB, DailyRoutine.CHURCH])
	check("each one is doing what their routine says", right)
	var shopping := population.residents.filter(func(r: DailyRoutine) -> bool: return r.activity_at(12.0, wd) == DailyRoutine.MARKET)
	check("the market crowd is the people whose shopping hour it is", population.count("shopper") <= shopping.size(), "%d out, %d due" % [population.count("shopper"), shopping.size()])
	await set_hour(3.0)
	await wait(10)
	var night := population.get_children().filter(func(c: Node) -> bool: return c is Civilian)
	check("3 am: the town is asleep", night.size() <= 1, "%d out" % night.size())


## One clerk's morning: out of his own front door, along to work, and in.
func _test_one_life() -> void:
	var wd := Population.weekday()
	var clerk: DailyRoutine = null
	for r in population.residents:
		if r.job == "clerk" and r.activity_at(7.0, wd) == DailyRoutine.HOME and r.activity_at(9.5, wd) == DailyRoutine.WORK and r.work != r.home:
			clerk = r
			break
	check("found a clerk who walks to work", clerk != null)
	if clerk == null:
		return
	await set_hour(7.0)
	GameClock.real_minutes_per_game_day = 6.0
	GameClock.paused = false
	var left := await wait_until(func() -> bool: return clerk.civ != null and is_instance_valid(clerk.civ), 1800)
	var from_home := left and clerk.civ.global_position.distance_to(clerk.home.global_position) < 3.0
	check("he comes out of his own front door", from_home, str(clerk.describe(wd)))
	var arrived := await wait_until(func() -> bool: return clerk.civ == null or not is_instance_valid(clerk.civ), 3600)
	GameClock.paused = true
	GameClock.real_minutes_per_game_day = 48.0
	check("walks to work and goes in", arrived and clerk.place == clerk.work, "%s at %s" % [clerk.activity, GameClock.clock_string()])


func _test_sunday() -> void:
	# Forward to Sunday morning (the story starts on a Thursday).
	while Population.weekday() != 1:
		GameClock.paused = true
		GameClock.advance(1440.0)
	await set_hour(9.0)
	var goers := population.residents.filter(func(r: DailyRoutine) -> bool: return r.activity_at(10.5, 1) == DailyRoutine.CHURCH)
	check("Sunday morning: churchgoers", goers.size() >= 10, "%d" % goers.size())
	check("the church has a door to go in by", goers.all(func(r: DailyRoutine) -> bool: return r.church != null and r.door_for(DailyRoutine.CHURCH) == r.church))
	GameClock.real_minutes_per_game_day = 6.0
	GameClock.paused = false
	var walking := await wait_until(func() -> bool: return population.count("churchgoer") > 0, 1800)
	GameClock.paused = true
	GameClock.real_minutes_per_game_day = 48.0
	check("...walking to St Giles for the service", walking)


func _test_rookery() -> void:
	var district: Node = get_nodes_in_group_safe("st_giles")[0]
	await set_hour(12.0)
	await wait(10)
	var noon: Dictionary = district.describe_wellbeing()
	await set_hour(23.0)
	await wait(10)
	var night: Dictionary = district.describe_wellbeing()
	check("beggars sit out by day and are gone at night", noon["beggars"] > 0 and night["beggars"] == 0, "%s / %s" % [noon, night])
	check("the soup queue forms at dinner time only", noon["queue"] > 0 and night["queue"] == 0)
	check("rookery folk are home at night", population.count("rookery") == 0)
	var meg: Array = population.residents.filter(func(r: DailyRoutine) -> bool: return r.display_name == "Old Meg")
	check("Old Meg lives in the rookery", not meg.is_empty() and (meg[0] as DailyRoutine).home.global_position.x < StGiles.TERRACE_BACK_X)


func _test_bodies() -> void:
	await set_hour(12.0)
	await wait(30)
	var civs := population.get_children().filter(func(c: Node) -> bool: return c is Civilian)
	var real := civs.filter(func(c: Node) -> bool: return ((c as Civilian).get_node("Body") as NPCBody).is_realistic())
	check("townsfolk are realistic people", not civs.is_empty() and real.size() == civs.size(), "%d of %d" % [real.size(), civs.size()])
	var mannequin := harry.find_children("*", "HarryMannequin", true, false)
	check("Harry is too", not mannequin.is_empty() and (mannequin[0] as HarryMannequin).is_realistic())
	# Two dressings from the same seed match; different seeds differ.
	var a := CharacterLook.instantiate("gentleman", 11)
	var b := CharacterLook.instantiate("gentleman", 11)
	var c := CharacterLook.instantiate("gentleman", 12345)
	check("a seed always dresses the same person", _signature(a) == _signature(b))
	check("different seeds make different people", _signature(a) != _signature(c))
	for n in [a, b, c]:
		n.free()
	# The skeleton follows the walk: a walking person's thighs swing.
	var walker: Civilian = null
	for x in civs:
		if (x as Civilian).is_walking():
			walker = x
			break
	if walker == null:
		walker = civs[0]
	# Close to the camera, so it animates at full detail.
	walker.global_position = harry.global_position + Vector3(2.0, 0.1, 3.0)
	await wait(40)
	var skel := (walker.get_node("Body") as NPCBody).get_look_model().find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var thigh := skel.find_bone("thigh_l")
	if thigh < 0:
		thigh = skel.find_bone("Bip01 L Thigh") # (the Rocketbox people)
	var samples: Array[Quaternion] = []
	for i in 6:
		walker.go_to(harry.global_position + Vector3(6.0, 0.0, 3.0 - i * 2.0), "wander")
		await wait(8)
		samples.append(skel.get_bone_pose_rotation(thigh))
	var swings := false
	for i in range(1, samples.size()):
		if samples[i].angle_to(samples[0]) > 0.05:
			swings = true
	check("the body's legs move with the walk", swings)


func _signature(model: Node3D) -> String:
	var out := ""
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		out += "%s%s" % [mi.name, "v" if mi.visible else "h"]
		if mi.mesh.get_blend_shape_count() > 0:
			out += "%.2f" % mi.get_blend_shape_value(0)
		var m := mi.get_surface_override_material(0)
		out += m.resource_name if m else ""
	return out


func set_hour(h: float) -> void:
	GameClock.paused = true
	GameClock.advance(fposmod(h * 60.0 - GameClock.minutes, 1440.0))
	await wait(45)
