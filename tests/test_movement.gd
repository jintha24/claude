extends "res://tests/test_base.gd"
## Phase 1: walking, running, sprinting, stopping, kerbs, stairs, jumping, crouching,
## fall damage, death and respawn.


func run_tests() -> void:
	await tp(Vector3(0, 0.05, 38.0))
	check("spawn on floor", harry.is_on_floor())

	Input.action_press("move_forward")
	await wait(60)
	check("run speed ~3.6 m/s", absf(harry.get_horizontal_speed() - harry.run_speed) < 0.1)
	Input.action_press("sprint")
	await wait(120)
	check("sprint speed ~6.4 m/s", absf(harry.get_horizontal_speed() - harry.sprint_speed) < 0.15)
	release_all()
	await wait(15)
	check("momentum: still moving 0.25 s after release", harry.get_horizontal_speed() > 1.0)
	await wait(60)
	check("comes to rest", harry.get_horizontal_speed() < 0.05 and harry.state == Harry.State.IDLE)

	await tp(Vector3(2.5, 0.05, 30.0))
	Input.action_press("move_right")
	await wait(100)
	check("steps up the kerb", absf(harry.global_position.y - 0.15) < 0.02)

	await tp(Vector3(7.5, 0.2, 4.6))
	Input.action_press("move_right")
	await wait(300)
	check("climbs alley stairs to 4.5 m landing", absf(harry.global_position.y - 4.5) < 0.05)
	await tp(Vector3(16.0, 4.6, 5.8))
	Input.action_press("move_left")
	await wait(300)
	check("climbs second flight to 9 m platform", absf(harry.global_position.y - 9.0) < 0.05)
	check("handrail stops him walking off", harry.global_position.x > 6.5)

	await tp(Vector3(0, 0.05, 20.0))
	await press_for("jump", 2)
	var peak := 0.0
	for i in 60:
		await wait(1)
		peak = maxf(peak, harry.global_position.y)
	check("standing jump height 0.5-0.65 m", peak > 0.5 and peak < 0.65, "peak %.2f" % peak)

	await press_for("crouch", 2)
	await wait(10)
	check("crouch", harry.is_crouching and harry.state == Harry.State.CROUCH_IDLE)
	await press_for("crouch", 2)
	await wait(10)
	check("stand up", not harry.is_crouching)

	await tp(Vector3(0, 3.4, 10.0))
	await wait(90)
	check("3.3 m drop: no damage", harry.health >= 100.0)
	await tp(Vector3(0, 9.0, 10.0))
	await wait(120)
	check("9 m drop: heavy damage", harry.health < 45.0 and harry.health > 20.0, "hp %.0f" % harry.health)
	await tp(Vector3(0, 13.0, 10.0))
	await wait(120)
	check("13 m drop: fatal", harry.state == Harry.State.DEAD and harry.health <= 0.0)
	Input.action_press("move_forward")
	await wait(30)
	check("dead Harry cannot move", harry.state == Harry.State.DEAD and harry.get_horizontal_speed() < 0.5)
	release_all()
	var back := await wait_until(func() -> bool: return harry.state != Harry.State.DEAD, 300)
	check("respawns after death", back and harry.health >= 100.0 and harry.global_position.distance_to(Vector3(0, 0, 38)) < 0.5)

	# Pushing a crate: find one and walk into it.
	var crate: RigidBody3D = null
	for n in main.get_node("LondonStreet/Props").get_children():
		if n is RigidBody3D and n.name.begins_with("Crate"):
			crate = n
			break
	if crate:
		var start := crate.global_position
		await tp(start + Vector3(-1.2, -0.25, 0), -PI * 0.5)
		Input.action_press("move_right")
		await wait(90)
		release_all()
		await wait(30)
		check("pushes a crate", crate.global_position.distance_to(start) > 0.1)
