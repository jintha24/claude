class_name CharacterRig
extends RefCounted
## Drives a generated character's skeleton (assets/characters/generated/*.glb) from the
## procedural "mannequin" pose rig that the game has always animated people with. The
## mannequin (hips, spine, head, thighs, knees, shoulders, elbows...) keeps doing the
## walking, running, crouching, climbing, fighting and falling; each frame its joint
## rotations are copied onto the matching bones of the realistic body.
##
## Works for any skeleton: the generated ones (every bone axis-aligned at rest, MakeHuman
## bone names) and the Rocketbox people (3ds Max biped: "Bip01 L Thigh"..., bones at
## arbitrary rest angles, a T-pose, facing +Z). A bone's pose is the mannequin joint's
## rotation, then one fixed correction per limb that swings the model's rest arm or leg to
## the mannequin's straight-down rest, then the bone's own rest orientation.

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
## Each bone's rest orientation in skeleton space (identity for the generated rigs).
var _rest_q: Array[Quaternion] = []
## The skeleton's frame relative to the character (the Rocketbox models face +Z and are
## turned round; the generated ones match).
var _frame_fix := Quaternion.IDENTITY
var _hips_rest_skel := Vector3.INF
## Blend weight per bone this frame, and the named bone groups (set_mask).
var _w := PackedFloat32Array()
var _masks := {}
## The model's bone names for the mannequin's (MakeHuman) names, when they differ.
const BIPED := {
	"pelvis": "Bip01 Pelvis", "spine_01": "Bip01 Spine", "spine_02": "Bip01 Spine1", "spine_03": "Bip01 Spine2",
	"neck_01": "Bip01 Neck", "head": "Bip01 Head",
	"clavicle_l": "Bip01 L Clavicle", "upperarm_l": "Bip01 L UpperArm", "lowerarm_l": "Bip01 L Forearm", "hand_l": "Bip01 L Hand",
	"clavicle_r": "Bip01 R Clavicle", "upperarm_r": "Bip01 R UpperArm", "lowerarm_r": "Bip01 R Forearm", "hand_r": "Bip01 R Hand",
	"thigh_l": "Bip01 L Thigh", "calf_l": "Bip01 L Calf", "foot_l": "Bip01 L Foot", "ball_l": "Bip01 L Toe0",
	"thigh_r": "Bip01 R Thigh", "calf_r": "Bip01 R Calf", "foot_r": "Bip01 R Foot", "ball_r": "Bip01 R Toe0",
}


## The bone called `mh_name` (MakeHuman naming) in this skeleton, or its biped twin.
func find(mh_name: String) -> int:
	var b := skeleton.find_bone(mh_name)
	if b < 0 and BIPED.has(mh_name):
		b = skeleton.find_bone(BIPED[mh_name])
	return b


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
	_rest_q.resize(n)
	for b in n:
		_parent[b] = skel.get_bone_parent(b)
		_rest_q[b] = Quaternion(skel.get_bone_global_rest(b).basis.orthonormalized())
	var body := hips_pivot.get_parent() as Node3D if hips_pivot else null
	if body and body.is_inside_tree() and skel.is_inside_tree():
		_frame_fix = (Quaternion(body.global_basis.orthonormalized()).inverse() * Quaternion(skel.global_basis.orthonormalized())).normalized()
	# Parent-first order.
	var done := {}
	for b in n:
		_visit(b, done)
	for bone_name: String in drivers:
		var b := find(bone_name)
		if b >= 0:
			_driver[b] = drivers[bone_name]
	_pelvis = find("pelvis")
	_root_bone = find("Root")
	if _pelvis >= 0:
		_pelvis_rest = skel.get_bone_rest(_pelvis).origin
		if _root_bone < 0 and hips_pivot and hips_pivot.is_inside_tree() and skel.is_inside_tree():
			# No root bone to carry the body (the Rocketbox skeletons): the pelvis follows
			# the hips pivot in the world, so a knocked-down body lies on the ground.
			_hips_rest_skel = skel.global_transform.affine_inverse() * hips_pivot.global_position
	# Hands follow forearms, feet follow shins, clavicles and the upper spine follow the
	# chest, the neck sits between chest and head.
	for pair: Array in [["hand_l", "lowerarm_l"], ["hand_r", "lowerarm_r"], ["foot_l", "calf_l"], ["foot_r", "calf_r"],
			["ball_l", "calf_l"], ["ball_r", "calf_r"], ["clavicle_l", "spine_03"], ["clavicle_r", "spine_03"]]:
		var b := find(pair[0])
		var f := find(pair[1])
		if b >= 0 and f >= 0 and not _driver.has(b):
			_follow[b] = f
	for spec: Array in [["spine_02", "pelvis", "spine_03", 0.5], ["spine_01", "pelvis", "spine_03", 0.2], ["neck_01", "spine_03", "head", 0.5]]:
		var b := find(spec[0])
		var x := find(spec[1])
		var y := find(spec[2])
		if b >= 0 and x >= 0 and y >= 0 and not _driver.has(b):
			_blend[b] = [x, y, spec[3]]
	# Limb corrections: the model's rest limb direction -> straight down.
	for pair: Array in [["upperarm_l", "lowerarm_l"], ["upperarm_r", "lowerarm_r"], ["lowerarm_l", "hand_l"], ["lowerarm_r", "hand_r"],
			["thigh_l", "calf_l"], ["thigh_r", "calf_r"], ["calf_l", "foot_l"], ["calf_r", "foot_r"]]:
		var b := find(pair[0])
		var c := find(pair[1])
		if b < 0 or c < 0:
			continue
		# (In the skeleton's frame: the mannequin's "down" seen from the model.)
		var d := (_rest_global(c) - _rest_global(b)).normalized()
		_offset[b] = _arc(d, (_frame_fix.inverse() * DOWN).normalized())
	_curl_fingers()


func _visit(b: int, done: Dictionary) -> void:
	if done.has(b):
		return
	if _parent[b] >= 0:
		_visit(_parent[b], done)
	done[b] = true
	_order.append(b)


func _rest_global(b: int) -> Vector3:
	return skeleton.get_bone_global_rest(b).origin


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


## Names a group of bones (mannequin names) that can be blended in on their own: an arm
## holding an umbrella over a recorded walk, say.
func set_mask(mask: String, mh_names: Array) -> void:
	var bones := PackedInt32Array()
	for n: String in mh_names:
		var b := find(n)
		if b >= 0:
			bones.append(b)
	_masks[mask] = bones


## Copies the mannequin's pose onto the skeleton. Call after the mannequin is posed.
## `weight` < 1 blends it over whatever pose the skeleton already has (motion capture);
## `masks` (mask name -> weight) blends named groups in by more.
func update(weight: float = 1.0, masks: Dictionary = {}) -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	if _plan.is_empty():
		_make_plan()
	if _w.size() != _parent.size():
		_w.resize(_parent.size())
	_w.fill(clampf(weight, 0.0, 1.0))
	for m: String in masks:
		var mw := clampf(float(masks[m]), 0.0, 1.0)
		for b in _masks.get(m, PackedInt32Array()):
			_w[b] = maxf(_w[b], mw)
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
				q = inv * Quaternion((_driver[b] as Node3D).global_basis.orthonormalized()) * _frame_fix
				if _offset.has(b):
					q = q * _offset[b]
				q = q * _rest_q[b]
			1: # the root, tilted with the whole body
				q = inv * Quaternion(_root_pivot.global_basis.orthonormalized()) * _frame_fix * _rest_q[b]
			2: # follows another bone (keeping how it sat against it at rest)
				q = _globals[a] * _rest_q[a].inverse() * _rest_q[b]
				_w[b] = maxf(_w[b], _w[a])
			3: # between two bones
				q = (_globals[a] * _rest_q[a].inverse()).slerp(_globals[c] * _rest_q[c].inverse(), _blend_t[b]) * _rest_q[b]
			_: # holds its rest relative to its parent
				var pr := _rest_q[parent] if parent >= 0 else Quaternion.IDENTITY
				_globals[b] = parent_q * pr.inverse() * _rest_q[b]
				continue
		_globals[b] = q
		var wb := _w[b]
		if wb >= 0.999:
			skeleton.set_bone_pose_rotation(b, (parent_q.inverse() * q).normalized())
		elif wb > 0.001:
			skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b).slerp((parent_q.inverse() * q).normalized(), wb))
	var pw := _w[_pelvis] if _pelvis >= 0 else 0.0
	if pw <= 0.001:
		pass
	elif _pelvis >= 0 and _hips_pivot and _hips_rest_skel != Vector3.INF:
		var target := frame.affine_inverse() * _hips_pivot.global_position
		var at := skeleton.get_bone_global_rest(_pelvis).origin + (target - _hips_rest_skel)
		var pp0 := _parent[_pelvis]
		if pp0 >= 0:
			at = skeleton.get_bone_global_rest(pp0).affine_inverse() * at
		skeleton.set_bone_pose_position(_pelvis, skeleton.get_bone_pose_position(_pelvis).lerp(at, pw))
	elif _pelvis >= 0 and _hips_pivot:
		# The hips' move, from the character's frame into the pelvis's parent's.
		var move := _frame_fix.inverse() * ((_hips_pivot.position - _hips_rest) * _unit)
		var pp := _parent[_pelvis]
		if pp >= 0:
			move = _rest_q[pp].inverse() * move
		skeleton.set_bone_pose_position(_pelvis, skeleton.get_bone_pose_position(_pelvis).lerp(_pelvis_rest + move, pw))
	if _root_bone >= 0 and _root_pivot:
		skeleton.set_bone_pose_position(_root_bone, skeleton.get_bone_rest(_root_bone).origin + frame.affine_inverse() * _root_pivot.global_position)


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
