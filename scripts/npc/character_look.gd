class_name CharacterLook
extends RefCounted
## Realistic people. Each outfit is a model built by tools/characters/build_characters.py
## from the CC0 MakeHuman body (assets/characters/generated/<look>.glb). This dresses an
## instance of one as a particular person, from a seed:
##   * build and face: blend shapes heavy / thin / muscular / old / face_a..c
##   * skin tone, eye colour, hair colour (grey with age), beard style or clean-shaven
##   * garment colours from period palettes for each kind of person, cloth by garment
##   * hat choice where there is one (top hat or bowler, cap or bare-headed)
## Materials are shared between people wherever they end up the same.

const DIR := "res://assets/characters/generated/"
const TEX := "res://assets/characters/textures/"
const LOOKS: Array[String] = ["gentleman", "worker", "ragged", "constable", "house_guard", "priest", "lady", "child", "harry"]

## Skin tints (multiplying the painted skin) and how common they are in 1860s London.
const SKIN_TONES: Array = [
	[Color(1.0, 0.99, 0.98), 30], [Color(0.98, 0.93, 0.89), 30], [Color(1.0, 0.9, 0.86), 16], [Color(0.93, 0.84, 0.76), 10],
	[Color(0.82, 0.7, 0.58), 6], [Color(0.62, 0.47, 0.37), 4], [Color(0.44, 0.32, 0.25), 4],
]
const HAIR_COLOURS: Array[Color] = [Color(0.05, 0.04, 0.035), Color(0.14, 0.09, 0.06), Color(0.28, 0.18, 0.11), Color(0.42, 0.22, 0.1), Color(0.6, 0.47, 0.3), Color(0.2, 0.13, 0.08)]
const EYES: Array[String] = ["eye_brown", "eye_brown", "eye_hazel", "eye_blue", "eye_blue", "eye_grey"]

## Garment palettes: slot -> list of colours.
const PALETTES := {
	"gentleman": {"coat": [Color(0.05, 0.05, 0.055), Color(0.1, 0.1, 0.11), Color(0.07, 0.08, 0.14), Color(0.16, 0.11, 0.08), Color(0.07, 0.12, 0.09)],
		"waistcoat": [Color(0.32, 0.07, 0.08), Color(0.55, 0.42, 0.14), Color(0.35, 0.35, 0.34), Color(0.08, 0.08, 0.08), Color(0.2, 0.26, 0.2)],
		"trousers": [Color(0.42, 0.41, 0.39), Color(0.55, 0.47, 0.36), Color(0.16, 0.16, 0.17), Color(0.28, 0.27, 0.3)],
		"cravat": [Color(0.04, 0.04, 0.04), Color(0.35, 0.05, 0.08), Color(0.06, 0.08, 0.2)], "shirt": [Color(0.93, 0.92, 0.88)],
		"hat": [Color(0.035, 0.035, 0.035)], "hatband": [Color(0.02, 0.02, 0.02)], "boots": [Color(0.04, 0.035, 0.03)], "collar": [Color(0.95, 0.94, 0.9)]},
	"worker": {"shirt": [Color(0.86, 0.84, 0.78), Color(0.62, 0.68, 0.76), Color(0.7, 0.68, 0.62), Color(0.78, 0.72, 0.64)],
		"waistcoat": [Color(0.3, 0.24, 0.17), Color(0.22, 0.22, 0.22), Color(0.1, 0.1, 0.1), Color(0.3, 0.28, 0.2)],
		"trousers": [Color(0.32, 0.24, 0.15), Color(0.28, 0.28, 0.2), Color(0.25, 0.24, 0.23), Color(0.38, 0.32, 0.24)],
		"cap": [Color(0.3, 0.26, 0.2), Color(0.22, 0.22, 0.22), Color(0.15, 0.13, 0.12)],
		"cravat": [Color(0.55, 0.1, 0.08), Color(0.1, 0.15, 0.35), Color(0.15, 0.3, 0.15), Color(0.6, 0.5, 0.15)], "boots": [Color(0.09, 0.07, 0.05)]},
	"ragged": {"shirt": [Color(0.6, 0.57, 0.5), Color(0.5, 0.48, 0.42)], "coat": [Color(0.28, 0.25, 0.2), Color(0.22, 0.22, 0.2), Color(0.3, 0.24, 0.16), Color(0.2, 0.18, 0.16)],
		"trousers": [Color(0.25, 0.22, 0.18), Color(0.2, 0.2, 0.19), Color(0.3, 0.26, 0.2)], "cap": [Color(0.22, 0.2, 0.17), Color(0.15, 0.14, 0.13)],
		"cravat": [Color(0.35, 0.12, 0.1), Color(0.2, 0.2, 0.25)], "boots": [Color(0.12, 0.09, 0.07)]},
	"child": {"shirt": [Color(0.66, 0.63, 0.55), Color(0.55, 0.55, 0.52)], "coat": [Color(0.3, 0.25, 0.18), Color(0.24, 0.22, 0.2), Color(0.18, 0.2, 0.25)],
		"trousers": [Color(0.28, 0.24, 0.18), Color(0.22, 0.2, 0.18)], "cap": [Color(0.25, 0.22, 0.18), Color(0.16, 0.15, 0.14)], "boots": [Color(0.12, 0.09, 0.07)],
		"stockings": [Color(0.12, 0.12, 0.13), Color(0.22, 0.2, 0.18), Color(0.3, 0.3, 0.32)]},
	"constable": {"coat": [Color(0.045, 0.055, 0.11)], "trousers": [Color(0.045, 0.05, 0.1)], "helmet": [Color(0.04, 0.05, 0.1)], "belt": [Color(0.02, 0.02, 0.02)],
		"boots": [Color(0.02, 0.02, 0.02)], "buttons": [Color(0.8, 0.8, 0.82)], "badge": [Color(0.82, 0.82, 0.85)]},
	"house_guard": {"coat": [Color(0.36, 0.06, 0.07)], "trim": [Color(0.78, 0.6, 0.26)], "trousers": [Color(0.08, 0.08, 0.08), Color(0.62, 0.55, 0.42)],
		"shirt": [Color(0.94, 0.93, 0.9)], "hat": [Color(0.3, 0.05, 0.06)], "hatband": [Color(0.05, 0.05, 0.05)], "boots": [Color(0.03, 0.03, 0.03)], "buttons": [Color(0.8, 0.62, 0.28)]},
	"priest": {"cassock": [Color(0.03, 0.03, 0.035)], "collar": [Color(0.95, 0.95, 0.93)], "boots": [Color(0.03, 0.03, 0.03)], "buttons": [Color(0.05, 0.05, 0.05)]},
	"lady": {"dress": [Color(0.25, 0.08, 0.3), Color(0.45, 0.06, 0.1), Color(0.08, 0.28, 0.18), Color(0.08, 0.12, 0.3), Color(0.3, 0.2, 0.12), Color(0.35, 0.36, 0.38), Color(0.15, 0.13, 0.14)],
		"shawl": [Color(0.5, 0.35, 0.22), Color(0.82, 0.78, 0.68), Color(0.35, 0.36, 0.38), Color(0.2, 0.08, 0.1)],
		"bonnet": [Color(0.78, 0.68, 0.46), Color(0.08, 0.08, 0.08), Color(0.12, 0.2, 0.14), Color(0.3, 0.1, 0.12)], "collar": [Color(0.95, 0.94, 0.9)]},
	"harry": {"greatcoat": [Color(0.24, 0.14, 0.085)], "waistcoat": [Color(0.09, 0.15, 0.16)], "trousers": [Color(0.12, 0.12, 0.115)], "shirt": [Color(0.84, 0.82, 0.76)],
		"boots": [Color(0.035, 0.027, 0.02)], "gloves": [Color(0.13, 0.085, 0.05)], "belt": [Color(0.06, 0.04, 0.03)], "cravat": [Color(0.4, 0.07, 0.06)],
		"hat": [Color(0.05, 0.045, 0.04)], "hatband": [Color(0.45, 0.07, 0.06)]},
}

## Which cloth texture each slot uses, and its roughness / metallic.
const SLOTS := {
	"shirt": ["linen", 0.9, 0.0], "stockings": ["wool", 0.95, 0.0], "collar": ["linen", 0.7, 0.0], "waistcoat": ["tweed", 0.85, 0.0], "coat": ["wool", 0.88, 0.0],
	"greatcoat": ["leather", 0.5, 0.0], "cassock": ["wool", 0.9, 0.0], "trousers": ["wool", 0.9, 0.0], "boots": ["leather", 0.38, 0.0],
	"gloves": ["leather", 0.45, 0.0], "belt": ["leather", 0.35, 0.0], "cravat": ["silk", 0.45, 0.0], "shawl": ["wool", 0.95, 0.0],
	"dress": ["silk", 0.5, 0.0], "hat": ["felt", 0.55, 0.0], "hatband": ["silk", 0.4, 0.0], "cap": ["tweed", 0.95, 0.0],
	"helmet": ["felt", 0.6, 0.0], "bonnet": ["felt", 0.8, 0.0], "trim": ["silk", 0.35, 0.8], "buttons": ["", 0.3, 0.9], "badge": ["", 0.25, 1.0],
}
## Pieces only drawn close to (faces), and small ones not drawn far away.
const FINE_DETAIL: Array[String] = ["eyes", "lashes", "teeth"]
const SMALL_DETAIL: Array[String] = ["collar", "cravat", "neckerchief", "cuffs", "belt", "gloves", "hair_bun", "beard_moustache", "beard_chops", "stockings"]
## The pieces that cast shadows (the silhouette); the rest would add draw calls for nothing.
const SHADOW_CASTERS: Array[String] = ["body", "coat", "cassock", "dress", "shawl", "trousers", "hat_top", "hat_bowler", "hat_cap", "hat_helmet", "hat_kepi", "hat_bonnet"]
const MORPHS: Array[String] = ["heavy", "thin", "muscular", "old", "face_a", "face_b", "face_c"]

const FAR_SHADER := "res://assets/characters/far_body.gdshader"
## Cloth textures average about this bright, so a flat colour matches them from afar.
const CLOTH_TONE := 0.78

static var _scenes := {}
static var _far_material: ShaderMaterial
static var _materials := {}
static var _textures := {}


static func has_look(look: String) -> bool:
	return ResourceLoader.exists(DIR + look + ".glb")


## The look for an NPCBody outfit (and height, for children).
static func for_outfit(outfit: int, height: float) -> String:
	if height < 1.55:
		return "child"
	match outfit:
		NPCBody.Outfit.CONSTABLE: return "constable"
		NPCBody.Outfit.GENTLEMAN: return "gentleman"
		NPCBody.Outfit.WORKER: return "worker"
		NPCBody.Outfit.LADY: return "lady"
		NPCBody.Outfit.HOUSE_GUARD: return "house_guard"
		NPCBody.Outfit.PRIEST: return "priest"
		NPCBody.Outfit.RAGGED: return "ragged"
	return "worker"


## A dressed instance of `look`, varied by `seed`. `age` 0..1 (0.5 = the model's own age).
static func instantiate(look: String, seed: int) -> Node3D:
	if not _scenes.has(look):
		_scenes[look] = load(DIR + look + ".glb") as PackedScene
	var packed: PackedScene = _scenes[look]
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	model.name = "Look"
	dress(model, look, seed)
	return model


static func dress(model: Node3D, look: String, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var female := look == "lady"
	var harry := look == "harry"
	# Build and face.
	var morph := {}
	if not harry:
		var build := rng.randf()
		morph["heavy"] = clampf(rng.randf_range(0.2, 1.0), 0.0, 1.0) if build < 0.3 else 0.0
		morph["thin"] = rng.randf_range(0.2, 1.0) if build > 0.72 else 0.0
		morph["muscular"] = rng.randf_range(0.0, 0.8) if look in ["worker", "constable", "house_guard", "ragged"] else rng.randf_range(0.0, 0.3)
		var age := rng.randf()
		morph["old"] = 0.0 if look == "child" else (rng.randf_range(0.4, 1.0) if age > 0.72 else rng.randf_range(0.0, 0.25))
		for f: String in ["face_a", "face_b", "face_c"]:
			morph[f] = rng.randf_range(0.0, 1.0) * rng.randf()
	# Skin, eyes, hair.
	var tone := _pick_weighted(rng, SKIN_TONES) if not harry else Color(0.97, 0.9, 0.84)
	var eye: String = EYES[rng.randi() % EYES.size()] if not harry else "eye_grey"
	var hair: Color = HAIR_COLOURS[rng.randi() % HAIR_COLOURS.size()] if not harry else Color(0.1, 0.065, 0.04)
	if tone.r < 0.7:
		hair = HAIR_COLOURS[0]
	var grey := clampf((float(morph.get("old", 0.0)) - 0.35) * 1.6, 0.0, 0.85)
	hair = hair.lerp(Color(0.62, 0.6, 0.58), grey)
	# Beards (men only), hats.
	var beard := ""
	if harry:
		beard = "chops"
	elif not female and look != "child":
		var r := rng.randf()
		beard = "full" if r < 0.22 else ("chops" if r < 0.4 else ("moustache" if r < 0.62 else ""))
	var hat_choice := ""
	if look == "gentleman":
		hat_choice = "top" if rng.randf() < 0.6 else "bowler"
	elif look == "lady":
		hat_choice = "bonnet" if rng.randf() < 0.6 else ""
	elif look in ["worker", "ragged", "child"]:
		hat_choice = "cap" if rng.randf() < 0.8 else ""
	var palette: Dictionary = PALETTES.get(look, {})
	var colours := {}
	for slot: String in palette:
		var list: Array = palette[slot]
		colours[slot] = list[rng.randi() % list.size()]
	var has_far := model.find_child("far_body", true, false) != null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		for m: String in morph:
			var idx := mi.find_blend_shape_by_name(m)
			if idx >= 0:
				mi.set_blend_shape_value(idx, morph[m])
		if n == "far_body":
			_dress_far(mi, look, colours, tone, hair, beard, hat_choice)
			continue
		# Optional pieces.
		if n.begins_with("beard_"):
			mi.visible = beard != "" and n == "beard_" + beard
		elif n.begins_with("hat_top"):
			mi.visible = look == "harry" or hat_choice == "top"
		elif n.begins_with("hat_bowler"):
			mi.visible = hat_choice == "bowler"
		elif n.begins_with("hat_cap"):
			mi.visible = hat_choice == "cap"
		elif n.begins_with("hat_bonnet"):
			mi.visible = hat_choice == "bonnet"
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var slot := src.resource_name if src else ""
			mi.set_surface_override_material(s, material(slot, look, colours, tone, eye, hair))
		# Each piece is a draw call (and more for shadows): small details stop being drawn
		# well before the person does, only the big pieces cast shadows, and beyond
		# RANGE_NEAR the whole person is the one-piece far body instead.
		var reach := PerfTuning.RANGE_NEAR if has_far else PerfTuning.RANGE_PERSON
		if n in FINE_DETAIL or n.ends_with("_buttons"):
			reach = minf(reach, PerfTuning.RANGE_FACE)
		elif n in SMALL_DETAIL or n.ends_with("_band") or n.ends_with("_peak") or n.ends_with("_plate"):
			reach = minf(reach, PerfTuning.RANGE_SMALL_DETAIL)
		mi.visibility_range_end = reach
		mi.visibility_range_end_margin = 2.0 if has_far and reach == PerfTuning.RANGE_NEAR else reach * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var big := SHADOW_CASTERS.any(func(prefix: String) -> bool: return n.begins_with(prefix))
		if not big or n.ends_with("_band") or n.ends_with("_peak") or n.ends_with("_plate"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The one-piece far body (see far_body.gdshader): this person's colours and the optional
## parts they wear, as instance parameters on a material shared by everyone.
static func _dress_far(mi: MeshInstance3D, look: String, colours: Dictionary, tone: Color, hair: Color, beard: String, hat_choice: String) -> void:
	if _far_material == null:
		_far_material = ShaderMaterial.new()
		_far_material.shader = load(FAR_SHADER) as Shader
	mi.material_override = _far_material
	var pick := func(slots: Array, fallback: Color) -> Color:
		for slot: String in slots:
			if colours.has(slot):
				return colours[slot] * CLOTH_TONE
		return fallback
	var base_skin := Color(0.86, 0.66, 0.56) if look != "child" else Color(0.9, 0.7, 0.6)
	mi.set_instance_shader_parameter("c_skin", base_skin * tone)
	mi.set_instance_shader_parameter("c_hair", hair * 0.8)
	mi.set_instance_shader_parameter("c_primary", pick.call(["coat", "dress", "cassock", "greatcoat"], Color(0.25, 0.22, 0.2)))
	mi.set_instance_shader_parameter("c_secondary", pick.call(["waistcoat", "shawl"], Color(0.3, 0.3, 0.3)))
	mi.set_instance_shader_parameter("c_legs", pick.call(["trousers", "dress"], Color(0.2, 0.2, 0.2)))
	mi.set_instance_shader_parameter("c_dark", pick.call(["boots", "belt"], Color(0.04, 0.03, 0.03)))
	mi.set_instance_shader_parameter("c_linen", pick.call(["shirt", "collar"], Color(0.9, 0.88, 0.84)))
	mi.set_instance_shader_parameter("c_accent", pick.call(["cravat", "trim", "buttons", "badge"], Color(0.4, 0.1, 0.1)))
	mi.set_instance_shader_parameter("c_hat", pick.call(["hat", "cap", "helmet", "bonnet"], Color(0.05, 0.05, 0.05)))
	var mask := 0
	match beard:
		"full": mask |= 1 << 1
		"moustache": mask |= 1 << 2
		"chops": mask |= 1 << 3
	match hat_choice:
		"top": mask |= 1 << 4
		"bowler": mask |= 1 << 5
		"cap": mask |= 1 << 6
		"bonnet": mask |= 1 << 7
	mi.set_instance_shader_parameter("variants", mask)
	mi.visibility_range_begin = PerfTuning.RANGE_NEAR
	mi.visibility_range_begin_margin = 2.0
	mi.visibility_range_end = PerfTuning.RANGE_PERSON
	mi.visibility_range_end_margin = PerfTuning.RANGE_PERSON * 0.1
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _pick_weighted(rng: RandomNumberGenerator, table: Array) -> Color:
	var total := 0
	for row: Array in table:
		total += int(row[1])
	var r := rng.randi() % total
	for row: Array in table:
		r -= int(row[1])
		if r < 0:
			return row[0]
	return table[0][0]


static func _tex(name: String) -> Texture2D:
	if not _textures.has(name):
		var path := TEX + name
		_textures[name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[name]


static func _q(c: Color) -> String:
	return "%02x%02x%02x" % [int(c.r * 40), int(c.g * 40), int(c.b * 40)]


## A material for a slot, shared by everyone who ends up with the same one.
static func material(slot: String, look: String, colours: Dictionary, tone: Color, eye: String, hair: Color) -> Material:
	var key := slot
	match slot:
		"skin": key += ":" + look + _q(tone)
		"eye": key += ":" + eye
		"hair", "beard": key += ":" + _q(hair)
		_: key += ":" + _q(colours.get(slot, Color(0.3, 0.3, 0.3)))
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	match slot:
		"skin":
			var skin := "skin_female" if look == "lady" else ("skin_child" if look == "child" else "skin_male")
			m.albedo_texture = _tex(skin + ".jpg")
			m.albedo_color = tone
			m.roughness = 0.58
			m.metallic_specular = 0.38
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.35
			m.subsurf_scatter_skin_mode = true
			m.rim_enabled = true
			m.rim = 0.12
			m.rim_tint = 0.6
		"eye":
			m.albedo_texture = _tex(eye + ".png")
			m.roughness = 0.08
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
		"lash":
			m.albedo_color = Color(0.03, 0.025, 0.02)
			m.roughness = 0.9
		"teeth":
			m.albedo_color = Color(0.85, 0.82, 0.74)
			m.roughness = 0.35
		"hair", "beard":
			m.albedo_texture = _tex("hair.png")
			m.albedo_color = hair
			m.normal_enabled = true
			m.normal_texture = _tex("hair_n.png")
			m.normal_scale = 0.6
			m.roughness = 0.6
			m.metallic_specular = 0.45
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5 if slot == "beard" else 0.3
			m.vertex_color_use_as_albedo = true # alpha thins out towards hairlines
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			var spec: Array = SLOTS.get(slot, ["wool", 0.85, 0.0])
			m.albedo_color = colours.get(slot, Color(0.3, 0.3, 0.3))
			if spec[0] != "":
				m.albedo_texture = _tex("cloth_%s.jpg" % spec[0])
				m.normal_enabled = true
				m.normal_texture = _tex("cloth_%s_n.png" % spec[0])
				m.normal_scale = 0.35 if spec[0] == "leather" else 0.7
			# Mapped in the model's own space, not along the body's UVs: those are laid out for
			# skin and would stretch the weave over the chest, knees and elbows.
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 5.0
			m.uv1_triplanar_sharpness = 2.0
			m.roughness = spec[1]
			m.metallic = spec[2]
			m.vertex_color_use_as_albedo = true
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = m
	return m
