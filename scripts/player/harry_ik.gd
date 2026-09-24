class_name HarryIK
extends SkeletonModifier3D
## Foot and hand inverse kinematics for Harry's real (skinned) model.
##
## Added automatically by HarryAnimator when harry.glb has a humanoid skeleton (Godot's
## retargeted names such as "LeftUpperLeg", or raw Mixamo names such as
## "mixamorig_LeftUpLeg"). It runs as the first skeleton modifier each physics frame:
##   * Feet: raycasts under each animated foot, lowers the pelvis for the lower foot and
##     sets targets for a TwoBoneIK3D so feet sit on stairs, kerbs and slopes.
##   * Hands: while hanging or on a drainpipe, a second TwoBoneIK3D pins the hands to
##     the ledge / pipe grip points supplied by HarryParkour.
## The mannequin stand-in doesn't need this; it poses itself procedurally.

const BONES := {
	"hips": ["Hips", "mixamorig_Hips", "mixamorig:Hips", "hips", "pelvis"],
	"l_thigh": ["LeftUpperLeg", "mixamorig_LeftUpLeg", "mixamorig:LeftUpLeg", "thigh.L"],
	"l_shin": ["LeftLowerLeg", "mixamorig_LeftLeg", "mixamorig:LeftLeg", "shin.L"],
	"l_foot": ["LeftFoot", "mixamorig_LeftFoot", "mixamorig:LeftFoot", "foot.L"],
	"r_thigh": ["RightUpperLeg", "mixamorig_RightUpLeg", "mixamorig:RightUpLeg", "thigh.R"],
	"r_shin": ["RightLowerLeg", "mixamorig_RightLeg", "mixamorig:RightLeg", "shin.R"],
	"r_foot": ["RightFoot", "mixamorig_RightFoot", "mixamorig:RightFoot", "foot.R"],
	"l_upper_arm": ["LeftUpperArm", "mixamorig_LeftArm", "mixamorig:LeftArm", "upper_arm.L"],
	"l_forearm": ["LeftLowerArm", "mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "forearm.L"],
	"l_hand": ["LeftHand", "mixamorig_LeftHand", "mixamorig:LeftHand", "hand.L"],
	"r_upper_arm": ["RightUpperArm", "mixamorig_RightArm", "mixamorig:RightArm", "upper_arm.R"],
	"r_forearm": ["RightLowerArm", "mixamorig_RightForeArm", "mixamorig:RightForeArm", "forearm.R"],
	"r_hand": ["RightHand", "mixamorig_RightHand", "mixamorig:RightHand", "hand.R"],
}

## Largest amount the pelvis may drop to reach a lower foot (m).
@export var max_pelvis_drop: float = 0.4
@export var foot_blend_speed: float = 6.0
@export var hand_blend_speed: float = 8.0

var harry: Harry
var _bone := {}
var _legs: TwoBoneIK3D
var _arms: TwoBoneIK3D
var _targets := {}
var _poles := {}
var _foot_w := 0.0
var _hand_w := 0.0
var _pelvis := 0.0


## Returns the IK node if the skeleton has every bone needed, otherwise null.
static func try_create(skeleton: Skeleton3D, owner_harry: Harry) -> HarryIK:
	var found := {}
	for key: String in BONES:
		var idx := -1
		for candidate: String in BONES[key]:
			idx = skeleton.find_bone(candidate)
			if idx != -1:
				break
		if idx == -1:
			push_warning("HarryIK: bone '%s' not found; foot/hand IK disabled." % key)
			return null
		found[key] = idx
	var ik := HarryIK.new()
	ik.name = "HarryIK"
	ik.harry = owner_harry
	ik._bone = found
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	skeleton.add_child(ik)
	ik._build(skeleton)
	return ik


func _build(skeleton: Skeleton3D) -> void:
	for key in ["l_foot", "r_foot", "l_hand", "r_hand", "l_knee", "r_knee", "l_elbow", "r_elbow"]:
		var marker := Node3D.new()
		marker.name = "Target_" + key
		marker.top_level = true
		add_child(marker)
		if key.ends_with("foot") or key.ends_with("hand"):
			_targets[key] = marker
		else:
			_poles[key] = marker

	_legs = _make_two_bone(skeleton, "LegIK", [
		["l_thigh", "l_shin", "l_foot", "l_foot", "l_knee"],
		["r_thigh", "r_shin", "r_foot", "r_foot", "r_knee"],
	])
	_arms = _make_two_bone(skeleton, "ArmIK", [
		["l_upper_arm", "l_forearm", "l_hand", "l_hand", "l_elbow"],
		["r_upper_arm", "r_forearm", "r_hand", "r_hand", "r_elbow"],
	])


func _make_two_bone(skeleton: Skeleton3D, node_name: String, chains: Array) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = node_name
	ik.influence = 0.0
	skeleton.add_child(ik) # added after HarryIK, so it solves after the targets are set
	ik.set_setting_count(chains.size())
	for i in chains.size():
		var c: Array = chains[i]
		ik.set_root_bone(i, _bone[c[0]])
		ik.set_middle_bone(i, _bone[c[1]])
		ik.set_end_bone(i, _bone[c[2]])
		ik.set_target_node(i, ik.get_path_to(_targets[c[3]]))
		ik.set_pole_node(i, ik.get_path_to(_poles[c[4]]))
	return ik


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or harry == null:
		return
	var xf := skel.global_transform
	var facing := harry.get_facing_dir()
	var right := facing.cross(Vector3.UP)
	var root_y := harry.global_position.y

	# ---------------- Feet ----------------
	var want_feet := 0.0
	match harry.state:
		Harry.State.IDLE, Harry.State.WALK, Harry.State.CROUCH_IDLE, Harry.State.CROUCH_WALK, Harry.State.LAND:
			want_feet = 1.0
		Harry.State.RUN:
			want_feet = 0.4
	_foot_w = move_toward(_foot_w, want_feet, foot_blend_speed * delta)
	var exclude: Array[RID] = [harry.get_rid()]
	var offsets := {"l_foot": 0.0, "r_foot": 0.0}
	var feet_pos := {}
	for key: String in offsets:
		var p: Vector3 = xf * skel.get_bone_global_pose(_bone[key]).origin
		feet_pos[key] = p
		if _foot_w <= 0.001:
			continue
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.6, ParkourSensor.MASK_SOLID, exclude)
		var hit := harry.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.6:
			offsets[key] = clampf((hit["position"] as Vector3).y - root_y, -max_pelvis_drop, 0.35)
	var want_pelvis := minf(minf(offsets["l_foot"], offsets["r_foot"]), 0.0) * _foot_w
	_pelvis = lerpf(_pelvis, want_pelvis, 1.0 - exp(-12.0 * delta))
	if absf(_pelvis) > 0.0005:
		var hips: int = _bone["hips"]
		var local_drop := xf.basis.inverse() * Vector3(0.0, _pelvis, 0.0)
		skel.set_bone_pose_position(hips, skel.get_bone_pose_position(hips) + local_drop)
	for key: String in offsets:
		var p: Vector3 = feet_pos[key]
		var foot_basis := xf.basis * skel.get_bone_global_pose(_bone[key]).basis
		(_targets[key] as Node3D).global_transform = Transform3D(foot_basis.orthonormalized(), p + Vector3.UP * offsets[key])
		var side := -1.0 if key == "l_foot" else 1.0
		(_poles[key.replace("foot", "knee")] as Node3D).global_position = p + facing * 0.8 + right * side * 0.1 + Vector3.UP * 0.5
	_legs.influence = _foot_w

	# ---------------- Hands ----------------
	var hand_targets := harry.parkour.get_hand_targets() if harry.parkour else ([] as Array[Vector3])
	_hand_w = move_toward(_hand_w, 1.0 if hand_targets.size() == 2 else 0.0, hand_blend_speed * delta)
	if hand_targets.size() == 2:
		for i in 2:
			var key := "l_hand" if i == 0 else "r_hand"
			var hand_basis := xf.basis * skel.get_bone_global_pose(_bone[key]).basis
			(_targets[key] as Node3D).global_transform = Transform3D(hand_basis.orthonormalized(), hand_targets[i])
			var side := -1.0 if i == 0 else 1.0
			(_poles[key.replace("hand", "elbow")] as Node3D).global_position = harry.global_position + Vector3.UP * 1.2 - facing * 0.4 + right * side * 0.6
	_arms.influence = _hand_w
