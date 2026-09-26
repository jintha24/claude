class_name AnimalLook
extends RefCounted
## The animals' bodies (assets/animals/<species>.glb, made by tools/animals/build_animals.py):
## a sculpted, skinned body on the standard quadruped skeleton (QuadrupedRig walks it),
## its eyes and its hair. Here they get their coats: the model's vertex colours are masks
## (animal.gdshader), and each species has a few real coat colours to pick from by seed.

const DIR := "res://assets/animals/"
## Per species: coats {coat, pale, points, marks, hair, rough}.
const COATS := {
	"horse": [
		{"name": "bay", "coat": Color(0.3, 0.13, 0.05), "pale": Color(0.4, 0.22, 0.12), "points": Color(0.03, 0.025, 0.02), "hair": Color(0.03, 0.025, 0.02), "rough": 0.45},
		{"name": "dark bay", "coat": Color(0.14, 0.07, 0.035), "pale": Color(0.22, 0.12, 0.07), "points": Color(0.025, 0.02, 0.018), "hair": Color(0.02, 0.018, 0.015), "rough": 0.45},
		{"name": "chestnut", "coat": Color(0.42, 0.17, 0.06), "pale": Color(0.5, 0.26, 0.12), "points": Color(0.36, 0.15, 0.06), "hair": Color(0.45, 0.22, 0.09), "rough": 0.45},
		{"name": "black", "coat": Color(0.035, 0.03, 0.03), "pale": Color(0.06, 0.05, 0.045), "points": Color(0.025, 0.022, 0.02), "hair": Color(0.02, 0.018, 0.016), "rough": 0.4},
		{"name": "grey", "coat": Color(0.56, 0.56, 0.54), "pale": Color(0.7, 0.7, 0.68), "points": Color(0.2, 0.2, 0.2), "hair": Color(0.62, 0.62, 0.6), "rough": 0.55},
	],
	"deer": [
		{"name": "red deer", "coat": Color(0.33, 0.18, 0.09), "pale": Color(0.66, 0.54, 0.38), "points": Color(0.05, 0.04, 0.035), "hair": Color(0.3, 0.17, 0.09), "rough": 0.8},
		{"name": "red deer (winter)", "coat": Color(0.22, 0.16, 0.11), "pale": Color(0.6, 0.5, 0.38), "points": Color(0.05, 0.04, 0.035), "hair": Color(0.2, 0.15, 0.1), "rough": 0.85},
	],
	"stag": [
		{"name": "stag", "coat": Color(0.27, 0.16, 0.09), "pale": Color(0.66, 0.55, 0.4), "points": Color(0.05, 0.04, 0.035), "hair": Color(0.15, 0.1, 0.065), "horn": Color(0.55, 0.47, 0.36), "rough": 0.82},
	],
	"fox": [
		{"name": "red fox", "coat": Color(0.6, 0.26, 0.08), "pale": Color(0.72, 0.45, 0.25), "points": Color(0.05, 0.04, 0.035), "marks": Color(0.88, 0.86, 0.82), "hair": Color(0.6, 0.26, 0.08), "rough": 0.75, "hair_strength": 0.3},
	],
	"rabbit": [
		{"name": "wild rabbit", "coat": Color(0.37, 0.3, 0.22), "pale": Color(0.84, 0.82, 0.78), "points": Color(0.06, 0.05, 0.04), "rough": 0.85, "hair_strength": 0.3},
	],
	"dog": [
		{"name": "tan", "coat": Color(0.44, 0.29, 0.15), "pale": Color(0.6, 0.45, 0.3), "points": Color(0.06, 0.05, 0.04), "marks": Color(0.85, 0.83, 0.78), "rough": 0.7},
		{"name": "black and white", "coat": Color(0.04, 0.035, 0.03), "pale": Color(0.08, 0.07, 0.06), "points": Color(0.03, 0.025, 0.02), "marks": Color(0.85, 0.83, 0.8), "rough": 0.6},
		{"name": "brindle", "coat": Color(0.28, 0.19, 0.11), "pale": Color(0.38, 0.28, 0.18), "points": Color(0.05, 0.04, 0.03), "marks": Color(0.6, 0.5, 0.4), "rough": 0.7, "mottle": 0.25},
		{"name": "grey", "coat": Color(0.36, 0.34, 0.31), "pale": Color(0.55, 0.52, 0.48), "points": Color(0.1, 0.09, 0.08), "marks": Color(0.8, 0.78, 0.74), "rough": 0.8},
	],
	"mastiff": [
		{"name": "fawn", "coat": Color(0.58, 0.43, 0.26), "pale": Color(0.68, 0.55, 0.38), "points": Color(0.04, 0.035, 0.03), "marks": Color(0.62, 0.5, 0.35), "rough": 0.6},
		{"name": "brindle", "coat": Color(0.26, 0.19, 0.12), "pale": Color(0.36, 0.28, 0.2), "points": Color(0.03, 0.025, 0.02), "marks": Color(0.3, 0.22, 0.14), "rough": 0.6, "mottle": 0.25},
	],
	"sheep": [
		{"name": "white-faced", "coat": Color(0.76, 0.72, 0.62), "points": Color(0.78, 0.74, 0.68), "pale": Color(0.12, 0.1, 0.09), "rough": 0.95, "hair_strength": 0.45, "hair_scale": 45.0, "dirt": 0.4},
		{"name": "black-faced", "coat": Color(0.74, 0.7, 0.6), "points": Color(0.06, 0.05, 0.05), "pale": Color(0.08, 0.07, 0.06), "rough": 0.95, "hair_strength": 0.45, "hair_scale": 45.0, "dirt": 0.4},
	],
	"cow": [
		{"name": "red shorthorn", "coat": Color(0.4, 0.16, 0.07), "pale": Color(0.48, 0.3, 0.22), "points": Color(0.08, 0.07, 0.06), "marks": Color(0.85, 0.83, 0.78), "horn": Color(0.78, 0.72, 0.6), "hair": Color(0.3, 0.12, 0.05), "rough": 0.75},
		{"name": "roan shorthorn", "coat": Color(0.45, 0.3, 0.24), "pale": Color(0.55, 0.44, 0.38), "points": Color(0.08, 0.07, 0.06), "marks": Color(0.85, 0.83, 0.78), "horn": Color(0.78, 0.72, 0.6), "hair": Color(0.4, 0.28, 0.2), "rough": 0.78},
	],
}

static var _scenes := {}
static var _materials := {}


static func has_species(species: String) -> bool:
	return ResourceLoader.exists(DIR + species + ".glb")


## A body for `species`, its coat picked by `seed` (or `coat`, an index into COATS, if
## >= 0). Null if the model is missing.
static func instantiate(species: String, seed: int, coat: int = -1) -> Node3D:
	var path := DIR + species + ".glb"
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var ps := _scenes[path] as PackedScene
	if ps == null:
		return null
	var model := ps.instantiate() as Node3D
	model.name = "Look"
	var coats: Array = COATS.get(species, [{}])
	var ci := coat if coat >= 0 else absi(seed) % coats.size()
	ci = clampi(ci, 0, coats.size() - 1)
	model.set_meta("species", species)
	model.set_meta("coat", String(coats[ci].get("name", "")))
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var kind := String(src.resource_name) if src else "coat"
			mi.set_surface_override_material(s, _material(species, ci, kind, coats[ci]))
		mi.visibility_range_end = 160.0
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return model


static func _material(species: String, ci: int, kind: String, c: Dictionary) -> Material:
	var key := "%s:%d:%s" % [species, ci, kind]
	if _materials.has(key):
		return _materials[key]
	var m: Material
	match kind:
		"eye":
			var e := StandardMaterial3D.new()
			e.albedo_color = Color(0.05, 0.03, 0.02)
			e.roughness = 0.05
			e.metallic_specular = 0.9
			e.clearcoat_enabled = true
			m = e
		"hair":
			var h := ShaderMaterial.new()
			h.shader = load(DIR + "animal_hair.gdshader")
			h.set_shader_parameter("strands", load(DIR + "hair.png"))
			var hc: Color = c.get("hair", Color(0.05, 0.04, 0.03))
			h.set_shader_parameter("hair", Vector3(hc.r, hc.g, hc.b))
			for p: String in ["coat", "pale", "points", "marks"]:
				if c.has(p):
					var col: Color = c[p]
					h.set_shader_parameter(p, Vector3(col.r, col.g, col.b))
			m = h
		"horn":
			var n := StandardMaterial3D.new()
			n.albedo_color = c.get("horn", Color(0.45, 0.38, 0.28))
			n.roughness = 0.6
			m = n
		_:
			var s := ShaderMaterial.new()
			s.shader = load(DIR + "animal.gdshader")
			for p: String in ["coat", "pale", "points", "marks"]:
				if c.has(p):
					var col: Color = c[p]
					s.set_shader_parameter(p, Vector3(col.r, col.g, col.b))
			s.set_shader_parameter("roughness", c.get("rough", 0.7))
			for p: String in ["hair_scale", "hair_strength", "mottle", "dirt"]:
				if c.has(p):
					s.set_shader_parameter(p, c[p])
			m = s
	_materials[key] = m
	return m
