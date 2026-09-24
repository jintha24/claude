extends "res://tests/test_base.gd"
## Phase 2: vault, mantle, drainpipes, roofs, drop-to-hang, shimmy, climb up, drops,
## wall-run grab, landing rolls, roof gaps and height-change pipes.

var street: Node3D


func run_tests() -> void:
	street = main.get_node("LondonStreet")

	# Vault the horse trough in the road (x = -3.3) running west.
	await tp(Vector3(1.5, 0.05, 20.0), PI * 0.5)
	Input.action_press("move_left")
	Input.action_press("sprint")
	var vaulted := false
	for i in 120:
		await wait(1)
		if harry.global_position.x < -2.2 and not vaulted:
			Input.action_press("jump")
		if harry.state == Harry.State.VAULT:
			vaulted = true
			Input.action_release("jump")
		if vaulted and harry.global_position.x < -4.4:
			break
	release_all()
	await wait(20)
	check("vault horse trough", vaulted and harry.global_position.x < -4.0 and harry.health >= 100.0)

	# Mantle onto the handcart.
	await tp(Vector3(-0.3, 0.05, -8.0), PI * 0.5)
	Input.action_press("move_left")
	var mantled := await wait_until(func() -> bool:
		if harry.global_position.x < -1.2:
			Input.action_press("jump")
		return harry.state == Harry.State.CLIMB_UP, 150)
	release_all()
	await wait_until(func() -> bool: return not harry.is_climbing(), 120)
	await wait(10)
	check("mantle onto handcart", mantled and harry.global_position.y > 0.95 and harry.is_on_floor())

	# Drainpipe to the roof of East_00.
	var b: BuildingFacade = street.get_node("East_00")
	var cs := (b.get_node("Drainpipe") as StaticBody3D).get_child(0) as CollisionShape3D
	var n := b.global_transform.basis.z.normalized()
	await tp(Vector3(cs.global_position.x, 0.2, cs.global_position.z) + n * 0.75, atan2(n.x, n.z))
	await press_for("jump", 3)
	await wait(25)
	check("grab drainpipe", harry.state == Harry.State.PIPE)
	Input.action_press("move_forward")
	var over := await wait_until(func() -> bool: return harry.state == Harry.State.CLIMB_UP, 1200)
	await wait_until(func() -> bool: return not harry.is_climbing(), 200)
	release_all()
	await wait(20)
	var roof_h := b.global_position.y + b.get_facade_height()
	check("climb pipe onto roof", over and harry.global_position.y > roof_h - 0.1 and harry.is_on_floor())

	# Crouch-walk off the eave into a hang.
	await press_for("crouch", 2)
	await wait(5)
	Input.action_press("move_left")
	var hung := await wait_until(func() -> bool: return harry.state == Harry.State.HANG, 240)
	release_all()
	await wait(30)
	check("drop to hang from cornice", hung and harry.state == Harry.State.HANG)
	var before := harry.global_position
	Input.action_press("move_forward")
	await wait(90)
	release_all()
	await wait(10)
	check("shimmy along cornice", harry.state == Harry.State.HANG and harry.global_position.distance_to(before) > 0.4)
	await press_for("jump", 3)
	var up := await wait_until(func() -> bool: return harry.state == Harry.State.CLIMB_UP, 30)
	await wait_until(func() -> bool: return not harry.is_climbing(), 150)
	await wait(20)
	check("climb up from hang", up and harry.global_position.y > roof_h - 0.1)

	# Hang again, then let go with crouch.
	await press_for("crouch", 2)
	Input.action_press("move_left")
	await wait_until(func() -> bool: return harry.state == Harry.State.HANG, 240)
	release_all()
	await wait(20)
	Input.action_press("crouch")
	await wait(5)
	var dropping := harry.state == Harry.State.FALL
	await wait_until(func() -> bool: return harry.is_on_floor(), 300)
	release_all()
	await wait(30)
	check("let go of ledge and fall", dropping and harry.global_position.y < 0.3)

	# Running wall-grab of a first-floor ledge.
	await tp(Vector3(1.0, 0.05, 30.0), -PI * 0.5)
	Input.action_press("move_right")
	var grabbed := await wait_until(func() -> bool:
		if harry.global_position.x > 4.6:
			Input.action_press("jump")
		return harry.state in [Harry.State.GRAB, Harry.State.HANG, Harry.State.CLIMB_UP], 150)
	release_all()
	await wait(40)
	check("running wall-grab of a ledge above 3 m", grabbed and float(harry.parkour.ledge.get("top", 0.0)) > 3.0)
	await press_for("crouch", 3)
	await wait(90)

	# Landing roll vs hard landing.
	await tp(Vector3(0.0, 5.6, 0.0), 0.0, 1)
	harry.velocity = Vector3(0, 0, -4.0)
	Input.action_press("move_forward")
	var rolled := await wait_until(func() -> bool: return harry.state == Harry.State.ROLL, 120)
	release_all()
	await wait(60)
	check("parkour roll after 5.5 m drop", rolled and harry.health > 90.0)
	await tp(Vector3(0.0, 5.6, -5.0), 0.0, 120)
	check("standing drop from 5.5 m hurts more", harry.health < 97.0 and harry.health > 50.0)

	# Alley platform -> adjacent roof.
	await tp(Vector3(7.2, 9.1, 4.6), 0.0)
	Input.action_press("move_forward")
	await wait(20)
	Input.action_press("jump")
	var m2 := await wait_until(func() -> bool: return harry.state == Harry.State.CLIMB_UP, 70)
	await wait_until(func() -> bool: return not harry.is_climbing(), 120)
	release_all()
	await wait(30)
	check("alley platform -> roof", m2 and harry.global_position.y > 9.5)

	# Jump the alley between the two roofs.
	await tp(Vector3(9.0, 12.0, 1.5), PI, 40)
	var y0 := harry.global_position.y
	Input.action_press("move_back")
	Input.action_press("sprint")
	for i in 120:
		await wait(1)
		if harry.global_position.z > 3.55 and harry.is_on_floor():
			Input.action_press("jump")
		if harry.global_position.z > 7.2 and harry.is_on_floor():
			break
	release_all()
	await wait(30)
	check("jump the alley gap roof-to-roof", harry.global_position.z > 6.5 and absf(harry.global_position.y - y0) < 1.0)

	# Side pipe up a one-storey height change between roofs.
	var rp: StaticBody3D = null
	for c in street.get_children():
		if c is StaticBody3D and c.is_in_group("climbable_pipe"):
			rp = c
			break
	check("height-change pipes exist", rp != null)
	if rp:
		var rcs := rp.get_child(0) as CollisionShape3D
		var rh := (rcs.shape as CylinderShape3D).height
		var base := rcs.global_position - Vector3.UP * rh * 0.5
		var space := harry.get_world_3d().direct_space_state
		var side := 1.0
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.0, 0), base + Vector3(0, 1.0, 0.5))).is_empty():
			side = -1.0
		await tp(base + Vector3(0, 0.42, side * 0.7), 0.0 if side > 0 else PI, 30)
		await press_for("jump", 3)
		var on_pipe := await wait_until(func() -> bool: return harry.state == Harry.State.PIPE, 40)
		Input.action_press("move_forward" if side > 0 else "move_back")
		var top_reached := await wait_until(func() -> bool: return harry.state == Harry.State.CLIMB_UP, 900)
		await wait_until(func() -> bool: return not harry.is_climbing(), 150)
		release_all()
		await wait(20)
		check("side pipe to the higher roof", on_pipe and top_reached and harry.global_position.y > base.y + rh - 0.2)

	# Falling while holding crouch never grabs a ledge.
	await tp(Vector3(5.5, 9.0, -30.0), -PI * 0.5, 1)
	Input.action_press("crouch")
	var grabbed_any := false
	for i in 100:
		await wait(1)
		if harry.is_climbing():
			grabbed_any = true
	release_all()
	check("holding crouch while falling: no grab", not grabbed_any)
