class_name NPCCharacter
extends CharacterBody3D
## Shared base for every walking NPC (constables, townsfolk, merchants, later servants).
## Provides: collision capsule, a NavigationAgent3D with crowd avoidance, walking along
## the navmesh, turning, stepping up kerbs, gravity, the visible NPCBody, and distance
## level-of-detail so large crowds stay fast.

const LAYER_NPC := 1 << 2

@export var display_name: String = "Passer-by"
@export var outfit: NPCBody.Outfit = NPCBody.Outfit.WORKER
@export_file("*.glb", "*.tscn") var body_model_path: String = ""
@export var turn_speed: float = 5.0

## 0 = near (full detail), 1 = middle distance (animation at a lower rate),
## 2 = far (no animation, thinking slowed down). Updated twice a second.
var lod_level: int = 0

var _agent: NavigationAgent3D
var _body: NPCBody
var _yaw := 0.0
var _look_yaw := NAN
var _moving := false
var _speed := 0.0
var _pose: NPCBody.Pose = NPCBody.Pose.NORMAL
var _safe_velocity := Vector3.ZERO
var _has_safe_velocity := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _lod_timer := 0.0
var _frame := 0


func _setup_npc(max_speed: float, body_height: float = 1.76) -> void:
	collision_layer = LAYER_NPC
	collision_mask = 1 | (1 << 1) | (1 << 3) | LAYER_NPC
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = body_height
	cs.shape = cap
	cs.position = Vector3(0, body_height * 0.5, 0)
	add_child(cs)

	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.radius = 0.35
	_agent.height = 1.8
	_agent.max_speed = max_speed
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = 5.0
	_agent.max_neighbors = 8
	_agent.time_horizon_agents = 1.2
	_agent.velocity_computed.connect(func(v: Vector3) -> void:
		_safe_velocity = v
		_has_safe_velocity = true)
	add_child(_agent)

	_body = NPCBody.new()
	_body.name = "Body"
	_body.outfit = outfit
	_body.model_path = body_model_path
	_body.height = body_height + 0.02
	add_child(_body)
	_yaw = rotation.y
	rotation = Vector3.ZERO
	_frame = randi() % 12
	_lod_timer = randf() * 0.5


func get_facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > 0


func _begin_frame(delta: float) -> void:
	_frame += 1
	_moving = false
	_speed = 0.0
	_agent.velocity = Vector3.ZERO
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.5
		var cam := get_viewport().get_camera_3d()
		var d := cam.global_position.distance_to(global_position) if cam else 0.0
		lod_level = 0 if d < 35.0 else (1 if d < 80.0 else 2)


## Walks towards `target` along the navmesh. Returns true on arrival.
func _move_to(target: Vector3, speed: float) -> bool:
	if _agent.target_position.distance_to(target) > 0.3:
		_agent.target_position = target
	var flat := Vector2(target.x - global_position.x, target.z - global_position.z).length()
	if flat < 0.6 or _agent.is_navigation_finished():
		return true
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return false
	dir = dir.normalized()
	_moving = true
	_speed = speed
	_agent.max_speed = speed
	_agent.velocity = dir * speed
	_look_yaw = atan2(-dir.x, -dir.z)
	return false


func _face_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		_look_yaw = atan2(-d.x, -d.z)


func _apply_movement(delta: float, frozen: bool = false) -> void:
	var h := Vector3.ZERO
	if _moving and not frozen:
		h = _safe_velocity if _has_safe_velocity else _agent.velocity
		h.y = 0.0
	var cur := Vector3(velocity.x, 0.0, velocity.z)
	cur = cur.move_toward(h, 12.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	if is_on_floor() and h != Vector3.ZERO:
		CharacterMotion.try_step_up(self, velocity, delta, 0.34)
	move_and_slide()
	if not is_nan(_look_yaw) and not frozen:
		_yaw = rotate_toward(_yaw, _look_yaw, turn_speed * delta)
	_body.rotation.y = _yaw
	# Level of detail: far-away people are animated less often (or not at all).
	var step := 1 if lod_level == 0 else (3 if lod_level == 1 else 0)
	if step > 0 and _frame % step == 0:
		_body.update_body(Vector2(velocity.x, velocity.z).length(), _pose, delta * step)
