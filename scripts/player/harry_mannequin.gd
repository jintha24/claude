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
var _hang_blend := 0.0
var _aim_blend := 0.0
var _bow_hand: Node3D
var _bow_back: Node3D
var _climb_phase := 0.0


func _ready() -> void:
	# A long, weathered leather greatcoat over a dark waistcoat, battered top hat, gloves:
	# a gentleman thief's silhouette from any distance.
	var coat := _mat(Color(0.33, 0.21, 0.13), 0.55)
	var coat_dark := _mat(Color(0.2, 0.13, 0.08), 0.6)
	var trousers := _mat(Color(0.12, 0.12, 0.11), 0.9)
	var boots := _mat(Color(0.05, 0.035, 0.025), 0.4)
	var skin := _mat(Color(0.74, 0.57, 0.47), 0.55)
	var hair := _mat(Color(0.12, 0.08, 0.05), 0.8)
	var scarf := _mat(Color(0.42, 0.08, 0.07), 0.95)
	var hat := _mat(Color(0.08, 0.075, 0.07), 0.6)
	var waistcoat := _mat(Color(0.1, 0.17, 0.18), 0.7)
	var shirt := _mat(Color(0.82, 0.8, 0.74), 0.9)
	var brass := _mat(Color(0.75, 0.58, 0.3), 0.3)
	brass.metallic = 1.0

	_hips = _pivot(self, Vector3(0, HIP_HEIGHT, 0))
	_capsule(_hips, 0.17, 0.26, Vector3(0, 0.02, 0), trousers, Vector3(0, 0, 90))
	# Belt with a brass buckle, and the quiver strap across the chest.
	_cylinder(_hips, 0.19, 0.07, Vector3(0, 0.1, 0), coat_dark)
	_box(_hips, Vector3(0.08, 0.06, 0.02), Vector3(0, 0.1, -0.19), brass)
	_spine = _pivot(_hips, Vector3(0, 0.08, 0))
	_capsule(_spine, 0.2, 0.58, Vector3(0, 0.27, 0), coat) # coat torso
	_box(_spine, Vector3(0.2, 0.34, 0.02), Vector3(0, 0.32, -0.19), waistcoat) # waistcoat, open coat front
	_box(_spine, Vector3(0.1, 0.1, 0.02), Vector3(0, 0.5, -0.195), shirt) # shirt at the throat
	for side in [-1.0, 1.0]:
		_box(_spine, Vector3(0.07, 0.4, 0.03), Vector3(side * 0.12, 0.33, -0.19), coat_dark) # lapels
	_box(_spine, Vector3(0.06, 0.55, 0.02), Vector3(0.02, 0.3, -0.205), coat_dark, Vector3(0, 0, 38)) # quiver strap
	# Turned-up collar and a leather shoulder guard (bow side).
	_box(_spine, Vector3(0.26, 0.11, 0.025), Vector3(0, 0.6, 0.11), coat_dark, Vector3(-20, 0, 0))
	for side in [-1.0, 1.0]:
		_box(_spine, Vector3(0.025, 0.1, 0.12), Vector3(side * 0.125, 0.59, 0.03), coat_dark, Vector3(0, side * 20, side * 10))
	var pad := MeshInstance3D.new()
	var pad_mesh := SphereMesh.new()
	pad_mesh.radius = 0.1
	pad_mesh.height = 0.12
	pad.mesh = pad_mesh
	pad.material_override = coat_dark
	pad.position = Vector3(-0.21, 0.5, 0)
	pad.scale = Vector3(1.1, 0.8, 1.3)
	_spine.add_child(pad)
	# The coat skirts: a back panel that swings with the stride, and front flaps that follow
	# each leg (the coat is split up the front, so it never hides the legs).
	_coat_skirt = _pivot(_hips, Vector3(0, 0.05, 0))
	# Panels hinge at the waist and flare out towards the hem, like heavy leather.
	var back := _pivot(_coat_skirt, Vector3(0, 0, 0.15))
	back.rotation.x = deg_to_rad(9.0)
	_box(back, Vector3(0.42, 0.7, 0.04), Vector3(0, -0.35, 0.0), coat)
	_box(back, Vector3(0.02, 0.4, 0.045), Vector3(0, -0.5, 0.0), coat_dark) # rear vent
	for side in [-1.0, 1.0]:
		var panel := _pivot(_coat_skirt, Vector3(side * 0.2, 0, 0.03))
		panel.rotation.z = deg_to_rad(side * 7.0)
		_box(panel, Vector3(0.04, 0.7, 0.3), Vector3(0, -0.35, 0.0), coat)
	var neck := _pivot(_spine, Vector3(0, 0.56, 0))
	_capsule(neck, 0.11, 0.18, Vector3(0, 0.02, 0), scarf) # scarf knotted at the neck
	_head = _pivot(neck, Vector3(0, 0.1, 0))
	_capsule(_head, 0.1, 0.25, Vector3(0, 0.05, -0.01), skin)
	_box(_head, Vector3(0.035, 0.05, 0.05), Vector3(0, 0.04, -0.115), skin) # nose
	_box(_head, Vector3(0.13, 0.016, 0.02), Vector3(0, 0.085, -0.1), hair) # brows
	_box(_head, Vector3(0.16, 0.06, 0.03), Vector3(0, -0.03, -0.085), _mat(Color(0.45, 0.33, 0.27), 0.9)) # stubble
	_capsule(_head, 0.106, 0.2, Vector3(0, 0.07, 0.02), hair, Vector3(90, 0, 0)) # hair under the hat
	# Battered top hat with a dark red band, tipped a little forward.
	var hat_pivot := _pivot(_head, Vector3(0, 0.15, 0))
	hat_pivot.rotation.x = deg_to_rad(-6.0)
	_cylinder(hat_pivot, 0.19, 0.012, Vector3(0, 0.0, 0), hat) # brim
	_cylinder(hat_pivot, 0.105, 0.17, Vector3(0, 0.09, 0), hat, 0.11) # crown
	_cylinder(hat_pivot, 0.108, 0.035, Vector3(0, 0.03, 0), scarf) # band

	for side in [-1.0, 1.0]:
		var thigh := _pivot(_hips, Vector3(side * 0.1, 0.0, 0))
		_capsule(thigh, 0.075, THIGH + 0.06, Vector3(0, -THIGH * 0.5, 0), trousers)
		var flap := _pivot(thigh, Vector3(side * 0.03, 0.02, -0.11))
		flap.rotation.x = deg_to_rad(-6.0)
		_box(flap, Vector3(0.19, 0.64, 0.035), Vector3(0, -0.3, 0), coat) # front coat flap
		var knee := _pivot(thigh, Vector3(0, -THIGH, 0))
		_capsule(knee, 0.062, SHIN + 0.04, Vector3(0, -SHIN * 0.5, 0), trousers)
		_capsule(knee, 0.07, 0.3, Vector3(0, -SHIN + 0.13, 0), boots) # tall riding boot
		_cylinder(knee, 0.075, 0.03, Vector3(0, -SHIN + 0.29, 0), coat_dark) # boot top
		var foot := _pivot(knee, Vector3(0, -SHIN, 0))
		_box(foot, Vector3(0.11, 0.08, 0.27), Vector3(0, -0.02, -0.06), boots)
		_thigh.append(thigh)
		_knee.append(knee)
		_foot.append(foot)

		var shoulder := _pivot(_spine, Vector3(side * 0.23, 0.5, 0))
		_capsule(shoulder, 0.064, UPPER_ARM + 0.06, Vector3(0, -UPPER_ARM * 0.5, 0), coat)
		var elbow := _pivot(shoulder, Vector3(0, -UPPER_ARM, 0))
		_capsule(elbow, 0.054, FOREARM + 0.04, Vector3(0, -FOREARM * 0.5, 0), coat)
		_cylinder(elbow, 0.06, 0.06, Vector3(0, -FOREARM + 0.02, 0), coat_dark) # turned-back cuff
		_capsule(elbow, 0.045, 0.14, Vector3(0, -FOREARM - 0.04, 0), _mat(Color(0.09, 0.065, 0.05), 0.5)) # leather glove
		_shoulder.append(shoulder)
		_elbow.append(elbow)


func _make_bow() -> Node3D:
	var bow := Node3D.new()
	var wood := _mat(Color(0.35, 0.22, 0.12), 0.55)
	var string_mat := _mat(Color(0.8, 0.78, 0.7), 0.9)
	# A 1.8 m yew longbow: grip plus two gently curved limbs, and the string.
	for side: float in [-1.0, 1.0]:
		for seg in 3:
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.012 - seg * 0.003
			mesh.bottom_radius = 0.014 - seg * 0.003
			mesh.height = 0.31
			mesh.radial_segments = 6
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = wood
			var y := side * (0.16 + seg * 0.29)
			var bend := side * deg_to_rad(4.0 + seg * 7.0)
			mi.position = Vector3(0, y, 0.02 * seg * seg)
			mi.rotation.x = -bend
			bow.add_child(mi)
	var s_mesh := CylinderMesh.new()
	s_mesh.top_radius = 0.002
	s_mesh.bottom_radius = 0.002
	s_mesh.height = 1.72
	var string_mi := MeshInstance3D.new()
	string_mi.mesh = s_mesh
	string_mi.material_override = string_mat
	string_mi.position = Vector3(0, 0, 0.19)
	bow.add_child(string_mi)
	return bow


func _pose_combat(h: Harry, delta: float) -> void:
	if _bow_hand == null:
		_bow_hand = _make_bow()
		_elbow[0].add_child(_bow_hand)
		_bow_hand.position = Vector3(0, -FOREARM - 0.05, 0)
		_bow_hand.rotation = Vector3(deg_to_rad(-90.0), 0, 0)
		_bow_back = _make_bow()
		_spine.add_child(_bow_back)
		_bow_back.position = Vector3(0, 0.3, 0.24)
		_bow_back.rotation = Vector3(0, 0, deg_to_rad(35.0))
	var aiming := h.is_aiming()
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, delta * 8.0)
	_bow_hand.visible = _aim_blend > 0.5
	_bow_back.visible = not _bow_hand.visible
	if _aim_blend > 0.0:
		var draw := h.combat.draw
		# Bow arm straight out towards the target, string hand drawn back to the jaw.
		_shoulder[0].rotation.x = lerpf(_shoulder[0].rotation.x, deg_to_rad(88.0), _aim_blend)
		_shoulder[0].rotation.z = lerpf(_shoulder[0].rotation.z, deg_to_rad(10.0), _aim_blend)
		_elbow[0].rotation.x = lerpf(_elbow[0].rotation.x, deg_to_rad(4.0), _aim_blend)
		_shoulder[1].rotation.x = lerpf(_shoulder[1].rotation.x, deg_to_rad(88.0), _aim_blend)
		_shoulder[1].rotation.z = lerpf(_shoulder[1].rotation.z, deg_to_rad(-25.0 - 10.0 * draw), _aim_blend)
		_elbow[1].rotation.x = lerpf(_elbow[1].rotation.x, deg_to_rad(60.0 + 90.0 * draw), _aim_blend)
		_spine.rotation.y = deg_to_rad(-12.0) * _aim_blend
	else:
		_spine.rotation.y = 0.0
	match h.state:
		Harry.State.TAKEDOWN:
			# Rear chokehold: both arms locked round the neck, weight back.
			for i in 2:
				_shoulder[i].rotation.x = deg_to_rad(75.0)
				_shoulder[i].rotation.z = (1.0 if i == 0 else -1.0) * deg_to_rad(25.0)
				_elbow[i].rotation.x = deg_to_rad(115.0)
			_spine.rotation.x = deg_to_rad(8.0)
			_hips.position.y = HIP_HEIGHT - 0.12
		Harry.State.PICKPOCKET:
			# Close behind the mark, right hand slipping into their coat pocket.
			_shoulder[1].rotation.x = deg_to_rad(35.0)
			_shoulder[1].rotation.z = deg_to_rad(-10.0)
			_elbow[1].rotation.x = deg_to_rad(55.0)
			_spine.rotation.x = -deg_to_rad(12.0)
			_head.rotation.x = deg_to_rad(15.0)
		Harry.State.LOCKPICK:
			# Hands up at the lock or the work in front of him, head bent close to listen.
			for i in 2:
				_shoulder[i].rotation.x = deg_to_rad(62.0)
				_shoulder[i].rotation.z = (1.0 if i == 0 else -1.0) * deg_to_rad(-12.0)
				_elbow[i].rotation.x = deg_to_rad(70.0)
			_head.rotation.x = deg_to_rad(18.0)
		Harry.State.ARRESTED:
			# On his knees, hands behind his back.
			for i in 2:
				_thigh[i].rotation.x = deg_to_rad(10.0)
				_knee[i].rotation.x = -deg_to_rad(95.0)
				_shoulder[i].rotation.x = deg_to_rad(-35.0)
				_elbow[i].rotation.x = deg_to_rad(70.0)
			_hips.position.y = 0.5
			_spine.rotation.x = -deg_to_rad(10.0)


func update_pose(h: Harry, delta: float) -> void:
	var state := h.state
	var speed := h.get_horizontal_speed() if not h.is_climbing() else 0.0
	var vertical_speed := h.velocity.y
	var crouching := state == Harry.State.CROUCH_IDLE or state == Harry.State.CROUCH_WALK or (state == Harry.State.LOCKPICK and h.is_crouching)
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

	_pose_parkour(h, delta)
	_pose_combat(h, delta)

	# Death: collapse forward onto the ground.
	rotation.x = -_death_blend * PI * 0.47
	position.y = _death_blend * 0.12
	position.z = -_death_blend * 0.4
	if state == Harry.State.ROLL:
		# Tuck and roll forward around the body's centre.
		var t := 1.0 - clampf(h.get_roll_time_left() / h.roll_duration, 0.0, 1.0)
		var angle := -smoothstep(0.0, 1.0, t) * TAU
		var c := Vector3(0, 0.55, 0)
		rotation.x = angle
		position = c - Basis(Vector3.RIGHT, angle) * c
		for i in 2:
			_thigh[i].rotation.x = deg_to_rad(110.0)
			_knee[i].rotation.x = -deg_to_rad(130.0)
			_shoulder[i].rotation.x = deg_to_rad(70.0)
			_elbow[i].rotation.x = deg_to_rad(90.0)
		_hips.position.y = 0.55
		_spine.rotation.x = -deg_to_rad(50.0)


## Poses for hanging, shimmying, drainpipes, climbing up and vaulting.
func _pose_parkour(h: Harry, delta: float) -> void:
	var state := h.state
	var p := h.parkour
	var hanging := state == Harry.State.HANG or state == Harry.State.GRAB or state == Harry.State.PIPE
	_hang_blend = move_toward(_hang_blend, 1.0 if hanging else 0.0, delta * 8.0)
	if _hang_blend > 0.0:
		var sway := 0.0
		if state == Harry.State.PIPE:
			_climb_phase += p.pipe_speed * delta * 5.0
		elif state == Harry.State.HANG:
			_climb_phase += absf(p.shimmy_speed) * delta * 7.0
			sway = sin(_climb_phase) * deg_to_rad(10.0) * clampf(absf(p.shimmy_speed) / p.shimmy_speed_max, 0.0, 1.0)
		for i in 2:
			var ph := _climb_phase + (PI if i == 1 else 0.0)
			var reach := deg_to_rad(165.0)
			var thigh := deg_to_rad(12.0)
			var knee := deg_to_rad(25.0)
			if state == Harry.State.PIPE:
				# Alternate hands and knees like climbing a ladder.
				reach = deg_to_rad(150.0) + sin(ph) * deg_to_rad(15.0)
				thigh = deg_to_rad(45.0) + sin(ph + PI) * deg_to_rad(25.0)
				knee = deg_to_rad(70.0) + sin(ph + PI) * deg_to_rad(20.0)
			_shoulder[i].rotation.x = lerpf(_shoulder[i].rotation.x, reach, _hang_blend)
			_shoulder[i].rotation.z = lerpf(_shoulder[i].rotation.z, (1.0 if i == 1 else -1.0) * deg_to_rad(-8.0), _hang_blend)
			_elbow[i].rotation.x = lerpf(_elbow[i].rotation.x, deg_to_rad(12.0), _hang_blend)
			_thigh[i].rotation.x = lerpf(_thigh[i].rotation.x, thigh, _hang_blend)
			_knee[i].rotation.x = lerpf(_knee[i].rotation.x, -knee, _hang_blend)
		_hips.position.y = lerpf(_hips.position.y, HIP_HEIGHT, _hang_blend)
		_hips.rotation.z = sway
		_spine.rotation.x = lerpf(_spine.rotation.x, deg_to_rad(4.0), _hang_blend)
		_head.rotation.x = lerpf(_head.rotation.x, deg_to_rad(18.0), _hang_blend) # look up at the hands
	else:
		_hips.rotation.z = 0.0

	if state == Harry.State.CLIMB_UP:
		# Pull up with the arms, bring a knee over the lip, then stand.
		var t := p.progress
		var pull := smoothstep(0.0, 0.5, t)
		var knee_up := smoothstep(0.3, 0.65, t) * (1.0 - smoothstep(0.8, 1.0, t))
		for i in 2:
			_shoulder[i].rotation.x = lerpf(deg_to_rad(165.0), deg_to_rad(-15.0), pull)
			_elbow[i].rotation.x = deg_to_rad(110.0) * sin(pull * PI)
			var lead := 1.0 if i == 0 else 0.35
			_thigh[i].rotation.x = deg_to_rad(95.0) * knee_up * lead
			_knee[i].rotation.x = -deg_to_rad(120.0) * knee_up * lead
		_spine.rotation.x = -deg_to_rad(35.0) * smoothstep(0.3, 0.6, t) * (1.0 - smoothstep(0.85, 1.0, t))
		_hips.position.y = HIP_HEIGHT - 0.25 * knee_up
	elif state == Harry.State.VAULT:
		# Speed vault: one hand on the obstacle, legs swing through to the side.
		var t := p.progress
		var tuck := sin(t * PI)
		_shoulder[0].rotation.x = deg_to_rad(40.0) * tuck
		_elbow[0].rotation.x = 0.0
		_shoulder[1].rotation.x = deg_to_rad(80.0) * tuck
		_shoulder[1].rotation.z = deg_to_rad(40.0) * tuck
		for i in 2:
			_thigh[i].rotation.x = deg_to_rad(80.0) * tuck
			_knee[i].rotation.x = -deg_to_rad(90.0) * tuck
		_hips.rotation.z = deg_to_rad(25.0) * tuck
		_spine.rotation.x = -deg_to_rad(20.0) * tuck


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


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)


## An upright cylinder (hat crowns, brims, belts, cuffs). `top_radius` < 0 = same as radius.
func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, top_radius: float = -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
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
