class_name HarryAnimator
extends Node3D
## Harry's visible body and animation.
##
## If res://assets/characters/harry/harry.glb exists (see docs/PHASE_1_GUIDE.md part 6 and
## docs/PHASE_2_GUIDE.md part 3), it is loaded, scaled to exactly 1.88 m and driven by an
## AnimationTree that this script builds in code: a state machine with blend spaces for
## locomotion, crouching and ledge shimmying, one-shot states for climbing, vaulting and
## rolling (time-scaled to match the gameplay action), and a time-scale node so the feet
## never slide. Foot and hand IK (HarryIK) are added when the skeleton is humanoid.
## Until the model exists, a procedurally animated mannequin is shown instead.
##
## Animation names looked for in harry.glb (case-insensitive; Mixamo names also work):
##   idle, walk, run, sprint, crouch_idle, crouch_walk, jump, fall, land, death,
##   hang_idle, shimmy_left, shimmy_right, climb_up, hop_up, pipe_climb, vault, roll
## Only idle, walk and run are required; missing ones fall back to the nearest clip.

@export_file("*.glb", "*.gltf", "*.tscn") var model_path: String = "res://assets/characters/harry/harry.glb"
## glTF models face +Z; Godot characters face -Z. 180 degrees fixes that.
@export var model_yaw_offset_degrees: float = 180.0
@export var target_height: float = 1.88
@export var enable_ik: bool = true

@export_group("Animation reference speeds (m/s)")
## The ground speed each in-place clip was authored for. Tune these until the feet stop
## sliding: if feet slide forward, lower the value; if they slide backward, raise it.
@export var walk_clip_speed: float = 1.45
@export var run_clip_speed: float = 3.6
@export var sprint_clip_speed: float = 6.4
@export var crouch_clip_speed: float = 1.1
## Vertical speed the pipe/ladder climbing clip was authored for.
@export var pipe_clip_speed: float = 0.8

## Searched in this order, so specific names are claimed before generic ones.
## The first alias is the exact name to use in Blender; the second is the Mixamo name.
const CLIP_ALIASES := {
	"pipe_climb": ["pipe_climb", "climbing ladder", "climbing up wall", "ladder"],
	"hop_up": ["hop_up", "braced hang hop up", "hop up"],
	"shimmy_left": ["shimmy_left", "left shimmy", "shimmy left"],
	"shimmy_right": ["shimmy_right", "right shimmy", "shimmy right"],
	"hang_idle": ["hang_idle", "hanging idle", "braced hang", "hanging"],
	"climb_up": ["climb_up", "braced hang to crouch", "climbing to top", "freehang climb", "climbing"],
	"vault": ["vault", "jump over", "jumping over"],
	"roll": ["roll", "falling to roll", "forward roll"],
	"crouch_idle": ["crouch_idle", "crouching idle", "crouch idle"],
	"crouch_walk": ["crouch_walk", "crouched walking", "sneak", "crouch walk"],
	"sprint": ["sprint", "fast run", "sprinting"],
	"idle": ["idle", "breathing idle", "happy idle"],
	"walk": ["walk", "walking"],
	"run": ["run", "running", "jog"],
	"land": ["land", "falling to landing", "hard landing", "landing"],
	"fall": ["fall", "falling idle", "falling"],
	"jump": ["jump", "jumping"],
	"death": ["death", "dying"],
	"aim": ["aim", "standing aim idle", "standing draw arrow", "bow aim"],
	"takedown": ["takedown", "chokehold", "choke"],
	"arrested": ["arrested", "kneeling", "surrender"],
	"pickpocket": ["pickpocket", "pick pocket", "picking up"],
}
const FALLBACK := {
	"sprint": "run", "crouch_idle": "idle", "crouch_walk": "walk",
	"jump": "fall", "fall": "idle", "land": "idle", "death": "fall",
	"hang_idle": "fall", "shimmy_left": "hang_idle", "shimmy_right": "hang_idle",
	"climb_up": "jump", "hop_up": "hang_idle", "pipe_climb": "hang_idle", "vault": "jump", "roll": "land",
	"aim": "idle", "takedown": "idle", "arrested": "idle", "pickpocket": "walk",
}
const FALLBACK_ORDER: Array[String] = [
	"sprint", "crouch_idle", "crouch_walk", "fall", "jump", "land", "death",
	"hang_idle", "shimmy_left", "shimmy_right", "climb_up", "hop_up", "pipe_climb", "vault", "roll",
	"aim", "takedown", "arrested", "pickpocket",
]
const LOOPING: Array[String] = [
	"idle", "walk", "run", "sprint", "crouch_idle", "crouch_walk", "fall",
	"hang_idle", "shimmy_left", "shimmy_right", "pipe_climb", "aim", "arrested", "pickpocket",
]
const ONE_SHOT: Array[String] = ["jump", "land", "death", "climb_up", "hop_up", "vault", "roll", "takedown"]
## States in which the clips' own root motion is cancelled (the code moves Harry instead).
const ROOT_MOTION_STATES: Array[String] = ["hang", "climb_up", "grab", "pipe", "vault", "roll"]

var has_model := false
var ik: HarryIK
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _mannequin: HarryMannequin
var _model_root: Node3D
var _model_base_y := 0.0
var _hang_align := 0.0
var _skeleton: Skeleton3D
var _hand_bones: Array[int] = []
var _hips_track := NodePath()
var _clips := {}
var _clip_len := {}
var _step_offset := 0.0
var _current_anim_state := ""


func _ready() -> void:
	if model_path != "" and ResourceLoader.exists(model_path):
		var scene := load(model_path) as PackedScene
		if scene:
			_setup_model(scene.instantiate() as Node3D)
	if not has_model:
		_mannequin = HarryMannequin.new()
		_mannequin.name = "Mannequin"
		add_child(_mannequin)


## Called by Harry every physics frame.
func update_animation(h: Harry, delta: float) -> void:
	rotation.y = h.facing_yaw
	_step_offset = move_toward(_step_offset, 0.0, maxf(1.2, _step_offset * 10.0) * delta)
	position.y = -_step_offset
	if has_model:
		_drive_tree(h)
		_align_hands_to_ledge(h, delta)
	elif _mannequin:
		_mannequin.update_pose(h, delta)


## When Harry pops up a step, lower the body and let it catch up smoothly.
func absorb_step(height: float) -> void:
	_step_offset = minf(_step_offset + height, 0.5)


func set_model_visible(v: bool) -> void:
	visible = v


# ---------------------------------------------------------------------------
# Imported model + AnimationTree
# ---------------------------------------------------------------------------
func _setup_model(model: Node3D) -> void:
	if model == null:
		return
	_model_root = Node3D.new()
	_model_root.name = "ModelRoot"
	add_child(_model_root)
	_model_root.add_child(model)
	model.rotation_degrees.y = model_yaw_offset_degrees

	# Scale to Harry's real height, feet on the ground.
	var aabb := _measure(model)
	if aabb.size.y > 0.01:
		var s := target_height / aabb.size.y
		_model_root.scale = Vector3.ONE * s
		_model_root.position.y = -aabb.position.y * s
	_model_base_y = _model_root.position.y
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		for bone_name in ["LeftHand", "mixamorig_LeftHand", "RightHand", "mixamorig_RightHand"]:
			var idx := _skeleton.find_bone(bone_name)
			if idx != -1:
				_hand_bones.append(idx)

	var players := model.find_children("*", "AnimationPlayer", true, false)
	has_model = true
	if players.is_empty():
		push_warning("HarryAnimator: %s has no AnimationPlayer; the model will not animate." % model_path)
		return
	_build_tree(players[0] as AnimationPlayer)
	if enable_ik and _skeleton:
		var h := get_parent() as Harry
		if h:
			ik = HarryIK.try_create(_skeleton, h)


func _measure(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var box := _relative_transform(mi, model) * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _find_clips(player: AnimationPlayer) -> Dictionary:
	var names := player.get_animation_list()
	var clips := {}
	var used := {}
	# Pass 1: exact names (after stripping any "Armature|" prefix).
	for key: String in CLIP_ALIASES:
		clips[key] = ""
		var aliases: Array = CLIP_ALIASES[key]
		for n in names:
			var simple := n.to_lower().get_slice("|", n.count("|")).strip_edges()
			if simple == aliases[0] or simple == aliases[1]:
				clips[key] = n
				used[n] = true
				break
	# Pass 2: "contains" matches, most specific alias first, never reusing a clip.
	for key: String in CLIP_ALIASES:
		if clips[key] != "":
			continue
		for alias: String in CLIP_ALIASES[key]:
			for n in names:
				if used.has(n):
					continue
				if n.to_lower().contains(alias):
					clips[key] = n
					used[n] = true
					break
			if clips[key] != "":
				break
	for key in FALLBACK_ORDER:
		if clips[key] == "":
			clips[key] = clips[FALLBACK[key]]
	return clips


func _build_tree(player: AnimationPlayer) -> void:
	_clips = _find_clips(player)
	if _clips["idle"] == "" or _clips["walk"] == "" or _clips["run"] == "":
		push_warning("HarryAnimator: harry.glb needs at least 'idle', 'walk' and 'run' animations. Found: %s" % str(player.get_animation_list()))
	for key: String in _clips:
		var clip: String = _clips[key]
		if clip == "" or not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		_clip_len[key] = anim.length
		if key in LOOPING:
			anim.loop_mode = Animation.LOOP_LINEAR
		elif key in ONE_SHOT and not _is_shared_with_loop(key):
			anim.loop_mode = Animation.LOOP_NONE

	var sm := AnimationNodeStateMachine.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = sprint_clip_speed
	loco.add_blend_point(_anim("idle"), 0.0, -1, "idle")
	loco.add_blend_point(_anim("walk"), walk_clip_speed, -1, "walk")
	loco.add_blend_point(_anim("run"), run_clip_speed, -1, "run")
	loco.add_blend_point(_anim("sprint"), sprint_clip_speed, -1, "sprint")
	sm.add_node("locomotion", loco, Vector2(0, 0))

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = 0.0
	crouch.max_space = crouch_clip_speed
	crouch.add_blend_point(_anim("crouch_idle"), 0.0, -1, "crouch_idle")
	crouch.add_blend_point(_anim("crouch_walk"), crouch_clip_speed, -1, "crouch_walk")
	sm.add_node("crouch", crouch, Vector2(0, 150))

	var hang := AnimationNodeBlendSpace1D.new()
	hang.min_space = -1.0
	hang.max_space = 1.0
	hang.add_blend_point(_anim("shimmy_left"), -1.0, -1, "shimmy_left")
	hang.add_blend_point(_anim("hang_idle"), 0.0, -1, "hang_idle")
	hang.add_blend_point(_anim("shimmy_right"), 1.0, -1, "shimmy_right")
	sm.add_node("hang", hang, Vector2(250, 300))

	sm.add_node("jump", _anim("jump"), Vector2(250, 0))
	sm.add_node("fall", _anim("fall"), Vector2(250, 150))
	sm.add_node("land", _anim("land"), Vector2(500, 0))
	sm.add_node("death", _anim("death"), Vector2(500, 150))
	sm.add_node("roll", _anim("roll"), Vector2(500, 300))
	sm.add_node("grab", _anim("hop_up"), Vector2(0, 450))
	sm.add_node("climb_up", _anim("climb_up"), Vector2(250, 450))
	sm.add_node("pipe", _anim("pipe_climb"), Vector2(500, 450))
	sm.add_node("vault", _anim("vault"), Vector2(750, 0))
	sm.add_node("aim", _anim("aim"), Vector2(750, 150))
	sm.add_node("takedown", _anim("takedown"), Vector2(750, 300))
	sm.add_node("arrested", _anim("arrested"), Vector2(750, 450))
	sm.add_node("pickpocket", _anim("pickpocket"), Vector2(1000, 0))
	var states: Array[String] = ["locomotion", "crouch", "jump", "fall", "land", "death", "hang", "roll", "grab", "climb_up", "pipe", "vault", "aim", "takedown", "arrested", "pickpocket"]
	for a in states:
		for b in states:
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = 0.12 if b in ["land", "grab", "vault", "roll"] or a == "land" else 0.22
			sm.add_transition(a, b, t)

	var blend := AnimationNodeBlendTree.new()
	blend.add_node("states", sm, Vector2(0, 0))
	blend.add_node("speed", AnimationNodeTimeScale.new(), Vector2(250, 0))
	blend.connect_node("speed", 0, "states")
	blend.connect_node("output", 0, "speed")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = blend
	player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	# Animation tracks are relative to the AnimationPlayer's root node, so the tree must use the same one.
	var anim_root := player.get_node(player.root_node)
	_tree.root_node = _tree.get_path_to(anim_root)
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_tree.active = true
	_playback = _tree.get("parameters/states/playback")
	_playback.start("locomotion")
	_current_anim_state = "locomotion"

	# Mixamo climb/vault/roll clips move the hips (root motion). In those states the hips
	# track is used as the root-motion track, which cancels that movement visually; the
	# gameplay code moves Harry's capsule along a collision-checked path instead.
	if _skeleton:
		for hips_name in ["Hips", "mixamorig_Hips", "mixamorig:Hips", "hips"]:
			if _skeleton.find_bone(hips_name) != -1:
				_hips_track = NodePath("%s:%s" % [str(anim_root.get_path_to(_skeleton)), hips_name])
				break


func _is_shared_with_loop(key: String) -> bool:
	for other in LOOPING:
		if _clips.get(other, "") == _clips[key]:
			return true
	return false


func _anim(key: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = _clips.get(key, "")
	return node


func _drive_tree(h: Harry) -> void:
	if _tree == null:
		return
	var target := "locomotion"
	var time_scale := 1.0
	var hspeed := h.get_horizontal_speed()
	match h.state:
		Harry.State.IDLE, Harry.State.WALK, Harry.State.RUN, Harry.State.SPRINT:
			_tree.set("parameters/states/locomotion/blend_position", minf(hspeed, sprint_clip_speed))
			# Faster than the sprint clip: speed the clip up so the feet keep contact.
			if hspeed > sprint_clip_speed:
				time_scale = hspeed / sprint_clip_speed
		Harry.State.CROUCH_IDLE, Harry.State.CROUCH_WALK:
			target = "crouch"
			_tree.set("parameters/states/crouch/blend_position", minf(hspeed, crouch_clip_speed))
			if hspeed > crouch_clip_speed:
				time_scale = hspeed / crouch_clip_speed
		Harry.State.JUMP:
			target = "jump"
		Harry.State.FALL:
			target = "fall"
		Harry.State.LAND:
			target = "land"
		Harry.State.DEAD:
			target = "death"
		Harry.State.ROLL:
			target = "roll"
			time_scale = _fit("roll", h.roll_duration)
		Harry.State.HANG:
			target = "hang"
			var p := h.parkour
			_tree.set("parameters/states/hang/blend_position", clampf(p.shimmy_speed / p.shimmy_speed_max, -1.0, 1.0))
		Harry.State.GRAB:
			target = "grab"
			time_scale = _fit("hop_up", h.parkour.get_action_duration())
		Harry.State.CLIMB_UP:
			target = "climb_up"
			time_scale = _fit("climb_up", h.parkour.get_action_duration())
		Harry.State.VAULT:
			target = "vault"
			time_scale = _fit("vault", h.parkour.get_action_duration())
		Harry.State.PIPE:
			target = "pipe"
			# The ladder clip plays backwards when climbing down and freezes when still.
			time_scale = h.parkour.pipe_speed / pipe_clip_speed
		Harry.State.TAKEDOWN:
			target = "takedown"
			time_scale = _fit("takedown", h.combat.takedown_time)
		Harry.State.ARRESTED:
			target = "arrested"
		Harry.State.LOCKPICK:
			target = "crouch" if h.is_crouching else "locomotion"
			time_scale = 0.0
		Harry.State.PICKPOCKET:
			target = "pickpocket"
			time_scale = maxf(hspeed / walk_clip_speed, 0.3)
	if h.is_aiming() and target in ["locomotion", "crouch"]:
		target = "aim"
	_tree.set("parameters/speed/scale", time_scale)
	if target != _current_anim_state:
		_playback.travel(target)
		_current_anim_state = target
		_tree.root_motion_track = _hips_track if target in ROOT_MOTION_STATES else NodePath()


## Time scale that makes a one-shot clip last exactly `duration` seconds.
func _fit(key: String, duration: float) -> float:
	var length: float = _clip_len.get(key, 0.0)
	if length <= 0.0 or duration <= 0.0:
		return 1.0
	return clampf(length / duration, 0.25, 4.0)


## While hanging, nudge the model up/down so the hands really sit on the ledge,
## whatever height the hanging clip was authored at.
func _align_hands_to_ledge(h: Harry, delta: float) -> void:
	if _model_root == null:
		return
	var want := 0.0
	if h.state == Harry.State.HANG and _skeleton and _hand_bones.size() == 2 and not h.parkour.ledge.is_empty():
		var hand_y := 0.0
		for b in _hand_bones:
			hand_y += (_skeleton.global_transform * _skeleton.get_bone_global_pose(b).origin).y
		hand_y *= 0.5
		want = clampf(_hang_align + (float(h.parkour.ledge["top"]) - hand_y), -0.5, 0.5)
	_hang_align = lerpf(_hang_align, want, 1.0 - exp(-6.0 * delta))
	_model_root.position.y = _model_base_y + _hang_align
