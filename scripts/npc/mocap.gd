class_name Mocap
extends RefCounted
## Motion capture for the real people (RealPeople): the Rocketbox clips
## (assets/characters/rocketbox/anims/, made by tools/import_rocketbox_anims.gd) played on
## an avatar's skeleton by an AnimationTree the owner steps by hand.
##
## Standing about, walking, running, sprinting, talking, listening, sitting, waving,
## holding up an umbrella, drunk (standing and staggering along), crouching: recorded from
## real actors. Walking, running and sprinting are one blend kept in step, played just
## fast enough that the feet don't slide at the speed the body moves. Anything the actors
## never recorded - fighting, climbing, falling, being knocked out - is still posed by the
## procedural rig (CharacterRig), blended over this.

const DIR := "res://assets/characters/rocketbox/anims/"
## The acts (other than moving about) a person can be doing.
const ACTS: Array[String] = ["loco", "look_around", "talk", "listen", "sit", "wave", "umbrella", "drunk", "drunk_walk", "crouch"]
const IDLES := 4

static var _libraries := {}

var tree: AnimationTree
var player: AnimationPlayer
var skeleton: Skeleton3D
var _library: AnimationLibrary
var _act := "loco"
var _walk_len := 1.2
var _run_len := 0.77
var _walk_travel := 1.2
var _run_travel := 2.36
var _sprint_len := 0.6
var _sprint_travel := 3.5
var _sprint := 0.0
var _drunk_rate := 1.0
var _move := 0.0
var _run := 0.0
## Skeleton units per actor unit, times the model's scale: how much shorter a child's
## stride is than the actor's.
var _stride_scale := 1.0


static func available(female: bool) -> bool:
	return _load(female) != null


static func _load(female: bool) -> AnimationLibrary:
	var path := DIR + ("female" if female else "male") + ".res"
	if not _libraries.has(path):
		_libraries[path] = load(path) if ResourceLoader.exists(path) else null
	return _libraries[path]


## Puts the player and tree on `skel` (an avatar's). `idle` picks which way of standing
## about this person has. Returns false if the clips are missing.
func setup(skel: Skeleton3D, female: bool, idle: int, pelvis_height: float, body_scale: float = 1.0) -> bool:
	_library = _load(female)
	if _library == null or skel == null:
		return false
	skeleton = skel
	var holder := skel.get_parent()
	player = AnimationPlayer.new()
	player.name = "Mocap"
	player.add_animation_library("rb", _library)
	holder.add_child(player)
	player.root_node = player.get_path_to(holder)
	var walk := _library.get_animation("walk")
	var run := _library.get_animation("run")
	_walk_len = walk.length
	_run_len = run.length
	_walk_travel = float(walk.get_meta("travel", 1.2))
	_run_travel = float(run.get_meta("travel", 2.36))
	var sprint := _library.get_animation("sprint")
	_sprint_len = sprint.length
	_sprint_travel = float(sprint.get_meta("travel", 3.5))
	var dw := _library.get_animation("drunk_walk")
	_drunk_rate = dw.length / maxf(float(dw.get_meta("travel", 1.5)), 0.1)
	# The actors' hips rise and fall (and drop on to a chair) by their own measure; a
	# smaller person's by less.
	skel.motion_scale = pelvis_height / maxf(float(_library.get_meta("standing", 0.9)), 0.1)
	_stride_scale = maxf(skel.motion_scale * body_scale, 0.2)
	tree = AnimationTree.new()
	tree.name = "MocapTree"
	tree.tree_root = _tree_for(female, idle)
	holder.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.root_node = tree.get_path_to(holder)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	return true


## The blend tree for one gender and one way of standing about. (Each person needs their
## own: two AnimationTrees on one tree_root leave the second one frozen.)
static func _tree_for(female: bool, idle: int) -> AnimationNodeBlendTree:
	var lib := _load(female)
	var bt := AnimationNodeBlendTree.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = "rb/idle_%d" % (1 + posmod(idle, IDLES))
	bt.add_node("idle", idle_node, Vector2(0, 0))
	for clip: String in ["walk", "run", "sprint"]:
		var n := AnimationNodeAnimation.new()
		n.animation = "rb/" + clip
		# Start on the same foot, so the two stay in step when blended.
		n.use_custom_timeline = true
		n.timeline_length = lib.get_animation(clip).length
		n.start_offset = float(lib.get_animation(clip).get_meta("phase0", 0.0))
		n.loop_mode = Animation.LOOP_LINEAR
		var y := {"walk": 200, "run": 400, "sprint": 600}[clip] as int
		bt.add_node(clip, n, Vector2(0, y))
		bt.add_node(clip + "_speed", AnimationNodeTimeScale.new(), Vector2(200, y))
		bt.connect_node(clip + "_speed", 0, clip)
	var stride := AnimationNodeBlend2.new()
	stride.sync = true
	bt.add_node("stride", stride, Vector2(400, 300))
	bt.connect_node("stride", 0, "walk_speed")
	bt.connect_node("stride", 1, "run_speed")
	var fast := AnimationNodeBlend2.new()
	fast.sync = true
	bt.add_node("fast", fast, Vector2(500, 400))
	bt.connect_node("fast", 0, "stride")
	bt.connect_node("fast", 1, "sprint_speed")
	bt.add_node("moving", AnimationNodeBlend2.new(), Vector2(600, 100))
	bt.connect_node("moving", 0, "idle")
	bt.connect_node("moving", 1, "fast")
	var act := AnimationNodeTransition.new()
	act.xfade_time = 0.45
	act.input_count = ACTS.size()
	for i in ACTS.size():
		act.set_input_name(i, ACTS[i])
	bt.add_node("act", act, Vector2(800, 200))
	bt.connect_node("act", 0, "moving")
	for i in range(1, ACTS.size()):
		var n := AnimationNodeAnimation.new()
		n.animation = "rb/" + ACTS[i]
		bt.add_node(ACTS[i], n, Vector2(600, 300 + 100 * i))
		if ACTS[i] == "drunk_walk":
			# Staggering along at whatever pace they manage.
			bt.add_node("drunk_walk_speed", AnimationNodeTimeScale.new(), Vector2(700, 300 + 100 * i))
			bt.connect_node("drunk_walk_speed", 0, "drunk_walk")
			bt.connect_node("act", i, "drunk_walk_speed")
		else:
			bt.connect_node("act", i, ACTS[i])
	bt.connect_node("output", 0, "act")
	return bt


## Steps the clips on by `delta`: moving at `speed` (m/s, in the character's own units)
## and doing `act` (one of ACTS; "loco" is standing about or on the move).
func update(delta: float, speed: float, act: String) -> void:
	if tree == null or not is_instance_valid(tree):
		return
	if act != _act and act in ACTS:
		_act = act
		tree.set("parameters/act/transition_request", act)
	var target_move := smoothstep(0.08, 0.45, speed)
	var target_run := smoothstep(2.0, 3.4, speed)
	_move = move_toward(_move, target_move, delta * 4.0)
	_run = move_toward(_run, target_run, delta * 2.5)
	_sprint = move_toward(_sprint, smoothstep(4.2, 5.8, speed), delta * 2.5)
	# One cycle (two steps) carries them this far; play just fast enough for the speed.
	var travel := lerpf(lerpf(_walk_travel, _run_travel, _run), _sprint_travel, _sprint)
	var cycles := maxf(speed, 0.35) / (travel * _stride_scale)
	tree.set("parameters/walk_speed/scale", cycles * _walk_len)
	tree.set("parameters/run_speed/scale", cycles * _run_len)
	tree.set("parameters/sprint_speed/scale", cycles * _sprint_len)
	tree.set("parameters/stride/blend_amount", _run)
	tree.set("parameters/fast/blend_amount", _sprint)
	tree.set("parameters/drunk_walk_speed/scale", maxf(speed, 0.3) * _drunk_rate / _stride_scale)
	tree.set("parameters/moving/blend_amount", _move)
	tree.advance(delta)


func current_act() -> String:
	return _act
