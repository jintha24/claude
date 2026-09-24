class_name LoadingScreen
extends CanvasLayer
## Travel between places (London and the hills). Saves Harry's belongings to GameState,
## loads the next scene on a background thread (ResourceLoader.load_threaded_request)
## behind a Victorian title card with a progress bar, then switches to it.

const PAPER := Color(0.1, 0.085, 0.07)
const INK := Color(0.93, 0.88, 0.76)
const BRASS := Color(0.72, 0.56, 0.3)

var scene_path: String
var title: String
var _bar: ColorRect
var _bar_back: ColorRect
var _progress := [0.0]
var _done := false


## Starts a journey. `spawn` names a node in group "spawn_points" in the new scene.
static func travel(tree: SceneTree, path: String, spawn: String, card_title: String) -> LoadingScreen:
	var harry := tree.get_first_node_in_group("player") as Harry
	if harry:
		GameState.capture(harry)
		GameState.arrived_mounted = harry.is_riding()
	GameState.spawn_at = spawn
	var ls := LoadingScreen.new()
	ls.scene_path = path
	ls.title = card_title
	tree.root.add_child(ls)
	return ls


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"])
	var label := Label.new()
	label.text = title
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 38)
	label.add_theme_color_override("font_color", INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.offset_top = -60.0
	add_child(label)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(0, 0, 0, 0.5)
	_bar_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_bar_back.offset_left = -200.0
	_bar_back.offset_right = 200.0
	_bar_back.offset_top = 20.0
	_bar_back.offset_bottom = 26.0
	add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.color = BRASS
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(0, 6)
	_bar_back.add_child(_bar)
	ResourceLoader.load_threaded_request(scene_path, "PackedScene", false)


func _process(_delta: float) -> void:
	if _done:
		return
	var status := ResourceLoader.load_threaded_get_status(scene_path, _progress)
	_bar.size.x = 400.0 * float(_progress[0])
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_done = true
			var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
			get_tree().change_scene_to_packed(packed)
			# Stay up a moment while the new place streams in its ground, then go.
			get_tree().create_timer(1.2).timeout.connect(queue_free)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_done = true
			push_error("LoadingScreen: could not load %s" % scene_path)
			queue_free()
