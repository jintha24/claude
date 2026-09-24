extends "res://tests/test_base.gd"
## Phase 11: the release set-up is consistent. The export presets exist and point at the
## icon; the icon is a real multi-size Windows .ico; the version is the same in the game,
## the .exe details and the installer; the installer ships the files it lists; and the
## game's built-in smoke test (--smoke-test) is wired to the title screen.


func make_scene() -> Node:
	return Node.new() # no world needed


func run_tests() -> void:
	var cfg := ConfigFile.new()
	check("export_presets.cfg reads", cfg.load("res://export_presets.cfg") == OK)
	var presets := {}
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			presets[cfg.get_value(section, "name")] = section
	check("Windows and Linux presets", presets.has("Windows Desktop") and presets.has("Linux"), str(presets.keys()))
	var win: String = presets.get("Windows Desktop", "preset.0")
	var opts := win + ".options"
	check("tests, tools and docs are left out of the game", String(cfg.get_value(win, "exclude_filter", "")).contains("tests/*") and String(cfg.get_value(win, "exclude_filter", "")).contains("tools/*"))
	check("64-bit Windows with desktop texture formats", cfg.get_value(opts, "binary_format/architecture", "") == "x86_64" and cfg.get_value(opts, "texture_format/s3tc_bptc", false))
	var icon_path: String = cfg.get_value(opts, "application/icon", "")
	var ico := FileAccess.get_file_as_bytes(icon_path)
	var images := ico.decode_u16(4) if ico.size() > 6 else 0
	check("the .exe icon is a real .ico with every size up to 256 px", ico.size() > 1000 and ico.decode_u16(2) == 1 and images >= 6, "%s: %d images" % [icon_path, images])
	check("the window icon is set too", String(ProjectSettings.get_setting("application/config/windows_native_icon", "")) == icon_path)
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	check("the game has a version number", version.split(".").size() == 3, version)
	check("the .exe details carry the same version", cfg.get_value(opts, "application/file_version", "") == version + ".0" and cfg.get_value(opts, "application/product_version", "") == version + ".0")
	var iss := FileAccess.get_file_as_string("res://installer/thief_of_london.iss")
	check("the installer carries the same version", iss.contains("#define AppVersion \"%s\"" % version))
	var exe_name := String(cfg.get_value(win, "export_path", "")).get_file()
	check("the installer installs what the export makes", iss.contains(exe_name) and iss.contains(exe_name.get_basename() + ".pck"), exe_name)
	var files_ok := true
	for f: String in ["README.txt", "LICENSE.txt", "THIRD_PARTY_NOTICES.txt"]:
		if not iss.contains(f) or not FileAccess.file_exists("res://installer/" + f):
			files_ok = false
	check("Read Me, licence and third-party notices ship with it", files_ok)
	var notices := FileAccess.get_file_as_string("res://installer/THIRD_PARTY_NOTICES.txt")
	check("the notices include Godot's MIT licence", notices.contains("Permission is hereby granted, free of charge"))
	check("uninstalling asks before deleting saves", iss.contains("userappdata") and iss.contains("ThiefOfLondon"))
	check("the saves folder matches the game's", String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")) == "ThiefOfLondon")
	check("builds can check themselves (--smoke-test)", FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd").contains("SmokeTest.requested()"))
