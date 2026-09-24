class_name MaterialLibrary
extends RefCounted
## Central place where every world material is created.
##
## For each material the library first looks for real photo-scanned textures in
## res://assets/textures/<folder>/ (unzipped straight from Poly Haven or ambientCG,
## no renaming needed). If the folder has no textures yet, it falls back to the
## procedural textures from ProceduralTextures so the game always works.
##
## Mapping modes:
##   "world"  - world-space triplanar. Used for static architecture so textures keep
##              a real-world scale on walls of any size and never stretch.
##   "local"  - object-space triplanar. Used for movable props (crates, barrels).
##   "uv"     - normal mesh UVs. Used for the road so parallax (height) mapping works.

const TEXTURE_ROOT := "res://assets/textures"

## tile_proc: real-world size (m) covered by one repeat of the procedural texture (x, y).
## tile_real: real-world size (m) covered by one repeat of a downloaded texture.
const DEFS := {
	"brick_yellow": {"tile_proc": Vector2(0.9, 0.6), "tile_real": 1.5, "mode": "world"},
	"brick_red": {"tile_proc": Vector2(0.9, 0.6), "tile_real": 1.5, "mode": "world"},
	"stucco": {"tile_proc": Vector2(3.0, 3.0), "tile_real": 2.0, "mode": "world"},
	"stone_trim": {"tile_proc": Vector2(2.0, 2.0), "tile_real": 2.0, "mode": "world"},
	"slate_roof": {"tile_proc": Vector2(1.0, 1.0), "tile_real": 2.0, "mode": "uv"},
	"cobblestone": {"tile_proc": Vector2(1.0, 1.0), "tile_real": 2.0, "mode": "uv", "parallax": 0.6},
	"pavement": {"tile_proc": Vector2(2.0, 2.0), "tile_real": 2.0, "mode": "world"},
	"curb_granite": {"tile_proc": Vector2(1.0, 1.0), "tile_real": 1.0, "mode": "world"},
	"wood_planks": {"tile_proc": Vector2(1.0, 1.0), "tile_real": 1.5, "mode": "world"},
	"wood_planks_local": {"folder": "wood_planks", "tile_proc": Vector2(1.0, 1.0), "tile_real": 1.5, "mode": "local"},
	"wood_painted": {"tile_proc": Vector2(1.0, 1.0), "tile_real": 1.0, "mode": "world"},
}

static var _cache: Dictionary = {}


## Returns a shared material. Call get_tinted() for coloured variants.
static func get_material(key: String) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat: StandardMaterial3D
	match key:
		"glass":
			mat = _glass()
		"iron":
			mat = _simple(Color(0.035, 0.035, 0.035), 0.45, 0.75)
		"brass":
			mat = _simple(Color(0.78, 0.6, 0.3), 0.3, 1.0)
		"terracotta":
			mat = _simple(Color(0.55, 0.29, 0.19), 0.85, 0.0)
		"canvas":
			mat = _simple(Color(0.45, 0.4, 0.32), 0.95, 0.0)
		"lamp_glass":
			mat = _lamp_glass()
		"gilt_letters":
			mat = _simple(Color(0.85, 0.66, 0.3), 0.35, 1.0)
		_:
			mat = _textured(key)
	_cache[key] = mat
	return mat


## A copy of a textured material multiplied by a colour (e.g. painted woodwork).
static func get_tinted(key: String, tint: Color) -> StandardMaterial3D:
	var cache_key := "%s#%s" % [key, tint.to_html(false)]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var mat: StandardMaterial3D = get_material(key).duplicate()
	mat.albedo_color = tint
	_cache[cache_key] = mat
	return mat


## Material for a flat mesh whose UVs span `size_m` metres (used by the road).
static func get_for_uv_plane(key: String, size_m: Vector2) -> StandardMaterial3D:
	var cache_key := "%s@%s" % [key, str(size_m)]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var mat: StandardMaterial3D = get_material(key).duplicate()
	var tile: Vector2 = mat.get_meta("tile_size", Vector2.ONE)
	mat.uv1_scale = Vector3(size_m.x / tile.x, size_m.y / tile.y, 1.0)
	_cache[cache_key] = mat
	return mat


static func _textured(key: String) -> StandardMaterial3D:
	var def: Dictionary = DEFS.get(key, {"tile_proc": Vector2.ONE, "tile_real": 1.0, "mode": "world"})
	var folder: String = def.get("folder", key)
	var mat := StandardMaterial3D.new()
	mat.resource_name = key
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var tile: Vector2
	var real := _find_downloaded(folder)
	if not real.is_empty():
		var t: float = def["tile_real"]
		tile = Vector2(t, t)
		mat.albedo_texture = real["albedo"]
		if real.has("normal"):
			mat.normal_enabled = true
			mat.normal_texture = real["normal"]
		if real.has("roughness"):
			mat.roughness_texture = real["roughness"]
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if real.has("ao"):
			mat.ao_enabled = true
			mat.ao_texture = real["ao"]
			mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if real.has("height"):
			mat.set_meta("height_texture", real["height"])
	else:
		tile = def["tile_proc"]
		var set := ProceduralTextures.get_set(key if not def.has("folder") else folder)
		mat.albedo_texture = set["albedo"]
		mat.normal_enabled = true
		mat.normal_texture = set["normal"]
		mat.normal_scale = 1.0
		mat.roughness_texture = set["orm"]
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.ao_enabled = true
		mat.ao_texture = set["orm"]
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.set_meta("height_texture", set["height"])
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.ao_light_affect = 0.4
	mat.set_meta("tile_size", tile)

	match def["mode"]:
		"world", "local":
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = def["mode"] == "world"
			mat.uv1_triplanar_sharpness = 4.0
			mat.uv1_scale = Vector3(1.0 / tile.x, 1.0 / tile.y, 1.0 / tile.x)
		"uv":
			if def.has("parallax") and mat.has_meta("height_texture"):
				mat.heightmap_enabled = true
				mat.heightmap_texture = mat.get_meta("height_texture")
				mat.heightmap_scale = def["parallax"]
				mat.heightmap_deep_parallax = true
				mat.heightmap_min_layers = 8
				mat.heightmap_max_layers = 24
	return mat


## Looks for textures downloaded from Poly Haven or ambientCG in the given folder.
## Recognises both naming schemes, e.g. "red_brick_03_diff_2k.jpg" / "Bricks076_2K-JPG_Color.jpg".
static func _find_downloaded(folder: String) -> Dictionary:
	var dir_path := "%s/%s" % [TEXTURE_ROOT, folder]
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return {}
	var found := {}
	for raw_name in dir.get_files():
		# In an exported game only the ".import" stubs are listed, so strip that suffix.
		var file_name := raw_name.trim_suffix(".import").trim_suffix(".remap")
		var lower := file_name.to_lower()
		if not (lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".png") or lower.ends_with(".webp") or lower.ends_with(".exr")):
			continue
		var path := "%s/%s" % [dir_path, file_name]
		if not ResourceLoader.exists(path):
			continue
		var slot := ""
		if lower.contains("_diff") or lower.contains("color") or lower.contains("albedo") or lower.contains("basecolor"):
			slot = "albedo"
		elif lower.contains("nor_gl") or lower.contains("normalgl") or (lower.contains("normal") and not lower.contains("dx")):
			slot = "normal"
		elif lower.contains("rough"):
			slot = "roughness"
		elif lower.contains("_ao") or lower.contains("ambientocclusion") or lower.contains("occlusion"):
			slot = "ao"
		elif lower.contains("disp") or lower.contains("height"):
			slot = "height"
		if slot != "" and not found.has(slot):
			found[slot] = load(path)
	if not found.has("albedo"):
		return {}
	return found


static func _simple(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


## Old crown glass: dark interior behind, very smooth, reflects the street (SSR + sky).
static func _glass() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "glass"
	mat.albedo_color = Color(0.045, 0.05, 0.055)
	mat.roughness = 0.04
	mat.metallic = 0.25
	mat.metallic_specular = 0.9
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.02
	return mat


## Glowing glass panes of a lit gas lantern.
static func _lamp_glass() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "lamp_glass"
	mat.albedo_color = Color(1.0, 0.85, 0.6)
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.68, 0.36)
	mat.emission_energy_multiplier = 6.0
	return mat
