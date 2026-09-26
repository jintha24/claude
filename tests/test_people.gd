extends "res://tests/test_base.gd"
## The real people (RealPeople: Rocketbox avatars dressed for 1866), driven by the
## mannequin rig: they stand up straight, arms hanging, walk with a stride, wear their
## hats and skirts, and fall down flat when knocked out.

const LOOKS := {
	"gentleman": NPCBody.Outfit.GENTLEMAN, "worker": NPCBody.Outfit.WORKER, "ragged": NPCBody.Outfit.RAGGED,
	"constable": NPCBody.Outfit.CONSTABLE, "lady": NPCBody.Outfit.LADY,
}


func run_tests() -> void:
	for look: String in LOOKS:
		await _test_look(look, LOOKS[look])
	await _test_child()
	await _test_harry()
	_test_textures()


func _body(outfit: int, seed: int, height := 1.76) -> NPCBody:
	var b := NPCBody.new()
	b.outfit = outfit as NPCBody.Outfit
	b.height = height
	b.variation_seed = seed
	main.add_child(b)
	b.global_position = Vector3(30.0 + seed * 2.0, 0.05, 30.0)
	return b


func _skel(b: NPCBody) -> Skeleton3D:
	var m := b.get_look_model()
	var s := m.find_children("*", "Skeleton3D", true, false) if m else []
	return s[0] if not s.is_empty() else null


func _world(sk: Skeleton3D, bone: String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func _test_look(look: String, outfit: int) -> void:
	var b := _body(outfit, 5)
	for i in 5:
		b.update_body(0.0, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
	var m := b.get_look_model()
	check("%s: a real person (%s)" % [look, str(m.get_meta("avatar", "")) if m else "-"], m != null and m.has_meta("avatar"))
	var sk := _skel(b)
	if sk == null:
		b.queue_free()
		return
	var hip := _world(sk, "Bip01 L Thigh")
	var knee := _world(sk, "Bip01 L Calf")
	var foot := _world(sk, "Bip01 L Foot")
	var hand := _world(sk, "Bip01 L Hand")
	var shoulder := _world(sk, "Bip01 L UpperArm")
	check("%s stands up straight: legs down, feet on the ground" % look, (knee - hip).normalized().dot(Vector3.DOWN) > 0.9 and foot.y < 0.25, "leg %.2f, foot %.2f" % [(knee - hip).normalized().dot(Vector3.DOWN), foot.y])
	check("%s's arms hang by their sides" % look, hand.y < shoulder.y - 0.4 and Vector2(hand.x - shoulder.x, hand.z - shoulder.z).length() < 0.3, "hand %.2f below the shoulder" % (shoulder.y - hand.y))
	# Walking: the thighs swing.
	var angles := []
	for i in 60:
		b.update_body(1.4, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
		var k := _world(sk, "Bip01 L Calf") - _world(sk, "Bip01 L Thigh")
		angles.append(rad_to_deg(atan2(k.z, -k.y)))
	check("%s walks with a stride" % look, angles.max() - angles.min() > 25.0, "%.0f degrees" % (angles.max() - angles.min()))
	match look:
		"gentleman", "constable":
			check("%s wears his hat" % look, not sk.find_children("*", "BoneAttachment3D", false, false).is_empty())
		"lady":
			var skirt := sk.find_children("*", "BoneAttachment3D", false, false).filter(func(n: Node) -> bool: return (n as BoneAttachment3D).bone_idx == sk.find_bone("Bip01 Pelvis"))
			check("a lady wears a long skirt", not skirt.is_empty())
	# Knocked out: down flat.
	for i in 90:
		b.update_body(0.0, NPCBody.Pose.UNCONSCIOUS, 1.0 / 60.0)
		await wait(1)
	check("%s falls flat when knocked out" % look, _world(sk, "Bip01 Pelvis").y < 0.45, "pelvis %.2f m up" % _world(sk, "Bip01 Pelvis").y)
	b.queue_free()


func _test_child() -> void:
	var b := _body(NPCBody.Outfit.RAGGED, 9, 1.3)
	await wait(3)
	var m := b.get_look_model()
	check("children are real children", m != null and String(m.get_meta("avatar", "")).contains("Child"), str(m.get_meta("avatar", "")) if m else "-")
	b.queue_free()


func _test_harry() -> void:
	var looks := harry.find_children("Look", "Node3D", true, false)
	check("Harry is a real person too", not looks.is_empty() and (looks[0] as Node3D).has_meta("avatar"), str(looks.size()))
	check("...in his top hat", not looks.is_empty() and not looks[0].find_children("*", "BoneAttachment3D", true, false).is_empty())


func _test_textures() -> void:
	# GPU-compressed with mipmaps (uncompressed they'd take gigabytes of video memory and
	# shimmer at a distance).
	var bad := []
	for d in DirAccess.get_directories_at("res://assets/characters/rocketbox"):
		for f in DirAccess.get_files_at("res://assets/characters/rocketbox/" + d):
			if not f.ends_with(".import") or f.ends_with(".glb.import"):
				continue
			var cfg := ConfigFile.new()
			cfg.load("res://assets/characters/rocketbox/%s/%s" % [d, f])
			if int(cfg.get_value("params", "compress/mode", 0)) != 2 or not bool(cfg.get_value("params", "mipmaps/generate", false)):
				bad.append(d + "/" + f)
	check("the avatars' textures are GPU-compressed with mipmaps", bad.is_empty(), str(bad.slice(0, 3)))
