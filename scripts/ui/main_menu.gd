extends Control
## The title screen: a sepia London skyline at dusk (drawn, not rendered, so it appears
## at once), the title, and Continue / New Game / Load Game / Settings / Quit.

const GAME_SCENE := "res://scenes/main/main.tscn"
## A new game begins where the story does: Harry's cave in the hills (Mission 1).
const NEW_GAME_SCENE := "res://scenes/wilderness/hills.tscn"

var _buttons: VBoxContainer
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameSettings.load_settings()
	GameSettings.apply(get_tree())
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var title := UIKit.label("The Thief of London", 64)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_top = 90.0
	add_child(title)
	var sub := UIKit.label("London, 1866", 26, UIKit.BRASS)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.offset_top = 170.0
	add_child(sub)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.custom_minimum_size = Vector2(320, 0)
	_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_buttons.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_buttons.grow_vertical = Control.GROW_DIRECTION_BOTH
	_buttons.offset_top = 40.0
	add_child(_buttons)
	var latest := SaveGame.latest()
	var cont := UIKit.button("Continue")
	cont.disabled = latest < 0
	cont.pressed.connect(func() -> void: SaveGame.load_game(get_tree(), SaveGame.latest()))
	_buttons.add_child(cont)
	var new_game := UIKit.button("New Game")
	new_game.pressed.connect(start_new_game)
	_buttons.add_child(new_game)
	var load_btn := UIKit.button("Load Game")
	load_btn.pressed.connect(func() -> void: SaveLoadMenu.open(get_tree(), false))
	_buttons.add_child(load_btn)
	var settings := UIKit.button("Settings")
	settings.pressed.connect(func() -> void: SettingsMenu.open(get_tree()))
	_buttons.add_child(settings)
	var quit := UIKit.button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	_buttons.add_child(quit)
	(cont if not cont.disabled else new_game).grab_focus.call_deferred()
	var credit := UIKit.label("\"Take from those who won't miss it. Give to those who can't live without it.\"", 16, UIKit.INK_DIM)
	credit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	credit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.offset_top = -60.0
	add_child(credit)


func start_new_game() -> void:
	SaveGame.new_game()
	GameState.spawn_at = "CaveClearing"
	var ls := LoadingScreen.new()
	ls.scene_path = NEW_GAME_SCENE
	ls.title = "Thursday, 20th September 1866"
	get_tree().root.add_child(ls)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Dusk sky: amber low down, slate above.
	var steps := 24
	for i in steps:
		var t := float(i) / steps
		var c := Color(0.1, 0.1, 0.13).lerp(Color(0.62, 0.42, 0.24), pow(t, 1.8))
		draw_rect(Rect2(0, h * t, w, h / steps + 1), c)
	# Distant skyline: St Paul's dome, spires, chimneys, rooftops, all in silhouette.
	var base := h * 0.78
	var ink := Color(0.06, 0.05, 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1866
	var x := 0.0
	while x < w:
		var bw := rng.randf_range(30.0, 90.0)
		var bh := rng.randf_range(30.0, 90.0)
		draw_rect(Rect2(x, base - bh, bw + 1, bh + h), ink)
		for k in rng.randi_range(0, 2):
			var cx := x + rng.randf_range(4.0, bw - 10.0)
			draw_rect(Rect2(cx, base - bh - 14, 7, 15), ink)
		x += bw
	var dome_x := w * 0.3
	draw_rect(Rect2(dome_x - 70, base - 150, 140, 150), ink)
	draw_circle(Vector2(dome_x, base - 150), 60, ink)
	draw_rect(Rect2(dome_x - 8, base - 250, 16, 50), ink)
	draw_circle(Vector2(dome_x, base - 252), 7, ink)
	for sx: float in [w * 0.62, w * 0.8]:
		draw_colored_polygon(PackedVector2Array([Vector2(sx - 14, base - 120), Vector2(sx, base - 230), Vector2(sx + 14, base - 120)]), ink)
		draw_rect(Rect2(sx - 16, base - 120, 32, 120), ink)
	# Smoke drifting from the chimneys.
	for k in 5:
		var sx2 := w * (0.1 + k * 0.2)
		for j in 6:
			var r := 10.0 + j * 7.0
			draw_circle(Vector2(sx2 + j * 18.0 + sin(_t * 0.3 + k) * 6.0, base - 110 - j * 22.0), r, Color(0.2, 0.18, 0.17, 0.12))
	draw_rect(Rect2(0, base, w, h - base), ink)
