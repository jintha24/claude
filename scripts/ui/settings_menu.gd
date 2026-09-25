class_name SettingsMenu
extends CanvasLayer
## Settings: Graphics (presets and each option), Display, Audio, Gameplay and Controls
## (re-bind any action on keyboard/mouse and controller). Changes apply at once and are
## saved to user://settings.cfg when you go back.

signal closed

var _root: Control
var _waiting_action := ""
var _waiting_pad := false
var _wait_label: Label


static func open(tree: SceneTree) -> SettingsMenu:
	var m := SettingsMenu.new()
	tree.root.add_child(m)
	return m


func _ready() -> void:
	layer = 75
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameSettings.values.is_empty():
		GameSettings.load_settings()
	_build()


func _build(tab: int = 0) -> void:
	if _root:
		_root.queue_free()
	var o := UIKit.overlay(self, "Settings", Vector2(820, 560))
	_root = o[0]
	var box: VBoxContainer = o[1]
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(760, 440)
	tabs.add_theme_font_override("font", UIKit.font())
	box.add_child(tabs)
	tabs.add_child(_graphics_tab())
	tabs.add_child(_display_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_gameplay_tab())
	tabs.add_child(_controls_tab())
	tabs.current_tab = tab
	var back := UIKit.button("Save and go back", 20)
	back.pressed.connect(close)
	box.add_child(back)
	back.grab_focus.call_deferred()


func _page(page_name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = page_name
	v.add_theme_constant_override("separation", 8)
	return v


func _check(key: String, text: String, page: VBoxContainer) -> void:
	var c := CheckBox.new()
	c.button_pressed = bool(GameSettings.get_value(key))
	c.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value(key, on)
		_apply())
	page.add_child(UIKit.row(text, c))


func _slide(key: String, text: String, lo: float, hi: float, step: float, page: VBoxContainer) -> void:
	var s := UIKit.slider(lo, hi, step, float(GameSettings.get_value(key)))
	s.value_changed.connect(func(v: float) -> void:
		GameSettings.set_value(key, v)
		_apply())
	page.add_child(UIKit.row(text, s))


func _graphics_tab() -> VBoxContainer:
	var p := _page("Graphics")
	var preset := OptionButton.new()
	var names := ["Low", "Medium", "High", "Ultra", "Custom"]
	for n in names:
		preset.add_item(n)
	preset.selected = names.find(String(GameSettings.get_value("graphics/preset")))
	preset.item_selected.connect(func(i: int) -> void:
		if names[i] != "Custom":
			GameSettings.apply_preset(names[i])
			_apply()
			_build.call_deferred(0))
	p.add_child(UIKit.row("Quality preset", preset))
	_check("graphics/sdfgi", "Global illumination (SDFGI)", p)
	_check("graphics/ssr", "Reflections (SSR)", p)
	_check("graphics/ssao", "Ambient occlusion (SSAO)", p)
	_check("graphics/ssil", "Indirect light (SSIL)", p)
	_check("graphics/volumetric_fog", "Volumetric fog", p)
	var shadows := OptionButton.new()
	var sizes := [2048, 4096, 8192]
	for s in sizes:
		shadows.add_item(["Low", "High", "Ultra"][sizes.find(s)] + " (%d)" % s)
	shadows.selected = maxi(sizes.find(int(GameSettings.get_value("graphics/shadow_size"))), 0)
	shadows.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("graphics/shadow_size", sizes[i])
		_apply())
	p.add_child(UIKit.row("Shadows", shadows))
	var softness := OptionButton.new()
	for n: String in ["Hard", "Soft (very low)", "Soft (low)", "Soft (medium)", "Soft (high)", "Soft (ultra)"]:
		softness.add_item(n)
	softness.selected = clampi(int(GameSettings.get_value("graphics/shadow_quality")), 0, 5)
	softness.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("graphics/shadow_quality", i)
		_apply())
	p.add_child(UIKit.row("Shadow edges", softness))
	_slide("graphics/shadow_distance", "Shadow distance (m)", 50, 250, 10, p)
	_check("graphics/skin_scattering", "Skin light scattering", p)
	_slide("graphics/render_scale", "Render scale (FSR 2 below 1.0)", 0.5, 1.0, 0.01, p)
	_check("graphics/dynamic_resolution", "Dynamic resolution (keeps the frame rate up)", p)
	_slide("graphics/view_distance", "View distance in the hills (chunks)", 3, 9, 1, p)
	return p


func _display_tab() -> VBoxContainer:
	var p := _page("Display")
	_check("display/fullscreen", "Fullscreen", p)
	_check("display/vsync", "Vertical sync", p)
	_slide("display/fov", "Field of view", 55, 90, 1, p)
	return p


func _audio_tab() -> VBoxContainer:
	var p := _page("Audio")
	for bus_name in GameSettings.AUDIO_BUSES:
		_slide("audio/" + bus_name, {"Master": "Master volume", "Music": "Music", "SFX": "Sound effects", "Ambience": "Ambience", "Voice": "Voices"}[bus_name], 0.0, 1.0, 0.05, p)
	return p


func _gameplay_tab() -> VBoxContainer:
	var p := _page("Gameplay")
	_slide("gameplay/mouse_sensitivity", "Mouse sensitivity", 0.3, 2.5, 0.05, p)
	_check("gameplay/invert_y", "Invert camera up/down", p)
	_check("gameplay/subtitles", "Subtitles", p)
	_slide("gameplay/day_minutes", "Length of a day (real minutes)", 24, 120, 4, p)
	return p


func _controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	var p := _page("List")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(p)
	_wait_label = UIKit.label("Click a binding, then press the new key, mouse button or controller button.", 15, UIKit.INK_DIM)
	p.add_child(_wait_label)
	for action: String in GameSettings.REBINDABLE:
		var h := HBoxContainer.new()
		var l := UIKit.label(GameSettings.REBINDABLE[action], 17)
		l.custom_minimum_size = Vector2(260, 0)
		h.add_child(l)
		for pad in [false, true]:
			var b := UIKit.button(GameSettings.binding_text(action, pad), 15)
			b.custom_minimum_size = Vector2(210, 34)
			b.pressed.connect(func() -> void:
				_waiting_action = action
				_waiting_pad = pad
				_wait_label.text = "Press the new %s for \"%s\" (Esc cancels)..." % ["controller button" if pad else "key or mouse button", GameSettings.REBINDABLE[action]])
			h.add_child(b)
		p.add_child(h)
	var reset := UIKit.button("Reset all controls to default", 17)
	reset.pressed.connect(func() -> void:
		GameSettings.reset_controls()
		_build.call_deferred(4))
	p.add_child(reset)
	return scroll


func _input(event: InputEvent) -> void:
	if _waiting_action == "":
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_waiting_action = ""
		_wait_label.text = "Cancelled."
		get_viewport().set_input_as_handled()
		return
	var ok := false
	if not _waiting_pad:
		ok = (event is InputEventKey and (event as InputEventKey).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	else:
		ok = (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed) or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6)
	if not ok:
		return
	var ev := event.duplicate() as InputEvent
	if ev is InputEventKey:
		(ev as InputEventKey).keycode = KEY_NONE
		(ev as InputEventKey).pressed = false
	if ev is InputEventJoypadMotion:
		(ev as InputEventJoypadMotion).axis_value = signf((ev as InputEventJoypadMotion).axis_value)
	GameSettings.rebind(_waiting_action, ev, _waiting_pad)
	_waiting_action = ""
	get_viewport().set_input_as_handled()
	_build.call_deferred(4)


func _apply() -> void:
	GameSettings.apply(get_tree())


func close() -> void:
	GameSettings.save_settings()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_action == "" and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()
