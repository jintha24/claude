extends "res://tests/test_base.gd"
## Phase 3: guards' eyes and ears, suspicion rules, searching, chasing and arrests,
## the police rattle, takedowns, discovering bodies, hiding, light, and the longbow.


func spawn_guard(pos: Vector3, yaw: float, guard_name: String = "TestGuard") -> Guard:
	var g := Guard.new()
	g.name = guard_name
	g.display_name = guard_name
	g.position = pos
	g.rotation.y = yaw
	main.add_child(g)
	return g


func clear_guards() -> void:
	for g in get_nodes_in_group_safe("guards"):
		g.free()
	await wait(2)


## Yaw that makes something at `from` face `to`.
func yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


func run_tests() -> void:
	await wait(10)

	# --- Suspicion rules --------------------------------------------------------
	var g := spawn_guard(Vector3(0, 0, 20), 0.0)
	await tp(Vector3(0, 0.05, 11.0), 0.0)
	await wait(180)
	check("ignores a man walking/standing in a public street", g.awareness < 0.05 and g.state == Guard.State.WAIT, "aw %.2f" % g.awareness)

	await press_for("crouch", 2)
	Input.action_press("move_left")
	await wait(12)
	Input.action_release("move_left")
	Input.action_press("move_right")
	var noticed := await wait_until(func() -> bool: return g.state in [Guard.State.SUSPICIOUS, Guard.State.INVESTIGATE, Guard.State.CHASE], 240)
	release_all()
	check("notices a man sneaking crouched in plain view", noticed, Guard.State.keys()[g.state])
	await clear_guards()

	# Line of sight: a wall between them hides Harry completely.
	g = spawn_guard(Vector3(0, 0, 20), 0.0)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(4, 3, 0.3)
	wcs.shape = wbox
	wall.add_child(wcs)
	wall.position = Vector3(0, 1.5, 16.0)
	main.add_child(wall)
	await tp(Vector3(0, 0.05, 13.0), 0.0)
	harry.stealth.commit_crime(10.0)
	await wait(90)
	check("wall blocks line of sight", g.vision_score() == 0.0 and g.awareness < 0.05)
	wall.free()
	await wait(3)
	check("same spot without the wall: plainly visible", g.vision_score() > 0.3, "score %.2f" % g.vision_score())
	await clear_guards()

	# Vision cone: directly behind the guard is invisible.
	g = spawn_guard(Vector3(0, 0, 20), 0.0)
	await tp(Vector3(0, 0.05, 24.0), 0.0)
	harry.stealth.commit_crime(10.0)
	await wait(60)
	check("outside the vision cone (behind him): not seen", g.vision_score() == 0.0 and g.awareness < 0.05)
	await clear_guards()

	# Trespassing in the private yard (the alley) is enough to be chased.
	g = spawn_guard(Vector3(6.9, 0.2, 5.6), -PI * 0.5)
	await tp(Vector3(12.0, 0.2, 5.8), PI * 0.5)
	await wait(5)
	check("the alley counts as a restricted zone", harry.stealth.is_in_restricted_zone())
	var chased := await wait_until(func() -> bool: return g.state == Guard.State.CHASE, 300)
	check("trespasser seen -> chase", chased)
	var caught := await wait_until(func() -> bool: return harry.is_arrested(), 400)
	check("constable runs him down and arrests him", caught)
	var back := await wait_until(func() -> bool: return not harry.is_arrested(), 400)
	await wait(5)
	check("after the arrest Harry respawns and the guard resets", back and g.state in [Guard.State.WAIT, Guard.State.PATROL] and g.awareness == 0.0)
	await clear_guards()

	# --- Hearing, search, give up -------------------------------------------------
	g = spawn_guard(Vector3(0, 0, 20), 0.0)
	g.search_duration = 4.0
	await tp(Vector3(1.5, 3.2, 25.0), 0.0, 1) # drop 3 m behind him: a thump
	var heard := await wait_until(func() -> bool: return g.state == Guard.State.INVESTIGATE, 120)
	check("hears a heavy landing behind him and investigates", heard)
	await tp(Vector3(-4.8, 0.2, 38.0), 0.0) # Harry slips away
	var searching := await wait_until(func() -> bool: return g.state == Guard.State.SEARCH, 400)
	check("reaches the spot and searches", searching)
	var gave_up := await wait_until(func() -> bool: return g.state in [Guard.State.RETURN, Guard.State.WAIT], 700)
	check("gives up the search and returns", gave_up)
	var home := await wait_until(func() -> bool: return g.state == Guard.State.WAIT, 600)
	check("back at his post", home and g.global_position.distance_to(Vector3(0, 0, 20)) < 1.0)
	await clear_guards()

	# Quiet crouched footsteps close behind a guard are not heard.
	g = spawn_guard(Vector3(0, 0, 20), 0.0)
	await tp(Vector3(0.0, 0.05, 23.5), 0.0)
	await press_for("crouch", 2)
	Input.action_press("move_forward")
	await wait(70)
	release_all()
	check("crouch-walking behind him is silent", g.state == Guard.State.WAIT and g.awareness < 0.05, "aw %.2f" % g.awareness)
	await press_for("crouch", 2)
	await clear_guards()

	# --- Police rattle brings help --------------------------------------------------
	var a := spawn_guard(Vector3(6.9, 0.2, 5.6), -PI * 0.5, "Caller")
	var b := spawn_guard(Vector3(0, 0, 30), 0.0, "Helper")
	await tp(Vector3(12.0, 0.2, 5.8), PI * 0.5)
	await wait_until(func() -> bool: return a.state == Guard.State.CHASE, 300)
	var helped := await wait_until(func() -> bool: return b.state in [Guard.State.INVESTIGATE, Guard.State.CHASE, Guard.State.SEARCH], 60)
	check("a rattle 25 m away brings another constable", helped)
	await tp(Vector3(0, 0.05, 38.0), 0.0) # reset
	await clear_guards()

	# --- Takedown -------------------------------------------------------------------
	g = spawn_guard(Vector3(0, 0, 20), 0.0)
	var witness := spawn_guard(Vector3(-4.0, 0, 30), yaw_to(Vector3(-4, 0, 30), Vector3(0, 0, 36)), "Witness")
	await tp(Vector3(0, 0.05, 20.8), 0.0)
	check("takedown refused from the front", not g.can_be_taken_down_from(g.global_position + Vector3(0, 0, -0.8)))
	check("takedown allowed from behind", g.can_be_taken_down_from(harry.global_position))
	await press_for("interact", 2)
	var took := harry.state == Harry.State.TAKEDOWN
	await wait(110)
	check("chokehold takedown knocks the guard out", took and g.state == Guard.State.UNCONSCIOUS and g.is_in_group("unconscious_guards"))
	check("takedown behind the witness's back went unseen", witness.state in [Guard.State.WAIT, Guard.State.PATROL, Guard.State.RETURN])
	# Now turn the witness towards the body.
	await tp(Vector3(0, 0.05, 38.0), 0.0)
	witness._yaw = yaw_to(witness.global_position, g.global_position)
	witness._look_yaw = witness._yaw
	var found := await wait_until(func() -> bool: return witness.state in [Guard.State.INVESTIGATE, Guard.State.SEARCH, Guard.State.CHASE], 60)
	check("a constable finding an unconscious colleague raises the alarm", found and witness.alertness >= 0.9)
	await clear_guards()

	# --- Hiding in the hay -------------------------------------------------------
	var hay := main.get_node("LondonStreet/Props/HayHeap") as Node3D
	g = spawn_guard(hay.global_position + Vector3(0, 0, -5.0), PI)
	await tp(hay.global_position + Vector3(0, 0.05, 0), 0.0)
	await press_for("crouch", 2)
	await wait(10)
	check("crouched in the hay: hidden", harry.stealth.is_hidden() and g.vision_score() == 0.0)
	await press_for("crouch", 2)
	await wait(10)
	check("standing up out of the hay: visible again", not harry.stealth.is_hidden() and g.vision_score() > 0.0)
	await clear_guards()

	# --- Light ---------------------------------------------------------------------
	GameClock.minutes = 22.0 * 60.0 # night: the lamplighter has been round
	await wait(45)
	check("at 10 pm it's dark and the gas lamps are lit", Stealth.ambient_light < 0.1 and get_nodes_in_group_safe("gas_lamps").all(func(l: Node) -> bool: return (l as GasLamp).lit))
	var lamp: GasLamp = null
	for n in get_nodes_in_group_safe("gas_lamps"):
		lamp = n as GasLamp
		if lamp.global_position.x < 0.0:
			break
	await tp(lamp.global_position + Vector3(1.2, 0.0, 0.0), 0.0)
	await wait(10)
	var lit_exposure := harry.stealth.exposure
	await tp(Vector3(0.0, 0.05, 4.0), 0.0) # midway between lamps
	await wait(10)
	var dark_exposure := harry.stealth.exposure
	check("at night, under a gas lamp is far brighter than between lamps", lit_exposure > dark_exposure + 0.3, "%.2f vs %.2f" % [lit_exposure, dark_exposure])

	# --- Longbow ---------------------------------------------------------------------
	await tp(lamp.global_position + Vector3(8.0, 0.0, 0.0), 0.0)
	var target := lamp.global_position + Vector3.UP * (GasLamp.LANTERN_HEIGHT + 0.05)
	var origin := harry.global_position + Vector3.UP * 1.5
	var arrow := Arrow.create("blunt")
	main.add_child(arrow)
	arrow.launch(origin, HarryCombat._ballistic_direction(origin, target, 50.0) * 50.0, harry)
	await wait(40)
	check("blunt arrow smashes a gas lamp and puts it out", not lamp.lit)
	await tp(lamp.global_position + Vector3(1.2, 0.0, 0.0), 0.0)
	await wait(10)
	check("the doused lamp no longer lights Harry", harry.stealth.exposure < lit_exposure - 0.3, "%.2f" % harry.stealth.exposure)
	lamp.remove_meta("broken")
	lamp.lit = true
	GameClock.minutes = 12.0 * 60.0
	await wait(45)

	g = spawn_guard(Vector3(0, 0, 20), 0.0)
	await tp(Vector3(0, 0.05, 30.0), 0.0)
	var head := g.global_position + Vector3.UP * 1.62
	origin = harry.global_position + Vector3.UP * 1.5
	arrow = Arrow.create("blunt")
	main.add_child(arrow)
	arrow.launch(origin, HarryCombat._ballistic_direction(origin, head, 50.0) * 50.0, harry)
	await wait(30)
	check("blunt arrow to the head knocks out an unwary guard", g.state == Guard.State.UNCONSCIOUS)
	await clear_guards()

	g = spawn_guard(Vector3(0, 0, 20), 0.0)
	var chest := g.global_position + Vector3.UP * 1.1
	arrow = Arrow.create("blunt")
	main.add_child(arrow)
	arrow.launch(origin, HarryCombat._ballistic_direction(origin, chest, 50.0) * 50.0, harry)
	await wait(20)
	check("body hit only stuns and alerts him", g.state == Guard.State.STUNNED and g.alertness >= 0.9)
	await clear_guards()

	# Townsfolk come to gawk at fallen constables: clear them out of the line of fire.
	for c in get_nodes_in_group_safe("civilians"):
		if (c as Node3D).global_position.distance_to(Vector3(-3.0, 0.0, 20.0)) < 15.0:
			c.free()
	g = spawn_guard(Vector3(0, 0, 20), 0.0)
	var spot := Vector3(-3.0, 0.0, 14.0)
	origin = Vector3(-6.0, 1.5, 28.0)
	arrow = Arrow.create("whistle")
	main.add_child(arrow)
	arrow.launch(origin, HarryCombat._ballistic_direction(origin, spot, 35.0) * 35.0, harry)
	var lured := await wait_until(func() -> bool: return g.state == Guard.State.INVESTIGATE, 120)
	check("whistle arrow lures a guard to investigate", lured and g.last_known.distance_to(spot) < 3.0, "last known %s" % str(g.last_known))
	await clear_guards()

	# Shooting through the real controls uses ammo and spawns an arrow.
	await tp(Vector3(0, 0.05, 30.0), 0.0)
	var ammo_before := harry.combat.get_ammo("blunt")
	Input.action_press("aim")
	await wait(20)
	var aiming := harry.is_aiming()
	Input.action_press("fire")
	await wait(60)
	Input.action_release("fire")
	await wait(3)
	release_all()
	check("aim, draw and loose with the real controls", aiming and harry.combat.get_ammo("blunt") == ammo_before - 1 and not get_nodes_in_group_safe("arrows").is_empty())
	await wait(120)
	var landed_arrow: Arrow = null
	for n in get_nodes_in_group_safe("arrow_pickups"):
		landed_arrow = n
	if landed_arrow:
		await tp(landed_arrow.global_position + Vector3(0.5, 0.05, 0.0), 0.0)
		await press_for("interact", 2)
		await wait(5)
		check("pick the arrow back up", harry.combat.get_ammo("blunt") == ammo_before)
	else:
		check("arrow landed as a pickup", false)

	# Ballistics: the aim solution really lands on target.
	var sim_origin := Vector3.ZERO
	var sim_target := Vector3(0, 1.0, -35.0)
	var v := HarryCombat._ballistic_direction(sim_origin, sim_target, 55.0) * 55.0
	var p := sim_origin
	var dt := 1.0 / 240.0
	while p.z > sim_target.z:
		v.y -= Arrow.GRAVITY * dt
		v -= v * Arrow.DRAG * v.length() * dt
		p += v * dt
	check("arrow drop compensation lands within 25 cm at 35 m", absf(p.y - sim_target.y) < 0.25, "error %.2f m" % (p.y - sim_target.y))
