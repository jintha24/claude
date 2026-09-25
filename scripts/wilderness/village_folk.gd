class_name VillageFolk
extends CharacterBody3D
## A villager in the hills: out of doors by day - to the well, the green, the smithy, the
## church, a neighbour's gate - into the inn of an evening, indoors at night.
## Walks in straight lines between the village's open spots (Village.spots) on its level
## ground; far from the player they only think now and then.

const LAYER_NPC := 1 << 2

var village: Village
var home := Vector3.ZERO
var look_seed := -1
var outfit: NPCBody.Outfit = NPCBody.Outfit.WORKER

var _body: NPCBody
var _target := Vector3.ZERO
var _pause := 0.0
var _indoors := false
var _yaw := 0.0
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var _think := 0
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pose: NPCBody.Pose = NPCBody.Pose.NORMAL


func _ready() -> void:
	add_to_group("villagers")
	_rng.seed = look_seed if look_seed >= 0 else hash(name)
	collision_layer = LAYER_NPC
	collision_mask = 1 | (1 << 1) | LAYER_NPC
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.72
	cs.shape = cap
	cs.position = Vector3(0, 0.86, 0)
	add_child(cs)
	_body = NPCBody.new()
	_body.name = "Body"
	_body.outfit = outfit
	_body.height = 1.72 if outfit != NPCBody.Outfit.LADY else 1.64
	_body.variation_seed = look_seed
	add_child(_body)
	_think = _rng.randi() % 10
	_pick_target()


func is_indoors() -> bool:
	return _indoors


func _physics_process(delta: float) -> void:
	var player := get_viewport().get_camera_3d()
	var dist := player.global_position.distance_to(global_position) if player else 0.0
	# Far away: think every 10th frame, and hop instead of walking.
	_think += 1
	var far := dist > 160.0
	if far and _think % 10 != 0:
		return
	var step := delta * (10.0 if far else 1.0)
	var h := GameClock.hours()
	var should_be_in := h < 6.5 or h >= 22.0 or (Weather.rain > 0.6 and _rng.randf() < 0.02)
	if _indoors:
		if not should_be_in and _rng.randf() < 0.02 * step * 10.0:
			_indoors = false
			visible = true
			collision_layer = LAYER_NPC
			_pick_target()
		return
	if should_be_in and _pause <= 0.0 and global_position.distance_to(home) < 1.5:
		_indoors = true
		visible = false
		collision_layer = 0
		return
	var to := _target - global_position
	to.y = 0.0
	var moving := false
	if _pause > 0.0:
		_pause -= step
		_pose = NPCBody.Pose.TALK if _rng.randf() < 0.002 else _pose
		if _pause <= 0.0:
			_pose = NPCBody.Pose.NORMAL
			_pick_target()
	elif to.length() < 0.8:
		_pause = _rng.randf_range(6.0, 30.0)
		_pose = NPCBody.Pose.BROWSE if _rng.randf() < 0.3 else NPCBody.Pose.NORMAL
	else:
		moving = true
	var speed := 1.25 if moving else 0.0
	var dir := to.normalized() if moving else Vector3.ZERO
	if moving:
		_yaw = rotate_toward(_yaw, atan2(-dir.x, -dir.z), 4.0 * step)
	if far:
		global_position += dir * speed * step
		if village and village.gen:
			global_position.y = village.gen.height(global_position.x, global_position.z)
	else:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
		move_and_slide()
		# Walked into something (a fence, a neighbour): try somewhere else.
		if moving:
			if global_position.distance_to(_last_pos) < speed * delta * 0.3:
				_stuck += delta
				if _stuck > 2.5:
					_stuck = 0.0
					_pick_target()
			else:
				_stuck = 0.0
		_last_pos = global_position
		_body.rotation.y = _yaw
		if dist < 90.0:
			_body.update_body(Vector2(velocity.x, velocity.z).length(), _pose, delta)


func _pick_target() -> void:
	if village == null or village.spots.is_empty():
		_target = global_position
		return
	var h := GameClock.hours()
	if h >= 21.5 or h < 6.5:
		_target = home
		return
	var want := ""
	if h >= 18.0:
		want = "inn" if _rng.randf() < 0.5 else ""
	elif h >= 9.0 and h < 12.0 and GameClock.date_string().begins_with("Sunday"):
		want = "church"
	for attempt in 8:
		var s: Array = village.spots[_rng.randi() % village.spots.size()]
		if want == "" or s[1] == want:
			_target = s[0]
			return
	_target = village.spots[_rng.randi() % village.spots.size()][0]
