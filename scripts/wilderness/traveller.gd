class_name Traveller
extends CharacterBody3D
## Someone on the road in the hills - a pedlar with his pack, a farm hand, a drover, a
## woman walking to market, a parson - walking a route of points over the terrain, and
## passing the time of day with Harry. Moved by hand over the ground (no navigation
## mesh in the hills); far from the player they only think now and then.

const LAYER_NPC := 1 << 2
const GREETINGS: Array[String] = [
	"Good day to you.", "Fine weather for it.", "Mornin'.", "Long road to London, this.",
	"Mind the ruts by the bridge.", "Evenin'. Getting cold.", "God keep you, sir.",
	"Seen any deer up by the woods? My master's keeper swears there's a poacher about.",
]

var route: Array[Vector3] = []
var gen: TerrainGenerator
var outfit: NPCBody.Outfit = NPCBody.Outfit.WORKER
var look_seed := -1
var walk_speed := 1.3
var job := "traveller"
## Stands and works (a farm hand in a field) instead of walking the route.
var standing := false

var _body: NPCBody
var _i := 0
var _yaw := 0.0
var _pause := 0.0
var _frame := 0
var _greet_cd := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("travellers")
	_rng.seed = look_seed if look_seed >= 0 else hash(name)
	collision_layer = LAYER_NPC
	collision_mask = 0
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
	_body.height = 1.64 if outfit == NPCBody.Outfit.LADY else _rng.randf_range(1.66, 1.8)
	_body.variation_seed = look_seed
	add_child(_body)
	_frame = _rng.randi() % 8
	if standing:
		_yaw = _rng.randf() * TAU


func get_facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _physics_process(delta: float) -> void:
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(global_position) if cam else 0.0
	var far := d > 120.0
	if far and _frame % 8 != 0:
		return
	var step := delta * (8.0 if far else 1.0)
	_greet_cd -= step
	var speed := 0.0
	var pose := NPCBody.Pose.NORMAL
	if standing:
		# Working a field: bent over the crop, now and then straightening up.
		pose = NPCBody.Pose.BROWSE if fmod(float(_frame) / 60.0, 14.0) < 10.0 else NPCBody.Pose.NORMAL
	elif _pause > 0.0:
		_pause -= step
	elif _i < route.size():
		var to := route[_i] - global_position
		to.y = 0.0
		if to.length() < 1.0:
			_i += 1
			if _rng.randf() < 0.08:
				_pause = _rng.randf_range(3.0, 10.0) # a rest by the road
		else:
			speed = walk_speed
			var dir := to.normalized()
			_yaw = rotate_toward(_yaw, atan2(-dir.x, -dir.z), step * 4.0)
			var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
			global_position += fwd * speed * step
	if gen:
		global_position.y = gen.height(global_position.x, global_position.z)
	# A word for Harry as they pass.
	var harry := get_tree().get_first_node_in_group("player") as Node3D
	if harry and _greet_cd <= 0.0 and harry.global_position.distance_to(global_position) < 4.0:
		_greet_cd = 60.0
		Stealth.bark(self, "%s: \"%s\"" % [job.capitalize(), GREETINGS[_rng.randi() % GREETINGS.size()]])
		var to_h := harry.global_position - global_position
		if standing:
			_yaw = atan2(-to_h.x, -to_h.z)
	_body.rotation.y = _yaw
	if d < 80.0:
		_body.update_body(speed, pose, step)


func finished() -> bool:
	return not standing and _i >= route.size()
