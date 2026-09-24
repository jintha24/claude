extends "res://tests/test_base.gd"
## Builds a stand-in humanoid (Godot humanoid bone names) with Mixamo-named clips, then
## checks that HarryAnimator maps the clips, builds the AnimationTree, adds foot/hand IK,
## scales the model to 1.88 m and follows Harry's states.

const FAKE := "user://_test_fake_character.tscn"


func make_scene() -> Node:
	_make_fake_character()
	var scene: Node = load("res://scenes/main/main.tscn").instantiate()
	(scene.get_node("Harry/Visual") as HarryAnimator).model_path = FAKE
	return scene


func _make_fake_character() -> void:
	var root_n := Node3D.new()
	root_n.name = "FakeChar"
	var skel := Skeleton3D.new()
	skel.name = "GeneralSkeleton"
	root_n.add_child(skel)
	skel.owner = root_n
	var bones := [
		["Hips", -1, Vector3(0, 1.0, 0)],
		["LeftUpperLeg", 0, Vector3(0.1, -0.05, 0)], ["LeftLowerLeg", 1, Vector3(0, -0.45, 0)], ["LeftFoot", 2, Vector3(0, -0.43, 0)],
		["RightUpperLeg", 0, Vector3(-0.1, -0.05, 0)], ["RightLowerLeg", 4, Vector3(0, -0.45, 0)], ["RightFoot", 5, Vector3(0, -0.43, 0)],
		["Spine", 0, Vector3(0, 0.2, 0)], ["Chest", 7, Vector3(0, 0.3, 0)],
		["LeftUpperArm", 8, Vector3(0.2, 0.1, 0)], ["LeftLowerArm", 9, Vector3(0.3, 0, 0)], ["LeftHand", 10, Vector3(0.28, 0, 0)],
		["RightUpperArm", 8, Vector3(-0.2, 0.1, 0)], ["RightLowerArm", 12, Vector3(-0.3, 0, 0)], ["RightHand", 13, Vector3(-0.28, 0, 0)],
		["Head", 8, Vector3(0, 0.35, 0)],
	]
	for b in bones:
		var i := skel.add_bone(b[0])
		if b[1] >= 0:
			skel.set_bone_parent(i, b[1])
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, b[2]))
	skel.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 1.7, 0.3)
	mi.mesh = bm
	mi.position.y = 0.85
	skel.add_child(mi)
	mi.owner = root_n
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root_n.add_child(ap)
	ap.owner = root_n
	var lib := AnimationLibrary.new()
	for clip in ["Breathing Idle", "Walking", "Running", "Fast Run", "Crouching Idle", "Crouched Walking",
			"Hanging Idle", "Braced Hang To Crouch", "Braced Hang Hop Up", "Climbing Ladder", "Left Shimmy",
			"Right Shimmy", "Falling To Roll", "Jump Over", "Falling Idle", "Jump", "Falling To Landing", "Dying"]:
		var a := Animation.new()
		a.length = 1.0
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath("GeneralSkeleton:Hips"))
		a.position_track_insert_key(t, 0.0, Vector3(0, 1.0, 0))
		a.position_track_insert_key(t, 1.0, Vector3(0, 1.3, 0.4))
		lib.add_animation(clip, a)
	ap.add_animation_library("", lib)
	var ps := PackedScene.new()
	ps.pack(root_n)
	ResourceSaver.save(ps, FAKE)
	root_n.free()


func run_tests() -> void:
	var v := harry.get_node("Visual") as HarryAnimator
	check("model loaded instead of mannequin", v.has_model and v.get_node_or_null("Mannequin") == null)
	var model_root := v.get_node("ModelRoot") as Node3D
	check("model scaled to 1.88 m", absf(model_root.scale.x * 1.7 - 1.88) < 0.01)
	var expected := {
		"idle": "Breathing Idle", "walk": "Walking", "run": "Running", "sprint": "Fast Run",
		"crouch_idle": "Crouching Idle", "crouch_walk": "Crouched Walking", "hang_idle": "Hanging Idle",
		"climb_up": "Braced Hang To Crouch", "hop_up": "Braced Hang Hop Up", "pipe_climb": "Climbing Ladder",
		"shimmy_left": "Left Shimmy", "shimmy_right": "Right Shimmy", "roll": "Falling To Roll",
		"vault": "Jump Over", "fall": "Falling Idle", "jump": "Jump", "land": "Falling To Landing", "death": "Dying",
	}
	var wrong := []
	for k: String in expected:
		if v._clips.get(k, "") != expected[k]:
			wrong.append("%s=%s" % [k, v._clips.get(k, "")])
	check("every Mixamo clip mapped to the right state", wrong.is_empty(), str(wrong))
	check("foot/hand IK created", v.ik != null)
	var tree := harry.find_children("*", "AnimationTree", true, false)[0] as AnimationTree
	var pb := tree.get("parameters/states/playback") as AnimationNodeStateMachinePlayback
	var legs := v.ik.get_parent().get_node("LegIK") as TwoBoneIK3D
	var arms := v.ik.get_parent().get_node("ArmIK") as TwoBoneIK3D
	await wait(30)
	check("idle: feet IK on, hands off", legs.influence > 0.9 and arms.influence < 0.01)

	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait(90)
	check("sprinting plays locomotion, feet IK off", pb.get_current_node() == "locomotion" and legs.influence < 0.05)
	release_all()
	await wait(60)

	await tp(Vector3(1.0, 0.05, 30.0), -PI * 0.5)
	Input.action_press("move_right")
	await wait_until(func() -> bool:
		if harry.global_position.x > 4.6:
			Input.action_press("jump")
		return harry.state == Harry.State.HANG, 150)
	release_all()
	await wait(40)
	check("hanging: hang state, root motion cancelled", pb.get_current_node() == "hang" and tree.root_motion_track == NodePath("GeneralSkeleton:Hips"))
	check("hanging: hand IK on, feet off", arms.influence > 0.9 and legs.influence < 0.05)
	await press_for("crouch", 3)
	await wait(60)
	check("back on the ground: root motion restored", tree.root_motion_track == NodePath())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FAKE))
