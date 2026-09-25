class_name GameSettings
extends RefCounted
## Player settings, kept in user://settings.cfg and applied at start and on change.
##
## Graphics presets (Low, Medium, High, Ultra) set every graphics option at once; each can
## then be changed individually (the preset reads "Custom"). Display, audio volumes,
## gameplay options and re-bound controls (keyboard, mouse and controller) are kept too.

const PATH := "user://settings.cfg"

const PRESETS := {
	"Low": {"graphics/sdfgi": false, "graphics/ssr": false, "graphics/ssao": false, "graphics/ssil": false, "graphics/volumetric_fog": false, "graphics/shadow_size": 2048, "graphics/render_scale": 0.67, "graphics/view_distance": 4,
		"graphics/shadow_quality": 1, "graphics/shadow_distance": 70.0, "graphics/skin_scattering": false, "graphics/shadow_splits": 2},
	"Medium": {"graphics/sdfgi": false, "graphics/ssr": false, "graphics/ssao": true, "graphics/ssil": false, "graphics/volumetric_fog": true, "graphics/shadow_size": 4096, "graphics/render_scale": 0.77, "graphics/view_distance": 5,
		"graphics/shadow_quality": 2, "graphics/shadow_distance": 100.0, "graphics/skin_scattering": true, "graphics/shadow_splits": 2},
	"High": {"graphics/sdfgi": true, "graphics/ssr": true, "graphics/ssao": true, "graphics/ssil": true, "graphics/volumetric_fog": true, "graphics/shadow_size": 4096, "graphics/render_scale": 1.0, "graphics/view_distance": 7,
		"graphics/shadow_quality": 3, "graphics/shadow_distance": 150.0, "graphics/skin_scattering": true, "graphics/shadow_splits": 4},
	"Ultra": {"graphics/sdfgi": true, "graphics/ssr": true, "graphics/ssao": true, "graphics/ssil": true, "graphics/volumetric_fog": true, "graphics/shadow_size": 8192, "graphics/render_scale": 1.0, "graphics/view_distance": 9,
		"graphics/shadow_quality": 4, "graphics/shadow_distance": 200.0, "graphics/skin_scattering": true, "graphics/shadow_splits": 4},
}
const AUDIO_BUSES: Array[String] = ["Master", "Music", "SFX", "Ambience", "Voice"]
## Actions that can be re-bound, with their names in the Controls menu.
const REBINDABLE := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left", "move_right": "Move right",
	"sprint": "Sprint / spur", "walk": "Walk", "crouch": "Crouch", "jump": "Jump / climb",
	"interact": "Use / take / pick", "aim": "Aim bow", "fire": "Loose arrow", "cycle_arrow": "Change arrow",
	"mount_horse": "Mount / dismount", "whistle_horse": "Whistle for Cinder", "swap_shoulder": "Swap shoulder",
	"inventory": "Ledger (hold)", "map": "Map", "pause": "Pause",
}

static var values: Dictionary = {}
static var _loaded := false


static func defaults() -> Dictionary:
	var d := {
		"graphics/preset": "High",
		"display/fullscreen": false,
		"display/vsync": true,
		"display/fov": 68.0,
		"audio/Master": 1.0, "audio/Music": 0.8, "audio/SFX": 1.0, "audio/Ambience": 0.9, "audio/Voice": 1.0,
		"gameplay/mouse_sensitivity": 1.0,
		"gameplay/invert_y": false,
		"gameplay/subtitles": true,
		"gameplay/day_minutes": 48.0,
		# Lower the render resolution by itself when the frame rate drops (see PerfGovernor).
		"graphics/dynamic_resolution": true,
	}
	d.merge(PRESETS["High"])
	return d


## The preset a new player starts on, from their graphics card: a discrete GPU gets
## High, integrated graphics Medium, anything else (software, virtual) Low.
static func detect_preset() -> String:
	if DisplayServer.get_name() == "headless":
		return "High"
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return "High"
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return "Medium"
	return "Low"


static func get_value(key: String) -> Variant:
	if not _loaded:
		load_settings()
	return values.get(key, defaults().get(key))


static func set_value(key: String, v: Variant) -> void:
	if not _loaded:
		load_settings()
	values[key] = v
	if key.begins_with("graphics/") and key != "graphics/preset":
		values["graphics/preset"] = _matching_preset()


static func apply_preset(preset: String) -> void:
	if not PRESETS.has(preset):
		return
	if not _loaded:
		load_settings()
	values.merge(PRESETS[preset], true)
	values["graphics/preset"] = preset


static func _matching_preset() -> String:
	for p: String in PRESETS:
		var ok := true
		for k: String in PRESETS[p]:
			if values.get(k) != PRESETS[p][k]:
				ok = false
				break
		if ok:
			return p
	return "Custom"


static func load_settings() -> void:
	_loaded = true
	values = defaults()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		# First run: start on the preset this PC can manage.
		var first := detect_preset()
		values.merge(PRESETS[first], true)
		values["graphics/preset"] = first
		return
	for section in cfg.get_sections():
		if section == "controls":
			continue
		for key in cfg.get_section_keys(section):
			values["%s/%s" % [section, key]] = cfg.get_value(section, key)
	# Settings saved by an older version lack the newer options: take them from the preset.
	var chosen := String(values.get("graphics/preset", ""))
	if PRESETS.has(chosen):
		for k: String in PRESETS[chosen]:
			var parts := k.split("/", true, 1)
			if not cfg.has_section_key(parts[0], parts[1]):
				values[k] = PRESETS[chosen][k]
	if cfg.has_section("controls"):
		for action in cfg.get_section_keys("controls"):
			if not InputMap.has_action(action):
				continue
			var events: Array = cfg.get_value("controls", action, [])
			InputMap.action_erase_events(action)
			for e: Dictionary in events:
				var ev := _dict_to_event(e)
				if ev:
					InputMap.action_add_event(action, ev)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k: String in values:
		var parts := k.split("/", true, 1)
		cfg.set_value(parts[0], parts[1], values[k])
	for action: String in REBINDABLE:
		var arr: Array = []
		for ev in InputMap.action_get_events(action):
			var d := _event_to_dict(ev)
			if not d.is_empty():
				arr.append(d)
		cfg.set_value("controls", action, arr)
	cfg.save(PATH)


## Applies everything: window, audio, and the current scene's graphics and camera.
static func apply(tree: SceneTree) -> void:
	if not _loaded:
		load_settings()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("display/fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("display/vsync") else DisplayServer.VSYNC_DISABLED)
	for bus_name in AUDIO_BUSES:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			var v := float(get_value("audio/" + bus_name))
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)
	GameClock.real_minutes_per_game_day = float(get_value("gameplay/day_minutes"))
	PerfGovernor.ensure(tree)
	if tree.current_scene:
		apply_to_scene(tree.current_scene)


static func apply_to_scene(root: Node) -> void:
	var vp := root.get_viewport()
	var scale := float(get_value("graphics/render_scale"))
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	var shadow := int(get_value("graphics/shadow_size"))
	RenderingServer.directional_shadow_atlas_set_size(shadow, true)
	vp.positional_shadow_atlas_size = shadow / 2
	var sq := int(get_value("graphics/shadow_quality")) as RenderingServer.ShadowQuality
	RenderingServer.directional_soft_shadow_filter_set_quality(sq)
	RenderingServer.positional_soft_shadow_filter_set_quality(sq)
	RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM if get_value("graphics/skin_scattering") else RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED)
	for sun in root.get_tree().get_nodes_in_group("sun"):
		if sun is DirectionalLight3D:
			(sun as DirectionalLight3D).directional_shadow_max_distance = float(get_value("graphics/shadow_distance"))
			# Each cascade draws the shadow casters again: two are plenty on lower presets.
			(sun as DirectionalLight3D).directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(get_value("graphics/shadow_splits")) <= 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var gov := root.get_tree().get_first_node_in_group("perf_governor") as PerfGovernor
	if gov:
		gov.enabled = bool(get_value("graphics/dynamic_resolution"))
		gov.max_scale = scale
		gov.scale = scale
	for we in root.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env == null:
			continue
		env.sdfgi_enabled = bool(get_value("graphics/sdfgi"))
		env.ssr_enabled = bool(get_value("graphics/ssr"))
		env.ssao_enabled = bool(get_value("graphics/ssao"))
		env.ssil_enabled = bool(get_value("graphics/ssil"))
		env.volumetric_fog_enabled = bool(get_value("graphics/volumetric_fog"))
	for s in root.get_tree().get_nodes_in_group("world_streamer"):
		(s as WorldStreamer).far_radius = int(get_value("graphics/view_distance"))
	for cam in root.find_children("*", "", true, false):
		if cam is ThirdPersonCamera:
			var c := cam as ThirdPersonCamera
			c.mouse_sensitivity = 0.0022 * float(get_value("gameplay/mouse_sensitivity"))
			c.invert_y = bool(get_value("gameplay/invert_y"))
			c.base_fov = float(get_value("display/fov"))
			c.sprint_fov = c.base_fov + 6.0


# ---------------------------------------------------------------------------
# Controls
# ---------------------------------------------------------------------------
## Replaces the keyboard/mouse (pad = false) or controller (pad = true) binding of `action`.
static func rebind(action: String, event: InputEvent, pad: bool) -> void:
	for ev in InputMap.action_get_events(action):
		if _is_pad(ev) == pad:
			InputMap.action_erase_event(action, ev)
			break
	InputMap.action_add_event(action, event)


static func reset_controls() -> void:
	InputMap.load_from_project_settings()


static func binding_text(action: String, pad: bool) -> String:
	for ev in InputMap.action_get_events(action):
		if _is_pad(ev) == pad:
			return event_text(ev)
	return "-"


static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if k.physical_keycode == 0:
			return OS.get_keycode_string(k.keycode)
		# Show the key as labelled on this keyboard's layout (where the platform can tell us).
		if DisplayServer.get_name() in ["headless", "Wayland"]:
			return OS.get_keycode_string(k.physical_keycode)
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode))
	if ev is InputEventMouseButton:
		return ["", "Left mouse", "Right mouse", "Middle mouse", "Wheel up", "Wheel down"][clampi((ev as InputEventMouseButton).button_index, 0, 5)]
	if ev is InputEventJoypadButton:
		return "Pad button %d" % (ev as InputEventJoypadButton).button_index
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return "Pad axis %d%s" % [m.axis, "+" if m.axis_value > 0 else "-"]
	return ev.as_text()


static func _is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


static func _event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "physical": (ev as InputEventKey).physical_keycode, "key": (ev as InputEventKey).keycode}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": (ev as InputEventMouseButton).button_index}
	if ev is InputEventJoypadButton:
		return {"type": "pad_button", "button": (ev as InputEventJoypadButton).button_index}
	if ev is InputEventJoypadMotion:
		return {"type": "pad_axis", "axis": (ev as InputEventJoypadMotion).axis, "value": (ev as InputEventJoypadMotion).axis_value}
	return {}


static func _dict_to_event(d: Dictionary) -> InputEvent:
	match String(d.get("type", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("physical", 0)) as Key
			k.keycode = int(d.get("key", 0)) as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button", 1)) as MouseButton
			return m
		"pad_button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(d.get("button", 0)) as JoyButton
			return b
		"pad_axis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(d.get("axis", 0)) as JoyAxis
			a.axis_value = float(d.get("value", 1.0))
			return a
	return null
