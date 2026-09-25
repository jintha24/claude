class_name PerfGovernor
extends Node
## Dynamic resolution: watches the frame time and lowers the 3D render scale (upscaled with
## FSR 2) when the game can't keep up with the target frame rate, then raises it again when
## there's room, a step at a time. Keeps busy moments (a crowded market in the rain) smooth
## on modest PCs without making quiet moments blurry. Settings: "Dynamic resolution".

## Never below this share of the screen resolution.
const MIN_SCALE := 0.6
const STEP := 0.05
## Seconds of frames averaged before each decision.
const WINDOW := 0.75

var enabled := true
## The ceiling: the player's chosen render scale.
var max_scale := 1.0
var scale := 1.0
## The frame time aimed for, in seconds (the display's refresh rate, 60 Hz if unknown).
var target := 1.0 / 60.0

var _sum := 0.0
var _frames := 0
var _good := 0


## The running governor, created on first use (it lives beside the scenes, not in them).
static func ensure(tree: SceneTree) -> PerfGovernor:
	var gov := tree.get_first_node_in_group("perf_governor") as PerfGovernor
	if gov == null and DisplayServer.get_name() != "headless":
		gov = PerfGovernor.new()
		gov.name = "PerfGovernor"
		tree.root.add_child.call_deferred(gov)
	return gov


func _ready() -> void:
	add_to_group("perf_governor")
	process_mode = Node.PROCESS_MODE_ALWAYS
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz > 20.0:
		target = 1.0 / minf(hz, 144.0)
	enabled = bool(GameSettings.get_value("graphics/dynamic_resolution"))
	max_scale = float(GameSettings.get_value("graphics/render_scale"))
	scale = max_scale


func _process(delta: float) -> void:
	if not enabled or get_tree().paused:
		_restore()
		return
	# A loading hitch or a breakpoint says nothing about the steady frame rate.
	_sum += minf(delta, target * 3.0)
	_frames += 1
	if _sum < WINDOW:
		return
	var avg := _sum / _frames
	_sum = 0.0
	_frames = 0
	if avg > target * 1.1 and scale > MIN_SCALE:
		_set_scale(maxf(scale - STEP, MIN_SCALE))
		_good = 0
	elif avg < target * 1.02 and scale < max_scale:
		# Room to spare for a while: sharpen a step.
		_good += 1
		if _good >= 3:
			_good = 0
			_set_scale(minf(scale + STEP, max_scale))
	else:
		_good = 0


func _restore() -> void:
	if not is_equal_approx(scale, max_scale):
		_set_scale(max_scale)


func _set_scale(s: float) -> void:
	scale = s
	var vp := get_viewport()
	vp.scaling_3d_scale = s
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if s < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
