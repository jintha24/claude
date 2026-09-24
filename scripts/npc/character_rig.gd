class_name CharacterRig
extends RefCounted
## Drives a generated character's skeleton (assets/characters/generated/*.glb) from the
## procedural "mannequin" pose rig that the game has always animated people with. The
## mannequin (hips, spine, head, thighs, knees, shoulders, elbows...) keeps doing the
## walking, running, crouching, climbing, fighting and falling; each frame its joint
## rotations are copied onto the matching bones of the realistic body.
##
## The generated skeletons have every bone axis-aligned at rest, so a pivot's rotation
## (relative to the character) is the bone's rotation, after one fixed correction per limb
## that swings the model's relaxed A-pose arms and legs to the mannequin's straight-down
## rest pose.

const DOWN := Vector3(0, -1, 0)

var skeleton: Skeleton3D
## Bone index -> pivot Node3D (the mannequin joint that drives it).
var _driver := {}
## Bone index -> index of another bone whose global rotation it copies (hands follow
## forearms, feet follow shins...), or -1.
var _follow := {}
## Bone index -> [bone a, bone b, t]: rotation half-way between two bones (the lower spine).
var _blend := {}
var _offset := {}
var _order: Array[int] = []
var _parent: Array[int] = []
var _globals: Array[Quaternion] = []
var _pelvis := -1
var _pelvis_rest := Vector3.ZERO
var _hips_pivot: Node3D
var _hips_rest := Vector3.ZERO
var _root_bone := -1
var _root_pivot: Node3D
var _unit := 1.0
var _plan := PackedInt32Array()
var _blend_t := {}


## skeleton: the model's (facing -Z like the mannequin, and scaled like the mannequin
## root); drivers: bone name -> pivot; hips_pivot and its rest local position move the
## pelvis; root_pivot (optional) moves and tilts the whole body (NPCs collapsing when
## knocked out); unit: skeleton units per mannequin unit (when the model is scaled and
## the mannequin isn't). Rotations are measured relative to the skeleton's own transform.
func setup(skel: Skeleton3D, drivers: Dictionary, hips_pivot: Node3D, hips_rest: Vector3, root_pivot: Node3D = null, unit: float = 1.0) -> void:
	skeleton = skel
	_unit = unit
	_hips_pivot = hips_pivot
	_hips_rest = hips_rest
	_root_pivot = root_pivot
	var n := skel.get_bone_count()
	_parent.resize(n)
	_globals.resize(n)
	for b in n:
		_parent[b] = skel.get_bone_parent(b)
	# Parent-first order.
	var done := {}
	for b in n:
		_visit(b, done)
	for bone_name: String in drivers:
		var b := skel.find_bone(bone_name)
		if b >= 0:
			_driver[b] = drivers[bone_name]
	_pelvis = skel.find_bone("pelvis")
	_root_bone = skel.find_bone("Root")
	if _pelvis >= 0:
		_pelvis_rest = skel.get_bone_rest(_pelvis).origin
	# Hands follow forearms, feet follow shins, clavicles and the upper spine follow the
	# chest, the neck sits between chest and head.
	for pair: Array in [["hand_l", "lowerarm_l"], ["hand_r", "lowerarm_r"], ["foot_l", "calf_l"], ["foot_r", "calf_r"],
			["ball_l", "calf_l"], ["ball_r", "calf_r"], ["clavicle_l", "spine_03"], ["clavicle_r", "spine_03"]]:
		var b := skel.find_bone(pair[0])
		var f := skel.find_bone(pair[1])
		if b >= 0 and f >= 0 and not _driver.has(b):
			_follow[b] = f
	for spec: Array in [["spine_02", "pelvis", "spine_03", 0.5], ["spine_01", "pelvis", "spine_03", 0.2], ["neck_01", "spine_03", "head", 0.5]]:
		var b := skel.find_bone(spec[0])
		var x := skel.find_bone(spec[1])
		var y := skel.find_bone(spec[2])
		if b >= 0 and x >= 0 and y >= 0 and not _driver.has(b):
			_blend[b] = [x, y, spec[3]]
	# Limb corrections: the model's rest limb direction -> straight down.
	for pair: Array in [["upperarm_l", "lowerarm_l"], ["upperarm_r", "lowerarm_r"], ["lowerarm_l", "hand_l"], ["lowerarm_r", "hand_r"],
			["thigh_l", "calf_l"], ["thigh_r", "calf_r"], ["calf_l", "foot_l"], ["calf_r", "foot_r"]]:
		var b := skel.find_bone(pair[0])
		var c := skel.find_bone(pair[1])
		if b < 0 or c < 0:
			continue
		var d := (_rest_global(c) - _rest_global(b)).normalized()
		_offset[b] = _arc(d, DOWN)
	_curl_fingers()


func _visit(b: int, done: Dictionary) -> void:
	if done.has(b):
		return
	if _parent[b] >= 0:
		_visit(_parent[b], done)
	done[b] = true
	_order.append(b)


func _rest_global(b: int) -> Vector3:
	var p := Vector3.ZERO
	var i := b
	while i >= 0:
		p += skeleton.get_bone_rest(i).origin
		i = _parent[i]
	return p


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var axis := from.cross(to)
	var d := clampf(from.dot(to), -1.0, 1.0)
	if axis.length() < 1e-5:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(Vector3.FORWARD, PI)
	return Quaternion(axis.normalized(), acos(d))


## A relaxed hand: fingers gently curled towards the palm, the thumb a little.
func _curl_fingers() -> void:
	for side: String in ["l", "r"]:
		var hand := skeleton.find_bone("hand_" + side)
		if hand < 0:
			continue
		var hp := _rest_global(hand)
		var inward := Vector3(-signf(hp.x), 0.0, 0.0)
		for finger: String in ["index", "middle", "ring", "pinky", "thumb"]:
			for k in [1, 2, 3]:
				var b := skeleton.find_bone("%s_0%d_%s" % [finger, k, side])
				if b < 0:
					continue
				var child := skeleton.find_bone("%s_0%d_%s" % [finger, k + 1, side]) if k < 3 else -1
				var d := (_rest_global(child) - _rest_global(b)).normalized() if child >= 0 else (_rest_global(b) - _rest_global(_parent[b])).normalized()
				var axis := d.cross(inward).normalized()
				if axis.length() < 0.5:
					continue
				var amount := deg_to_rad(8.0 if finger == "thumb" else 8.0 + 6.0 * k)
				skeleton.set_bone_pose_rotation(b, Quaternion(axis, amount))


## Copies the mannequin's pose onto the skeleton. Call after the mannequin is posed.
func update() -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	if _plan.is_empty():
		_make_plan()
	var frame := skeleton.global_transform
	var inv := Quaternion(frame.basis.orthonormalized()).inverse()
	var i := 0
	var count := _plan.size()
	while i < count:
		var b: int = _plan[i]
		var kind: int = _plan[i + 1]
		var a: int = _plan[i + 2]
		var c: int = _plan[i + 3]
		i += 4
		var parent := _parent[b]
		var parent_q := _globals[parent] if parent >= 0 else Quaternion.IDENTITY
		var q: Quaternion
		match kind:
			0: # driven by a pivot
				q = inv * Quaternion((_driver[b] as Node3D).global_basis.orthonormalized())
				if _offset.has(b):
					q = q * _offset[b]
			1: # the root, tilted with the whole body
				q = inv * Quaternion(_root_pivot.global_basis.orthonormalized())
			2: # follows another bone
				q = _globals[a]
			3: # between two bones
				q = _globals[a].slerp(_globals[c], _blend_t[b])
			_: # holds its rest relative to its parent
				_globals[b] = parent_q
				continue
		_globals[b] = q
		skeleton.set_bone_pose_rotation(b, (parent_q.inverse() * q).normalized())
	if _pelvis >= 0 and _hips_pivot:
		skeleton.set_bone_pose_position(_pelvis, _pelvis_rest + (_hips_pivot.position - _hips_rest) * _unit)
	if _root_bone >= 0 and _root_pivot:
		skeleton.set_bone_pose_position(_root_bone, frame.affine_inverse() * _root_pivot.global_position)


## The bones worth touching each frame, flattened as [bone, kind, a, b] in parent-first
## order. Fingers keep the curl set once in setup (their pose is relative to the hand), so
## they are left out: that is more than half the skeleton.
func _make_plan() -> void:
	var needed := {}
	for b in _order:
		if _driver.has(b) or _follow.has(b) or _blend.has(b) or b == _root_bone or b == _pelvis:
			var j := b
			while j >= 0 and not needed.has(j):
				needed[j] = true
				j = _parent[j]
	for b in _order:
		if not needed.has(b):
			continue
		if _driver.has(b):
			_plan.append_array([b, 0, -1, -1])
		elif b == _root_bone and _root_pivot:
			_plan.append_array([b, 1, -1, -1])
		elif _follow.has(b):
			_plan.append_array([b, 2, _follow[b], -1])
		elif _blend.has(b):
			var spec: Array = _blend[b]
			_blend_t[b] = spec[2]
			_plan.append_array([b, 3, spec[0], spec[1]])
		else:
			_plan.append_array([b, 4, -1, -1])
