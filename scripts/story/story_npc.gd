class_name StoryNPC
extends NPCCharacter
## A named character in the story (Aldous, Pip, Big Tom, Father Bernard...). Missions
## direct them: stand and face someone, walk or run somewhere (along the navmesh where
## there is one, straight there where there isn't), run a route, follow Harry, or be
## moved by hand (a fight, a fall). Barks go to the subtitles.

enum Mode { IDLE, GOTO, PATH, FOLLOW, PUPPET }

@export var body_height: float = 1.76
## Stand-in look while idle (TALK, SIT, WAVE...); walking always uses the walk cycle.
@export var idle_pose: NPCBody.Pose = NPCBody.Pose.NORMAL

var mode: Mode = Mode.IDLE
var pose_override: int = -1
var move_speed: float = 1.4
var use_navmesh: bool = true

var _target := Vector3.ZERO
var _path: Array[Vector3] = []
var _path_i := 0
var _follow: Node3D = null
var _follow_dist := 2.0
var _face: Variant = null
var _arrived := true


func _ready() -> void:
	add_to_group("story_npcs")
	_setup_npc(7.0, body_height)


## Walks (or runs, with a higher speed) to `p`.
func go_to(p: Vector3, speed: float = 1.4) -> void:
	mode = Mode.GOTO
	_target = p
	move_speed = speed
	_arrived = false


## Runs through `points` in order.
func run_path(points: Array[Vector3], speed: float) -> void:
	mode = Mode.PATH
	_path = points.duplicate()
	_path_i = 0
	move_speed = speed
	_arrived = _path.is_empty()


func follow(node: Node3D, distance: float = 2.2, speed: float = 1.6) -> void:
	mode = Mode.FOLLOW
	_follow = node
	_follow_dist = distance
	move_speed = speed


func stop() -> void:
	mode = Mode.IDLE
	_arrived = true


## Keeps turning to face `what` (a Vector3 or a Node3D) while standing.
func face(what: Variant) -> void:
	_face = what


## Hands the body over to a script (a fight, a fall): it stops walking and thinking.
func set_puppet(on: bool) -> void:
	mode = Mode.PUPPET if on else Mode.IDLE
	velocity = Vector3.ZERO


func has_arrived() -> bool:
	return _arrived


func path_index() -> int:
	return _path_i


func set_yaw(yaw: float) -> void:
	_yaw = yaw
	_look_yaw = yaw
	_body.rotation.y = yaw


func get_yaw() -> float:
	return _yaw


func say(line: String) -> void:
	Stealth.bark(self, "%s: \"%s\"" % [display_name, line])


func _physics_process(delta: float) -> void:
	if mode == Mode.PUPPET:
		_body.rotation.y = _yaw
		_body.update_body(0.0, (pose_override if pose_override >= 0 else idle_pose) as NPCBody.Pose, delta)
		return
	_begin_frame(delta)
	match mode:
		Mode.GOTO:
			if _step_towards(_target, move_speed):
				_arrived = true
				mode = Mode.IDLE
		Mode.PATH:
			if _path_i < _path.size() and _step_towards(_path[_path_i], move_speed):
				_path_i += 1
				if _path_i >= _path.size():
					_arrived = true
					mode = Mode.IDLE
		Mode.FOLLOW:
			if is_instance_valid(_follow):
				var d := global_position.distance_to(_follow.global_position)
				if d > _follow_dist:
					_step_towards(_follow.global_position, move_speed if d < _follow_dist * 3.0 else move_speed * 2.2)
				else:
					_face_point(_follow.global_position)
	if not _moving and _face != null:
		if _face is Vector3:
			_face_point(_face)
		elif _face is Node3D and is_instance_valid(_face):
			_face_point((_face as Node3D).global_position)
	_pose = NPCBody.Pose.NORMAL if _moving else ((pose_override if pose_override >= 0 else idle_pose) as NPCBody.Pose)
	_apply_movement(delta)


## Moves one frame towards `p`; true once there.
func _step_towards(p: Vector3, speed: float) -> bool:
	if use_navmesh and _nav_ready():
		return _move_to(p, speed)
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.5:
		return true
	var dir := d.normalized()
	_moving = true
	_speed = speed
	_agent.velocity = dir * speed
	_safe_velocity = dir * speed
	_look_yaw = atan2(-dir.x, -dir.z)
	return false
