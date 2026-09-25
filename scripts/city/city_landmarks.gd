class_name CityLandmarks
extends Node3D
## The two buildings you can see from anywhere in London: St Paul's Cathedral and the
## Palace of Westminster, built once at full size (they are far too big to stream), with
## solid walls. Their grounds are ordinary city blocks (CityPlan.Kind.LANDMARK).

const ST_PAULS := CityPlan.ST_PAULS
const WESTMINSTER := CityPlan.WESTMINSTER


func _ready() -> void:
	_build_st_pauls()
	_build_westminster()
	_build_collision()


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	add_child(body)
	var o := ST_PAULS
	var c := o + Vector3(8, 0, 0)
	var boxes := [
		[Vector3(150, 30, 38), o + Vector3(0, 15, 0)], [Vector3(40, 30, 90), o + Vector3(8, 15, 0)],
		[Vector3(10, 26, 38), o + Vector3(-78, 13, 0)], [Vector3(12, 40, 12), o + Vector3(-80, 20, -15)],
		[Vector3(12, 40, 12), o + Vector3(-80, 20, 15)], [Vector3(40, 60, 40), c + Vector3(0, 30, 0)],
		[Vector3(265, 24, 60), WESTMINSTER + Vector3(0, 12, 0)], [Vector3(23, 90, 23), WESTMINSTER + Vector3(140, 45, -10)],
		[Vector3(14, 70, 14), WESTMINSTER + Vector3(-142, 35, 20)],
	]
	for bx: Array in boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bx[0]
		cs.shape = shape
		cs.position = bx[1]
		body.add_child(cs)
	# The steps up to St Paul's west front.
	for k in 6:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.0, 0.17 * (k + 1) + 0.15, 36)
		cs.shape = shape
		cs.position = o + Vector3(-90.0 + k * 1.0 + 0.5 + 6.0 - 6.0, shape.size.y * 0.5, 0)
		body.add_child(cs)


# ---------------------------------------------------------------------------
# St Paul's Cathedral (Wren, 1710): dome 111 m to the cross
# ---------------------------------------------------------------------------
func _build_st_pauls() -> void:
	var stone := _plain(Color(0.86, 0.84, 0.78), 0.85)
	var lead := _plain(Color(0.42, 0.45, 0.47), 0.55)
	var gilt := MaterialLibrary.get_material("gilt")
	var dark := _plain(Color(0.12, 0.12, 0.13), 0.5)
	var mb := MeshBuilder.new()
	var o := ST_PAULS
	# Nave and choir (east-west), transepts (north-south).
	mb.add_box(Vector3(150, 30, 38), o + Vector3(0, 15, 0), stone)
	mb.add_box(Vector3(40, 30, 90), o + Vector3(8, 15, 0), stone)
	mb.add_box(Vector3(150, 3, 30), o + Vector3(0, 31.5, 0), lead)
	# West front: portico and the two towers.
	mb.add_box(Vector3(10, 26, 38), o + Vector3(-78, 13, 0), stone)
	for z: float in [-15.0, 15.0]:
		mb.add_box(Vector3(12, 40, 12), o + Vector3(-80, 20, z), stone)
		mb.add_cylinder(4.5, 4.0, 12, o + Vector3(-80, 46, z), stone, 12)
		mb.add_cylinder(3.0, 0.3, 12, o + Vector3(-80, 58, z), lead, 12)
		mb.add_mesh(_sphere(0.9), Transform3D(Basis.IDENTITY, o + Vector3(-80, 64.5, z)), gilt)
	for k in 6:
		mb.add_cylinder(1.0, 1.0, 12, o + Vector3(-85, 7, -10 + k * 4.0), stone, 10)
	mb.add_box(Vector3(4, 6, 26), o + Vector3(-85, 16, 0), stone) # pediment band
	# Crossing: drum ringed with columns, upper drum, dome, lantern, ball and cross.
	var c := o + Vector3(8, 0, 0)
	mb.add_cylinder(20.0, 20.0, 22, c + Vector3(0, 41, 0), stone, 40)
	for k in 32:
		var a := TAU * k / 32.0
		mb.add_cylinder(0.9, 0.9, 18, c + Vector3(cos(a) * 21.5, 41, sin(a) * 21.5), stone, 8)
	mb.add_cylinder(22.5, 22.5, 2.0, c + Vector3(0, 51, 0), stone, 40)
	mb.add_cylinder(17.5, 17.0, 9, c + Vector3(0, 56.5, 0), stone, 36)
	var dome := SphereMesh.new()
	dome.radius = 17.5
	dome.height = 35.0
	dome.is_hemisphere = true
	dome.radial_segments = 40
	dome.rings = 16
	mb.add_mesh(dome, Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.25, 1)), c + Vector3(0, 61, 0)), lead)
	for k in 16:
		var a := TAU * k / 16.0
		mb.add_box(Vector3(0.6, 20, 0.6), c + Vector3(cos(a) * 12.0, 71, sin(a) * 12.0), stone, Basis(Vector3(-sin(a), 0, cos(a)), 0.62))
	mb.add_cylinder(3.4, 3.0, 12, c + Vector3(0, 89, 0), stone, 16)
	mb.add_cylinder(3.2, 0.5, 5, c + Vector3(0, 97.5, 0), lead, 16)
	mb.add_mesh(_sphere(1.4), Transform3D(Basis.IDENTITY, c + Vector3(0, 101.5, 0)), gilt)
	mb.add_box(Vector3(0.4, 7, 0.4), c + Vector3(0, 106, 0), gilt)
	mb.add_box(Vector3(3.2, 0.4, 0.4), c + Vector3(0, 107.5, 0), gilt)
	# Rows of tall windows.
	for side: float in [-19.1, 19.1]:
		for k in 12:
			mb.add_box(Vector3(3, 8, 0.2), o + Vector3(-60 + k * 11.0, 17, side), dark)
	_finish(mb, "StPauls")


# ---------------------------------------------------------------------------
# The Palace of Westminster (Barry and Pugin): the Clock Tower (96 m) and the
# Victoria Tower (98 m) at either end of a 265 m Gothic river front
# ---------------------------------------------------------------------------
func _build_westminster() -> void:
	var stone := _plain(Color(0.74, 0.64, 0.48), 0.85)
	var lead := _plain(Color(0.36, 0.4, 0.42), 0.55)
	var gilt := MaterialLibrary.get_material("gilt")
	var dark := _plain(Color(0.1, 0.1, 0.11), 0.5)
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.95, 0.93, 0.85)
	face.emission_enabled = true
	face.emission = Color(1.0, 0.85, 0.55)
	face.emission_energy_multiplier = 0.25
	var mb := MeshBuilder.new()
	var o := WESTMINSTER
	# The long river front with its roofs and rows of pinnacles.
	mb.add_box(Vector3(265, 24, 60), o + Vector3(0, 12, 0), stone)
	mb.add_box(Vector3(265, 6, 50), o + Vector3(0, 27, 0), lead)
	for k in 54:
		var x := -130.0 + k * 5.0
		for side: float in [-30.5, 30.5]:
			mb.add_cylinder(0.5, 0.05, 5.0, o + Vector3(x, 26.5, side), stone, 4)
			mb.add_box(Vector3(2.0, 9, 0.2), o + Vector3(x, 12, side), dark)
	# Central tower and spire.
	mb.add_cylinder(8.0, 8.0, 50, o + Vector3(0, 25, 0), stone, 8)
	mb.add_cylinder(8.0, 0.4, 42, o + Vector3(0, 71, 0), lead, 8)
	# Victoria Tower (south end): a massive square tower with corner pinnacles.
	var v := o + Vector3(140, 0, -10)
	mb.add_box(Vector3(23, 90, 23), v + Vector3(0, 45, 0), stone)
	for sx: float in [-11.0, 11.0]:
		for sz: float in [-11.0, 11.0]:
			mb.add_box(Vector3(3, 100, 3), v + Vector3(sx, 50, sz), stone)
			mb.add_cylinder(1.5, 0.1, 10, v + Vector3(sx, 105, sz), lead, 4)
	mb.add_box(Vector3(24, 4, 24), v + Vector3(0, 92, 0), stone)
	mb.add_box(Vector3(0.3, 12, 0.3), v + Vector3(0, 100, 0), dark) # flagstaff
	for k in 4:
		mb.add_box(Vector3(4, 40, 0.3), v + Vector3(-6 + k * 4.0, 50, -11.6), dark)
	# The Clock Tower (north end): shaft, belfry with four clock faces, spire.
	var t := o + Vector3(-142, 0, 20)
	mb.add_box(Vector3(12, 55, 12), t + Vector3(0, 27.5, 0), stone)
	for k in 4:
		mb.add_box(Vector3(1.0, 50, 12.2), t + Vector3(-4.5 + k * 3.0, 27.5, 0), stone)
	mb.add_box(Vector3(14, 12, 14), t + Vector3(0, 61, 0), stone)
	for dir: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var clock := CylinderMesh.new()
		clock.top_radius = 3.5
		clock.bottom_radius = 3.5
		clock.height = 0.2
		clock.radial_segments = 32
		var basis := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		mb.add_mesh(clock, Transform3D(basis, t + Vector3(0, 61, 0) + dir * 7.1), face)
		mb.add_box(Vector3(0.25, 2.8, 0.1), t + Vector3(0, 62.2, 0) + dir * 7.25, dark) # hands
	mb.add_box(Vector3(12, 10, 12), t + Vector3(0, 72, 0), stone) # belfry
	mb.add_cylinder(9.0, 3.0, 8, t + Vector3(0, 81, 0), lead, 4, Basis(Vector3.UP, PI * 0.25))
	mb.add_cylinder(3.0, 0.2, 12, t + Vector3(0, 91, 0), lead, 4, Basis(Vector3.UP, PI * 0.25))
	mb.add_mesh(_sphere(0.6), Transform3D(Basis.IDENTITY, t + Vector3(0, 97.2, 0)), gilt)
	for sx: float in [-6.5, 6.5]:
		for sz: float in [-6.5, 6.5]:
			mb.add_cylinder(0.7, 0.05, 7, t + Vector3(sx, 70.5, sz), gilt, 4)
	_finish(mb, "Westminster")



# ---------------------------------------------------------------------------
func _finish(mb: MeshBuilder, n: String) -> void:
	var mi := mb.build_into(self, n, true)
	if mi:
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _plain(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s
