extends "res://tests/test_base.gd"
## The camp in the clearing (CampLife): a campfire, tents and a woodpile, Aldous living
## there on a daily routine, and the Lantern Men who have joined coming up in the evening.

var camp: CampLife


func make_scene() -> Node:
	return load("res://scenes/wilderness/hills.tscn").instantiate()


func run_tests() -> void:
	camp = main.get_node("Camp")
	Weather.automatic = false
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Story.reset()
	await wait(5)
	check("nobody lives at the camp before Aldous's first mission", camp.residents().is_empty())
	check("the campfire burns", camp.get_node("CampfireLight") != null)
	Story.completed.append("cold_hearth")
	Story.bus().mission_completed.emit("cold_hearth")
	await wait(5)
	var aldous := camp.person("aldous")
	check("after Cold Hearth, Aldous lives at the camp", aldous != null)
	if aldous == null:
		return
	# Through his day, watched from the clearing.
	var fire := camp.ground(CampLife.FIRE)
	await tp(fire + Vector3(4.0, 0.3, 4.0))
	await _at_hour(7.8)
	check("in the morning he splits wood at the block", camp.activity("aldous") == "chop")
	var reached := await wait_until(func() -> bool: return camp.is_settled("aldous"), 3600)
	check("...walking over to it", reached and aldous.global_position.distance_to(camp.ground(CampLife.BLOCK)) < 2.0, "%.1f m" % aldous.global_position.distance_to(camp.ground(CampLife.BLOCK)))
	await wait(60)
	check("...swinging the axe", aldous.pose_override in [NPCBody.Pose.WINDUP, NPCBody.Pose.PUNCH])
	var dogs := get_nodes_in_group_safe("dogs")
	check("his old dog keeps him company", dogs.size() == 1 and (dogs[0] as Node3D).global_position.distance_to(aldous.global_position) < 5.0)
	await _at_hour(11.0)
	await wait_until(func() -> bool: return not aldous.visible, 1800)
	check("late morning he goes off into the woods", camp.activity("aldous") == "away" and not aldous.visible)
	await _at_hour(19.0)
	var back := await wait_until(func() -> bool: return aldous.visible and camp.is_settled("aldous") and camp.activity("aldous") == "fire", 3600)
	check("in the evening he comes back and sits by the fire", back and camp.activity("aldous") == "fire" and aldous.pose_override == NPCBody.Pose.SIT)
	check("he'll talk to Harry", _talk("aldous").get_prompt(harry) == "Talk to Aldous")
	# The band come up from London of an evening.
	Story.join_band("pip")
	Story.join_band("tom")
	await wait(5)
	check("the Lantern Men who've joined live at the camp too", camp.person("pip") != null and camp.person("tom") != null)
	await _at_hour(19.6) # Pip's up from London by half past seven
	var pip := camp.person("pip")
	var at_fire := await wait_until(func() -> bool: return pip.visible and camp.is_settled("pip") and camp.activity("pip") == "fire", 3600)
	check("Pip sits at the fire of an evening", at_fire)
	await _at_hour(23.8)
	await wait(30)
	check("at night they sleep in the tents", camp.activity("aldous") == "sleep" and camp.activity("pip") == "sleep" and camp.activity("tom") == "sleep")
	check("...and you can't chat to a sleeping man", _talk("aldous").get_prompt(harry) == "")
	# Harry far away: the camp keeps its hours without him.
	await tp(fire + Vector3(200.0, 5.0, 0.0))
	streamer_prime()
	await _at_hour(7.8)
	await wait(10)
	check("while Harry's away the day goes on", camp.activity("aldous") == "chop" and camp.activity("tom") == "away")
	Story.reset()


func streamer_prime() -> void:
	(main.get_node("Streamer") as WorldStreamer).prime(harry.global_position)


func _talk(id: String) -> StoryTalk:
	return camp.get_node("Talk_" + camp.person(id).name) as StoryTalk


func _at_hour(h: float) -> void:
	GameClock.advance(fposmod(h * 60.0 - GameClock.minutes, 1440.0))
	await wait(40) # (the camp looks at the clock twice a second)
