extends SceneTree
## Writes installer/THIRD_PARTY_NOTICES.txt: the Godot Engine's licence and the licences
## of the libraries built into it, which the MIT licence requires the game to include.
## Run whenever you change Godot version:
##   godot --headless --path . --script res://tools/make_notices.gd


func _init() -> void:
	var out := PackedStringArray()
	out.append("THE THIEF OF LONDON - THIRD-PARTY NOTICES")
	out.append("")
	out.append("This game uses the Godot Engine (https://godotengine.org), version %s." % Engine.get_version_info()["string"])
	out.append("")
	out.append("=== Godot Engine ===")
	out.append(Engine.get_license_text())
	out.append("")
	out.append("=== Character data ===")
	out.append("The people in the game are built from the MakeHuman data (base mesh, shape")
	out.append("targets, skeleton, skin weights and eyes), (c) MakeHuman Community, released")
	out.append("under CC0 1.0 (public domain): https://github.com/makehumancommunity/mpfb2 and")
	out.append("https://github.com/makehumancommunity/makehuman. With thanks.")
	out.append("")
	out.append("=== Components built into Godot ===")
	for info: Dictionary in Engine.get_copyright_info():
		out.append("")
		out.append("- %s" % info["name"])
		for part: Dictionary in info["parts"]:
			for c: String in part["copyright"]:
				out.append("    (c) %s" % c)
			out.append("    Licence: %s" % part["license"])
	out.append("")
	out.append("=== Licence texts ===")
	var licences := Engine.get_license_info()
	for key: String in licences:
		out.append("")
		out.append("--- %s ---" % key)
		out.append(licences[key])
	var f := FileAccess.open("res://installer/THIRD_PARTY_NOTICES.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	print("Wrote installer/THIRD_PARTY_NOTICES.txt (%d components)" % Engine.get_copyright_info().size())
	quit()
