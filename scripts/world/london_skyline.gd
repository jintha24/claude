@tool
class_name LondonSkyline
extends Node3D
## The London beyond the city's edge (CityPlan.HALF): a sea of terraces with chimney
## stacks fading into the coal-smoke haze, out to the horizon.
##
## None of it is reachable: it's scenery, drawn cheaply. All the houses are one
## MultiMesh (a single draw call per material), with no collision and no shadows.
## Everything nearer is the walkable city (CityStreamer).

## The walkable city (x, z, width, depth): no scenery houses are placed inside.
@export var keep_clear: Rect2 = Rect2(-1700.0, -1700.0, 3400.0, 3400.0)
@export var inner_radius: float = 1700.0
@export var outer_radius: float = 2700.0
@export var cell_size: float = 32.0
@export var layout_seed: int = 1866

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rng.seed = layout_seed
	_build_rooftops()


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
			if keep_clear.grow(8.0).has_point(c) or (c.y > CityPlan.RIVER_Z0 - 20.0 and c.y < CityPlan.RIVER_Z1 + 20.0):
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
