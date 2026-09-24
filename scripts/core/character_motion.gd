class_name CharacterMotion
extends RefCounted
## Movement helpers shared by every walking character (Harry, guards, townsfolk).


## Lets a CharacterBody3D walk straight up a step (kerb, stoop, stair) no higher than
## `max_step`. Call just before move_and_slide() while on the floor. If a step is found the
## body is lifted onto it and the lifted height is returned (0 when nothing happened).
static func try_step_up(body: CharacterBody3D, velocity: Vector3, delta: float, max_step: float, min_probe: float = 0.14) -> float:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	if horizontal.length() < 0.0005:
		return 0.0
	# Look a little further ahead than one frame so fast movement still finds the step.
	var probe := horizontal.normalized() * maxf(horizontal.length(), min_probe)
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	params.from = body.global_transform
	params.motion = probe
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
		return 0.0 # nothing in the way
	if result.get_collision_normal().y > 0.7:
		return 0.0 # a walkable slope: move_and_slide handles it
	var up := Vector3.UP * max_step
	params.motion = up
	if PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
		return 0.0 # ceiling above
	params.from = body.global_transform.translated(up)
	params.motion = probe
	if PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
		return 0.0 # still blocked: a wall, not a step
	params.from = body.global_transform.translated(up + probe)
	params.motion = -up
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
		return 0.0 # no floor there
	if result.get_collision_normal().y < cos(body.floor_max_angle):
		return 0.0
	var step_height := max_step + result.get_travel().y
	if step_height < 0.02:
		return 0.0
	body.global_position.y += step_height + 0.005
	return step_height
