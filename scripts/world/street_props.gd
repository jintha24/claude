class_name StreetProps
extends RefCounted
## Factory for street clutter: physics crates and barrels, and a costermonger's handcart.
## Crates and barrels are RigidBody3D with real masses so Harry (and later carts) can
## shove them around.

const LAYER_PROPS := 1 << 3
const LAYER_WORLD := 1

static var _wood_on_stone: PhysicsMaterial


## Dry timber sliding on stone setts: friction about 0.5, very little bounce.
static func wood_material() -> PhysicsMaterial:
	if _wood_on_stone == null:
		_wood_on_stone = PhysicsMaterial.new()
		_wood_on_stone.friction = 0.5
		_wood_on_stone.bounce = 0.05
	return _wood_on_stone


static func make_crate(size: float = 0.6) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Crate"
	body.physics_material_override = wood_material()
	body.mass = 22.0 * pow(size / 0.6, 3.0)
	body.collision_layer = LAYER_PROPS
	body.collision_mask = LAYER_WORLD | LAYER_PROPS | (1 << 1) | (1 << 2)
	body.can_sleep = true
	body.sleeping = true
	var wood := MaterialLibrary.get_material("wood_planks_local")
	var dark := MaterialLibrary.get_tinted("wood_planks_local", Color(0.6, 0.55, 0.5))
	var mb := MeshBuilder.new()
	mb.add_box(Vector3.ONE * (size - 0.04), Vector3.ZERO, wood)
	# Corner battens make it read as a slatted crate rather than a cube.
	var e := size * 0.5 - 0.03
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(0.07, size, 0.07), Vector3(sx * e, 0, sz * e), dark)
	for sy in [-1.0, 1.0]:
		mb.add_box(Vector3(size, 0.07, 0.07), Vector3(0, sy * e, e), dark)
		mb.add_box(Vector3(size, 0.07, 0.07), Vector3(0, sy * e, -e), dark)
		mb.add_box(Vector3(0.07, 0.07, size), Vector3(e, sy * e, 0), dark)
		mb.add_box(Vector3(0.07, 0.07, size), Vector3(-e, sy * e, 0), dark)
	var mi := mb.build_into(body, "Mesh")
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * size
	cs.shape = box
	body.add_child(cs)
	return body


static func make_barrel() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Barrel"
	body.physics_material_override = wood_material()
	body.mass = 45.0
	body.collision_layer = LAYER_PROPS
	body.collision_mask = LAYER_WORLD | LAYER_PROPS | (1 << 1) | (1 << 2)
	body.can_sleep = true
	body.sleeping = true
	var wood := MaterialLibrary.get_tinted("wood_planks_local", Color(0.75, 0.62, 0.5))
	var iron := MaterialLibrary.get_material("iron")
	var mb := MeshBuilder.new()
	# Bulging staves: three stacked frustums.
	mb.add_cylinder(0.25, 0.3, 0.3, Vector3(0, -0.28, 0), wood, 18)
	mb.add_cylinder(0.3, 0.3, 0.26, Vector3(0, 0.0, 0), wood, 18)
	mb.add_cylinder(0.3, 0.25, 0.3, Vector3(0, 0.28, 0), wood, 18)
	for y in [-0.36, -0.14, 0.14, 0.36]:
		var r := 0.3 - absf(y) * 0.14 + 0.008
		mb.add_cylinder(r, r, 0.045, Vector3(0, y, 0), iron, 18)
	var mi := mb.build_into(body, "Mesh")
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.29
	cyl.height = 0.86
	cs.shape = cyl
	body.add_child(cs)
	return body


## A static costermonger's barrow (Phase 4 turns these into market stalls).
static func make_handcart() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Handcart"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var wood := MaterialLibrary.get_material("wood_planks")
	var paint := MaterialLibrary.get_tinted("wood_painted", Color(0.35, 0.12, 0.08))
	var iron := MaterialLibrary.get_material("iron")
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(1.1, 0.06, 1.8), Vector3(0, 0.78, 0), wood) # bed
	mb.add_box(Vector3(0.05, 0.25, 1.8), Vector3(-0.55, 0.92, 0), paint)
	mb.add_box(Vector3(0.05, 0.25, 1.8), Vector3(0.55, 0.92, 0), paint)
	mb.add_box(Vector3(1.1, 0.25, 0.05), Vector3(0, 0.92, -0.9), paint)
	mb.add_box(Vector3(1.1, 0.25, 0.05), Vector3(0, 0.92, 0.9), paint)
	for sx in [-0.4, 0.4]:
		mb.add_box(Vector3(0.06, 0.06, 1.4), Vector3(sx, 0.72, 1.55), wood) # shafts
	mb.add_box(Vector3(0.06, 0.7, 0.06), Vector3(0, 0.4, -0.8), wood) # rest leg
	var wheel_basis := Basis(Vector3.FORWARD, PI * 0.5)
	for sx in [-0.66, 0.66]:
		mb.add_cylinder(0.62, 0.62, 0.05, Vector3(sx, 0.62, 0.15), iron, 24, wheel_basis) # iron tyre
		mb.add_cylinder(0.57, 0.57, 0.06, Vector3(sx, 0.62, 0.15), paint, 24, wheel_basis)
		mb.add_cylinder(0.09, 0.09, 0.14, Vector3(sx, 0.62, 0.15), iron, 10, wheel_basis) # hub
	mb.add_cylinder(0.03, 0.03, 1.35, Vector3(0, 0.62, 0.15), iron, 6, wheel_basis) # axle
	var mi := mb.build_into(body, "Mesh")
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.05, 1.9)
	cs.shape = box
	cs.position = Vector3(0, 0.55, 0.05)
	body.add_child(cs)
	return body


## A granite horse trough (0.8 m high), vaultable. Long side runs along Z.
static func make_horse_trough() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "HorseTrough"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var granite := MaterialLibrary.get_material("curb_granite")
	var water := MaterialLibrary.get_material("glass")
	var mb := MeshBuilder.new()
	var size := Vector3(0.75, 0.8, 2.4)
	mb.add_box(Vector3(size.x, 0.12, size.z), Vector3(0, 0.06, 0), granite) # base
	mb.add_box(Vector3(0.1, size.y, size.z), Vector3(-size.x * 0.5 + 0.05, size.y * 0.5, 0), granite)
	mb.add_box(Vector3(0.1, size.y, size.z), Vector3(size.x * 0.5 - 0.05, size.y * 0.5, 0), granite)
	mb.add_box(Vector3(size.x, size.y, 0.1), Vector3(0, size.y * 0.5, -size.z * 0.5 + 0.05), granite)
	mb.add_box(Vector3(size.x, size.y, 0.1), Vector3(0, size.y * 0.5, size.z * 0.5 - 0.05), granite)
	mb.add_plane(Vector2(size.x - 0.2, size.z - 0.2), Vector3(0, size.y - 0.12, 0), water) # still water
	var mi := mb.build_into(body, "Mesh")
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	return body


## A loose heap of hay (no collision) with a HidingSpot inside it.
static func make_hay_heap(color: Color = Color(0.72, 0.6, 0.33)) -> Node3D:
	var root := Node3D.new()
	root.name = "HayHeap"
	var hay := StandardMaterial3D.new()
	hay.albedo_color = color
	hay.roughness = 1.0
	var noise := NoiseTexture2D.new()
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.08
	noise.noise = fnl
	noise.seamless = true
	noise.as_normal_map = true
	noise.bump_strength = 12.0
	hay.normal_enabled = true
	hay.normal_texture = noise
	hay.uv1_triplanar = true
	hay.uv1_scale = Vector3(3, 3, 3)
	var blobs := [
		[Vector3(0, 0.45, 0), Vector3(1.9, 1.05, 1.7)],
		[Vector3(0.45, 0.35, 0.35), Vector3(1.2, 0.8, 1.1)],
		[Vector3(-0.5, 0.3, -0.3), Vector3(1.1, 0.7, 1.2)],
		[Vector3(0.1, 0.85, -0.1), Vector3(1.1, 0.7, 1.0)],
	]
	for b in blobs:
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 16
		mesh.rings = 8
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = hay
		mi.position = b[0]
		mi.scale = b[1]
		root.add_child(mi)
	var spot := HidingSpot.new()
	spot.name = "HidingSpot"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.3, 1.3)
	cs.shape = box
	cs.position = Vector3(0, 0.65, 0)
	spot.add_child(cs)
	root.add_child(spot)
	return root


## A costermonger's market stall: trestle table under a canvas awning, laden with goods.
## Faces local -Z (customers stand in front, the trader behind). 2.6 m wide.
## goods: "fish", "fruit", "vegetables", "bread", "flowers", "cloth", "crockery", "chestnuts"
static func make_market_stall(goods: String, awning: Color, seed_value: int) -> StaticBody3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := StaticBody3D.new()
	body.name = "Stall"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var wood := MaterialLibrary.get_material("wood_planks")
	var cloth := MaterialLibrary.get_tinted("wood_painted", awning)
	var stripe := MaterialLibrary.get_tinted("wood_painted", Color(0.85, 0.82, 0.72))
	var mb := MeshBuilder.new()
	var w := 2.6
	var d := 1.1
	var h := 0.85
	mb.add_box(Vector3(w, 0.05, d), Vector3(0, h, 0), wood) # table top
	mb.add_box(Vector3(w, h - 0.05, 0.03), Vector3(0, (h - 0.05) * 0.5, -d * 0.5 + 0.02), cloth) # front cloth
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			mb.add_box(Vector3(0.06, 2.3 if sz > 0 else 2.1, 0.06), Vector3(sx * (w * 0.5 - 0.05), (2.3 if sz > 0 else 2.1) * 0.5, sz * (d * 0.5 + 0.35)), wood)
	# Striped awning sloping down towards the customers.
	var stripes := 8
	for i in stripes:
		var x := -w * 0.5 - 0.1 + (w + 0.2) * (float(i) + 0.5) / stripes
		mb.add_box(Vector3((w + 0.2) / stripes, 0.02, d + 1.2), Vector3(x, 2.22, 0.0), cloth if i % 2 == 0 else stripe, Basis(Vector3.RIGHT, deg_to_rad(-9.0)))
	# Goods.
	var produce := func(color: Color, radius: float, count: int, area: Vector2, y: float) -> void:
		var mat := MaterialLibrary.get_tinted("wood_painted", color)
		for i in count:
			var p := Vector3(rng.randf_range(-area.x, area.x), y + radius, rng.randf_range(-area.y, area.y))
			var m := SphereMesh.new()
			m.radius = radius * rng.randf_range(0.85, 1.15)
			m.height = m.radius * 2.0 * rng.randf_range(0.85, 1.0)
			m.radial_segments = 8
			m.rings = 4
			mb.add_mesh(m, Transform3D(Basis.IDENTITY, p), mat)
	for bx: float in [-0.8, 0.0, 0.8]:
		mb.add_box(Vector3(0.7, 0.14, 0.55), Vector3(bx, h + 0.1, 0.05), wood) # wooden trays
	match goods:
		"fish":
			var ice := MaterialLibrary.get_tinted("wood_painted", Color(0.85, 0.9, 0.95))
			var fish := MaterialLibrary.get_tinted("iron", Color(0.55, 0.58, 0.6))
			mb.add_box(Vector3(2.3, 0.06, 0.6), Vector3(0, h + 0.18, 0.05), ice)
			for i in 14:
				var m := CapsuleMesh.new()
				m.radius = 0.04
				m.height = rng.randf_range(0.28, 0.4)
				var basis := Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, rng.randf_range(-0.4, 0.4))
				mb.add_mesh(m, Transform3D(basis, Vector3(rng.randf_range(-1.0, 1.0), h + 0.25, rng.randf_range(-0.2, 0.25))), fish)
		"fruit":
			produce.call(Color(0.62, 0.1, 0.06), 0.04, 30, Vector2(1.0, 0.22), h + 0.16)
			produce.call(Color(0.9, 0.5, 0.08), 0.045, 24, Vector2(1.0, 0.22), h + 0.16)
		"vegetables":
			produce.call(Color(0.3, 0.45, 0.18), 0.09, 12, Vector2(1.0, 0.2), h + 0.16)
			produce.call(Color(0.45, 0.33, 0.2), 0.045, 26, Vector2(1.0, 0.22), h + 0.16)
		"bread":
			var crust := MaterialLibrary.get_tinted("wood_painted", Color(0.62, 0.4, 0.18))
			for i in 12:
				var m := CapsuleMesh.new()
				m.radius = 0.06
				m.height = 0.26
				mb.add_mesh(m, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(rng.randf_range(-1.0, 1.0), h + 0.24, rng.randf_range(-0.2, 0.2))), crust)
		"flowers":
			for c: Color in [Color(0.75, 0.1, 0.15), Color(0.9, 0.85, 0.3), Color(0.9, 0.9, 0.9), Color(0.5, 0.2, 0.6)]:
				produce.call(c, 0.035, 14, Vector2(1.0, 0.22), h + 0.3)
		"cloth":
			for i in 8:
				var m := CylinderMesh.new()
				m.top_radius = 0.07
				m.bottom_radius = 0.07
				m.height = 0.55
				var c := Color.from_hsv(rng.randf(), 0.5, rng.randf_range(0.3, 0.7))
				mb.add_mesh(m, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-1.0 + i * 0.28, h + 0.25, 0.05)), MaterialLibrary.get_tinted("wood_painted", c))
		"crockery":
			var glaze := MaterialLibrary.get_tinted("wood_painted", Color(0.88, 0.86, 0.8))
			for i in 10:
				var m := CylinderMesh.new()
				m.top_radius = rng.randf_range(0.06, 0.1)
				m.bottom_radius = m.top_radius * 0.7
				m.height = rng.randf_range(0.1, 0.25)
				mb.add_mesh(m, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-1.0, 1.0), h + 0.17 + m.height * 0.5, rng.randf_range(-0.2, 0.2))), glaze)
		_:
			produce.call(Color(0.35, 0.2, 0.1), 0.025, 40, Vector2(1.0, 0.22), h + 0.16) # chestnuts
	var mi := mb.build_into(body, "Mesh")
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h + 0.1, d)
	cs.shape = box
	cs.position = Vector3(0, (h + 0.1) * 0.5, 0)
	body.add_child(cs)
	return body


# ---------------------------------------------------------------------------
# Trees
# ---------------------------------------------------------------------------
static var _foliage_mats: Dictionary = {}


## Leafy crowns: noisy cut-out shells that sway with the wind (global shader parameter
## `wind_strength`, set by WeatherEffects). One material per leaf colour, shared.
static func foliage_material(leaf: Color) -> ShaderMaterial:
	var key := leaf.to_html(false)
	if _foliage_mats.has(key):
		return _foliage_mats[key]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
global uniform float wind_strength;
uniform vec3 leaf_color : source_color = vec3(0.3, 0.42, 0.18);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 world_pos;
void vertex() {
	vec3 o = NODE_POSITION_WORLD;
	float sway = sin(TIME * 1.1 + o.x * 0.37 + o.z * 0.21) * 0.6 + sin(TIME * 2.7 + VERTEX.y * 1.3) * 0.25;
	VERTEX.xz += vec2(sway, sway * 0.6) * 0.05 * (0.25 + wind_strength) * max(VERTEX.y, 0.0) * 0.25;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// Leaf-sized holes: fine noise cut-outs over broader clumps.
	float n = texture(noise_tex, world_pos.xz * 1.6 + world_pos.y * 0.9).r;
	float m = texture(noise_tex, world_pos.zy * 2.6 + vec2(0.3)).r;
	if (n * 0.55 + m * 0.45 < 0.45) {
		discard;
	}
	float shade = 0.65 + 0.55 * m;
	ALBEDO = leaf_color * shade * (FRONT_FACING ? 1.0 : 0.6);
	ROUGHNESS = 0.8;
	BACKLIGHT = leaf_color * 0.35;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("leaf_color", leaf)
	var tex := NoiseTexture2D.new()
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.09
	fnl.fractal_octaves = 3
	tex.noise = fnl
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	tex.generate_mipmaps = true
	mat.set_shader_parameter("noise_tex", tex)
	_foliage_mats[key] = mat
	return mat


## A London plane (or lime, with `leaf` tinted): mottled trunk, spreading branches and a
## crown of leafy clusters. `height` is to the top of the crown. The trunk is solid.
static func make_tree(seed_value: int, height: float = 14.0, leaf: Color = Color(0.3, 0.44, 0.17)) -> StaticBody3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := StaticBody3D.new()
	body.name = "Tree"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var trunk_r := height * 0.028
	var trunk_h := height * 0.45
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = trunk_r
	cyl.height = trunk_h
	cs.shape = cyl
	cs.position = Vector3(0, trunk_h * 0.5, 0)
	body.add_child(cs)
	var bark := MaterialLibrary.get_tinted("stucco", Color(0.55, 0.5, 0.42)) # plane bark: grey-olive, flaking
	var mb := MeshBuilder.new()
	mb.add_cylinder(trunk_r * 0.8, trunk_r * 1.25, trunk_h, Vector3(0, trunk_h * 0.5, 0), bark, 10)
	var crown_c := Vector3(0, height * 0.66, 0)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf() * 0.5
		var tip := crown_c + Vector3(cos(a) * height * 0.22, rng.randf_range(-0.5, 1.5), sin(a) * height * 0.22)
		var from := Vector3(0, trunk_h * 0.9, 0)
		var d := tip - from
		var basis := Basis(Vector3.UP.cross(d.normalized()).normalized(), Vector3.UP.angle_to(d.normalized())) if Vector3.UP.cross(d.normalized()).length() > 0.01 else Basis.IDENTITY
		mb.add_cylinder(trunk_r * 0.25, trunk_r * 0.55, d.length(), from + d * 0.5, bark, 6, basis)
	var trunk_mi := mb.build_into(body, "Trunk")
	trunk_mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var leaves := MeshBuilder.new()
	# Several overlapping lobes of leaf cards make an irregular, open crown.
	for k in 5:
		var off := Vector3(rng.randf_range(-1.0, 1.0) * height * 0.14, rng.randf_range(-0.08, 0.16) * height, rng.randf_range(-1.0, 1.0) * height * 0.14)
		var rr := height * rng.randf_range(0.17, 0.24)
		Foliage.add_crown(leaves, crown_c + off, Vector3(rr, rr * 0.75, rr), 70, height * 0.13, leaf, seed_value * 31 + k)
	var crown := leaves.build_into(body, "Crown")
	crown.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return body


## A cast-iron bollard (many were made from old cannon): keeps carts off the pavement.
static func make_bollard() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Bollard"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.13
	cyl.height = 0.95
	cs.shape = cyl
	cs.position = Vector3(0, 0.475, 0)
	body.add_child(cs)
	var iron := MaterialLibrary.get_material("iron")
	var mb := MeshBuilder.new()
	mb.add_cylinder(0.14, 0.12, 0.8, Vector3(0, 0.4, 0), iron, 12)
	mb.add_cylinder(0.15, 0.15, 0.06, Vector3(0, 0.62, 0), iron, 12) # collar
	var cap := SphereMesh.new()
	cap.radius = 0.12
	cap.height = 0.2
	cap.radial_segments = 12
	cap.rings = 5
	mb.add_mesh(cap, Transform3D(Basis.IDENTITY, Vector3(0, 0.84, 0)), iron)
	mb.build_into(body, "Mesh")
	return body
