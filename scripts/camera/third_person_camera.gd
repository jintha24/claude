class_name ThirdPersonCamera
extends Node3D
## Over-the-shoulder third-person camera.
##
## Node layout (built automatically in _ready):
##   ThirdPersonCamera (follows Harry with a slight lag)
##     Yaw (turns left/right)
##       Pitch (looks up/down)
##         ShoulderArm (SpringArm3D pointing sideways: the shoulder offset, collision-safe)
##           BoomArm (SpringArm3D pointing backwards: the camera distance, collision-safe)
##             Mount (placed at the end of the arm by the SpringArm3D)
##               Camera3D (offset only by the subtle head-bob)
## Both arms are SpringArm3Ds, so neither the sideways offset nor the distance can ever
## push the camera through a wall: in tight alleys it pulls in close to Harry.

@export var target_path: NodePath

@export_group("Controls")
## Radians per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0022
## Radians per second at full right-stick deflection.
@export var stick_sensitivity: float = 2.6
@export var invert_y: bool = false
@export_range(-89.0, 0.0) var pitch_min_degrees: float = -70.0
@export_range(0.0, 89.0) var pitch_max_degrees: float = 55.0

@export_group("Framing")
@export var stand_pivot_height: float = 1.62
@export var crouch_pivot_height: float = 1.05
@export var stand_distance: float = 2.5
@export var crouch_distance: float = 2.0
@export var sprint_distance: float = 3.2
## Pulled back a little while hanging or climbing so the wall and next ledge are visible.
@export var climb_distance: float = 3.1
@export var shoulder_offset: float = 0.55
@export var base_fov: float = 68.0
@export var sprint_fov: float = 74.0

@export_group("Feel")
## Higher = tighter follow. 12 gives a slight, natural lag.
@export var follow_sharpness: float = 12.0
@export var vertical_follow_sharpness: float = 7.0
@export var framing_sharpness: float = 4.0
@export var head_bob_enabled: bool = true
@export var head_bob_amount: float = 0.022

var _target: Harry
var _yaw_node: Node3D
var _pitch_node: Node3D
var _shoulder_arm: SpringArm3D
var _boom_arm: SpringArm3D
var _camera: Camera3D
var _yaw := 0.0
var _pitch := deg_to_rad(-12.0)
var _side := 1.0
var _side_target := 1.0
var _pivot_height := 1.62
var _distance := 2.5
var _bob_phase := 0.0
var _follow_pos := Vector3.ZERO


func _ready() -> void:
	top_level = true
	# This node is moved every rendered frame (not in physics), so it must not be interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_rig()
	if not target_path.is_empty():
		_target = get_node(target_path) as Harry
	if _target:
		var mask_exclude := _target.get_rid()
		_shoulder_arm.add_excluded_object(mask_exclude)
		_boom_arm.add_excluded_object(mask_exclude)
		_follow_pos = _target.global_position
		_yaw = _target.facing_yaw
		global_position = _follow_pos + Vector3.UP * stand_pivot_height
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_rig() -> void:
	_yaw_node = Node3D.new()
	_yaw_node.name = "Yaw"
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	_yaw_node.add_child(_pitch_node)

	var probe := SphereShape3D.new()
	probe.radius = 0.18 # keeps the near plane out of walls

	_shoulder_arm = SpringArm3D.new()
	_shoulder_arm.name = "ShoulderArm"
	_shoulder_arm.shape = probe
	_shoulder_arm.collision_mask = 1 | (1 << 3) # world + props
	_shoulder_arm.margin = 0.05
	_pitch_node.add_child(_shoulder_arm)

	_boom_arm = SpringArm3D.new()
	_boom_arm.name = "BoomArm"
	_boom_arm.shape = probe
	_boom_arm.collision_mask = 1 | (1 << 3)
	_boom_arm.margin = 0.08
	_shoulder_arm.add_child(_boom_arm)

	# SpringArm3D sets its children's transforms, so the head-bob is applied to the camera
	# inside a mount node instead of fighting the arm for the camera's position.
	var mount := Node3D.new()
	mount.name = "Mount"
	_boom_arm.add_child(mount)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.near = 0.05
	_camera.far = 2000.0
	_camera.fov = base_fov
	_camera.current = true
	mount.add_child(_camera)
	for n: Node3D in [_yaw_node, _pitch_node, _shoulder_arm, _boom_arm, mount, _camera]:
		n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Heading of the camera around the vertical axis. Harry moves relative to this.
func get_yaw() -> float:
	return _yaw


func get_camera() -> Camera3D:
	return _camera


## Instantly place the camera behind Harry (used after respawning).
func snap_behind(yaw: float) -> void:
	_yaw = yaw
	_pitch = deg_to_rad(-12.0)
	if _target:
		_follow_pos = _target.global_position
		global_position = _follow_pos + Vector3.UP * _pivot_height


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := (event as InputEventMouseMotion).screen_relative
		_yaw -= motion.x * mouse_sensitivity
		_pitch -= motion.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
		_clamp_pitch()
	elif event.is_action_pressed("swap_shoulder"):
		_side_target = -_side_target


func _process(delta: float) -> void:
	if _target == null:
		return
	# Right stick.
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if stick != Vector2.ZERO:
		# Squared response gives fine control near the centre of the stick.
		var curved := stick * stick.length()
		_yaw -= curved.x * stick_sensitivity * delta
		_pitch -= curved.y * stick_sensitivity * 0.7 * delta * (-1.0 if invert_y else 1.0)
		_clamp_pitch()

	# Follow Harry's interpolated (smooth) position with a slight lag.
	var harry_pos := _target.get_global_transform_interpolated().origin
	var t_h := 1.0 - exp(-follow_sharpness * delta)
	var t_v := 1.0 - exp(-vertical_follow_sharpness * delta)
	_follow_pos.x = lerpf(_follow_pos.x, harry_pos.x, t_h)
	_follow_pos.z = lerpf(_follow_pos.z, harry_pos.z, t_h)
	_follow_pos.y = lerpf(_follow_pos.y, harry_pos.y, t_v)

	# Framing: lower and closer when crouching, further back and wider when sprinting.
	var t_f := 1.0 - exp(-framing_sharpness * delta)
	var want_height := crouch_pivot_height if _target.is_crouching else stand_pivot_height
	var want_distance := stand_distance
	var want_fov := base_fov
	if _target.is_climbing():
		want_distance = climb_distance
	elif _target.is_crouching:
		want_distance = crouch_distance
	elif _target.is_sprinting():
		want_distance = sprint_distance
		want_fov = sprint_fov
	_pivot_height = lerpf(_pivot_height, want_height, t_f)
	_distance = lerpf(_distance, want_distance, t_f)
	_camera.fov = lerpf(_camera.fov, want_fov, t_f)
	_side = move_toward(_side, _side_target, delta * 4.0)

	global_position = _follow_pos + Vector3.UP * _pivot_height
	_yaw_node.rotation = Vector3(0, _yaw, 0)
	_pitch_node.rotation = Vector3(_pitch, 0, 0)
	# The shoulder arm points along +X (right) or -X (left); the boom arm then points back.
	var side_angle := PI * 0.5 * signf(_side if absf(_side) > 0.001 else 1.0)
	_shoulder_arm.rotation = Vector3(0, side_angle, 0)
	_shoulder_arm.spring_length = absf(_side) * shoulder_offset
	_boom_arm.rotation = Vector3(0, -side_angle, 0)
	_boom_arm.spring_length = _distance

	# Subtle head bob, only while running or sprinting on the ground.
	var bob := Vector3.ZERO
	var speed := _target.get_horizontal_speed()
	if head_bob_enabled and not _target.is_airborne() and speed > 2.5:
		_bob_phase += delta * speed / 1.3 * PI
		var amt := head_bob_amount * clampf((speed - 2.5) / 3.5, 0.0, 1.0)
		bob = Vector3(cos(_bob_phase * 0.5) * amt * 0.5, absf(sin(_bob_phase)) * amt, 0.0)
	_camera.position = _camera.position.lerp(bob, 1.0 - exp(-12.0 * delta))

	# Hide Harry if the camera is pushed right into him (e.g. backed against a wall).
	var cam_dist := _camera.global_position.distance_to(global_position)
	var visual := _target.get_node_or_null("Visual") as Node3D
	if visual:
		visual.visible = cam_dist > 0.45


func _clamp_pitch() -> void:
	_pitch = clampf(_pitch, deg_to_rad(pitch_min_degrees), deg_to_rad(pitch_max_degrees))
