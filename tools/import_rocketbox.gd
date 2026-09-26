extends SceneTree
## Turns Rocketbox avatars (FBX, copied into res://tmp_rb/) into clean GLBs for the game:
## the skeleton and the skinned mesh only (no animation player, no texture paths). Their
## textures are made by tools/rocketbox/textures.py; CharacterLook puts them on.
##   godot --headless --path . --script res://tools/import_rocketbox.gd -- Name [Name ...]

const SRC := "res://tmp_rb/"
const OUT := "res://assets/characters/rocketbox/"


func _init() -> void:
	for name in OS.get_cmdline_user_args():
		var ps := load(SRC + name + ".fbx") as PackedScene
		if ps == null:
			push_error("can't load " + name)
			continue
		var root := ps.instantiate() as Node3D
		for n in root.find_children("*", "AnimationPlayer", true, false):
			n.get_parent().remove_child(n)
			n.free()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			for s in mesh.get_surface_count():
				var old := mesh.surface_get_material(s)
				var m := StandardMaterial3D.new()
				m.resource_name = old.resource_name if old else "surface%d" % s
				mesh.surface_set_material(s, m)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + name))
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_scene(root, state)
		if err == OK:
			err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT + name + "/" + name + ".glb"))
		print("%-22s %s" % [name, "ok" if err == OK else "error %d" % err])
		root.free()
	quit()
