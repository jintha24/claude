class_name StreetProps
extends RefCounted
## Factory for street clutter: physics crates and barrels, and a costermonger's handcart.
## Crates and barrels are RigidBody3D with real masses so Harry (and later carts) can
## shove them around.

const LAYER_PROPS := 1 << 3
const LAYER_WORLD := 1


static func make_crate(size: float = 0.6) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Crate"
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
