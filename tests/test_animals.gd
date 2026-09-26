extends "res://tests/test_base.gd"
## The animals (AnimalBody: sculpted models walked by QuadrupedRig): every species is there
## and rigged; horses change gait with speed; a hoof on the ground stays put (no sliding);
## the dead lie flat on their sides; nothing goes to NaN; and the game's animals use them.

const SPECIES := ["horse", "deer", "stag", "fox", "rabbit", "dog", "mastiff", "sheep", "cow"]


func run_tests() -> void:
	_test_species()
	await _test_gaits()
	await _test_planted("horse", 1.5)
	await _test_planted("horse", 3.6)
	await _test_planted("deer", 1.2)
	await _test_planted("dog", 1.0)
	await _test_poses()
	await _test_in_game()


func _body(species: String, pos := Vector3.INF) -> AnimalBody:
	var b := AnimalBody.new()
	b.species = species
	b.variation_seed = 3
	main.add_child(b)
	# In front of the camera (far off, bodies are stepped less often).
	if pos == Vector3.INF:
		var cam := root.get_viewport().get_camera_3d()
		pos = cam.global_position + Vector3(0, -cam.global_position.y + 0.05, -6.0) if cam else Vector3(40, 0.05, 40)
	b.global_position = pos
	return b


func _skel(b: AnimalBody) -> Skeleton3D:
	var s := b.find_children("*", "Skeleton3D", true, false)
	return s[0] if not s.is_empty() else null


func _world(sk: Skeleton3D, bone: String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func _test_species() -> void:
	var missing := []
	for sp: String in SPECIES:
		var b := _body(sp)
		if not b.is_ok():
			missing.append(sp)
		b.free()
	check("every animal has a real, rigged body (%d species)" % SPECIES.size(), missing.is_empty(), str(missing))


func _test_gaits() -> void:
	var b := _body("horse")
	var seen := {}
	for v: float in [1.5, 3.5, 6.5, 11.0]:
		for i in 60:
			b.global_position += Vector3(0, 0, -v / 60.0)
			b.update_body(1.0 / 60.0, v)
			await wait(1)
		seen[v] = b.rig.gait_name()
	check("a horse walks, trots, canters and gallops by speed", seen[1.5] == "walk" and seen[3.5] == "trot" and seen[6.5] == "canter" and seen[11.0] == "gallop", str(seen))
	b.queue_free()


## Moving the animal along at `speed`, a hoof on the ground stays where it is.
func _test_planted(species: String, speed: float) -> void:
	var b := _body(species)
	var sk := _skel(b)
	for i in 90:
		b.global_position += Vector3(0, 0, -speed / 60.0)
		b.update_body(1.0 / 60.0, speed)
		await wait(1)
	var hoof := "fhoof.L"
	var track := []
	for i in 120:
		b.global_position += Vector3(0, 0, -speed / 60.0)
		b.update_body(1.0 / 60.0, speed)
		await wait(1)
		track.append(_world(sk, hoof))
	var low := INF
	for p: Vector3 in track:
		low = minf(low, p.y)
	var slides := []
	for i in range(1, track.size()):
		if track[i].y < low + 0.015 and track[i - 1].y < low + 0.015:
			slides.append(absf(track[i].z - track[i - 1].z) * 60.0)
	slides.sort()
	var med: float = slides[slides.size() / 2] if not slides.is_empty() else 99.0
	check("%s at %.1f m/s: a hoof on the ground stays put (slides %.2f m/s)" % [species, speed, med], med < speed * 0.2 and slides.size() > 8, "%d frames down" % slides.size())
	b.queue_free()


func _test_poses() -> void:
	var b := _body("deer")
	var sk := _skel(b)
	var stand := _world(sk, "pelvis").y
	b.want("dead", 1.0, 3.0)
	for i in 90:
		b.update_body(1.0 / 60.0, 0.0)
		await wait(1)
	var lying := _world(sk, "pelvis").y
	check("a dead deer lies flat on its side", lying < stand * 0.55, "pelvis %.2f (standing %.2f)" % [lying, stand])
	var finite := true
	for pose: String in ["graze", "alert", "lie", "jump", "rear", "sit"]:
		b.want("dead", 0.0, 10.0)
		b.want(pose, 1.0, 10.0)
		for i in 20:
			b.update_body(1.0 / 60.0, 3.0 if pose == "jump" else 0.0)
			await wait(1)
		for bone in sk.get_bone_count():
			finite = finite and sk.get_bone_pose_rotation(bone).is_finite()
		b.want(pose, 0.0, 10.0)
	check("every pose is sound (no broken bones)", finite)
	var head_stand := _world(sk, "head").y
	b.want("graze", 1.0, 10.0)
	for i in 40:
		b.update_body(1.0 / 60.0, 0.0)
		await wait(1)
	check("grazing, the head goes down to the grass", _world(sk, "head").y < head_stand * 0.6, "%.2f -> %.2f" % [head_stand, _world(sk, "head").y])
	b.queue_free()


func _test_in_game() -> void:
	# Cabs, carts and omnibuses in London are drawn by real horses.
	var real := 0
	var all := 0
	for v in get_nodes_in_group_safe("vehicles"):
		for h in v.find_children("*", "AnimalBody", true, false):
			all += 1
			if (h as AnimalBody).is_ok():
				real += 1
	if all == 0:
		# (No traffic out yet: make a cab.)
		var hv := HorseVehicle.new()
		main.add_child(hv)
		hv.global_position = Vector3(20, 0.05, 50)
		await wait(2)
		for h in hv.find_children("*", "AnimalBody", true, false):
			all += 1
			if (h as AnimalBody).is_ok():
				real += 1
		hv.queue_free()
	check("London's cab horses are real horses", real > 0 and real == all, "%d of %d" % [real, all])
