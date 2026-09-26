class_name RealPeople
extends RefCounted
## Professionally modelled people: the Microsoft Rocketbox avatars (MIT licence), with
## photographed faces and skin (assets/characters/rocketbox/<Name>/, made by
## tools/rocketbox/textures.py and tools/import_rocketbox.gd). Their clothes are modern,
## so each is dressed for 1866 here: dark clothes made darker and duller, and a top hat or
## bowler for a gentleman, a cap for a working man, the custodian helmet for a constable,
## a bonnet and a long full skirt for a lady.
##
## CharacterLook asks this first; a look with no avatars falls back to the generated one.

const DIR := "res://assets/characters/rocketbox/"
## Avatars that can pass for each kind of Londoner.
const AVATARS := {
	"gentleman": ["Business_Male_01", "Business_Male_02", "Business_Male_03", "Business_Male_04", "Business_Male_05", "Male_Adult_03"],
	"worker": ["Male_Adult_02", "Male_Adult_05", "Male_Adult_14", "Male_Adult_20", "Gardener_Male_01", "Delivery_Male_01"],
	"ragged": ["Male_Adult_07", "Male_Adult_11", "Male_Adult_20", "Gardener_Male_01"],
	"constable": ["Police_Male_03", "Pilot_Male_01", "Pilot_Male_02"],
	"lady": ["Business_Female_02", "Business_Female_03", "Female_Adult_02", "Female_Adult_09", "Female_Adult_11", "Female_Adult_14"],
	"child": ["Male_Child_01", "Male_Child_02", "Female_Child_01", "Female_Child_02"],
	# The Hill Fox himself: a young man in a dark jacket, browned to his leather greatcoat.
	"harry": ["Male_Adult_07"],
}
## How their clothes are toned for the period (multiplies the body texture).
const CLOTH_TINT := {
	"gentleman": Color(0.8, 0.78, 0.76), "worker": Color(0.86, 0.8, 0.7), "ragged": Color(0.72, 0.66, 0.56),
	"constable": Color(0.55, 0.58, 0.72), "lady": Color(0.9, 0.86, 0.84), "child": Color(0.82, 0.76, 0.66),
	"harry": Color(0.7, 0.52, 0.38),
}
const SKIRTS: Array[Color] = [Color(0.2, 0.06, 0.22), Color(0.36, 0.05, 0.08), Color(0.06, 0.22, 0.14), Color(0.06, 0.09, 0.24), Color(0.25, 0.17, 0.1), Color(0.12, 0.11, 0.12)]

## Off: everyone is the generated look (tools/bake_crowd.gd bakes from those).
static var enabled := true
static var _scenes := {}
static var _materials := {}
static var _available := {}
static var _skins := {}


## The avatars actually present for `look` (the list above, as far as they've been
## converted).
static func avatars(look: String) -> Array:
	if not _available.has(look):
		var out := []
		for name: String in AVATARS.get(look, []):
			if ResourceLoader.exists(DIR + name + "/" + name + ".glb"):
				out.append(name)
		_available[look] = out
	return _available[look]


static func has_look(look: String) -> bool:
	return enabled and not avatars(look).is_empty()


## A dressed avatar for `look`, picked by `seed`; null if there are none.
static func instantiate(look: String, seed: int) -> Node3D:
	var list := avatars(look)
	if list.is_empty() or not enabled:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var name: String = list[rng.randi() % list.size()]
	var path := DIR + name + "/" + name + ".glb"
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var ps := _scenes[path] as PackedScene
	if ps == null:
		return null
	var avatar := ps.instantiate() as Node3D
	var model := Node3D.new()
	model.name = "Look"
	model.set_meta("avatar", name)
	model.add_child(avatar)
	# The avatars face +Z; everyone in the game faces -Z.
	avatar.rotation.y = PI
	for n in avatar.find_children("*", "MeshInstance3D", true, false):
		_dress_mesh(n as MeshInstance3D, name, look)
	var skel := avatar.find_children("*", "Skeleton3D", true, false)
	if not skel.is_empty():
		var sk := skel[0] as Skeleton3D
		_biped_names(sk, avatar, path)
		_add_period_clothes(sk, model, look, rng)
		model.set_meta("female", name.contains("Female"))
		model.set_meta("pelvis_height", _pelvis_height(sk, model))
	return model


## The children's bipeds are "Bip02": renamed "Bip01" like everyone else's, so the rig,
## the clothes and the motion capture all find their bones. (The skin binds bones by
## name, so it gets the new names too: one renamed copy per avatar.)
static func _biped_names(sk: Skeleton3D, avatar: Node, path: String) -> void:
	if sk.find_bone("Bip02 Pelvis") < 0:
		return
	for b in sk.get_bone_count():
		var bn := sk.get_bone_name(b)
		if bn.begins_with("Bip02"):
			sk.set_bone_name(b, "Bip01" + bn.substr(5))
	for n in avatar.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null:
			continue
		var key := "%s:skin:%s" % [path, mi.name]
		if not _skins.has(key):
			var skin := mi.skin.duplicate() as Skin
			for i in skin.get_bind_count():
				var bn := String(skin.get_bind_name(i))
				if bn.begins_with("Bip02"):
					skin.set_bind_name(i, "Bip01" + bn.substr(5))
			_skins[key] = skin
		mi.skin = _skins[key]


## How high the hips are at rest (model space, before the model is scaled).
static func _pelvis_height(sk: Skeleton3D, model: Node3D) -> float:
	var pelvis := sk.find_bone("Bip01 Pelvis")
	if pelvis < 0:
		return 0.9
	var rel := Transform3D()
	var n: Node = sk
	while n and n != model:
		rel = (n as Node3D).transform * rel
		n = n.get_parent()
	return (rel * sk.get_bone_global_rest(pelvis).origin).y


static func _dress_mesh(mi: MeshInstance3D, name: String, look: String) -> void:
	var mesh := mi.mesh
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s)
		var part := "body"
		var rn := String(src.resource_name) if src else ""
		if rn.ends_with("head"):
			part = "head"
		elif rn.ends_with("opacity"):
			part = "hair"
		mi.set_surface_override_material(s, _material(name, part, look))
	mi.visibility_range_end = PerfTuning.RANGE_PERSON
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _material(name: String, part: String, look: String) -> Material:
	var key := name + ":" + part
	if _materials.has(key):
		return _materials[key]
	var dir := DIR + name + "/"
	var m := StandardMaterial3D.new()
	m.resource_name = key
	match part:
		"hair":
			m.albedo_texture = load(dir + "hair.png")
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			m.alpha_hash_scale = 1.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.7
			m.metallic_specular = 0.3
		"head":
			# Face, ears, neck and hair: photographed. A little light through the skin.
			m.albedo_texture = load(dir + "head.jpg")
			m.normal_enabled = true
			m.normal_texture = load(dir + "head_n.jpg")
			m.roughness = 1.0
			m.roughness_texture = load(dir + "head_r.png")
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.metallic_specular = 0.4
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.12
			m.subsurf_scatter_skin_mode = true
		_:
			# Clothes and hands.
			m.albedo_texture = load(dir + "body.jpg")
			m.albedo_color = CLOTH_TINT.get(look, Color.WHITE)
			m.normal_enabled = true
			m.normal_texture = load(dir + "body_n.jpg")
			m.roughness = 1.0
			m.roughness_texture = load(dir + "body_r.png")
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.metallic_specular = 0.3
	_materials[key] = m
	return m


# ---------------------------------------------------------------------------
# Dressed for 1866
# ---------------------------------------------------------------------------
static func _add_period_clothes(skel: Skeleton3D, model: Node3D, look: String, rng: RandomNumberGenerator) -> void:
	var head := skel.find_bone("Bip01 Head")
	var pelvis := skel.find_bone("Bip01 Pelvis")
	# The skeleton's frame within the model (the avatars' skeletons sit rotated, in the
	# biped's Z-up frame).
	var rel := Transform3D()
	var n: Node = skel
	while n and n != model:
		rel = (n as Node3D).transform * rel
		n = n.get_parent()
	var hat := ""
	match look:
		"gentleman":
			hat = "top" if rng.randf() < 0.6 else "bowler"
		"worker", "ragged":
			hat = "cap" if rng.randf() < 0.8 else ""
		"constable":
			hat = "helmet"
		"lady":
			hat = "bonnet" if rng.randf() < 0.7 else ""
		"child":
			hat = "cap" if rng.randf() < 0.5 else ""
		"harry":
			hat = "top"
	if hat != "" and head >= 0:
		# (Heads are longer front to back than across: so are hats.)
		_attach(skel, rel, head, _hat_mesh(hat, look, rng), _head_top(skel, rel, head), Vector3(1.04, 1.0, 1.22))
	var cloth: Array[ClothSway] = []
	if look == "lady" and pelvis >= 0:
		var waist := rel * skel.get_bone_global_rest(pelvis).origin + Vector3(0, 0.08, 0)
		var sway := ClothSway.new()
		sway.drag = 0.035
		sway.max_angle = 0.18
		_attach(skel, rel, pelvis, _skirt_mesh(waist.y, SKIRTS[rng.randi() % SKIRTS.size()]), Vector3(0, waist.y, waist.z), Vector3.ONE, sway)
		cloth.append(sway)
	model.set_meta("cloth", cloth)


## Swings the skirts of a model made here (see ClothSway).
static func step_cloth(model: Node3D, delta: float) -> void:
	if model == null or not model.has_meta("cloth"):
		return
	for c: ClothSway in model.get_meta("cloth"):
		if is_instance_valid(c):
			c.step(delta)


## Where a hat sits on this head (model space, at rest).
static func _head_top(skel: Skeleton3D, rel: Transform3D, head: int) -> Vector3:
	var p := rel * skel.get_bone_global_rest(head).origin
	# The brim sits just above the eyebrows (the highest bones of the face).
	var brows := p.y + 0.1
	for b in skel.get_bone_count():
		if skel.get_bone_parent(b) == head:
			brows = maxf(brows, (rel * skel.get_bone_global_rest(b).origin).y)
	return Vector3(p.x, brows + 0.045, p.z + 0.012)


## Fixes `mesh` to bone `bone`, placed level at `at` (model space, rest pose). With
## `sway`, the mesh hangs from it (and swings).
static func _attach(skel: Skeleton3D, rel: Transform3D, bone: int, mesh: Mesh, at: Vector3, scale := Vector3.ONE, sway: ClothSway = null) -> void:
	var ba := BoneAttachment3D.new()
	ba.bone_idx = bone
	skel.add_child(ba)
	var mi := MeshInstance3D.new()
	var part := skel.get_bone_name(bone).get_slice(" ", 1)
	mi.name = "Period_%s" % part
	mi.mesh = mesh
	mi.visibility_range_end = PerfTuning.RANGE_PERSON
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# From the bone's rest frame, through the skeleton's, to a level placement in the model.
	var place := skel.get_bone_global_rest(bone).affine_inverse() * rel.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(scale), at)
	if sway == null:
		ba.add_child(mi)
		mi.transform = place
		return
	var holder := Node3D.new()
	holder.name = "Hang_%s_%d" % [part, ba.get_index()]
	ba.add_child(holder)
	holder.transform = place
	sway.name = "Sway"
	holder.add_child(sway)
	sway.add_child(mi)


static func _cloth(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "cloth:" + c.to_html(false) + str(rough)
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.albedo_texture = load("res://assets/characters/textures/cloth_wool.jpg")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 6.0
	m.normal_enabled = true
	m.normal_texture = load("res://assets/characters/textures/cloth_wool_n.png")
	m.normal_scale = 0.6
	_materials[key] = m
	return m


static func _hat_mesh(kind: String, look: String, rng: RandomNumberGenerator) -> Mesh:
	var mb := MeshBuilder.new()
	var dark := _cloth(Color(0.03, 0.03, 0.03), 0.6)
	match kind:
		"top":
			mb.add_cylinder(0.104, 0.1, 0.19, Vector3(0, 0.07, 0), dark, 20)
			mb.add_cylinder(0.175, 0.175, 0.012, Vector3(0, -0.02, 0), dark, 24)
			mb.add_cylinder(0.105, 0.105, 0.03, Vector3(0, -0.005, 0), _cloth(Color(0.02, 0.02, 0.02), 0.4), 20)
		"bowler":
			var dome := SphereMesh.new()
			dome.radius = 0.105
			dome.height = 0.17
			dome.is_hemisphere = true
			mb.add_mesh(dome, Transform3D(Basis.IDENTITY, Vector3(0, -0.015, 0)), _cloth(Color(0.05, 0.04, 0.035), 0.55))
			mb.add_cylinder(0.15, 0.15, 0.01, Vector3(0, -0.02, 0), _cloth(Color(0.05, 0.04, 0.035), 0.55), 24)
		"cap":
			var tone: Array[Color] = [Color(0.22, 0.19, 0.15), Color(0.16, 0.15, 0.14), Color(0.28, 0.24, 0.18)]
			var c := _cloth(tone[rng.randi() % tone.size()], 0.95)
			var crown := SphereMesh.new()
			crown.radius = 0.118
			crown.height = 0.1
			crown.is_hemisphere = true
			mb.add_mesh(crown, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 1.08)), Vector3(0, -0.035, 0.012)), c)
			# (Faces look along -Z: the peak goes there, dipping a little.)
			mb.add_box(Vector3(0.17, 0.012, 0.075), Vector3(0, -0.035, -0.125), c, Basis(Vector3.RIGHT, -0.15))
		"helmet":
			var navy := _cloth(Color(0.03, 0.04, 0.09), 0.7)
			var dome := SphereMesh.new()
			dome.radius = 0.112
			dome.height = 0.34
			mb.add_mesh(dome, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), navy)
			mb.add_cylinder(0.13, 0.13, 0.012, Vector3(0, -0.06, 0), navy, 24)
			mb.add_box(Vector3(0.06, 0.07, 0.01), Vector3(0, 0.02, -0.11), _cloth(Color(0.75, 0.75, 0.78), 0.3))
		"bonnet":
			# A lady's small hat: straw or felt, a shallow crown, a narrow brim and a ribbon,
			# worn tipped forward.
			var straw := rng.randf() < 0.5
			var c := _cloth(Color(0.74, 0.62, 0.4) if straw else [Color(0.08, 0.08, 0.08), Color(0.12, 0.2, 0.14), Color(0.3, 0.1, 0.12)][rng.randi() % 3], 0.9)
			var ribbon := _cloth([Color(0.35, 0.05, 0.1), Color(0.05, 0.1, 0.3), Color(0.06, 0.06, 0.06)][rng.randi() % 3], 0.5)
			var tip := Basis(Vector3.RIGHT, -0.18)
			mb.add_cylinder(0.075, 0.085, 0.07, Vector3(0, 0.005, -0.01), c, 20, tip)
			mb.add_cylinder(0.14, 0.14, 0.01, Vector3(0, -0.03, -0.012), c, 24, tip)
			mb.add_cylinder(0.087, 0.087, 0.022, Vector3(0, -0.012, -0.011), ribbon, 20, tip)
	return mb.build()


## A long, full skirt from the waist to the ground, hung from the pelvis: gathered at the
## waist into soft folds that open out towards a gently uneven hem, with a waistband.
static func _skirt_mesh(waist_y: float, colour: Color) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var seg := 64
	var length := waist_y - 0.03
	var folds := 18.0
	for r in rings + 1:
		var t := float(r) / rings
		for k in seg + 1:
			var a := TAU * k / seg
			# Fuller behind (+Z: a Victorian skirt), folds deepening towards the hem.
			var back := 1.0 + 0.18 * maxf(sin(a), 0.0) * t
			var fold := 1.0 + (0.025 + 0.07 * t) * sin(a * folds + sin(a * 3.0) * 0.8)
			var rad := lerpf(0.16, 0.43, pow(t, 1.25)) * back * fold
			var hem := 0.02 * sin(a * 5.0 + 1.3) * t * t
			st.set_uv(Vector2(float(k) / seg * 5.0, t * 3.0))
			st.add_vertex(Vector3(cos(a) * rad * 1.06, -t * length + hem, sin(a) * rad))
	for r in rings:
		for k in seg:
			var i0 := r * (seg + 1) + k
			var j0 := i0 + seg + 1
			for idx in [i0, j0, i0 + 1, i0 + 1, j0, j0 + 1]:
				st.add_index(idx)
	st.generate_normals()
	var m := _cloth(colour, 0.8).duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	var mesh := st.commit()
	# The waistband.
	var mb := MeshBuilder.new()
	mb.add_cylinder(0.168, 0.17, 0.05, Vector3(0, -0.005, 0), _cloth(colour * 0.7, 0.6), 32, Basis.IDENTITY.scaled(Vector3(1.06, 1.0, 1.0)))
	var band := mb.build()
	for sidx in band.get_surface_count():
		(mesh as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, band.surface_get_arrays(sidx))
		(mesh as ArrayMesh).surface_set_material(mesh.get_surface_count() - 1, band.surface_get_material(sidx))
	return mesh
