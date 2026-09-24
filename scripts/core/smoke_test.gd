class_name SmokeTest
extends Node
## A start-up check any build of the game can run on itself:
##   TheThiefOfLondon.exe --headless -- --smoke-test
## (on Linux: ./TheThiefOfLondon.x86_64 --headless -- --smoke-test)
## It loads London and the hills, runs each for a few seconds, and prints "SMOKE OK" (exit
## code 0) or "SMOKE FAIL: ..." (exit code 1). tools/build_release.sh runs it on every
## exported build, which proves the packed game has everything it needs.

const PLACES: Array[String] = ["res://scenes/main/main.tscn", "res://scenes/wilderness/hills.tscn"]
const FRAMES_PER_PLACE := 240

var _i := -1
var _frames := 0
var _scene: Node


## True if the game was started with --smoke-test after "--".
static func requested() -> bool:
	return "--smoke-test" in OS.get_cmdline_user_args()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_next.call_deferred()


func _next() -> void:
	if _scene:
		var ok := _scene.get_node_or_null("Harry") is Harry and AudioDirector.current() != null
		if not ok:
			_finish("SMOKE FAIL: %s is missing parts" % PLACES[_i])
			return
		print("smoke: %s ran %d frames" % [PLACES[_i].get_file(), _frames])
	_i += 1
	_frames = 0
	if _i >= PLACES.size():
		_finish("SMOKE OK")
		return
	var packed := load(PLACES[_i]) as PackedScene
	if packed == null:
		_finish("SMOKE FAIL: couldn't load %s" % PLACES[_i])
		return
	get_tree().change_scene_to_packed(packed)
	_scene = null


func _process(_delta: float) -> void:
	if _i < 0 or _i >= PLACES.size():
		return
	if _scene == null:
		_scene = get_tree().current_scene
		return
	_frames += 1
	if _frames >= FRAMES_PER_PLACE:
		_next()


func _finish(message: String) -> void:
	print(message)
	get_tree().quit(0 if message == "SMOKE OK" else 1)
