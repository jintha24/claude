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
static func make_hay_heap() -> Node3D:
	var root := Node3D.new()
	root.name = "HayHeap"
	var hay := StandardMaterial3D.new()
	hay.albedo_color = Color(0.72, 0.6, 0.33)
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
