class_name HarryMannequin
extends Node3D
## Stand-in body for Harry shown until the real character model is imported.
## Built at Harry's real proportions (1.88 m) with a procedural walk/run/sprint/crouch
## cycle whose stride length matches ground speed, so movement can be judged for feel
## and scale right away. Dressed in the silhouette of his Victorian working clothes.

const HIP_HEIGHT := 0.97
const THIGH := 0.46
const SHIN := 0.44
const UPPER_ARM := 0.32
const FOREARM := 0.29

var _hips: Node3D
var _spine: Node3D
var _head: Node3D
var _thigh: Array[Node3D] = []
var _knee: Array[Node3D] = []
var _foot: Array[Node3D] = []
var _shoulder: Array[Node3D] = []
var _elbow: Array[Node3D] = []
var _coat_skirt: Node3D

var _phase := 0.0
var _crouch_blend := 0.0
var _air_blend := 0.0
var _land_blend := 0.0
var _death_blend := 0.0
var _speed_smooth := 0.0
var _breath := 0.0


func _ready() -> void:
	var coat := _mat(Color(0.12, 0.105, 0.09), 0.85)
	var trousers := _mat(Color(0.09, 0.085, 0.08), 0.9)
	var boots := _mat(Color(0.03, 0.025, 0.02), 0.45)
	var skin := _mat(Color(0.72, 0.55, 0.45), 0.6)
	var scarf := _mat(Color(0.32, 0.07, 0.06), 0.95)
	var cap := _mat(Color(0.16, 0.15, 0.13), 0.9)
	var shirt := _mat(Color(0.55, 0.52, 0.46), 0.9)

	_hips = _pivot(self, Vector3(0, HIP_HEIGHT, 0))
	_capsule(_hips, 0.17, 0.26, Vector3(0, 0.02, 0), trousers, Vector3(0, 0, 90))
	_spine = _pivot(_hips, Vector3(0, 0.08, 0))
	_capsule(_spine, 0.2, 0.58, Vector3(0, 0.27, 0), coat) # coat torso
	_box(_spine, Vector3(0.2, 0.3, 0.02), Vector3(0, 0.34, -0.19), shirt) # waistcoat/shirt front
	_coat_skirt = _pivot(_hips, Vector3(0, 0.05, 0))
	_box(_coat_skirt, Vector3(0.44, 0.6, 0.3), Vector3(0, -0.27, 0.02), coat) # long coat tails
	var neck := _pivot(_spine, Vector3(0, 0.56, 0))
	_capsule(neck, 0.11, 0.2, Vector3(0, 0.02, 0), scarf) # scarf wrapped round the neck
	_head = _pivot(neck, Vector3(0, 0.1, 0))
	_capsule(_head, 0.1, 0.25, Vector3(0, 0.05, -0.01), skin)
	_box(_head, Vector3(0.21, 0.11, 0.2), Vector3(0, -0.01, -0.02), scarf) # scarf pulled over the face
	_capsule(_head, 0.115, 0.24, Vector3(0, 0.085, 0.0), cap, Vector3(90, 0, 0)) # flat cap crown
	_box(_head, Vector3(0.2, 0.02, 0.1), Vector3(0, 0.065, -0.15), cap) # cap peak

	for side in [-1.0, 1.0]:
		var thigh := _pivot(_hips, Vector3(side * 0.1, 0.0, 0))
		_capsule(thigh, 0.075, THIGH + 0.06, Vector3(0, -THIGH * 0.5, 0), trousers)
		var knee := _pivot(thigh, Vector3(0, -THIGH, 0))
		_capsule(knee, 0.062, SHIN + 0.04, Vector3(0, -SHIN * 0.5, 0), trousers)
		_capsule(knee, 0.068, 0.24, Vector3(0, -SHIN + 0.1, 0), boots) # boot shaft
		var foot := _pivot(knee, Vector3(0, -SHIN, 0))
		_box(foot, Vector3(0.11, 0.08, 0.27), Vector3(0, -0.02, -0.06), boots)
		_thigh.append(thigh)
		_knee.append(knee)
		_foot.append(foot)

		var shoulder := _pivot(_spine, Vector3(side * 0.23, 0.5, 0))
		_capsule(shoulder, 0.062, UPPER_ARM + 0.06, Vector3(0, -UPPER_ARM * 0.5, 0), coat)
		var elbow := _pivot(shoulder, Vector3(0, -UPPER_ARM, 0))
		_capsule(elbow, 0.052, FOREARM + 0.04, Vector3(0, -FOREARM * 0.5, 0), coat)
		_capsule(elbow, 0.045, 0.14, Vector3(0, -FOREARM - 0.04, 0), skin) # hand
		_shoulder.append(shoulder)
		_elbow.append(elbow)


func update_pose(state: Harry.State, speed: float, vertical_speed: float, delta: float) -> void:
	var crouching := state == Harry.State.CROUCH_IDLE or state == Harry.State.CROUCH_WALK
	var airborne := state == Harry.State.JUMP or state == Harry.State.FALL
	var dead := state == Harry.State.DEAD
	_crouch_blend = move_toward(_crouch_blend, 1.0 if crouching else 0.0, delta * 5.0)
	_air_blend = move_toward(_air_blend, 1.0 if airborne else 0.0, delta * 6.0)
	_land_blend = move_toward(_land_blend, 1.0 if state == Harry.State.LAND else 0.0, delta * 10.0)
	_death_blend = move_toward(_death_blend, 1.0 if dead else 0.0, delta * 1.6)
	_speed_smooth = lerpf(_speed_smooth, speed, 1.0 - exp(-10.0 * delta))
	_breath += delta * 1.6

	# Stride length grows with speed (real gait data: ~0.75 m walking, ~1.9 m sprinting).
	var stride := lerpf(0.75, 1.9, clampf((_speed_smooth - 1.4) / 5.0, 0.0, 1.0))
	if crouching:
		stride = 0.55
	if not airborne:
		_phase = fmod(_phase + delta * _speed_smooth / (2.0 * stride) * TAU, TAU)

	var move := clampf(_speed_smooth / 1.45, 0.0, 1.0)
	var run_t := clampf((_speed_smooth - 1.8) / 2.0, 0.0, 1.0)
	var sprint_t := clampf((_speed_smooth - 4.0) / 2.4, 0.0, 1.0)
	var leg_amp := deg_to_rad(lerpf(24.0, 42.0, run_t) + 12.0 * sprint_t) * move
	var knee_amp := deg_to_rad(lerpf(35.0, 90.0, run_t) + 20.0 * sprint_t) * move
	var arm_amp := deg_to_rad(lerpf(16.0, 45.0, run_t) + 15.0 * sprint_t) * move
	var elbow_base := deg_to_rad(lerpf(12.0, 85.0, run_t))
	var lean := deg_to_rad(lerpf(2.0, 7.0, run_t) + 8.0 * sprint_t)
	var bob := absf(sin(_phase)) * lerpf(0.02, 0.06, run_t) * move

	for i in 2:
		var p := _phase + (PI if i == 1 else 0.0)
		var swing := sin(p) * leg_amp
		var knee := maxf(0.0, -cos(p)) * knee_amp + deg_to_rad(4.0)
		# Crouch-sneak: deep knee bend, thighs forward.
		swing = lerpf(swing, deg_to_rad(55.0) + sin(p) * deg_to_rad(20.0) * move, _crouch_blend)
		knee = lerpf(knee, deg_to_rad(95.0) + maxf(0.0, -cos(p)) * deg_to_rad(20.0) * move, _crouch_blend)
		# In the air: legs tucked, one forward. Landing: absorb with a squat.
		swing = lerpf(swing, deg_to_rad(35.0 if i == 0 else 10.0), _air_blend)
		knee = lerpf(knee, deg_to_rad(60.0 if i == 0 else 40.0), _air_blend)
		swing = lerpf(swing, deg_to_rad(60.0), _land_blend)
		knee = lerpf(knee, deg_to_rad(100.0), _land_blend)
		_thigh[i].rotation.x = swing
		_knee[i].rotation.x = -knee
		_foot[i].rotation.x = knee * 0.35 - swing * 0.3

		var arm := -sin(p) * arm_amp
		arm = lerpf(arm, deg_to_rad(25.0), _crouch_blend)
		arm = lerpf(arm, deg_to_rad(-35.0 if i == 0 else 45.0), _air_blend)
		_shoulder[i].rotation.x = arm
		_shoulder[i].rotation.z = (1.0 if i == 1 else -1.0) * deg_to_rad(6.0 + 20.0 * _air_blend)
		_elbow[i].rotation.x = elbow_base + maxf(0.0, arm) * 0.6 + deg_to_rad(40.0) * _crouch_blend

	var hips_y := HIP_HEIGHT + bob - move * 0.02
	hips_y = lerpf(hips_y, 0.62, _crouch_blend)
	hips_y = lerpf(hips_y, HIP_HEIGHT - 0.03, _air_blend)
	hips_y = lerpf(hips_y, 0.68, _land_blend)
	_hips.position.y = hips_y
	_spine.rotation.x = -(lean + deg_to_rad(28.0) * _crouch_blend + deg_to_rad(20.0) * _land_blend)
	_spine.scale = Vector3.ONE * (1.0 + sin(_breath) * 0.006 * (1.0 - move))
	_head.rotation.x = -_spine.rotation.x * 0.6
	_coat_skirt.rotation.x = -deg_to_rad(12.0) * run_t + deg_to_rad(25.0) * _crouch_blend + clampf(vertical_speed * 0.05, -0.3, 0.3) * _air_blend

	# Death: collapse forward onto the ground.
	rotation.x = -_death_blend * PI * 0.47
	position.y = _death_blend * 0.12
	position.z = -_death_blend * 0.4


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 16
	mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
