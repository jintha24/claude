class_name Harry
extends CharacterBody3D
## Harry Crane, "The Hill Fox". Third-person character controller.
##
## Responsibilities of this script: reading input, realistic movement (momentum,
## acceleration, turning), jumping, crouching, steps and stairs, falling, fall damage
## and landing rolls, pushing physics props, and the movement state machine.
## Climbing and parkour live in HarryParkour (child node "Parkour"), visuals and
## animation in HarryAnimator ("Visual"), and the camera in ThirdPersonCamera.
##
## Later phases add RIDE, SWIM, FISH, PICKPOCKET and LOCKPICK states.

signal state_changed(old_state: State, new_state: State)
signal health_changed(health: float, max_health: float)
signal landed(fall_height: float)
signal died
signal arrested(by: Node)
signal respawned

enum State {
	IDLE, WALK, RUN, SPRINT, CROUCH_IDLE, CROUCH_WALK, JUMP, FALL, LAND, ROLL,
	GRAB, HANG, CLIMB_UP, PIPE, VAULT, TAKEDOWN, ARRESTED, DEAD,
}

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
## Moving at least this fast when landing from a big drop turns it into a parkour roll.
@export var roll_min_speed: float = 2.0
## Rolls only work up to this height; above it the impact is too great.
@export var roll_max_height: float = 7.5
## Fraction of fall damage still taken when rolling.
@export_range(0.0, 1.0) var roll_damage_factor: float = 0.35
@export var roll_duration: float = 0.8

@export_group("Steps")
## Highest step Harry walks straight up without jumping (stairs, kerbs, stoops).
@export var max_step_height: float = 0.36

@export_group("Health")
@export var max_health: float = 100.0
@export var regen_delay: float = 8.0
@export var regen_per_second: float = 3.0

@export_group("Physics")
## Force Harry leans into crates and barrels he walks into (a strong push is 300-500 N).
@export var push_force: float = 350.0

@export_group("Scene links")
@export var camera_path: NodePath

var state: State = State.IDLE
var health: float
var facing_yaw: float = 0.0
var is_crouching: bool = false
var parkour: HarryParkour
var stealth: HarryStealth
var combat: HarryCombat

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
var _roll_timer := 0.0
var _respawning := false
var _wish_dir := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 2) | (1 << 3) # world + NPCs + props
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
	parkour = get_node_or_null("Parkour") as HarryParkour
	if parkour == null:
		parkour = HarryParkour.new()
		parkour.name = "Parkour"
		add_child(parkour)
	parkour.setup(self, CAPSULE_RADIUS, STAND_CAPSULE_HEIGHT, CROUCH_CAPSULE_HEIGHT)
	stealth = _ensure_child("StealthProfile", HarryStealth) as HarryStealth
	stealth.setup(self)
	combat = _ensure_child("Combat", HarryCombat) as HarryCombat
	combat.setup(self)
	if not camera_path.is_empty():
		_camera = get_node(camera_path) as ThirdPersonCamera
	health = max_health
	facing_yaw = rotation.y
	rotation = Vector3.ZERO
	_spawn_transform = global_transform
	_spawn_transform.basis = Basis(Vector3.UP, facing_yaw)
	_air_peak_y = global_position.y


func _ensure_child(child_name: String, type: Script) -> Node:
	var n := get_node_or_null(child_name)
	if n == null:
		n = type.new()
		n.name = child_name
		add_child(n)
	return n


func set_spawn(xform: Transform3D) -> void:
	_spawn_transform = xform
	respawn()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_sprinting() -> bool:
	return state == State.SPRINT


func is_airborne() -> bool:
	return state == State.JUMP or state == State.FALL


func is_climbing() -> bool:
	return parkour != null and parkour.is_busy()


## Camera-relative movement input as a horizontal world direction (length 0..1).
func get_wish_dir() -> Vector3:
	return _wish_dir


## The horizontal direction Harry's body is facing.
func get_facing_dir() -> Vector3:
	return Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))


func get_roll_time_left() -> float:
	return _roll_timer


func set_crouched(crouched: bool) -> void:
	is_crouching = crouched
	_set_capsule_height(CROUCH_CAPSULE_HEIGHT if crouched else STAND_CAPSULE_HEIGHT)


func is_dead() -> bool:
	return state == State.DEAD


func is_arrested() -> bool:
	return state == State.ARRESTED


func is_aiming() -> bool:
	return combat != null and combat.is_aiming()


## Caught by a constable: led away, then the game continues from the spawn point.
func arrest(by: Node) -> void:
	if state == State.DEAD or state == State.ARRESTED:
		return
	parkour.cancel()
	combat.cancel()
	velocity = Vector3.ZERO
	_set_state(State.ARRESTED)
	arrested.emit(by)
	get_tree().create_timer(4.0).timeout.connect(respawn)


func _physics_process(delta: float) -> void:
	if state == State.DEAD or state == State.ARRESTED:
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)
		velocity.y -= _gravity * delta
		move_and_slide()
		return

	# ---- Input -------------------------------------------------------------
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var strength := minf(input.length(), 1.0)
	var wish_dir := Vector3.ZERO
	if strength > 0.05:
		var yaw := _camera.get_yaw() if _camera else 0.0
		wish_dir = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw).normalized()
	_wish_dir = wish_dir * strength

	# ---- Takedowns own the body while they run --------------------------------
	if combat.is_busy():
		_update_timers(delta, true)
		combat.physics_update(delta)
		if _animator:
			_animator.update_animation(self, delta)
		return

	# ---- Climbing / parkour actions own the body while they run --------------
	if parkour.is_busy():
		_update_timers(delta, false)
		parkour.physics_update(delta)
		_air_peak_y = global_position.y
		_was_on_floor = false
		_coyote_timer = 0.0
		if not parkour.is_busy():
			_jump_buffer = 0.0
			if state == State.JUMP or state == State.FALL:
				_air_peak_y = global_position.y
		if _animator:
			_animator.update_animation(self, delta)
		return

	var on_floor := is_on_floor()
	_update_timers(delta, on_floor)

	if Input.is_action_just_pressed("crouch") and on_floor and state != State.ROLL:
		_toggle_crouch()
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	combat.handle_input(delta, on_floor)
	if combat.is_busy():
		if _animator:
			_animator.update_animation(self, delta)
		return
	var aiming := combat.is_aiming()
	if aiming:
		_jump_buffer = 0.0

	# Parkour from the ground: vault, mantle, climb, jump-grab, drainpipe.
	if _jump_buffer > 0.0 and on_floor and state != State.LAND and state != State.ROLL:
		if parkour.try_ground_action(wish_dir, get_horizontal_speed()):
			_jump_buffer = 0.0
			if _animator:
				_animator.update_animation(self, delta)
			return
	# Crouch-walking off an edge lowers Harry into a hang instead of dropping him.
	if is_crouching and on_floor and wish_dir != Vector3.ZERO:
		if parkour.try_drop_to_hang(wish_dir):
			if _animator:
				_animator.update_animation(self, delta)
			return
	# In the air: catch ledges and drainpipes within reach.
	if not on_floor and (state == State.JUMP or state == State.FALL) and not Input.is_action_pressed("crouch"):
		if parkour.try_air_grab(wish_dir):
			if _animator:
				_animator.update_animation(self, delta)
			return

	# ---- Choose a gait and target speed -----------------------------------
	var wants_sprint := Input.is_action_pressed("sprint") and strength > 0.6 and not is_crouching and not aiming
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
	if aiming:
		target_speed = minf(target_speed, walk_speed * 0.8) # walking with a drawn bow
	if state == State.ROLL:
		# Keep the momentum through the roll, along the way Harry is facing.
		wish_dir = get_facing_dir()
		target_speed = maxf(get_horizontal_speed(), 3.2)

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

	if _jump_buffer > 0.0 and _coyote_timer > 0.0 and state != State.LAND and state != State.ROLL:
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
	_push_props(delta, wish_dir)

	# ---- Facing ------------------------------------------------------------
	var hspeed := get_horizontal_speed()
	if aiming and _camera:
		facing_yaw = rotate_toward(facing_yaw, _camera.get_yaw(), 14.0 * delta)
	elif hspeed > 0.2 and state != State.ROLL:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		var rate := lerpf(turn_rate_slow, turn_rate_fast, clampf(hspeed / sprint_speed, 0.0, 1.0))
		facing_yaw = rotate_toward(facing_yaw, target_yaw, rate * delta)
	elif is_crouching and wish_dir != Vector3.ZERO:
		facing_yaw = rotate_toward(facing_yaw, atan2(-wish_dir.x, -wish_dir.z), turn_rate_slow * delta)

	# ---- Landing and state --------------------------------------------------
	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor and not stepped:
		_on_landed()
		if state == State.DEAD:
			_was_on_floor = true
			if _animator:
				_animator.update_animation(self, delta)
			return
	_was_on_floor = now_on_floor
	_update_state(now_on_floor, hspeed)

	if _animator:
		_animator.update_animation(self, delta)


func _update_timers(delta: float, on_floor: bool) -> void:
	_coyote_timer = coyote_time if on_floor else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _land_timer > 0.0:
		_land_timer -= delta
	if _roll_timer > 0.0:
		_roll_timer -= delta
		if _roll_timer <= 0.0 and is_crouching:
			_try_stand_up()
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
	if _roll_timer > 0.0:
		_set_state(State.ROLL)
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


func set_state(new_state: State) -> void:
	_set_state(new_state)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	# Once dead or arrested, only respawn() may bring Harry back.
	if (state == State.DEAD or state == State.ARRESTED) and not _respawning:
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
	var damage := 0.0
	if fall > safe_fall_height:
		var t := clampf((fall - safe_fall_height) / (fatal_fall_height - safe_fall_height), 0.0, 1.0)
		damage = pow(t, 1.4) * max_health * 1.02
	if fall >= hard_landing_height:
		if fall <= roll_max_height and get_horizontal_speed() >= roll_min_speed:
			# Parkour roll: spread the impact over the roll and keep running.
			_roll_timer = roll_duration
			damage *= roll_damage_factor
			if not is_crouching:
				is_crouching = true
				_set_capsule_height(CROUCH_CAPSULE_HEIGHT)
		else:
			# Knees absorb the impact: longer recovery for bigger drops.
			_land_timer = clampf(0.25 + (fall - hard_landing_height) * 0.12, 0.25, 1.2)
	if _roll_timer > 0.0:
		_set_state(State.ROLL)
	landed.emit(fall)
	apply_damage(damage)


func apply_damage(amount: float) -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_regen_timer = 0.0
	health_changed.emit(health, max_health)
	if health <= 0.0:
		parkour.cancel()
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
	_roll_timer = 0.0
	parkour.cancel()
	combat.cancel()
	reset_physics_interpolation()
	_respawning = true
	_set_state(State.IDLE)
	_respawning = false
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
	var lifted := CharacterMotion.try_step_up(self, velocity, delta, max_step_height, CAPSULE_RADIUS * 0.5)
	if lifted > 0.0 and _animator:
		_animator.absorb_step(lifted)
	return lifted > 0.0


func _push_props(delta: float, wish_dir: Vector3) -> void:
	if wish_dir == Vector3.ZERO:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb == null:
			continue
		var push_dir := -col.get_normal()
		push_dir.y = 0.0
		if push_dir.length_squared() < 0.001:
			continue
		push_dir = push_dir.normalized()
		var effort := clampf(wish_dir.dot(push_dir), 0.0, 1.0)
		if effort <= 0.0:
			continue
		# Push where the body touches it, but no higher than just above its centre, so
		# crates slide and tall barrels can rock without being flipped unrealistically.
		var contact := col.get_position()
		var point := Vector3(contact.x, minf(contact.y, rb.global_position.y + 0.2), contact.z)
		rb.sleeping = false
		rb.apply_impulse(push_dir * push_force * effort * delta, point - rb.global_position)
