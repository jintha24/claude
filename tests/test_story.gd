extends "res://tests/test_base.gd"
## Phase 10 in London: the St Giles district (Church Lane, the Fleet ditch, the footbridge,
## the church and its crypt, the district improving with charity), the sound (procedural
## sounds, footsteps, ambience, the church bell, chase music) and Act 1 missions 2 to 6
## played start to finish (the chase after Pip, the rent bag, the fight on the bridge,
## Father Bernard, Crowe's manhunt), with a failure and retry from a checkpoint.

var district: StGiles
var ui: StoryUI


func tp(pos: Vector3, yaw: float = 0.0, settle: int = 20) -> void:
	(main.get_node("ThirdPersonCamera") as ThirdPersonCamera).snap_behind(yaw)
	await super.tp(pos, yaw, settle)


func run_tests() -> void:
	district = main.get_node("StGiles") as StGiles
	ui = StoryUI.find(self)
	Weather.automatic = false
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Progress.reset()
	Story.reset()
	GameClock.minutes = 10.0 * 60.0
	await _test_district()
	await _test_sound()
	await _test_story_basics()
	await _test_crowded_pockets()
	await _test_collector()
	await _test_bridge()
	await _test_bernard()
	await _test_wanted()


## Moves every conversation and cutscene along until the mission is waiting on Harry.
func talk_through(max_frames: int = 1200) -> void:
	for i in max_frames:
		if ui.cutscene.is_playing():
			ui.cutscene.skip()
		elif ui.dialogue.is_playing():
			ui.dialogue.advance()
		else:
			var menus := get_nodes_in_group_safe("choice_menus")
			if menus.is_empty():
				await wait(3)
				if not ui.cutscene.is_playing() and not ui.dialogue.is_playing():
					return
				continue
			return
		await wait(2)


## The mission being played (including one that's just failed and awaits a retry).
## Moves conversations along until mission `id` is complete (or time runs out).
func finish(id: String, max_frames: int = 1800) -> bool:
	for i in max_frames:
		if Story.is_done(id):
			return true
		if ui.cutscene.is_playing():
			ui.cutscene.skip()
		elif ui.dialogue.is_playing():
			ui.dialogue.advance()
		await wait(2)
	return Story.is_done(id)


func mission() -> Mission:
	return Story.active if Story.active != null and is_instance_valid(Story.active) else null


func objective() -> String:
	return mission().objective if mission() else ""


func walk(action: String, frames: int) -> void:
	await press_for(action, frames)


# ---------------------------------------------------------------------------
func _test_district() -> void:
	check("St Giles is built behind the street", district != null and district.get_child_count() > 40)
	# Church Lane: walk west from the street into the rookery.
	await tp(Vector3(-4.6, 0.2, -4.3), PI * 0.5)
	Input.action_press("move_forward")
	var in_lane := await wait_until(func() -> bool: return harry.global_position.x < -24.0, 600)
	release_all()
	check("Church Lane leads from the street into the rookery", in_lane, describe())
	# The footbridge over the Fleet.
	await tp(StGiles.BRIDGE_MID + Vector3.UP * 0.3, PI * 0.5, 30)
	check("the footbridge holds Harry over the ditch", harry.is_on_floor() and absf(harry.global_position.y - StGiles.BRIDGE_TOP) < 0.1, describe())
	# The ditch: into the water, wading slowly.
	await tp(Vector3(-37.0, -2.5, 10.0), PI, 40)
	check("the Fleet ditch has a bed 3 m down", harry.is_on_floor() and harry.global_position.y < -2.8, describe())
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait(90)
	var wading_speed := harry.get_horizontal_speed()
	release_all()
	check("wading the ditch is slow", wading_speed > 0.3 and wading_speed < 4.0, "%.2f m/s" % wading_speed)
	check("...and splashes underfoot", harry.stealth.surface == "water", harry.stealth.surface)
	# Climb out by an iron ladder.
	var ladder := Vector3(StGiles.DITCH_X1 - 0.12, StGiles.DITCH_FLOOR, 12.0)
	await tp(Vector3(ladder.x - 0.7, StGiles.DITCH_FLOOR + 0.1, ladder.z), -PI * 0.5, 30)
	await press_for("jump", 3)
	var on_ladder := await wait_until(func() -> bool: return harry.state == Harry.State.PIPE, 60)
	check("iron ladders up the ditch walls", on_ladder, describe())
	Input.action_press("move_forward")
	var out := await wait_until(func() -> bool: return harry.global_position.y > -0.2 and harry.is_on_floor() and not harry.is_climbing(), 900)
	release_all()
	check("...climb out onto the rookery side", out, describe())
	# Or walk out up the stone steps at the south end.
	await tp(Vector3(StGiles.DITCH_X1 - 0.65, StGiles.DITCH_FLOOR + 0.1, -29.8), 0.0, 30)
	Input.action_press("move_forward")
	await wait_until(func() -> bool: return harry.global_position.y > -0.3, 600)
	release_all()
	# At the top the steps come out onto the east bank.
	Input.action_press("move_right")
	var up := await wait_until(func() -> bool: return harry.global_position.y > -0.05 and harry.global_position.x > StGiles.DITCH_X1, 300)
	release_all()
	check("steps lead up out of the ditch", up, describe())
	# The church: in through the south door, then down to the crypt.
	await tp(Vector3(StGiles.DOOR_X, 0.1, StGiles.NAVE_Z0 - 2.5), PI, 20)
	Input.action_press("move_forward")
	var inside := await wait_until(func() -> bool: return StGiles.in_church(harry.global_position) and harry.global_position.z > StGiles.NAVE_Z0 + 1.5, 400)
	release_all()
	check("in through the church door", inside, describe())
	await tp(Vector3(StGiles.STAIR.end.x + 0.9, StGiles.FLOOR_TOP + 0.1, StGiles.STAIR.get_center().y), PI * 0.5, 20)
	Input.action_press("move_forward")
	var down := await wait_until(func() -> bool: return harry.global_position.y < StGiles.CRYPT_FLOOR + 0.2 and harry.global_position.x < StGiles.CRYPT.end.x, 900)
	release_all()
	check("stairs down to the crypt", down, describe())
	check("the crypt is pitch dark by day", InteriorVolume.daylight_at(harry.global_position + Vector3.UP) == 0.0)
	var bed := district.get_node("CryptBed") as SafehouseBed
	check("the crypt cot isn't Harry's yet", bed.get_prompt(harry) == "")
	# The district improves with charity.
	Progress.wellbeing = 0.0
	district.call("_apply_wellbeing")
	var poor := district.describe_wellbeing()
	Progress.wellbeing = 60.0
	district.call("_apply_wellbeing")
	var better := district.describe_wellbeing()
	check("a poor rookery: beggars, no flowers", poor["beggars"] == 5 and not poor["flowers"] and not poor["bunting"], str(poor))
	check("as the Fox gives: flowers, bunting, fewer beggars, more fed", better["flowers"] and better["bunting"] and better["beggars"] == 2 and better["queue"] > poor["queue"], str(better))
	Progress.wellbeing = 0.0
	district.call("_apply_wellbeing")


# ---------------------------------------------------------------------------
func _test_sound() -> void:
	var ok := true
	var names: Array = SoundLibrary.one_shot_names()
	names.append_array(SoundLibrary.LOOPS)
	for n: String in names:
		var s := SoundLibrary.get_stream(n) as AudioStreamWAV
		if s == null or s.data.size() < 400 or (n in SoundLibrary.LOOPS) != (s.loop_mode == AudioStreamWAV.LOOP_FORWARD):
			ok = false
			print("  bad sound: ", n)
	check("every sound is built (one-shots and seamless loops)", ok, "%d sounds" % names.size())
	var audio := AudioDirector.current()
	check("London has an audio director", audio != null)
	await tp(Vector3(0.0, 0.1, 20.0), PI, 10)
	Input.action_press("move_forward")
	await wait(90)
	release_all()
	var playing := audio.find_children("*", "AudioStreamPlayer3D", false, false).any(func(p: Node) -> bool: return (p as AudioStreamPlayer3D).playing)
	check("footsteps sound as Harry walks", playing)
	await wait(60)
	check("city hum and birdsong by day", audio.bed_levels["city"] > 0.2 and audio.bed_levels["birds"] > 0.02, str(audio.bed_levels))
	Weather.set_weather(Weather.Kind.STORM, true)
	await wait(200)
	check("rain on the stones", audio.bed_levels["rain"] > 0.3 and audio.is_bed_playing("rain"), str(audio.bed_levels["rain"]))
	Weather.set_weather(Weather.Kind.CLEAR, true)
	GameClock.bus().hour_passed.emit(3)
	await wait(10)
	check("St Giles's bell tolls the hour", audio.get("_bell_left") == 2, str(audio.get("_bell_left")))
	var g := Guard.new()
	g.name = "SoundTestConstable"
	g.position = Vector3(0.0, 0.05, -40.0)
	main.add_child(g)
	await wait(5)
	g.start_chase(harry.global_position)
	await wait_until(func() -> bool: return audio.is_music_playing("chase"), 150)
	check("a chase brings the music in", audio.mood == AudioDirector.Mood.CHASE and audio.is_music_playing("chase"), "mood %s, guard %s, pulse built %s" % [AudioDirector.Mood.keys()[audio.mood], Guard.State.keys()[g.state], SoundLibrary.is_cached("pulse")])
	g.queue_free()
	await wait(200)
	check("...and it fades when it's over", audio.mood == AudioDirector.Mood.CALM)


# ---------------------------------------------------------------------------
func _test_story_basics() -> void:
	check("the story starts with Cold Hearth (in the hills)", Story.next_mission()["id"] == "cold_hearth")
	var givers := get_nodes_in_group_safe("mission_givers")
	check("London's missions are waiting for their turn", givers.size() == 5 and givers.all(func(g: Node) -> bool: return not (g as MissionGiver).is_available()))
	Story.completed.append("cold_hearth")
	check("after Cold Hearth, Crowded Pockets is next", Story.next_mission()["id"] == "crowded_pockets")
	var d := Story.to_dict()
	Story.from_dict({"completed": ["cold_hearth", "crowded_pockets"], "flags": {"band_pip": true}})
	check("story progress saves and loads", Story.is_done("crowded_pockets") and Story.has_band("pip") and Story.band() == ["pip"])
	Story.from_dict(d)
	check("the ending follows the Ledger and the Legend", Story.ending()["id"] == "the_legend")


# ---------------------------------------------------------------------------
func _test_crowded_pockets() -> void:
	harry.inventory.money = 480
	await tp(Vector3(0.0, 0.1, -58.0), PI, 10)
	var started := await wait_until(func() -> bool: return mission() != null, 300)
	check("walking into the market by day starts Crowded Pockets", started and mission().id == "crowded_pockets")
	check("...with a title banner", ui.hud.get("_banner") != "")
	var pip := main.find_child("Pip", true, false) as StoryNPC
	var lost := await wait_until(func() -> bool: return harry.inventory.money == 0, 900)
	check("a boy bumps into Harry and takes his purse", lost and pip != null)
	await wait(60)
	check("Catch the boy!", objective() == "Catch the boy!" and pip.mode == StoryNPC.Mode.PATH, objective())
	await wait_until(func() -> bool: return pip.path_index() >= 1, 600)
	check("he runs for it round the market", pip.path_index() >= 1 and pip.global_position.distance_to(Vector3(0.0, 0.0, -58.0)) > 12.0, "at %s" % pip.global_position)
	# Harry catches him up.
	await tp(pip.global_position + Vector3(0.6, 0.1, 0.6), 0.0, 3)
	var caught := await wait_until(func() -> bool: return ui.dialogue.is_playing(), 120)
	check("caught him!", caught)
	await talk_through()
	check("he gives the purse back", harry.inventory.money == 480, str(harry.inventory.money))
	check("...and dares Harry to lift a toff's purse", objective().contains("gentleman"), objective())
	harry.inventory.stolen.emit("gentleman", 120)
	await wait(10)
	check("done: go back to Pip", objective().contains("Pip"), objective())
	await tp(pip.global_position + Vector3(1.2, 0.1, 0.0), -PI * 0.5, 5)
	var done := await finish("crowded_pockets")
	check("Crowded Pockets complete: Pip joins the Lantern Men", done and Story.has_band("pip"))
	await wait(30)
	var resident := get_nodes_in_group_safe("story_npcs").any(func(n: Node) -> bool: return (n as StoryNPC).display_name == "Pip" and n.visible)
	check("Pip hangs about the market afterwards", resident)


# ---------------------------------------------------------------------------
func _test_collector() -> void:
	var giver := main.find_child("Giver_the_collector", true, false) as MissionGiver
	check("Mrs Hale needs help", giver != null and giver.is_available() and giver.npc.visible)
	await tp(giver.npc.global_position + Vector3(1.6, 0.1, 0.0), PI * 0.5, 10)
	check("E: Talk to Mrs Hale", harry.interaction.prompt.begins_with("Talk to Mrs Hale"), harry.interaction.prompt)
	await press_for("interact", 2)
	await wait(5)
	check("The Collector begins", mission() != null and mission().id == "the_collector")
	await talk_through()
	var sloane := main.find_child("MrSloane", true, false) as Civilian
	check("Mr Sloane sets off for Ashcombe House with the rent", sloane != null and sloane.visible and objective().contains("Sloane"), objective())
	await wait(120)
	check("...walking up the street", sloane.global_position.z < 30.5, str(sloane.global_position))
	# First try: too late. He reaches the gate: mission failed.
	sloane.global_position = m3_gate() + Vector3(-1.5, 0.0, 0.0)
	var failed_ok := await wait_until(func() -> bool: return mission() != null and mission().failed, 300)
	check("if Sloane gets to the house, the mission fails", failed_ok, mission().fail_reason if mission() else "")
	var menu_up := await wait_until(func() -> bool: return not get_nodes_in_group_safe("choice_menus").is_empty(), 200)
	check("...and offers a retry from the last checkpoint", menu_up)
	(get_nodes_in_group_safe("choice_menus")[0] as ChoiceMenu).choose(0)
	await wait(20)
	sloane = main.find_child("MrSloane", true, false) as Civilian
	check("retried: Sloane is back at the bottom of the street", mission() != null and not mission().failed and mission().step == 1 and sloane != null and sloane.global_position.z > 25.0)
	# This time Harry lifts the bag.
	await wait(30)
	var loot := sloane.take_loot()
	harry.inventory.receive_loot(loot)
	await wait(10)
	check("the rent bag lifted: back to Mrs Hale", objective().contains("Mrs Hale"), objective())
	var legend := Progress.legend
	await tp(giver.global_position + Vector3(1.4, 0.1, 0.0), PI * 0.5, 10)
	var menu := await wait_until(func() -> bool: return not get_nodes_in_group_safe("choice_menus").is_empty(), 200)
	check("a choice: give it all back, or keep a little", menu)
	(get_nodes_in_group_safe("choice_menus")[0] as ChoiceMenu).choose(0)
	await wait(5)
	await talk_through()
	await wait_until(func() -> bool: return Story.is_done("the_collector"), 300)
	check("all of it back to the widow: the Legend begins", Story.is_done("the_collector") and Story.get_flag("hale_full") and Progress.legend > legend + 3.0, "%.1f -> %.1f" % [legend, Progress.legend])
	check("...and the bag is gone from Harry's coat", harry.inventory.items.all(func(it: Dictionary) -> bool: return not it.get("rent_bag", false)))


func m3_gate() -> Vector3:
	return Vector3(39.0, 0.05, -71.0)


# ---------------------------------------------------------------------------
func _fight_well(fight: BrawlFight) -> void:
	# Sway away from every blow, jab when he's open.
	var tapped := 0
	for i in 3000:
		if not is_instance_valid(fight) or fight.over:
			break
		if fight.foe_act == BrawlFight.FoeAct.WINDUP and fight.foe_windup - fight.foe_t < 0.2 and fight.harry_act == BrawlFight.Act.GUARD:
			Input.action_press("move_left")
			await wait(1)
			Input.action_release("move_left")
		elif fight.foe_act in [BrawlFight.FoeAct.RECOVER, BrawlFight.FoeAct.STAGGER, BrawlFight.FoeAct.GUARD] and fight.harry_act == BrawlFight.Act.GUARD and fight.gap() <= BrawlFight.REACH and tapped <= 0:
			Input.action_press("fire")
			await wait(2)
			Input.action_release("fire")
			tapped = 12
		else:
			Input.action_press("move_forward")
			await wait(1)
			Input.action_release("move_forward")
		tapped -= 1
	release_all()


func _test_bridge() -> void:
	await tp(Vector3(-28.0, 0.1, -4.3), PI * 0.5, 10)
	Input.action_press("move_forward")
	var started := await wait_until(func() -> bool: return mission() != null, 300)
	release_all()
	check("walking up to the footbridge starts The Bridge", started and mission().id == "the_bridge")
	await talk_through()
	var fight := BrawlFight.current
	check("a fist fight on the bridge", fight != null and harry.brawl == fight)
	# First: stand there and take it.
	var lost := await wait_until(func() -> bool: return mission() != null and mission().failed, 6000)
	check("a man who won't defend himself goes in the Fleet", lost and harry.global_position.y < -1.0, describe())
	check("...the fight hurts, but never kills", harry.health >= 15.0 and not harry.is_dead())
	await wait_until(func() -> bool: return not get_nodes_in_group_safe("choice_menus").is_empty(), 200)
	(get_nodes_in_group_safe("choice_menus")[0] as ChoiceMenu).choose(0)
	await wait(20)
	fight = BrawlFight.current
	check("retry: back on the bridge, fists up", fight != null and mission().step == 1 and harry.global_position.y > 0.0, describe())
	await _fight_well(fight)
	await wait(30)
	check("sway and jab: Tom goes into the Fleet", mission() != null and not mission().failed and mission().step == 2, "landed %d, taken %d" % [fight.hits_landed if is_instance_valid(fight) else -1, fight.hits_taken if is_instance_valid(fight) else -1])
	await wait_until(func() -> bool: return objective() == "Talk to Big Tom", 300)
	var tom := main.find_child("BigTom", true, false) as StoryNPC
	check("Tom climbs out of the ditch, laughing", tom != null and tom.global_position.y > -0.5, str(tom.global_position) if tom else "")
	await tp(tom.global_position + Vector3(1.5, 0.1, 0.0), PI * 0.5, 10)
	var done := await finish("the_bridge")
	check("Big Tom joins the Lantern Men", done and Story.has_band("tom"))


# ---------------------------------------------------------------------------
func _test_bernard() -> void:
	var giver := main.find_child("Giver_bernards_kitchen", true, false) as MissionGiver
	check("Father Bernard at his soup kitchen", giver != null and giver.is_available())
	var m := giver.begin()
	await wait(5)
	await talk_through()
	check("give at least a pound in the poor box", m != null and objective().contains("poor box"), objective())
	harry.inventory.money = 600
	AlmsBox.give(harry, 240)
	await wait(10)
	check("given: follow Father Bernard into the church", objective().contains("church"), objective())
	await tp(StGiles.ALTAR_POINT + Vector3(-2.5, 0.1, 0.0), -PI * 0.5, 30)
	var done := await finish("bernards_kitchen")
	check("the crypt is Harry's safehouse now", done and Story.get_flag("st_giles_safehouse"))
	var bed := district.get_node("CryptBed") as SafehouseBed
	check("...with a cot to sleep and save on", bed.get_prompt(harry).begins_with("Sleep"), bed.get_prompt(harry))
	# Sanctuary: a constable on Harry's heels loses him inside the church.
	await tp(Vector3(StGiles.DOOR_X, StGiles.FLOOR_TOP + 0.1, 12.0), 0.0, 10)
	var g := Guard.new()
	g.name = "SanctuaryTestConstable"
	g.position = Vector3(StGiles.DOOR_X - 3.0, 0.05, -2.0)
	main.add_child(g)
	await wait(5)
	g.start_chase(harry.global_position)
	await tp(Vector3(-58.0, StGiles.FLOOR_TOP + 0.1, 18.5), 0.0, 5) # behind a pier, out of sight
	var gave_up := await wait_until(func() -> bool: return g.state != Guard.State.CHASE, 400)
	check("sanctuary: chasers lose him in the church", gave_up, Guard.State.keys()[g.state])
	g.queue_free()


# ---------------------------------------------------------------------------
func _test_wanted() -> void:
	var giver := main.find_child("Giver_wanted", true, false) as MissionGiver
	check("the newsboy is crying the Hill Fox", giver != null and giver.is_available())
	await tp(giver.npc.global_position + Vector3(-1.4, -0.05, 0.0), -PI * 0.5, 10)
	check("E: Buy a newspaper", harry.interaction.prompt.begins_with("Buy a newspaper"), harry.interaction.prompt)
	var money := harry.inventory.money
	await press_for("interact", 2)
	await wait(5)
	check("Wanted: The Hill Fox begins", mission() != null and mission().id == "wanted")
	var saved := SaveGame.save(self, 3)
	check("no saving in the middle of a mission", not saved)
	await talk_through()
	await wait(20)
	check("a penny for the Police News", harry.inventory.money == money - 1)
	check("named in the papers: posters and extra constables", Progress.escalation() >= 2, "notoriety %.0f" % Progress.notoriety)
	await wait_until(func() -> bool: return objective().begins_with("Escape"), 300)
	await talk_through()
	var crowe := main.find_child("CaptainCrowe", true, false) as Guard
	check("Captain Crowe and his men give chase", crowe != null and crowe.state == Guard.State.CHASE, Guard.State.keys()[crowe.state] if crowe else "none")
	# Harry makes for the sanctuary of St Giles.
	await tp(Vector3(-58.0, StGiles.FLOOR_TOP + 0.1, 18.5), 0.0, 5)
	var escaped := await wait_until(func() -> bool: return mission() == null or mission().step >= 3, 900)
	var done := await finish("wanted")
	check("escaped into the church: the end of Act One", escaped and done and Story.get_flag("act1_complete"))
	check("Act Two is next", Story.act() == 2 and Story.next_mission().is_empty())
	check("Crowe's men are gone", not is_instance_valid(crowe))
	check("the Legend has grown", Progress.legend > 15.0, "%.1f (%s)" % [Progress.legend, Progress.rank()])
