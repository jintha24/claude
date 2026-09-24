class_name ProceduralTextures
extends RefCounted
## Generates tileable PBR texture sets (albedo, normal, ORM) in code.
##
## These are the FALLBACK textures used until you download the real photo-scanned
## textures from Poly Haven / ambientCG (see docs/ASSETS.md). Every set is seamless,
## has mipmaps, and is cached to user://texture_cache so it is only generated once.
##
## ORM texture layout (same as glTF): R = ambient occlusion, G = roughness, B = metallic.

const CACHE_DIR := "user://texture_cache"
const CACHE_VERSION := 3
const SIZE := 512

## Returns {"albedo": Texture2D, "normal": Texture2D, "orm": Texture2D, "height": Texture2D}
static func get_set(kind: String) -> Dictionary:
	var cached := _load_cached(kind)
	if not cached.is_empty():
		return cached
	var images: Dictionary
	match kind:
		"brick_yellow":
			images = _brick(Color(0.62, 0.53, 0.38), Color(0.55, 0.53, 0.49), 11)
		"brick_red":
			images = _brick(Color(0.50, 0.24, 0.17), Color(0.58, 0.56, 0.52), 23)
		"cobblestone":
			images = _setts()
		"pavement":
			images = _flagstones()
		"curb_granite":
			images = _granite()
		"slate_roof":
			images = _slates()
		"stucco":
			images = _render(Color(0.80, 0.76, 0.67), 0.88, 31)
		"stone_trim":
			images = _render(Color(0.74, 0.72, 0.67), 0.82, 47)
		"wood_planks":
			images = _planks(Color(0.42, 0.31, 0.21))
		"wood_painted":
			images = _render(Color(0.92, 0.92, 0.92), 0.55, 59)
		"grass":
			images = _render(Color(0.22, 0.31, 0.12), 0.95, 71)
		"gravel":
			images = _render(Color(0.62, 0.57, 0.47), 0.95, 83)
		"plaster":
			images = _render(Color(0.9, 0.87, 0.8), 0.9, 97)
		"marble":
			images = _render(Color(0.9, 0.89, 0.86), 0.2, 101)
		"floorboards":
			images = _planks(Color(0.34, 0.2, 0.1))
		_:
			images = _render(Color(0.5, 0.5, 0.5), 0.8, 1)
	_save_cached(kind, images)
	return _to_textures(images)


# --------------------------------------------------------------------------
# Generators. Each returns {"albedo": Image, "height": Image, "orm": Image}
# --------------------------------------------------------------------------

## Stock bricks in stretcher bond. Tile = 4 bricks wide x 8 courses (0.9 m x 0.6 m).
static func _brick(base: Color, mortar: Color, seed_value: int) -> Dictionary:
	var s := SIZE
	var bricks_x := 4
	var rows := 8
	var bw := s / bricks_x
	var bh := s / rows
	var mortar_x := 6
	var mortar_y := 8
	var grime := _noise(seed_value, 0.012, 4)
	var fine := _noise(seed_value + 1, 0.12, 2)
	var albedo := PackedByteArray()
	var height := PackedByteArray()
	var orm := PackedByteArray()
	albedo.resize(s * s * 3)
	height.resize(s * s)
	orm.resize(s * s * 3)
	for y in s:
		var row := y / bh
		var ly := y % bh
		var offset := (row % 2) * (bw / 2)
		for x in s:
			var i := y * s + x
			var xx := (x + offset) % s
			var col := xx / bw
			var lx := xx % bw
			var g := grime[i] / 255.0
			var f := fine[i] / 255.0
			var c: Color
			var h: float
			var rough: float
			var ao: float
			if lx < mortar_x or ly < mortar_y:
				c = mortar * (0.85 + 0.2 * f)
				c = c.lerp(Color(0.2, 0.19, 0.18), g * 0.35)
				h = 0.15 + 0.1 * f
				rough = 0.95
				ao = 0.55
			else:
				var r := _hash(col, row, seed_value)
				var r2 := _hash(col, row, seed_value + 7)
				c = base * (0.78 + 0.4 * r)
				if r2 > 0.9:
					c = c.darkened(0.35) # over-fired "burnt" brick
				elif r2 < 0.12:
					c = c.lerp(Color(0.72, 0.42, 0.26), 0.35)
				c = c * (0.9 + 0.2 * f)
				c = c.lerp(Color(0.16, 0.15, 0.14), g * 0.45) # soot and city grime
				var edge := minf(minf(float(lx - mortar_x), float(bw - 1 - lx)), minf(float(ly - mortar_y), float(bh - 1 - ly)))
				var bevel := clampf(edge / 5.0, 0.0, 1.0)
				h = 0.55 + 0.3 * bevel + 0.15 * f
				rough = 0.8 + 0.12 * f
				ao = 0.8 + 0.2 * bevel
			_put_rgb(albedo, i, c)
			height[i] = int(clampf(h, 0.0, 1.0) * 255.0)
			_put_rgb(orm, i, Color(ao, rough, 0.0))
	return _pack(albedo, height, orm)


## Granite setts (Victorian road surface). Tile = 1 m x 1 m, 4 setts x 8 rows.
static func _setts() -> Dictionary:
	var s := SIZE
	var per_row := 4
	var rows := 8
	var bw := s / per_row
	var bh := s / rows
	var speckle := _noise(71, 0.35, 1)
	var dirt := _noise(72, 0.02, 3)
	var albedo := PackedByteArray()
	var height := PackedByteArray()
	var orm := PackedByteArray()
	albedo.resize(s * s * 3)
	height.resize(s * s)
	orm.resize(s * s * 3)
	for y in s:
		var row := y / bh
		var ly := y % bh
		var offset := int(_hash(row, 3, 71) * float(bw))
		for x in s:
			var i := y * s + x
			var xx := (x + offset) % s
			var col := xx / bw
			var lx := xx % bw
			var sp := speckle[i] / 255.0
			var d := dirt[i] / 255.0
			var joint_l := 4 + int(_hash(col, row, 5) * 5.0)
			var joint_t := 4 + int(_hash(col, row, 6) * 5.0)
			var c: Color
			var h: float
			var rough: float
			var ao: float
			if lx < joint_l or ly < joint_t:
				c = Color(0.16, 0.13, 0.10) * (0.8 + 0.4 * d)
				h = 0.05 + 0.1 * d
				rough = 0.97
				ao = 0.35
			else:
				var r := _hash(col, row, 71)
				var tint := Color(0.42, 0.40, 0.38).lerp(Color(0.46, 0.38, 0.34), _hash(col, row, 9))
				c = tint * (0.75 + 0.45 * r) * (0.85 + 0.3 * sp)
				c = c.lerp(Color(0.2, 0.17, 0.13), d * 0.3)
				var ex := minf(float(lx - joint_l), float(bw - 1 - lx)) / 18.0
				var ey := minf(float(ly - joint_t), float(bh - 1 - ly)) / 14.0
				var dome := 1.0 - pow(1.0 - clampf(minf(ex, ey), 0.0, 1.0), 2.0)
				var tilt := (float(lx) / float(bw) - 0.5) * (_hash(col, row, 13) - 0.5) * 0.25
				h = 0.35 + 0.55 * dome + tilt + 0.05 * sp
				rough = lerpf(0.72, 0.48, dome) # tops are polished by wheels and boots
				ao = 0.7 + 0.3 * dome
			_put_rgb(albedo, i, c)
			height[i] = int(clampf(h, 0.0, 1.0) * 255.0)
			_put_rgb(orm, i, Color(ao, rough, 0.0))
	return _pack(albedo, height, orm)


## York stone paving flags. Tile = 2 m x 2 m, 4 rows of 2 slabs with random offsets.
static func _flagstones() -> Dictionary:
	var s := SIZE
	var rows := 4
	var bh := s / rows
	var bw := s / 2
	var n := _noise(81, 0.04, 4)
	var grain := _noise(82, 0.25, 1)
	var albedo := PackedByteArray()
	var height := PackedByteArray()
	var orm := PackedByteArray()
	albedo.resize(s * s * 3)
	height.resize(s * s)
	orm.resize(s * s * 3)
	for y in s:
		var row := y / bh
		var ly := y % bh
		var offset := int(_hash(row, 1, 81) * float(bw))
		for x in s:
			var i := y * s + x
			var xx := (x + offset) % s
			var col := xx / bw
			var lx := xx % bw
			var nn := n[i] / 255.0
			var gg := grain[i] / 255.0
			var c: Color
			var h: float
			var rough: float
			var ao: float
			if lx < 3 or ly < 3:
				c = Color(0.18, 0.16, 0.14)
				h = 0.1
				rough = 0.95
				ao = 0.45
			else:
				var r := _hash(col, row, 81)
				c = Color(0.56, 0.53, 0.47) * (0.8 + 0.3 * r) * (0.88 + 0.24 * gg)
				c = c.lerp(Color(0.25, 0.23, 0.2), nn * 0.35)
				var edge := clampf(minf(minf(float(lx - 3), float(bw - 1 - lx)), minf(float(ly - 3), float(bh - 1 - ly))) / 4.0, 0.0, 1.0)
				h = 0.6 + 0.25 * edge + 0.15 * gg + (r - 0.5) * 0.1
				rough = 0.78 + 0.15 * gg
				ao = 0.75 + 0.25 * edge
			_put_rgb(albedo, i, c)
			height[i] = int(clampf(h, 0.0, 1.0) * 255.0)
			_put_rgb(orm, i, Color(ao, rough, 0.0))
	return _pack(albedo, height, orm)


## Speckled grey granite used for kerbs and steps.
static func _granite() -> Dictionary:
	var s := SIZE
	var speck := _noise(91, 0.5, 1)
	var cloud := _noise(92, 0.03, 3)
	var albedo := PackedByteArray()
	var height := PackedByteArray()
	var orm := PackedByteArray()
	albedo.resize(s * s * 3)
	height.resize(s * s)
	orm.resize(s * s * 3)
	for i in s * s:
		var sp := speck[i] / 255.0
		var cl := cloud[i] / 255.0
		var c := Color(0.47, 0.46, 0.45) * (0.75 + 0.5 * sp)
		if sp > 0.78:
			c = Color(0.15, 0.14, 0.14)
		elif sp < 0.18:
			c = Color(0.72, 0.66, 0.62)
		c = c.lerp(Color(0.22, 0.2, 0.18), cl * 0.3)
		_put_rgb(albedo, i, c)
		height[i] = int((0.5 + 0.3 * sp) * 255.0)
		_put_rgb(orm, i, Color(1.0, 0.55 + 0.2 * cl, 0.0))
	return _pack(albedo, height, orm)


## Welsh slate roof. Tile = 1 m x 1 m, 4 slates across x 4 courses.
static func _slates() -> Dictionary:
	var s := SIZE
	var per_row := 4
	var rows := 4
	var bw := s / per_row
	var bh := s / rows
	var n := _noise(101, 0.08, 3)
	var albedo := PackedByteArray()
	var height := PackedByteArray()
	var orm := PackedByteArray()
	albedo.resize(s * s * 3)
	height.resize(s * s)
	orm.resize(s * s * 3)
	for y in s:
		var row := y / bh
		var ly := y % bh
		var offset := (row % 2) * (bw / 2)
		for x in s:
			var i := y * s + x
			var xx := (x + offset) % s
			var col := xx / bw
			var lx := xx % bw
			var nn := n[i] / 255.0
			var r := _hash(col, row, 101)
			var c := Color(0.20, 0.21, 0.23) * (0.75 + 0.5 * r) * (0.9 + 0.2 * nn)
			var t := float(ly) / float(bh)
			var h := 0.25 + 0.7 * t + 0.05 * nn
			var rough := 0.5 + 0.2 * nn
			var ao := 0.55 + 0.45 * t
			if lx < 3:
				c = Color(0.05, 0.05, 0.06)
				h = 0.05
				ao = 0.3
			if ly > bh - 4:
				c = c.lightened(0.08) # the thick bottom edge catches light
			_put_rgb(albedo, i, c)
			height[i] = int(clampf(h, 0.0, 1.0) * 255.0)
			_put_rgb(orm, i, Color(ao, rough, 0.0))
	return _pack(albedo, height, orm)


## Lime render / painted stucco / Portland stone: smooth surface with stains.
static func _render(base: Color, roughness: float, seed_value: int) -> Dictionary:
	var s := SIZE
	var stain := _noise(seed_value, 0.01, 4)
	var mid := _noise(seed_value + 1, 0.05, 3)
	var fine := _noise(seed_value + 2, 0.3, 1)
	var albedo := PackedByteArray()
	var height := PackedByteArray()
	var orm := PackedByteArray()
	albedo.resize(s * s * 3)
	height.resize(s * s)
	orm.resize(s * s * 3)
	for i in s * s:
		var st := stain[i] / 255.0
		var m := mid[i] / 255.0
		var f := fine[i] / 255.0
		var c := base * (0.92 + 0.12 * m) * (0.95 + 0.1 * f)
		c = c.lerp(Color(0.3, 0.28, 0.25), maxf(st - 0.45, 0.0) * 0.8)
		_put_rgb(albedo, i, c)
		height[i] = int((0.5 + 0.25 * m + 0.25 * f) * 255.0)
		_put_rgb(orm, i, Color(1.0, clampf(roughness + 0.08 * (f - 0.5), 0.0, 1.0), 0.0))
	return _pack(albedo, height, orm)


## Weathered timber planks running along X. Tile = 1 m, 4 planks.
static func _planks(base: Color) -> Dictionary:
	var s := SIZE
	var planks := 4
	var ph := s / planks
	var n := _noise(111, 0.06, 3)
	var albedo := PackedByteArray()
	var height := PackedByteArray()
	var orm := PackedByteArray()
	albedo.resize(s * s * 3)
	height.resize(s * s)
	orm.resize(s * s * 3)
	for y in s:
		var plank := y / ph
		var ly := y % ph
		var r := _hash(plank, 0, 111)
		for x in s:
			var i := y * s + x
			var nn := n[i] / 255.0
			var grain := 0.5 + 0.5 * sin((float(ly) + nn * 24.0 + r * 50.0) * 0.55)
			var c := base * (0.75 + 0.4 * r) * (0.82 + 0.25 * grain)
			c = c.lerp(Color(0.45, 0.43, 0.4), nn * 0.35) # silvery weathering
			var h := 0.6 + 0.2 * grain
			var ao := 1.0
			if ly < 4:
				c = Color(0.08, 0.06, 0.05)
				h = 0.1
				ao = 0.4
			_put_rgb(albedo, i, c)
			height[i] = int(clampf(h, 0.0, 1.0) * 255.0)
			_put_rgb(orm, i, Color(ao, 0.75 + 0.15 * grain, 0.0))
	return _pack(albedo, height, orm)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

## Returns a seamless noise image as raw bytes (one byte per pixel).
static func _noise(seed_value: int, frequency: float, octaves: int) -> PackedByteArray:
	var fnl := FastNoiseLite.new()
	fnl.seed = seed_value
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = frequency
	fnl.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	fnl.fractal_octaves = octaves
	var img := fnl.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _hash(x: int, y: int, s: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + s * 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func _put_rgb(buf: PackedByteArray, i: int, c: Color) -> void:
	var o := i * 3
	buf[o] = int(clampf(c.r, 0.0, 1.0) * 255.0)
	buf[o + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
	buf[o + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)


static func _pack(albedo: PackedByteArray, height: PackedByteArray, orm: PackedByteArray) -> Dictionary:
	var a := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, albedo)
	var h := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, height)
	var n := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, height)
	n.convert(Image.FORMAT_RGBA8)
	n.bump_map_to_normal_map(6.0)
	n.convert(Image.FORMAT_RGB8)
	var o := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, orm)
	return {"albedo": a, "normal": n, "orm": o, "height": h}


static func _to_textures(images: Dictionary) -> Dictionary:
	var result := {}
	for key: String in images:
		var img: Image = images[key]
		img.generate_mipmaps()
		result[key] = ImageTexture.create_from_image(img)
	return result


static func _cache_path(kind: String, map: String) -> String:
	return "%s/%s_v%d_%s.png" % [CACHE_DIR, kind, CACHE_VERSION, map]


static func _load_cached(kind: String) -> Dictionary:
	var images := {}
	for map in ["albedo", "normal", "orm", "height"]:
		var path := _cache_path(kind, map)
		if not FileAccess.file_exists(path):
			return {}
		var img := Image.load_from_file(path)
		if img == null or img.is_empty():
			return {}
		images[map] = img
	return _to_textures(images)


static func _save_cached(kind: String, images: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for map: String in images:
		var img: Image = images[map]
		img.save_png(_cache_path(kind, map))
