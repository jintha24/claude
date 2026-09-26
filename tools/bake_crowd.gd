extends SceneTree
## Bakes the background crowd's walkers (see scripts/world/throng.gd): for each look, the
## one-piece far body posed mid-stride with the left foot forward, and with the right foot
## forward. The mesh holds the first pose, and CUSTOM0 the move to the second; the crowd
## shader swings between them, so a walker costs no bones and no CPU at all.
## Run from the project folder after the characters are rebuilt:
##   godot --headless --path . --script res://tools/bake_crowd.gd

const LOOKS: Array[String] = ["gentleman", "lady", "worker", "ragged", "child", "constable"]
const OUT := "res://assets/characters/crowd/"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	RealPeople.enabled = false # (the one-piece far bodies are the generated looks')
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for look in LOOKS:
		var body := NPCBody.new()
		body.look = look
		body.variation_seed = 7
		body.height = 1.78
		root.add_child(body)
		for i in 3:
			await process_frame
		var model := body.get_look_model()
		var far := model.find_child("far_body", true, false) as MeshInstance3D if model else null
		if far == null:
			push_error("%s: no far body" % look)
			quit(1)
			return
		var poses: Array[ArrayMesh] = []
		for phase: float in [PI * 0.5, PI * 1.5]:
			body.set("_speed", 1.4)
			body.set("_phase", phase)
			body.call("_pose_mannequin", 0.0)
			(body.get("_rig") as CharacterRig).update()
			for i in 3:
				await process_frame
			var baked := far.bake_mesh_from_current_skeleton_pose()
			poses.append(_to_body_space(baked, body.global_transform.affine_inverse() * far.global_transform))
		var mesh := _simplify(_combine(poses[0], poses[1]), 0.22)
		var err := ResourceSaver.save(mesh, OUT + look + ".res")
		print("%-10s %6d verts  %s" % [look, _verts(mesh), "ok" if err == OK else "error %d" % err])
		body.queue_free()
		await process_frame
	quit()


func _to_body_space(m: ArrayMesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		for i in v.size():
			v[i] = xf * v[i]
			n[i] = (xf.basis * n[i]).normalized()
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_BONES] = null
		a[Mesh.ARRAY_WEIGHTS] = null
		a[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out


## Pose A, with the move to pose B in CUSTOM0 (xyz).
func _combine(a: ArrayMesh, b: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in a.get_surface_count():
		var arr := a.surface_get_arrays(s)
		var va: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var vb: PackedVector3Array = b.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var d := PackedFloat32Array()
		d.resize(va.size() * 4)
		for i in va.size():
			var dv := vb[i] - va[i]
			d[i * 4] = dv.x
			d[i * 4 + 1] = dv.y
			d[i * 4 + 2] = dv.z
		arr[Mesh.ARRAY_CUSTOM0] = d
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return out


## The crowd is only seen from 16 m and more: about a fifth of the triangles will do.
func _simplify(m: ArrayMesh, keep: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, "", Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		im.generate_lods(25.0, 60.0, [])
		arr = im.get_surface_arrays(0) # (LOD generation may re-index the vertices)
		var full := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var best: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for l in im.get_surface_lod_count(0):
			var idx := im.get_surface_lod_indices(0, l)
			if idx.size() >= full * keep * 0.6 and idx.size() < best.size():
				best = idx
		# Coarser still further off: the engine picks these by distance.
		var lods := {}
		for l in im.get_surface_lod_count(0):
			var idx := im.get_surface_lod_indices(0, l)
			if idx.size() < best.size() and idx.size() >= 150 * 3:
				lods[im.get_surface_lod_size(0, l)] = idx
		arr[Mesh.ARRAY_INDEX] = best
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], lods, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var sizes := lods.values().map(func(i: PackedInt32Array) -> int: return i.size() / 3)
		print("  surface %d: %d -> %d triangles, far levels %s" % [s, full / 3, best.size() / 3, str(sizes)])
	return out


func _verts(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n
