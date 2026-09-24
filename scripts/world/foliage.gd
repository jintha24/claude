class_name Foliage
extends RefCounted
## Realistic tree crowns the way games build them: dozens of cut-out "leaf cards" (quads
## textured with a cluster of leaves, alpha-tested) scattered through the crown, lit from
## behind by the sun (translucent leaves) and swaying in the wind.
##
## The leaf texture is painted once in code (clusters of pointed ovate leaves in varied
## greens on transparent ground) and cached per colour. Replace it with a photo-scanned
## leaf atlas (see docs/REALISTIC_LOOK.md) for even more realism: drop a PNG with alpha at
## res://assets/textures/foliage/leaves.png.

const TEX_SIZE := 256
const ATLAS_PATH := "res://assets/textures/foliage/leaves.png"

static var _materials: Dictionary = {}
static var _texture: Texture2D


## Shared leaf-card material, tinted `leaf`.
static func material(leaf: Color) -> ShaderMaterial:
	var key := leaf.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
global uniform float wind_strength;
uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
void vertex() {
	vec3 o = NODE_POSITION_WORLD;
	float t = TIME * 1.3 + o.x * 0.37 + o.z * 0.21 + VERTEX.x * 0.4;
	float h = max(VERTEX.y, 0.0) * 0.08;
	VERTEX.x += sin(t) * (0.03 + 0.12 * wind_strength) * h;
	VERTEX.z += cos(t * 1.3) * (0.02 + 0.08 * wind_strength) * h;
}
void fragment() {
	vec4 c = texture(leaves, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * tint * (FRONT_FACING ? 1.0 : 0.8);
	ROUGHNESS = 0.7;
	SPECULAR = 0.3;
	BACKLIGHT = c.rgb * tint * 0.6;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("leaves", leaf_texture())
	mat.set_shader_parameter("tint", Color(leaf.r / 0.3, leaf.g / 0.42, leaf.b / 0.17))
	_materials[key] = mat
	return mat


static func leaf_texture() -> Texture2D:
	if _texture:
		return _texture
	if ResourceLoader.exists(ATLAS_PATH):
		_texture = load(ATLAS_PATH)
		return _texture
	var img := Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.3, 0.12, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1866
	# Twigs first, then about 140 leaves along and around them.
	for k in 6:
		var a := Vector2(rng.randf_range(0.2, 0.8), 1.0) * TEX_SIZE
		var b := Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.05, 0.4)) * TEX_SIZE
		for s in 60:
			var p := a.lerp(b, s / 59.0)
			_disc(img, p, 1.2, Color(0.25, 0.18, 0.1, 1.0))
	for k in 140:
		var p := Vector2(rng.randf_range(0.08, 0.92), rng.randf_range(0.05, 0.95)) * TEX_SIZE
		var length := rng.randf_range(16.0, 26.0)
		var width := length * rng.randf_range(0.38, 0.5)
		var ang := rng.randf() * TAU
		var shade := rng.randf_range(0.7, 1.15)
		var col := Color(0.3 * shade, 0.42 * shade, 0.17 * shade * rng.randf_range(0.8, 1.1), 1.0)
		_leaf(img, p, length, width, ang, col)
	img.generate_mipmaps()
	_texture = ImageTexture.create_from_image(img)
	return _texture


static func _disc(img: Image, p: Vector2, r: float, c: Color) -> void:
	for y in range(int(p.y - r), int(p.y + r) + 1):
		for x in range(int(p.x - r), int(p.x + r) + 1):
			if x >= 0 and y >= 0 and x < TEX_SIZE and y < TEX_SIZE and Vector2(x, y).distance_to(p) <= r:
				img.set_pixel(x, y, c)


## A pointed ovate leaf with a paler midrib, drawn into its bounding box only.
static func _leaf(img: Image, center: Vector2, length: float, width: float, ang: float, c: Color) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var nrm := Vector2(-dir.y, dir.x)
	var r := int(length * 0.5) + 2
	for y in range(int(center.y) - r, int(center.y) + r + 1):
		for x in range(int(center.x) - r, int(center.x) + r + 1):
			if x < 0 or y < 0 or x >= TEX_SIZE or y >= TEX_SIZE:
				continue
			var d := Vector2(x, y) - center
			var u := d.dot(dir) / (length * 0.5) # -1 .. 1 along the leaf
			var v := d.dot(nrm) / (width * 0.5)
			if absf(u) > 1.0:
				continue
			# Widest a third of the way from the stalk, pointed at the tip.
			var half := sin(clampf((u + 1.0) * 0.5, 0.0, 1.0) * PI) * (1.0 - 0.35 * maxf(u, 0.0))
			if absf(v) > half:
				continue
			var col := c * (1.0 + 0.12 * (1.0 - absf(v)))
			if absf(v) < 0.08:
				col = c.lightened(0.25)
			col.a = 1.0
			img.set_pixel(x, y, col)


## Adds a crown of leaf cards to `mb`: `count` quads of `card` metres, scattered through an
## ellipsoid of radii `r` round `center`, facing every which way (seeded).
static func add_crown(mb: MeshBuilder, center: Vector3, r: Vector3, count: int, card: float, leaf: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mat := material(leaf)
	var quad := QuadMesh.new()
	quad.size = Vector2(card, card)
	for i in count:
		# A point inside the ellipsoid, biased to the outer shell (where leaves catch light).
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if d.length() > 1.0:
			d = d.normalized()
		d = d.normalized() * pow(d.length(), 0.4) if d.length() > 0.001 else Vector3.UP
		var p := center + Vector3(d.x * r.x, d.y * r.y, d.z * r.z)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-1.2, 1.2)) * Basis(Vector3.BACK, rng.randf_range(-0.6, 0.6))
		mb.add_mesh(quad, Transform3D(basis, p), mat)
