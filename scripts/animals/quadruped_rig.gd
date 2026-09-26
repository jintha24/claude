class_name QuadrupedRig
extends RefCounted
## Walks a four-legged animal's skeleton (AnimalLook models: the standard quadruped bones,
## tools/animals/species.py) the way the real animal moves.
##
## Gaits by speed, each with its real footfall pattern: the walk (four beats, a lateral
## sequence), the trot (diagonal pairs), the canter (three beats) and the gallop (four
## beats and a moment in the air); rabbits bound. While a foot bears weight it stays put
## on the ground (it moves back under the body exactly as fast as the body goes forward);
## in the air it is lifted, the knee or hock folding, and put down ahead. The legs reach
## their feet by inverse kinematics, the body rises and falls and pitches with the gait,
## bends into turns, and the neck carries the head: grazing, alert, looking about.
## Poses over the top: lying down, lying dead on its side, jumping, rearing.
##
## The skeleton's rest is axis-aligned (every bone's rest rotation is identity), so a
## bone's pose is just its rotation relative to its parent's.

## Gaits: [name, footfall offsets FL, FR, HL, HR (fraction of the cycle), duty (share
## of the cycle a foot is down), metres travelled per cycle (for a 1.4 m hip; scaled),
## lift (m, scaled), fold (degrees the lower leg folds in the air), bob (m), pitch (deg)].
const GAITS := {
	"walk": [[0.25, 0.75, 0.0, 0.5], 0.64, 1.7, 0.1, 55.0, 0.025, 1.5],
	"trot": [[0.0, 0.5, 0.5, 0.0], 0.44, 2.6, 0.2, 95.0, 0.05, 1.0],
	"canter": [[0.38, 0.58, 0.0, 0.32], 0.4, 3.4, 0.24, 100.0, 0.07, 5.0],
	"gallop": [[0.45, 0.57, 0.0, 0.12], 0.3, 5.4, 0.3, 110.0, 0.08, 6.0],
	"bound": [[0.5, 0.55, 0.0, 0.04], 0.32, 1.6, 0.18, 70.0, 0.07, 12.0],
}
const LEGS := ["L", "R", "L", "R"]

var skeleton: Skeleton3D
## Species tuning: gait speeds (m/s) walk->trot, trot->canter, canter->gallop; the gait
## used for running (canter/gallop or bound); how the neck carries the head.
var trot_at := 2.0
var canter_at := 4.8
var gallop_at := 8.5
var run_gait := "gallop"
var bounding := false
var tail_swish := 0.4
var graze_neck := 1.0

## Inputs, set by the owner every frame.
var speed := 0.0
## Turning rate (rad/s, + to the left).
var turn := 0.0
## 0..1 blends: head down grazing, head up alert, lying down, dead on its side, jumping,
## rearing, sitting (dogs).
var graze := 0.0
var alert := 0.0
var lie := 0.0
var dead := 0.0
var jump := 0.0
var rear := 0.0
var sit := 0.0
## Where the head looks (yaw, radians, + left) and how far down (pitch).
var look_yaw := 0.0
var look_pitch := 0.0

var _b := {}
var _rest_pos := {} # bone -> global rest position (skeleton space)
var _rest_local := {}
var _parent := {}
var _order: Array[int] = []
var _q := {} # bone -> global rotation this frame
var _p := {} # bone -> global position this frame
var _hip_h := 1.4
var _scale := 1.0
var _cycle := 0.0
var _offsets := [0.25, 0.75, 0.0, 0.5]
var _duty := 0.64
var _gait := "walk"
var _stride := 1.7
var _lift := 0.1
var _fold := 55.0
var _bob := 0.025
var _pitch := 1.5
var _t := 0.0
var _smooth_speed := 0.0
var _smooth_turn := 0.0
var _toe := [] # rest toe positions per leg
var _seed := 0.0


func setup(skel: Skeleton3D, seed: int = 0) -> bool:
	skeleton = skel
	for b in skel.get_bone_count():
		_b[skel.get_bone_name(b)] = b
		_rest_pos[b] = skel.get_bone_global_rest(b).origin
		_rest_local[b] = skel.get_bone_rest(b).origin
		_parent[b] = skel.get_bone_parent(b)
	for need in ["pelvis", "chest", "head", "upperarm.L", "thigh.L", "fhoof.L", "hhoof.L"]:
		if not _b.has(need):
			return false
	var done := {}
	for b in skel.get_bone_count():
		_visit(b, done)
	_hip_h = maxf(_rest_pos[_b["thigh.L"]].y, 0.1)
	_scale = _hip_h / 1.3
	_seed = float(absi(seed) % 1000) * 0.37
	for i in 4:
		var hoof: Vector3 = _rest_pos[_b[("fhoof." if i < 2 else "hhoof.") + LEGS[i]]]
		# The toe is under the hoof's front, on the ground.
		_toe.append(Vector3(hoof.x, 0.0, hoof.z - 0.05 * _scale))
	_set_gait("walk", 1.0)
	return true


func _visit(b: int, done: Dictionary) -> void:
	if done.has(b):
		return
	if _parent[b] >= 0:
		_visit(_parent[b], done)
	done[b] = true
	_order.append(b)


func gait_name() -> String:
	return _gait


## Steps the animal on by `delta` and poses the skeleton.
func update(delta: float) -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	_t += delta
	_smooth_speed = move_toward(_smooth_speed, speed, delta * 12.0)
	_smooth_turn = lerpf(_smooth_turn, turn, 1.0 - exp(-6.0 * delta))
	var v := absf(_smooth_speed)
	var want := "walk"
	if bounding and v > trot_at * 0.5:
		want = "bound"
	elif v >= gallop_at:
		want = run_gait
	elif v >= canter_at:
		want = "canter"
	elif v >= trot_at:
		want = "trot"
	_set_gait(want, delta)
	var stride := _stride * _scale
	var freq := maxf(v / maxf(stride, 0.01), 0.0)
	_cycle = fposmod(_cycle + freq * delta * signf(_smooth_speed + 0.0001), 1.0)
	var moving := clampf(v / (0.35 * _scale), 0.0, 1.0)
	var run_len := v / maxf(freq, 0.001) if freq > 0.0 else 0.0
	_pose_body(moving)
	_pose_head(moving, delta)
	_pose_tail(moving)
	for i in 4:
		_pose_leg(i, run_len, moving)
	_apply()


# ---------------------------------------------------------------------------
func _set_gait(g: String, delta: float) -> void:
	var spec: Array = GAITS[g]
	var k := clampf(delta * 3.0, 0.0, 1.0) if g == _gait else clampf(delta * 3.0, 0.0, 1.0)
	_gait = g
	for i in 4:
		# Footfalls ease round to the new pattern (the shortest way round the cycle).
		var target: float = spec[0][i]
		var d: float = fposmod(target - _offsets[i] + 0.5, 1.0) - 0.5
		_offsets[i] = fposmod(_offsets[i] + d * k, 1.0)
	_duty = lerpf(_duty, spec[1], k)
	_stride = lerpf(_stride, spec[2], k)
	_lift = lerpf(_lift, spec[3], k)
	_fold = lerpf(_fold, spec[4], k)
	_bob = lerpf(_bob, spec[5], k)
	_pitch = lerpf(_pitch, spec[6], k)


func _bone(name: String) -> int:
	return _b.get(name, -1)


## Pelvis, spine and chest: rising and falling twice a step, pitching with the canter and
## gallop, bending into turns; lying, dead, rearing.
func _pose_body(moving: float) -> void:
	var pelvis := _bone("pelvis")
	var c := _cycle * TAU
	var bob := -absf(sin(c * (1.0 if _gait in ["canter", "gallop", "bound"] else 2.0))) * _bob * _scale * moving
	var pitch := deg_to_rad(sin(c) * _pitch) * moving
	var bend := clampf(_smooth_turn * 0.25, -0.3, 0.3)
	var roll := clampf(-_smooth_turn * absf(_smooth_speed) * 0.02, -0.25, 0.25)
	# Lying down: the body sinks, legs folded under (see _pose_leg); dead: over on its side.
	var down := maxf(lie, dead)
	var body_h: float = _rest_pos[pelvis].y
	var lie_y := -body_h * 0.62
	var q := Quaternion(Vector3.RIGHT, pitch) * Quaternion(Vector3.BACK, roll)
	var pos: Vector3 = _rest_pos[pelvis] + Vector3(0, bob, 0)
	pos.y += lie_y * lie
	# Rearing: the body pitches up about the hind feet.
	if rear > 0.0:
		var hind_z: float = _toe[2].z
		var ang := deg_to_rad(48.0) * rear
		var rel := pos - Vector3(0, 0, hind_z)
		rel = Basis(Vector3.RIGHT, ang) * rel
		pos = Vector3(0, 0, hind_z) + rel
		q = Quaternion(Vector3.RIGHT, ang) * q
	# Sitting (dogs): the hindquarters down, the front up.
	if sit > 0.0:
		pos.y -= body_h * 0.45 * sit
		pos.z += 0.12 * _scale * sit
		q = Quaternion(Vector3.RIGHT, deg_to_rad(38.0) * sit) * q
	if dead > 0.0:
		# Over on its right side, the belly towards the viewer's left.
		var side := Quaternion(Vector3.BACK, deg_to_rad(88.0) * dead)
		q = side * q
		pos.y = lerpf(pos.y, 0.28 * _hip_h * 0.9, dead)
	# Jumping: the body gathers and stretches.
	if jump > 0.0:
		q = Quaternion(Vector3.RIGHT, deg_to_rad(-8.0) * jump) * q
	_q[pelvis] = q
	_p[pelvis] = pos
	var spine := _bone("spine")
	var chest := _bone("chest")
	var flex := Quaternion(Vector3.UP, bend * 0.5) * Quaternion(Vector3.RIGHT, deg_to_rad(sin(c * 2.0) * 1.5) * moving * float(_gait in ["gallop", "bound"]) * 3.0)
	if spine >= 0:
		_q[spine] = q * flex
		_p[spine] = pos + q * (_rest_pos[spine] - _rest_pos[pelvis])
	if chest >= 0:
		_q[chest] = _q[spine] * flex if spine >= 0 else q
		var sp := spine if spine >= 0 else pelvis
		_p[chest] = _p[sp] + _q[sp] * (_rest_pos[chest] - _rest_pos[sp])


func _pose_head(moving: float, delta: float) -> void:
	var chest := _bone("chest")
	var c := _cycle * TAU
	# Nodding with the walk (a horse's head bobs with each front foot).
	var nod := sin(c * 2.0) * deg_to_rad(4.0) * moving * float(_gait == "walk")
	var gallop_reach := deg_to_rad(6.0) * sin(c) * moving * float(_gait in ["canter", "gallop"])
	# Positive pitch here lowers the head (rotation about -X swings a raised neck forward
	# and down).
	var neck_down := deg_to_rad(100.0) * graze * graze_neck - deg_to_rad(18.0) * alert + nod + gallop_reach
	neck_down += deg_to_rad(15.0) * moving * float(_gait in ["canter", "gallop", "bound"])
	neck_down -= deg_to_rad(35.0) * rear
	neck_down += deg_to_rad(55.0) * lie * 0.3
	var head_down := deg_to_rad(25.0) * graze - deg_to_rad(10.0) * alert + look_pitch
	var yaw := look_yaw + sin(_t * 0.4 + _seed) * deg_to_rad(6.0) * (1.0 - moving) * (1.0 - graze)
	var parent_q: Quaternion = _q[chest]
	var parent := chest
	var shares := {"neck1": 0.45, "neck2": 0.35, "head": 0.2}
	for n: String in ["neck1", "neck2", "head"]:
		var b := _bone(n)
		if b < 0:
			continue
		var down := neck_down * (0.6 if n == "neck1" else (0.4 if n == "neck2" else 0.0))
		if n == "head":
			down = head_down
		var q := parent_q * Quaternion(Vector3.UP, yaw * shares[n]) * Quaternion(Vector3.LEFT, down)
		if dead > 0.0 and n == "neck1":
			q = q * Quaternion(Vector3.LEFT, deg_to_rad(-25.0) * dead)
		_q[b] = q
		_p[b] = _p[parent] + parent_q * (_rest_pos[b] - _rest_pos[parent])
		parent_q = q
		parent = b
	# Ears: flicking, and pricked forward when alert.
	for s: String in ["L", "R"]:
		var e := _bone("ear." + s)
		if e < 0:
			continue
		var flick := sin(_t * (1.3 if s == "L" else 1.1) + _seed * (1.0 if s == "L" else 2.0))
		var ang := deg_to_rad(20.0) * smoothstep(0.85, 1.0, flick) - deg_to_rad(15.0) * alert
		_q[e] = parent_q * Quaternion(Vector3.RIGHT, ang) * Quaternion(Vector3.UP, (1.0 if s == "L" else -1.0) * deg_to_rad(10.0) * (1.0 - alert))
		_p[e] = _p[parent] + parent_q * (_rest_pos[e] - _rest_pos[parent])


func _pose_tail(moving: float) -> void:
	var parent := _bone("pelvis")
	var parent_q: Quaternion = _q[parent]
	for i in range(1, 6):
		var b := _bone("tail%d" % i)
		if b < 0:
			break
		var swish := sin(_t * 1.7 + _seed + i * 0.6) * tail_swish * (0.3 + 0.7 * (1.0 - moving))
		# Lifted and streaming at speed.
		var lift := -deg_to_rad(12.0) * moving * float(_gait in ["canter", "gallop"]) * float(i)
		var q := parent_q * Quaternion(Vector3.UP, swish * 0.35) * Quaternion(Vector3.RIGHT, lift + deg_to_rad(10.0) * alert)
		_q[b] = q
		_p[b] = _p[parent] + parent_q * (_rest_pos[b] - _rest_pos[parent])
		parent_q = q
		parent = b


## One leg: where its foot should be this moment of the gait, and the joints that reach it.
func _pose_leg(i: int, run_len: float, moving: float) -> void:
	var front := i < 2
	var s: String = LEGS[i]
	var names := ["shoulder", "upperarm", "forearm", "fcannon", "fpastern", "fhoof"] if front else ["thigh", "shin", "hcannon", "hpastern", "hhoof"]
	var bones: Array[int] = []
	for n: String in names:
		bones.append(_bone(n + "." + s))
	var anchor_parent := _bone("chest") if front else _bone("pelvis")
	var pq: Quaternion = _q[anchor_parent]
	# The shoulder blade rides on the chest.
	var top := 0
	if front:
		_q[bones[0]] = pq
		_p[bones[0]] = _p[anchor_parent] + pq * (_rest_pos[bones[0]] - _rest_pos[anchor_parent])
		anchor_parent = bones[0]
		top = 1
	var a := bones[top] # upper arm / thigh
	var mid := bones[top + 1] # forearm / shin
	var low := bones[top + 2] # cannon
	var pas := bones[top + 3] # pastern
	var hoof := bones[top + 4]
	var pa: Vector3 = _p[anchor_parent] + _q[anchor_parent] * (_rest_pos[a] - _rest_pos[anchor_parent])
	# Where the foot goes.
	var phase := fposmod(_cycle - _offsets[i], 1.0)
	var toe: Vector3 = _toe[i]
	var fold := 0.0
	var target := toe
	# While down, the foot goes back as far as the body goes forward in that time (the
	# cycle's travel times the share of it spent on the ground); in the air it comes
	# back the same way.
	var reach := run_len * _duty
	if phase < _duty:
		var u := phase / _duty
		target.z = toe.z + reach * (u - 0.5) * signf(_smooth_speed + 0.0001)
	else:
		var u := (phase - _duty) / (1.0 - _duty)
		var e := u * u * (3.0 - 2.0 * u)
		target.z = toe.z + reach * (0.5 - e) * signf(_smooth_speed + 0.0001)
		target.y = sin(u * PI) * _lift * _scale * moving
		fold = sin(u * PI) * moving
	# (Forward is -Z: a foot on the ground moves to +Z, back under the body.)
	# Posed on top: folded under lying down, stretched out dead, tucked jumping, folded
	# rearing (the front legs), sitting.
	var fold_deg := _fold * fold
	var tuck := 0.0
	if jump > 0.0:
		tuck = jump
		fold_deg = lerpf(fold_deg, 120.0 if front else 60.0, jump)
		target = target.lerp(toe + Vector3(0, _hip_h * (0.45 if front else 0.25), (-0.15 if front else 0.35) * _scale), jump)
	if rear > 0.0 and front:
		fold_deg = lerpf(fold_deg, 110.0, rear)
		target = target.lerp(pa + Vector3(0, -_hip_h * 0.45, -0.25 * _scale), rear)
	if lie > 0.0:
		fold_deg = lerpf(fold_deg, 150.0, lie)
		target = target.lerp(Vector3(toe.x * 0.8, 0.05 * _scale, toe.z + (0.25 if front else -0.35) * _scale), lie)
	if sit > 0.0 and not front:
		fold_deg = lerpf(fold_deg, 20.0, sit)
		target = target.lerp(Vector3(toe.x, 0.0, toe.z - 0.2 * _scale), sit)
	if dead > 0.0:
		# Stiff and out from the body (in the body's frame: the body's rolled over).
		var out: Vector3 = _q[_bone("pelvis")] * (_rest_pos[hoof] - _rest_pos[a]) * Vector3(1, 0.92, 1)
		target = target.lerp(pa + out + Vector3(0, -0.05, (-0.1 if front else 0.12) * _scale), dead)
		fold_deg = lerpf(fold_deg, 15.0, dead)
	# The lower leg as one piece: cannon, then pastern and hoof folding further.
	var rest_a: Vector3 = _rest_pos[a]
	var rest_m: Vector3 = _rest_pos[mid]
	var rest_k: Vector3 = _rest_pos[low]
	var rest_f: Vector3 = _rest_pos[pas]
	var rest_h: Vector3 = _rest_pos[hoof]
	var rest_t := Vector3(rest_h.x, 0.0, _toe[i].z)
	# Front knees fold back (the cannon swings up behind); hocks fold less, the fetlock more.
	var body_q: Quaternion = _q[_bone("pelvis")]
	# (A turn about +X swings a hanging bone's tip forward, to -Z.)
	var cannon_ang := deg_to_rad(fold_deg) * (-1.0 if front else 0.3)
	var pastern_ang := deg_to_rad(fold_deg) * (-1.25 if front else -0.6)
	var qc := body_q * Quaternion(Vector3.RIGHT, cannon_ang) if dead > 0.0 or lie > 0.0 else Quaternion(Vector3.RIGHT, cannon_ang)
	var qp := body_q * Quaternion(Vector3.RIGHT, pastern_ang) if dead > 0.0 or lie > 0.0 else Quaternion(Vector3.RIGHT, pastern_ang)
	var k_to_f := qc * (rest_f - rest_k)
	var f_to_t := qp * (rest_t - rest_f)
	var knee := target - k_to_f - f_to_t
	# Two bones reach the knee (or hock): elbows bend back, stifles forward.
	var l1 := rest_a.distance_to(rest_m)
	var l2 := rest_m.distance_to(rest_k)
	var mid_pos := _two_bone(pa, knee, l1, l2, 1.0 if front else -1.0, body_q)
	var knee_pos := mid_pos + (knee - mid_pos).normalized() * l2
	_aim(a, pa, mid_pos, rest_a, rest_m)
	_aim(mid, mid_pos, knee_pos, rest_m, rest_k)
	_q[low] = qc
	_p[low] = knee_pos
	_q[pas] = qp
	_p[pas] = knee_pos + qc * (rest_f - rest_k)
	_q[hoof] = qp
	_p[hoof] = _p[pas] + qp * (rest_h - rest_f)


## The middle joint of a two-bone limb from `a` towards `c`: bending the way `bend` says
## (+1: behind, towards +Z in the body's frame).
func _two_bone(a: Vector3, c: Vector3, l1: float, l2: float, bend: float, body_q: Quaternion) -> Vector3:
	var d := a.distance_to(c)
	d = clampf(d, absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := (c - a).normalized()
	if dir.length() < 0.5:
		dir = Vector3.DOWN
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var ang := acos(cos_a)
	# Bend within the body's side plane.
	var side := body_q * Vector3.RIGHT
	var perp := side.cross(dir).normalized() * -bend
	return a + (dir * cos(ang) + perp * sin(ang)) * l1


## Turns bone `b` (at `from`) to point at `to`, as it pointed from its rest head to its
## child's rest head.
func _aim(b: int, from: Vector3, to: Vector3, rest_from: Vector3, rest_to: Vector3) -> void:
	var r := (rest_to - rest_from).normalized()
	var n := (to - from).normalized()
	_q[b] = _arc(r, n)
	_p[b] = from


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var axis := from.cross(to)
	var d := clampf(from.dot(to), -1.0, 1.0)
	if axis.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(Vector3.RIGHT, PI)
	return Quaternion(axis.normalized(), acos(d))


## Writes the frame's global rotations and positions to the skeleton as local poses.
func _apply() -> void:
	for b in _order:
		if not _q.has(b):
			# Unposed bones (odd extras) follow their parent.
			var p: int = _parent[b]
			_q[b] = _q[p] if p >= 0 and _q.has(p) else Quaternion.IDENTITY
			_p[b] = (_p[p] + _q[p] * _rest_local[b]) if p >= 0 and _p.has(p) else _rest_pos[b]
		var p: int = _parent[b]
		if p < 0:
			skeleton.set_bone_pose_rotation(b, _q[b])
			skeleton.set_bone_pose_position(b, _p[b])
			continue
		var pq: Quaternion = _q[p]
		skeleton.set_bone_pose_rotation(b, (pq.inverse() * _q[b]).normalized())
		# Keep the rest offset (bones don't stretch), except where IK has moved a limb's
		# joint: that is the same offset rotated, so only rotations are written.
	_q.clear()
	_p.clear()
