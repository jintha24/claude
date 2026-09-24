@tool
class_name LondonSkyline
extends Node3D
## Distant London, 1866, seen over the rooftops: a sea of terraces with chimney stacks
## fading into the blue coal-smoke haze, factory chimneys trailing smoke, St Paul's
## Cathedral and the new Palace of Westminster with its Clock Tower (finished 1859) and
## Victoria Tower (1860).
##
## None of it is reachable: it's scenery, drawn cheaply. All the houses are one
## MultiMesh (a single draw call per material), with no collision and no shadows.
## Phase 10 replaces the nearer ring with real, walkable districts.

## The playable neighbourhood (x, z, width, depth): no scenery houses are placed inside.
@export var keep_clear: Rect2 = Rect2(-75.0, -150.0, 215.0, 225.0)
@export var inner_radius: float = 130.0
@export var outer_radius: float = 760.0
@export var cell_size: float = 24.0
@export var layout_seed: int = 1866

const ST_PAULS := Vector3(-430.0, 0.0, 250.0)
const WESTMINSTER := Vector3(-900.0, 0.0, 520.0)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rng.seed = layout_seed
	_build_rooftops()
	_build_st_pauls()
	_build_westminster()
	_build_factory_chimneys()
	_build_church_spires()


# ---------------------------------------------------------------------------
# The sea of rooftops
# ---------------------------------------------------------------------------
func _build_rooftops() -> void:
	var mesh := _terrace_mesh()
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var n := int(outer_radius / cell_size)
	var wall_tones: Array[Color] = [
		Color(0.62, 0.53, 0.39), Color(0.55, 0.46, 0.34), Color(0.5, 0.26, 0.19),
		Color(0.45, 0.28, 0.22), Color(0.86, 0.82, 0.73), Color(0.7, 0.66, 0.58),
	]
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var c := Vector2(gx * cell_size, gz * cell_size)
			var r := c.length()
			if r < inner_radius or r > outer_radius:
				continue
			if keep_clear.grow(8.0).has_point(c) or _near_landmark(Vector3(c.x, 0.0, c.y)):
				continue
			if _rng.randf() < 0.07:
				continue # a square, a churchyard, a railway cutting
			# Streets run in two directions; each cell holds one or two terrace rows.
			var along_x := (gx + gz) % 3 != 0
			var rows := 2 if _rng.randf() < 0.65 else 1
			for row in rows:
				var length := _rng.randf_range(cell_size * 0.55, cell_size * 0.9)
				var depth := _rng.randf_range(7.0, 10.0)
				var height := _rng.randf_range(8.5, 14.0)
				if _rng.randf() < 0.06:
					height = _rng.randf_range(16.0, 24.0) # a warehouse or tenement block
				var off := (row - (rows - 1) * 0.5) * (depth + 0.3)
				var pos := Vector3(c.x, 0.0, c.y) + (Vector3(0, 0, off) if along_x else Vector3(off, 0, 0))
				pos += Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
				var basis := Basis(Vector3.UP, 0.0 if along_x else PI * 0.5) * Basis.from_scale(Vector3(length, height, depth))
				xforms.append(Transform3D(basis, pos))
				var tone: Color = wall_tones[_rng.randi() % wall_tones.size()]
				colors.append(tone * _rng.randf_range(0.88, 1.08))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rooftops"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)


## A unit terrace block (1 x 1 x 1, origin at the ground centre): walls tinted per
## instance, a slate ridge roof and a row of chimney stacks.
func _terrace_mesh() -> ArrayMesh:
	var walls := StandardMaterial3D.new()
	walls.vertex_color_use_as_albedo = true
	walls.albedo_color = Color.WHITE
	walls.roughness = 0.95
	var slate := StandardMaterial3D.new()
	slate.albedo_color = Color(0.25, 0.27, 0.3)
	slate.roughness = 0.7
	var soot := StandardMaterial3D.new()
	soot.vertex_color_use_as_albedo = true
	soot.albedo_color = Color(0.7, 0.62, 0.55)
	soot.roughness = 0.9
	var window_band := StandardMaterial3D.new()
	window_band.albedo_color = Color(0.07, 0.07, 0.08)
	window_band.roughness = 0.3
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(1.0, 1.0, 1.0), Vector3(0, 0.5, 0), walls)
	# Rows of windows on both long faces (at this distance, dark bands read as windows).
	for side: float in [-1.0, 1.0]:
		for floor_y: float in [0.3, 0.55, 0.8]:
			mb.add_box(Vector3(0.9, 0.08, 0.01), Vector3(0.0, floor_y, side * 0.502), window_band)
	# Pitched roof: two sloping planes meeting at a ridge (pitch set by the instance scale).
	var roof := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.18 # ridge height, in units of the block height
	var pts := [Vector3(-0.5, 1.0, -0.52), Vector3(0.5, 1.0, -0.52), Vector3(0.5, 1.0 + r, 0.0), Vector3(-0.5, 1.0 + r, 0.0), Vector3(-0.5, 1.0, 0.52), Vector3(0.5, 1.0, 0.52)]
	for tri: Array in [[0, 2, 1], [0, 3, 2], [4, 5, 2], [4, 2, 3]]:
		var a: Vector3 = pts[tri[0]]
		var b: Vector3 = pts[tri[1]]
		var c: Vector3 = pts[tri[2]]
		st.set_normal((b - a).cross(c - a).normalized())
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	# Gable ends.
	for side: float in [-0.5, 0.5]:
		var ga := Vector3(side, 1.0, -0.52)
		var gb := Vector3(side, 1.0, 0.52)
		var gc := Vector3(side, 1.0 + r, 0.0)
		st.set_normal(Vector3(signf(side), 0, 0))
		if side < 0.0:
			st.add_vertex(ga)
			st.add_vertex(gb)
			st.add_vertex(gc)
		else:
			st.add_vertex(ga)
			st.add_vertex(gc)
			st.add_vertex(gb)
	st.set_material(slate)
	st.commit(roof)
	mb.add_mesh(roof, Transform3D.IDENTITY, slate)
	# Chimney stacks along the ridge.
	for k in 3:
		mb.add_box(Vector3(0.08, 0.2, 0.18), Vector3(-0.33 + k * 0.33, 1.14, 0.0), soot)
	return mb.build()


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
# Factory chimneys and church spires
# ---------------------------------------------------------------------------
const FACTORY_SPOTS: Array[Vector3] = [
	Vector3(420, 0, -180), Vector3(520, 0, 60), Vector3(380, 0, 260), Vector3(610, 0, -320),
	Vector3(-300, 0, -520), Vector3(200, 0, -600), Vector3(-640, 0, -150), Vector3(260, 0, 540),
]
const SPIRE_SPOTS: Array[Vector3] = [
	Vector3(-260, 0, 120), Vector3(-330, 0, 330), Vector3(-200, 0, 380), Vector3(160, 0, -260),
	Vector3(-560, 0, 200), Vector3(300, 0, 200),
]


func _near_landmark(p: Vector3) -> bool:
	if p.distance_to(ST_PAULS) < 95.0 or p.distance_to(WESTMINSTER) < 180.0:
		return true
	for q in FACTORY_SPOTS:
		if p.distance_to(q + Vector3(12, 0, 6)) < 28.0:
			return true
	for q in SPIRE_SPOTS:
		if p.distance_to(q + Vector3(8, 0, 0)) < 22.0:
			return true
	return false


func _build_factory_chimneys() -> void:
	var brick := _plain(Color(0.42, 0.26, 0.2), 0.95)
	var soot := _plain(Color(0.1, 0.09, 0.09), 0.9)
	var mb := MeshBuilder.new()
	# East End breweries, sugar refineries and gasworks, and a few across the river.
	var spots := FACTORY_SPOTS
	for i in spots.size():
		var p := spots[i]
		var h := _rng.randf_range(42.0, 62.0)
		mb.add_cylinder(2.8, 1.7, h, p + Vector3(0, h * 0.5, 0), brick, 12)
		mb.add_cylinder(2.0, 2.0, 2.0, p + Vector3(0, h + 1.0, 0), soot, 12)
		mb.add_box(Vector3(26, 14, 18), p + Vector3(12, 7, 6), brick) # the works
		var smoke := ChimneySmoke.new()
		smoke.name = "FactorySmoke%d" % i
		smoke.position = p + Vector3(0, h + 2.0, 0)
		smoke.amount = 36
		smoke.lifetime = 45.0
		smoke.preprocess = 45.0
		smoke.visibility_aabb = AABB(Vector3(-150, -10, -150), Vector3(300, 140, 300))
		var pm := (smoke.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 3.0
		pm.scale_min = 6.0
		pm.scale_max = 9.0
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.1, 0.09, 0.09, 0.0))
		ramp.set_color(1, Color(0.55, 0.55, 0.56, 0.0))
		ramp.add_point(0.06, Color(0.3, 0.29, 0.28, 0.55))
		ramp.add_point(0.5, Color(0.55, 0.55, 0.56, 0.25))
		var grt := GradientTexture1D.new()
		grt.gradient = ramp
		pm.color_ramp = grt
		smoke.process_material = pm
		smoke.wind = Vector3(3.0, 0.4, 1.2)
		add_child(smoke)
	_finish(mb, "Factories")


func _build_church_spires() -> void:
	var stone := _plain(Color(0.8, 0.78, 0.72), 0.85)
	var lead := _plain(Color(0.35, 0.37, 0.4), 0.55)
	var mb := MeshBuilder.new()
	# Wren's City churches and Hawksmoor's Christ Church, Spitalfields (to the north).
	for p: Vector3 in SPIRE_SPOTS:
		var h := _rng.randf_range(30.0, 42.0)
		mb.add_box(Vector3(8, h, 8), p + Vector3(0, h * 0.5, 0), stone)
		mb.add_box(Vector3(6, 8, 6), p + Vector3(0, h + 4.0, 0), stone)
		mb.add_cylinder(3.6, 0.1, h * 0.8, p + Vector3(0, h + 8.0 + h * 0.4, 0), lead, 8)
		mb.add_box(Vector3(22, 16, 12), p + Vector3(15, 8, 0), stone)
	_finish(mb, "Spires")


# ---------------------------------------------------------------------------
func _finish(mb: MeshBuilder, n: String) -> void:
	var mi := mb.build_into(self, n, false)
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
