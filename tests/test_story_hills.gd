extends "res://tests/test_base.gd"
## Phase 10 in the hills: Act 1, Mission 1 "Cold Hearth" from Aldous's first words to
## supper, and the hills' sound (birdsong, the lake, the cave fire).

var streamer: WorldStreamer
var ui: StoryUI


func make_scene() -> Node:
	return load("res://scenes/wilderness/hills.tscn").instantiate()


func tp(pos: Vector3, yaw: float = 0.0, settle: int = 20) -> void:
	(main.get_node("ThirdPersonCamera") as ThirdPersonCamera).snap_behind(yaw)
	await super.tp(pos, yaw, settle)


func run_tests() -> void:
	streamer = main.get_node("Streamer")
	ui = StoryUI.find(self)
	Weather.automatic = false
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Progress.reset()
	Story.reset()
	GameClock.minutes = 9.0 * 60.0
	await _test_cold_hearth()
	await _test_hills_sound()


func talk_through(max_frames: int = 1200) -> void:
	for i in max_frames:
		if ui.cutscene.is_playing():
			ui.cutscene.skip()
		elif ui.dialogue.is_playing():
			ui.dialogue.advance()
		else:
			await wait(3)
			if not ui.cutscene.is_playing() and not ui.dialogue.is_playing():
				return
			continue
		await wait(2)


func objective() -> String:
	return Story.active.objective if Story.is_active() else ""


func _test_cold_hearth() -> void:
	await wait(10)
	var giver := main.find_child("Giver_cold_hearth", true, false) as MissionGiver
	check("Aldous waits at the clearing with the first mission", giver != null and giver.is_available() and giver.npc != null and giver.npc.visible)
	var a := giver.npc.global_position
	streamer.prime(a)
	await tp(a + Vector3(-1.6, 0.3, -1.0), atan2(-1.6, -1.0), 20)
	check("E: Talk to Aldous (Cold Hearth)", harry.interaction.prompt.contains("Aldous") and harry.interaction.prompt.contains("Cold Hearth"), harry.interaction.prompt)
	var arrows := harry.combat.get_ammo("broadhead")
	await press_for("interact", 2)
	await wait(5)
	check("Cold Hearth begins with a cutscene", Story.is_active() and ui.cutscene.is_playing())
	check("Harry stands still while they talk", harry.controls_locked)
	await talk_through()
	check("Aldous hands over his broadheads", harry.combat.get_ammo("broadhead") >= maxi(arrows, 6))
	check("hunt a deer", objective().contains("deer"), objective())
	var deer := get_nodes_in_group_safe("wild_animals").filter(func(n: Node) -> bool: return (n as WildAnimal).species == WildAnimal.Species.DEER)
	check("...there's a herd within reach", not deer.is_empty())
	check("the HUD marks the quarry", Story.active.objective_position() != Vector3.INF)
	# The hunting itself is covered by test_wilderness: here Harry comes back with venison.
	harry.inventory.add_item({"name": "Venison", "value": 60, "kind": "provision", "victim_class": "game"})
	await wait(10)
	check("venison in the bag: now catch a fish", objective().contains("fish"), objective())
	harry.inventory.add_item({"name": "Tench (1 lb 8 oz)", "value": 18, "kind": "provision", "victim_class": "game", "fish": "Tench", "weight": 1.5})
	await wait(10)
	check("a tench: take supper to Aldous", objective().contains("Aldous"), objective())
	await tp(a + Vector3(-1.4, 0.3, -1.4), atan2(-1.4, -1.4), 10)
	await wait(10)
	await talk_through()
	var done := await wait_until(func() -> bool: return Story.is_done("cold_hearth"), 300)
	check("Cold Hearth complete", done)
	check("...the venison went in the pot", harry.inventory.items.all(func(it: Dictionary) -> bool: return it.get("name", "") != "Venison"))
	check("next: Crowded Pockets, in London", Story.next_mission()["id"] == "crowded_pockets" and Story.next_mission()["place"] == "london")
	await wait(30)
	var camp := main.get_node("Camp") as CampLife
	var aldous := camp.person("aldous")
	check("Aldous stays on at the camp, to talk to", aldous != null and (aldous.visible or camp.activity("aldous") == "away"), camp.activity("aldous"))


func _test_hills_sound() -> void:
	var audio := AudioDirector.current()
	check("the hills have their own audio director", audio != null and audio.place == AudioDirector.Place.HILLS)
	await wait(200)
	check("birdsong by day in the hills, no city", audio.bed_levels["birds"] > 0.3 and audio.bed_levels["city"] == 0.0, str(audio.bed_levels))
	var jetty := main.get_node("Jetty") as Node3D
	streamer.prime(jetty.global_position)
	await tp(jetty.global_position + Vector3.UP * 0.2, 0.0, 20)
	await wait(240)
	check("water lapping by the lake", audio.bed_levels["water_lap"] > 0.3, str(audio.bed_levels["water_lap"]))
	GameClock.minutes = 23.0 * 60.0
	await wait(300)
	check("crickets at night", audio.bed_levels["crickets"] > 0.2 and audio.bed_levels["birds"] < 0.05, str(audio.bed_levels))
