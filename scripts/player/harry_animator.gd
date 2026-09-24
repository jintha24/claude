class_name HarryAnimator
extends Node3D
## Harry's visible body and animation.
##
## If res://assets/characters/harry/harry.glb exists (see docs/PHASE_1_GUIDE.md, part 6),
## it is loaded, scaled to exactly 1.88 m and driven by an AnimationTree that this script
## builds in code: a state machine with blend spaces for locomotion and crouching, plus a
## time-scale node so the feet never slide. Until the model exists, a procedurally
## animated mannequin with the same proportions is shown instead.
##
## Expected animation names in harry.glb (case-insensitive; Mixamo names also work):
##   idle, walk, run, sprint, crouch_idle, crouch_walk, jump, fall, land, death
## Only idle, walk and run are required; missing ones fall back to the nearest clip.

@export_file("*.glb", "*.gltf", "*.tscn") var model_path: String = "res://assets/characters/harry/harry.glb"
## glTF models face +Z; Godot characters face -Z. 180 degrees fixes that.
@export var model_yaw_offset_degrees: float = 180.0
@export var target_height: float = 1.88

@export_group("Animation reference speeds (m/s)")
## The ground speed each in-place clip was authored for. Tune these until the feet stop
## sliding: if feet slide forward, lower the value; if they slide backward, raise it.
@export var walk_clip_speed: float = 1.45
@export var run_clip_speed: float = 3.6
@export var sprint_clip_speed: float = 6.4
@export var crouch_clip_speed: float = 1.1

const CLIP_ALIASES := {
	"idle": ["idle", "breathing idle", "happy idle"],
	"walk": ["walk", "walking"],
	"run": ["run", "running", "jog"],
	"sprint": ["sprint", "fast run", "sprinting"],
	"crouch_idle": ["crouch_idle", "crouching idle", "crouch idle"],
	"crouch_walk": ["crouch_walk", "crouched walking", "sneak", "crouch walk"],
	"jump": ["jump", "jumping"],
	"fall": ["fall", "falling idle", "falling"],
	"land": ["land", "falling to landing", "hard landing", "landing"],
	"death": ["death", "dying"],
}
const FALLBACK := {
	"sprint": "run", "crouch_idle": "idle", "crouch_walk": "walk",
	"jump": "fall", "fall": "idle", "land": "idle", "death": "fall",
}
const LOOPING: Array[String] = ["idle", "walk", "run", "sprint", "crouch_idle", "crouch_walk", "fall"]

var has_model := false
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _mannequin: HarryMannequin
var _model_root: Node3D
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
func update_animation(state: Harry.State, hspeed: float, yaw: float, vertical_speed: float, delta: float) -> void:
	rotation.y = yaw
	_step_offset = move_toward(_step_offset, 0.0, maxf(1.2, _step_offset * 10.0) * delta)
	position.y = -_step_offset
	if has_model:
		_drive_tree(state, hspeed)
	elif _mannequin:
		_mannequin.update_pose(state, hspeed, vertical_speed, delta)


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
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_warning("HarryAnimator: %s has no AnimationPlayer; the model will not animate." % model_path)
		has_model = true
		return
	_build_tree(players[0] as AnimationPlayer)
	has_model = true


func _measure(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := _relative_transform(mi, model)
		var box := xf * mi.get_aabb()
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


func _find_clip(player: AnimationPlayer, key: String) -> String:
	var names := player.get_animation_list()
	var aliases: Array = CLIP_ALIASES[key]
	# Exact names first, then "contains" matches (e.g. "Armature|walk").
	for n in names:
		var simple := n.to_lower().get_slice("|", n.count("|")).strip_edges()
		if simple in aliases:
			return n
	for n in names:
		var lower := n.to_lower()
		for a: String in aliases:
			if lower.contains(a) and not (key == "run" and lower.contains("fast")) and not (key == "walk" and lower.contains("crouch")) and not (key == "idle" and lower.contains("crouch")):
				return n
	return ""


func _build_tree(player: AnimationPlayer) -> void:
	var clips := {}
	for key: String in CLIP_ALIASES:
		clips[key] = _find_clip(player, key)
	for key: String in ["sprint", "crouch_idle", "crouch_walk", "fall", "jump", "land", "death"]:
		if clips[key] == "":
			clips[key] = clips[FALLBACK[key]]
	if clips["idle"] == "" or clips["walk"] == "" or clips["run"] == "":
		push_warning("HarryAnimator: harry.glb needs at least 'idle', 'walk' and 'run' animations. Found: %s" % str(player.get_animation_list()))
	for key in LOOPING:
		var clip: String = clips[key]
		if clip != "" and player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for key: String in ["jump", "land", "death"]:
		var clip: String = clips[key]
		if clip != "" and player.has_animation(clip) and clip != clips["fall"] and clip != clips["idle"]:
			player.get_animation(clip).loop_mode = Animation.LOOP_NONE

	var sm := AnimationNodeStateMachine.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = sprint_clip_speed
	loco.add_blend_point(_anim(clips["idle"]), 0.0, -1, "idle")
	loco.add_blend_point(_anim(clips["walk"]), walk_clip_speed, -1, "walk")
	loco.add_blend_point(_anim(clips["run"]), run_clip_speed, -1, "run")
	loco.add_blend_point(_anim(clips["sprint"]), sprint_clip_speed, -1, "sprint")
	sm.add_node("locomotion", loco, Vector2(0, 0))

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = 0.0
	crouch.max_space = crouch_clip_speed
	crouch.add_blend_point(_anim(clips["crouch_idle"]), 0.0, -1, "crouch_idle")
	crouch.add_blend_point(_anim(clips["crouch_walk"]), crouch_clip_speed, -1, "crouch_walk")
	sm.add_node("crouch", crouch, Vector2(0, 150))

	sm.add_node("jump", _anim(clips["jump"]), Vector2(250, 0))
	sm.add_node("fall", _anim(clips["fall"]), Vector2(250, 150))
	sm.add_node("land", _anim(clips["land"]), Vector2(500, 0))
	sm.add_node("death", _anim(clips["death"]), Vector2(500, 150))
	var states: Array[String] = ["locomotion", "crouch", "jump", "fall", "land", "death"]
	for a in states:
		for b in states:
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = 0.12 if b == "land" or a == "land" else 0.22
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
	_tree.root_node = _tree.get_path_to(player.get_node(player.root_node))
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_tree.active = true
	_playback = _tree.get("parameters/states/playback")
	_playback.start("locomotion")
	_current_anim_state = "locomotion"


func _anim(clip: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node


func _drive_tree(state: Harry.State, hspeed: float) -> void:
	if _tree == null:
		return
	var target := "locomotion"
	var time_scale := 1.0
	match state:
		Harry.State.IDLE, Harry.State.WALK, Harry.State.RUN, Harry.State.SPRINT:
			var pos := minf(hspeed, sprint_clip_speed)
			_tree.set("parameters/states/locomotion/blend_position", pos)
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
	_tree.set("parameters/speed/scale", time_scale)
	if target != _current_anim_state:
		_playback.travel(target)
		_current_anim_state = target
