extends "res://tests/test_base.gd"
## Motion capture (Mocap): the real people stand, walk and run as the Rocketbox actors
## did - every avatar upright, children too; feet planted while they carry the weight (no
## sliding); walking, running and sprinting in step; and handed over smoothly to the
## procedural rig for what was never recorded (knocked out, jumping, climbing).


func run_tests() -> void:
	await _test_every_avatar()
	await _test_no_foot_slide(NPCBody.Outfit.GENTLEMAN, 1.4)
	await _test_no_foot_slide(NPCBody.Outfit.LADY, 1.3)
	await _test_no_foot_slide(NPCBody.Outfit.WORKER, 4.0)
	await _test_hand_over()
	await _test_drunk()
	await _test_skirt()
	await _test_harry()


func _body(outfit: int, seed: int, height := 1.76) -> NPCBody:
	var b := NPCBody.new()
	b.outfit = outfit as NPCBody.Outfit
	b.height = height
	b.variation_seed = seed
	main.add_child(b)
	b.global_position = Vector3(30.0, 0.05, 30.0)
	return b


func _skel(n: Node) -> Skeleton3D:
	var s := n.find_children("*", "Skeleton3D", true, false)
	return s[0] if not s.is_empty() else null


func _world(sk: Skeleton3D, bone: String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


## Every avatar there is, standing about by motion capture: upright, feet down, head up.
func _test_every_avatar() -> void:
	var bad := []
	var seen := {}
	for look: String in RealPeople.AVATARS:
		for name: String in RealPeople.avatars(look):
			if seen.has(name):
				continue
			seen[name] = true
			var model: Node3D = null
			for seed in 200:
				var m := RealPeople.instantiate(look, seed)
				if m and m.get_meta("avatar") == name:
					model = m
					break
				if m:
					m.free()
			if model == null:
				continue
			var holder := Node3D.new()
			main.add_child(holder)
			holder.global_position = Vector3(40.0, 0.0, 40.0)
			holder.add_child(model)
			var sk := _skel(model)
			var mc := Mocap.new()
			var ok := mc.setup(sk, bool(model.get_meta("female")), 0, float(model.get_meta("pelvis_height")))
			for i in 10:
				mc.update(1.0 / 30.0, 0.0, "loco")
				await wait(1)
			var head := _world(sk, "Bip01 Head")
			var pelvis := _world(sk, "Bip01 Pelvis")
			var foot := _world(sk, "Bip01 L Foot")
			var knee := _world(sk, "Bip01 L Calf")
			var thigh := _world(sk, "Bip01 L Thigh")
			var tall := float(model.get_meta("pelvis_height"))
			if not ok or head.y < pelvis.y + 0.35 * tall or foot.y > 0.2 or absf(pelvis.y - tall) > 0.12 or (knee - thigh).normalized().dot(Vector3.DOWN) < 0.85:
				bad.append("%s (head %.2f pelvis %.2f foot %.2f)" % [name, head.y, pelvis.y, foot.y])
			holder.queue_free()
	check("every avatar stands upright by motion capture (%d avatars)" % seen.size(), bad.is_empty() and seen.size() >= 20, str(bad))
	# Children: their "Bip02" bones renamed, so they are posed and clothed like everyone.
	var kid := _body(NPCBody.Outfit.RAGGED, 9, 1.3)
	await wait(3)
	var ksk := _skel(kid.get_look_model())
	check("children's bones answer to the same names", ksk != null and ksk.find_bone("Bip01 Pelvis") >= 0 and ksk.find_bone("Bip02 Pelvis") < 0)
	check("children move by motion capture too", kid.is_mocap())
	kid.queue_free()


## While a foot carries the weight it stays put on the ground: seen from the body walking
## at `speed`, it goes back at `speed`.
func _test_no_foot_slide(outfit: int, speed: float) -> void:
	var b := _body(outfit, 21)
	var sk := _skel(b.get_look_model())
	for i in 60:
		b.update_body(speed, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
	# The body stands still here, so a planted foot should move back at the walking speed.
	var track := []
	for i in 120:
		b.update_body(speed, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
		track.append(_world(sk, "Bip01 L Foot"))
	# Planted: the ankle within 2 cm of its lowest.
	var low := INF
	for f: Vector3 in track:
		low = minf(low, f.y)
	var slide := []
	for i in range(1, track.size()):
		if track[i].y < low + 0.02 and track[i - 1].y < low + 0.02:
			slide.append((track[i - 1].z - track[i].z) * 60.0)
	# The body faces -Z: a planted foot moves to +Z at `speed`.
	var planted := slide.filter(func(v: float) -> bool: return v < 0.0)
	var med := 0.0
	if not planted.is_empty():
		planted.sort()
		med = -float(planted[planted.size() / 2])
	check("%s at %.1f m/s: the planted foot keeps pace with the ground (%.2f m/s)" % [NPCBody.Outfit.keys()[outfit], speed, med],
		absf(med - speed) < speed * 0.3, "%d planted frames" % planted.size())
	b.queue_free()


## Knocked out, the rig takes over within a moment; back on their feet, the clips return.
func _test_hand_over() -> void:
	var b := _body(NPCBody.Outfit.GENTLEMAN, 33)
	var sk := _skel(b.get_look_model())
	# (Lambdas capture by value: the running worst lives in an array.)
	var acc := [0.0, Vector3.INF]
	var step := func() -> void:
		var p := _world(sk, "Bip01 Head")
		if acc[1] != Vector3.INF:
			acc[0] = maxf(acc[0], p.distance_to(acc[1]))
		acc[1] = p
	for i in 40:
		b.update_body(1.4, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
		step.call()
	for pose: int in [NPCBody.Pose.ALERT, NPCBody.Pose.GUARD, NPCBody.Pose.TALK, NPCBody.Pose.SIT, NPCBody.Pose.WAVE, NPCBody.Pose.LOOK_AROUND, NPCBody.Pose.STUNNED, NPCBody.Pose.NORMAL]:
		for i in 60:
			b.update_body(0.0, pose, 1.0 / 60.0)
			await wait(1)
			step.call()
	check("no pops between poses (the head never jumps)", acc[0] < 0.035, "worst %.3f m in a frame" % acc[0])
	# Knocked out: a fall (quick, but no quicker than falling).
	acc[0] = 0.0
	var down_in := -1
	for i in 120:
		b.update_body(0.0, NPCBody.Pose.UNCONSCIOUS, 1.0 / 60.0)
		await wait(1)
		step.call()
		if down_in < 0 and _world(sk, "Bip01 Pelvis").y < 0.45:
			down_in = i
	check("knocked out: down flat", _world(sk, "Bip01 Pelvis").y < 0.45, "pelvis %.2f" % _world(sk, "Bip01 Pelvis").y)
	check("...falling like a body, not snapping down", down_in > 25 and acc[0] < 0.13, "down in %d frames, head %.3f m/frame at most" % [down_in, acc[0]])
	var finite := true
	for bone in sk.get_bone_count():
		finite = finite and sk.get_bone_pose_rotation(bone).is_finite() and sk.get_bone_pose_position(bone).is_finite()
	check("no broken bones (every pose finite)", finite)
	b.queue_free()


## Turned out of the pub: swaying on the spot, staggering along.
func _test_drunk() -> void:
	var b := _body(NPCBody.Outfit.WORKER, 44)
	b.drunk = true
	var m: Mocap = b.get("_mocap")
	for i in 30:
		b.update_body(0.0, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
	var standing := m.current_act()
	for i in 60:
		b.update_body(1.0, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
	check("a drunk sways standing and staggers walking", standing == "drunk" and m.current_act() == "drunk_walk", "%s, %s" % [standing, m.current_act()])
	b.queue_free()


## A lady's skirt trails behind her as she walks and settles when she stops.
func _test_skirt() -> void:
	var b := _body(NPCBody.Outfit.LADY, 5)
	var sways := b.get_look_model().find_children("Sway", "ClothSway", true, false)
	check("a lady's skirt hangs so it can swing", not sways.is_empty())
	if sways.is_empty():
		b.queue_free()
		return
	var sway := sways[0] as ClothSway
	var most := 0.0
	for i in 90:
		# Walking along -Z (the way she faces).
		b.global_position += Vector3(0, 0, -1.4 / 60.0)
		b.update_body(1.4, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
		most = minf(most, sway.rotation.x)
	for i in 120:
		b.update_body(0.0, NPCBody.Pose.NORMAL, 1.0 / 60.0)
		await wait(1)
	check("...trailing behind as she walks and settling when she stops", most < -0.03 and absf(sway.rotation.x) < 0.01,
		"%.3f walking, %.3f stopped" % [most, sway.rotation.x])
	b.queue_free()


func _test_harry() -> void:
	var mq := harry.find_children("*", "HarryMannequin", true, false)
	var m: Node = mq[0] if not mq.is_empty() else null
	check("Harry moves by motion capture", m != null and m.get("_mocap") != null)
	if m == null or m.get("_mocap") == null:
		return
	await tp(Vector3(0, 0.05, 20.0))
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait(90)
	check("sprinting: the recorded run (rig out of it)", float(m.get("_proc")) < 0.05, "proc %.2f, %s" % [float(m.get("_proc")), state_name()])
	release_all()
	await wait(30)
	await press_for("jump", 2)
	var air := 0.0
	for i in 30:
		await wait(1)
		air = maxf(air, float(m.get("_proc")))
	check("jumping: the rig takes over in the air", air > 0.8, "proc %.2f" % air)
	await wait(60)
	check("landed: back on the recorded feet", float(m.get("_proc")) < 0.05, "proc %.2f, %s" % [float(m.get("_proc")), state_name()])
