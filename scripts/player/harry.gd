class_name Harry
extends CharacterBody3D
## Harry Crane, "The Hill Fox". Third-person character controller.
##
## Responsibilities of this script: reading input, realistic movement (momentum,
## acceleration, turning), jumping, crouching, steps and stairs, falling and fall
## damage, pushing physics props, and the movement state machine.
## Visuals and animation live in HarryAnimator; the camera lives in ThirdPersonCamera.
##
## Phase 2 adds the CLIMB, HANG, VAULT and ROLL states; later phases add RIDE, SWIM,
## FISH, PICKPOCKET and LOCKPICK. Every state has enter/exit handling in _enter_state().

signal state_changed(old_state: State, new_state: State)
signal health_changed(health: float, max_health: float)
signal landed(fall_height: float)
signal died
signal respawned

enum State { IDLE, WALK, RUN, SPRINT, CROUCH_IDLE, CROUCH_WALK, JUMP, FALL, LAND, DEAD }

# --- Real-world body measurements ---------------------------------------------
const HEIGHT := 1.88 # 6 ft 2 in
const CAPSULE_RADIUS := 0.28
const STAND_CAPSULE_HEIGHT := 1.84
const CROUCH_CAPSULE_HEIGHT := 1.2

@export_group("Speeds (m/s)")
## Typical human walking pace is 1.3-1.5 m/s, jogging 3-4 m/s, sprinting 6-8 m/s.
@export var walk_speed: float = 1.45
@export var run_speed: float = 3.6
@export var sprint_speed: float = 6.4
@export var crouch_speed: float = 1.1

@export_group("Momentum")
@export var ground_acceleration: float = 7.0
@export var ground_deceleration: float = 10.0
@export var sprint_acceleration: float = 4.5
@export var air_acceleration: float = 1.2
## How fast Harry's body turns to face his movement (radians/second) at low and top speed.
@export var turn_rate_slow: float = 10.0
@export var turn_rate_fast: float = 4.0

@export_group("Jumping and falling")
## 3.3 m/s gives a ~0.55 m standing jump, realistic for a fit adult.
@export var jump_velocity: float = 3.3
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.15
## Falls shorter than this cause no damage.
@export var safe_fall_height: float = 3.5
## Falls this high or higher are fatal.
@export var fatal_fall_height: float = 11.0
@export var hard_landing_height: float = 2.2

@export_group("Steps")
## Highest step Harry walks straight up without jumping (stairs, kerbs, stoops).
@export var max_step_height: float = 0.36

@export_group("Health")
@export var max_health: float = 100.0
@export var regen_delay: float = 8.0
@export var regen_per_second: float = 3.0

@export_group("Physics")
## Force Harry applies to crates and barrels he walks into (N per kg of his own mass).
@export var push_strength: float = 2.0
@export var body_mass: float = 82.0

@export_group("Scene links")
@export var camera_path: NodePath

var state: State = State.IDLE
var health: float
var facing_yaw: float = 0.0
var is_crouching: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: ThirdPersonCamera
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _animator: HarryAnimator
var _coyote_timer := 0.0
var _jump_buffer := 0.0
var _air_peak_y := 0.0
var _was_on_floor := true
var _land_timer := 0.0
var _regen_timer := 0.0
var _spawn_transform: Transform3D
var _stand_check_shape: CapsuleShape3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 3) # world + props
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.4
	floor_constant_speed = true
	floor_stop_on_slope = true
	max_slides = 6
	safe_margin = 0.002

	_collision = $CollisionShape3D
	_capsule = _collision.shape as CapsuleShape3D
	_capsule.radius = CAPSULE_RADIUS
	_set_capsule_height(STAND_CAPSULE_HEIGHT)
	_stand_check_shape = CapsuleShape3D.new()
	_stand_check_shape.radius = CAPSULE_RADIUS - 0.02
	_stand_check_shape.height = STAND_CAPSULE_HEIGHT

	_animator = $Visual as HarryAnimator
	if not camera_path.is_empty():
		_camera = get_node(camera_path) as ThirdPersonCamera
	health = max_health
	facing_yaw = rotation.y
	rotation = Vector3.ZERO
	_spawn_transform = global_transform
	_spawn_transform.basis = Basis(Vector3.UP, facing_yaw)
	_air_peak_y = global_position.y


func set_spawn(xform: Transform3D) -> void:
	_spawn_transform = xform
	respawn()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_sprinting() -> bool:
	return state == State.SPRINT


func is_airborne() -> bool:
	return state == State.JUMP or state == State.FALL


func is_dead() -> bool:
	return state == State.DEAD


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)
		velocity.y -= _gravity * delta
		move_and_slide()
		return

	var on_floor := is_on_floor()
	_update_timers(delta, on_floor)

	# ---- Input -------------------------------------------------------------
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var strength := minf(input.length(), 1.0)
	var wish_dir := Vector3.ZERO
	if strength > 0.05:
		var yaw := _camera.get_yaw() if _camera else 0.0
		wish_dir = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw).normalized()

	if Input.is_action_just_pressed("crouch") and on_floor:
		_toggle_crouch()
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time

	# ---- Choose a gait and target speed -----------------------------------
	var wants_sprint := Input.is_action_pressed("sprint") and strength > 0.6 and not is_crouching
	var wants_walk := Input.is_action_pressed("walk") or strength < 0.55
	if wants_sprint and is_crouching:
		_try_stand_up()
	var target_speed := 0.0
	if strength > 0.05:
		if is_crouching:
			target_speed = crouch_speed * clampf(strength * 1.5, 0.4, 1.0)
		elif wants_sprint:
			target_speed = sprint_speed
		elif wants_walk:
			target_speed = walk_speed * clampf(strength * 1.8, 0.5, 1.0)
		else:
			target_speed = run_speed
	if state == State.LAND:
		target_speed *= 0.35 # recovering from a heavy landing

	# ---- Horizontal momentum ---------------------------------------------
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_vel := wish_dir * target_speed
	var accel: float
	if not on_floor:
		accel = air_acceleration
	elif target_vel.length() < horizontal.length() - 0.05 or horizontal.dot(target_vel) < 0.0:
		accel = ground_deceleration
	elif target_speed > run_speed + 0.1:
		accel = sprint_acceleration
	else:
		accel = ground_acceleration
	# A sprinting body can't turn on the spot: blend direction first, then speed.
	if on_floor and horizontal.length() > 0.5 and wish_dir != Vector3.ZERO:
		var speed_ratio := clampf(horizontal.length() / sprint_speed, 0.0, 1.0)
		var turn_rate := lerpf(turn_rate_slow * 1.6, turn_rate_fast * 1.4, speed_ratio)
		var cur_dir := horizontal.normalized()
		var angle := cur_dir.signed_angle_to(wish_dir, Vector3.UP)
		if absf(angle) < deg_to_rad(135.0):
			var step := clampf(angle, -turn_rate * delta, turn_rate * delta)
			horizontal = horizontal.rotated(Vector3.UP, step)
	horizontal = horizontal.move_toward(target_vel, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# ---- Vertical ----------------------------------------------------------
	if on_floor:
		_air_peak_y = global_position.y
	else:
		velocity.y -= _gravity * delta
		_air_peak_y = maxf(_air_peak_y, global_position.y)

	if _jump_buffer > 0.0 and _coyote_timer > 0.0 and state != State.LAND:
		if is_crouching:
			_try_stand_up()
		else:
			velocity.y = jump_velocity + horizontal.length() * 0.08 # a running jump goes a bit higher
			_jump_buffer = 0.0
			_coyote_timer = 0.0
			_set_state(State.JUMP)

	# ---- Move --------------------------------------------------------------
	var stepped := false
	if on_floor and state != State.JUMP:
		stepped = _try_step_up(delta)
	move_and_slide()
	_push_props()

	# ---- Facing ------------------------------------------------------------
	var hspeed := get_horizontal_speed()
	if hspeed > 0.2:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		var rate := lerpf(turn_rate_slow, turn_rate_fast, clampf(hspeed / sprint_speed, 0.0, 1.0))
		facing_yaw = rotate_toward(facing_yaw, target_yaw, rate * delta)
	elif is_crouching and wish_dir != Vector3.ZERO:
		facing_yaw = rotate_toward(facing_yaw, atan2(-wish_dir.x, -wish_dir.z), turn_rate_slow * delta)

	# ---- Landing and state --------------------------------------------------
	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor and not stepped:
		_on_landed()
	_was_on_floor = now_on_floor
	_update_state(now_on_floor, hspeed)

	if _animator:
		_animator.update_animation(state, hspeed, facing_yaw, velocity.y, delta)


func _update_timers(delta: float, on_floor: bool) -> void:
	_coyote_timer = coyote_time if on_floor else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _land_timer > 0.0:
		_land_timer -= delta
	_regen_timer += delta
	if _regen_timer > regen_delay and health < max_health:
		health = minf(health + regen_per_second * delta, max_health)
		health_changed.emit(health, max_health)


func _update_state(on_floor: bool, hspeed: float) -> void:
	if not on_floor:
		if state != State.JUMP or velocity.y < 0.0:
			if _coyote_timer <= 0.0 or state == State.JUMP:
				_set_state(State.FALL)
		return
	if _land_timer > 0.0:
		_set_state(State.LAND)
		return
	if is_crouching:
		_set_state(State.CROUCH_WALK if hspeed > 0.15 else State.CROUCH_IDLE)
	elif hspeed < 0.15:
		_set_state(State.IDLE)
	elif hspeed < (walk_speed + run_speed) * 0.5:
		_set_state(State.WALK)
	elif hspeed < (run_speed + sprint_speed) * 0.5:
		_set_state(State.RUN)
	else:
		_set_state(State.SPRINT)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	_enter_state(new_state, old)
	state_changed.emit(old, new_state)


func _enter_state(new_state: State, _old_state: State) -> void:
	match new_state:
		State.JUMP, State.FALL:
			if is_crouching:
				is_crouching = false
				_set_capsule_height(STAND_CAPSULE_HEIGHT)
		_:
			pass


# ---------------------------------------------------------------------------
# Landing and fall damage
# ---------------------------------------------------------------------------
func _on_landed() -> void:
	var fall := _air_peak_y - global_position.y
	_air_peak_y = global_position.y
	landed.emit(fall)
	if fall >= hard_landing_height:
		# Knees absorb the impact: longer recovery for bigger drops.
		_land_timer = clampf(0.25 + (fall - hard_landing_height) * 0.12, 0.25, 1.2)
	if fall > safe_fall_height:
		var t := clampf((fall - safe_fall_height) / (fatal_fall_height - safe_fall_height), 0.0, 1.0)
		apply_damage(pow(t, 1.4) * max_health * 1.02)


func apply_damage(amount: float) -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_regen_timer = 0.0
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_set_state(State.DEAD)
		died.emit()
		get_tree().create_timer(3.5).timeout.connect(respawn)


func respawn() -> void:
	global_transform = Transform3D(Basis.IDENTITY, _spawn_transform.origin)
	facing_yaw = _spawn_transform.basis.get_euler().y
	velocity = Vector3.ZERO
	health = max_health
	is_crouching = false
	_set_capsule_height(STAND_CAPSULE_HEIGHT)
	_air_peak_y = global_position.y
	_land_timer = 0.0
	reset_physics_interpolation()
	_set_state(State.IDLE)
	if _camera:
		_camera.snap_behind(facing_yaw)
	health_changed.emit(health, max_health)
	respawned.emit()


# ---------------------------------------------------------------------------
# Crouching
# ---------------------------------------------------------------------------
func _toggle_crouch() -> void:
	if is_crouching:
		_try_stand_up()
	else:
		is_crouching = true
		_set_capsule_height(CROUCH_CAPSULE_HEIGHT)


func _try_stand_up() -> void:
	if not is_crouching:
		return
	# Only stand if there is head room (e.g. not under a cart or a low beam).
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_check_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, STAND_CAPSULE_HEIGHT * 0.5 + 0.03, 0))
	query.collision_mask = 1 | (1 << 3)
	var exclude: Array[RID] = [get_rid()]
	query.exclude = exclude
	if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		is_crouching = false
		_set_capsule_height(STAND_CAPSULE_HEIGHT)


func _set_capsule_height(h: float) -> void:
	_capsule.height = h
	_collision.position = Vector3(0, h * 0.5, 0)


# ---------------------------------------------------------------------------
# Steps: walk straight up kerbs, stoops and stairs up to max_step_height.
# ---------------------------------------------------------------------------
func _try_step_up(delta: float) -> bool:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	if horizontal.length() < 0.0005:
		return false
	# Look a little further ahead than one frame so fast movement still detects the step.
	var probe := horizontal.normalized() * maxf(horizontal.length(), CAPSULE_RADIUS * 0.5)
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	params.from = global_transform
	params.motion = probe
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return false # nothing in the way
	if result.get_collision_normal().y > 0.7:
		return false # it's a walkable slope, move_and_slide handles it
	# Try the same move from max_step_height higher up.
	var up := Vector3.UP * max_step_height
	params.motion = up
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return false # ceiling above
	params.from = global_transform.translated(up)
	params.motion = probe
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return false # still blocked: it's a wall, not a step
	# Drop back down onto the step.
	params.from = global_transform.translated(up + probe)
	params.motion = -up
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return false # no floor there
	if result.get_collision_normal().y < cos(floor_max_angle):
		return false
	var step_height := max_step_height + result.get_travel().y
	if step_height < 0.02:
		return false
	global_position.y += step_height + 0.005
	if _animator:
		_animator.absorb_step(step_height)
	return true


func _push_props() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb == null:
			continue
		var push_dir := -col.get_normal()
		push_dir.y = 0.0
		if push_dir.length_squared() < 0.001:
			continue
		var speed_into := maxf(Vector3(velocity.x, 0, velocity.z).dot(push_dir.normalized()), 0.3)
		var mass_ratio := clampf(body_mass / rb.mass, 0.1, 2.0)
		rb.apply_impulse(push_dir.normalized() * push_strength * speed_into * mass_ratio, col.get_position() - rb.global_position)
