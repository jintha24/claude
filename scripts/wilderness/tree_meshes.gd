class_name TreeMeshes
extends RefCounted
## Shared meshes for the countryside, built once: a broadleaf (oak or beech) and a Scots
## pine, each in a detailed version (near) and a cheap one (far), and a grass tuft.
## All foliage sways in the wind (global shader parameter `wind_strength`).

static var _meshes: Dictionary = {}


static func prepare() -> void:
	if not _meshes.is_empty():
		return
	_meshes["broadleaf"] = _broadleaf(false)
	_meshes["broadleaf_far"] = _broadleaf(true)
	_meshes["pine"] = _pine(false)
	_meshes["pine_far"] = _pine(true)
	_meshes["grass"] = _grass()


## kind 0 = broadleaf, 1 = pine.
static func get_mesh(kind: int, far: bool) -> Mesh:
	prepare()
	var key := ("broadleaf" if kind == 0 else "pine") + ("_far" if far else "")
	return _meshes[key]


static func grass_tuft() -> Mesh:
	prepare()
	return _meshes["grass"]


static func _bark() -> Material:
	return MaterialLibrary.get_tinted("rock", Color(0.42, 0.34, 0.26))


static func _broadleaf(far: bool) -> Mesh:
	var mb := MeshBuilder.new()
	var h := 13.0
	mb.add_cylinder(0.24, 0.42, h * 0.5, Vector3(0, h * 0.25, 0), _bark(), 5 if far else 10)
	var leaf := Color(0.26, 0.38, 0.15)
	if far:
		var m := StandardMaterial3D.new()
		m.albedo_color = leaf * 0.9
		m.roughness = 0.9
		var s := SphereMesh.new()
		s.radius = h * 0.3
		s.height = h * 0.45
		s.radial_segments = 8
		s.rings = 4
		mb.add_mesh(s, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.68, 0)), m)
		return mb.build()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for k in 5:
		var a := TAU * k / 5.0
		var tip := Vector3(cos(a) * 2.6, h * 0.62, sin(a) * 2.6)
		var from := Vector3(0, h * 0.42, 0)
		var d := tip - from
		mb.add_cylinder(0.07, 0.16, d.length(), from + d * 0.5, _bark(), 6, Basis(Vector3.UP.cross(d.normalized()).normalized(), Vector3.UP.angle_to(d.normalized())))
	for k in 5:
		var off := Vector3(rng.randf_range(-2.0, 2.0), h * 0.68 + rng.randf_range(-1.0, 1.6), rng.randf_range(-2.0, 2.0))
		Foliage.add_crown(mb, off, Vector3(2.8, 2.2, 2.8), 60, 1.8, leaf, 400 + k)
	return mb.build()


static func _pine(far: bool) -> Mesh:
	var mb := MeshBuilder.new()
	var h := 16.0
	mb.add_cylinder(0.18, 0.34, h * 0.8, Vector3(0, h * 0.4, 0), _bark(), 5 if far else 8)
	var needle := Color(0.14, 0.24, 0.13)
	var mat: Material
	if far:
		var m := StandardMaterial3D.new()
		m.albedo_color = needle
		m.roughness = 0.9
		mat = m
		for k in 2:
			var t := float(k) / 2.0
			mb.add_cylinder(lerpf(3.0, 1.0, t), 0.2, 7.0, Vector3(0, h * (0.5 + 0.45 * t) - 1.5, 0), mat, 8)
		return mb.build()
	# Scots pine: a flat-topped crown of needle clusters on the upper trunk.
	for k in 6:
		var t := float(k) / 6.0
		Foliage.add_crown(mb, Vector3(0, h * (0.62 + 0.36 * t), 0), Vector3(lerpf(2.8, 1.2, t), 1.0, lerpf(2.8, 1.2, t)), 34, 1.5, needle, 500 + k)
	return mb.build()


## Three crossed blades-cards with a cut-out blade pattern, swaying in the wind.
static func _grass() -> Mesh:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
global uniform float wind_strength;
varying float blade_h;
void vertex() {
	blade_h = UV.y;
	vec3 o = NODE_POSITION_WORLD + VERTEX;
	float sway = sin(TIME * 2.1 + o.x * 0.6 + o.z * 0.4) * (0.06 + 0.2 * wind_strength);
	VERTEX.x += sway * (1.0 - UV.y);
	VERTEX.z += sway * 0.5 * (1.0 - UV.y);
}
uniform sampler2D blades : filter_linear_mipmap;
void fragment() {
	float a = texture(blades, UV).r;
	if (a < 0.5) {
		discard;
	}
	float h = 1.0 - UV.y;
	// (Toned to the turf they grow from, so tufts read as grass, not pale cards.)
	vec3 base = vec3(0.045, 0.075, 0.025);
	vec3 tip = vec3(0.17, 0.22, 0.075) * (0.85 + 0.3 * texture(blades, UV * vec2(3.0, 0.2)).g);
	ALBEDO = mix(base, tip, h);
	ROUGHNESS = 0.95;
	SPECULAR = 0.05; // no sky sheen off the upright cards
	// Lit like the ground they grow from, not like upright cards facing the sun or moon.
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.8));
	BACKLIGHT = vec3(0.08, 0.1, 0.03);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("blades", _blade_texture())
	var mb := MeshBuilder.new()
	for k in 3:
		var q := QuadMesh.new()
		q.size = Vector2(0.7, 0.45)
		mb.add_mesh(q, Transform3D(Basis(Vector3.UP, PI * k / 3.0), Vector3(0, 0.22, 0)), mat)
	return mb.build()


## Tapering, slightly curved blades of grass (R = coverage, G = per-blade shade).
static func _blade_texture() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 34:
		var x0 := rng.randf_range(4.0, n - 4.0)
		var top := rng.randf_range(n * 0.05, n * 0.55)
		var lean := rng.randf_range(-18.0, 18.0)
		var w0 := rng.randf_range(1.6, 3.2)
		var shade := rng.randf()
		var steps := int(n - top)
		for s in steps:
			var t := float(s) / steps # 0 at the root, 1 at the tip
			var y := n - 1 - s
			var cx := x0 + lean * t * t
			var w := w0 * (1.0 - t)
			for x in range(int(cx - w - 1.0), int(cx + w + 1.0) + 1):
				if x >= 0 and x < n and absf(x - cx) <= w + 0.5:
					img.set_pixel(x, y, Color(1.0, shade, 0.0, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
