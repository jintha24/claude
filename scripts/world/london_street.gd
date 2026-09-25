@tool
class_name LondonStreet
extends Node3D
## Phase 1 test level: one Victorian London street, about 92 m long, at real-world scale.
##
## Layout (world space, metres):
##   * Street runs along Z from z = -46 to z = +46.
##   * Cobbled carriageway x = -3.8 .. 3.8 (surface at y = 0).
##   * Granite kerbs and York-stone pavements up to x = +/-6.3 (surface at y = 0.15).
##   * Terraced houses and shops on both sides, closed off by buildings at each end.
##   * A narrow alley on the east side (z = 4 .. 6.4) with a two-flight timber stair
##     up to 4.5 m and 9 m platforms, used to test stairs and fall damage.
## Everything is generated from code, so it appears in the editor too (this is a @tool script).

const ROAD_HALF := 3.8
const KERB_W := 0.25
const PAVE_TOP := 0.15
const FACADE_X := 6.3
const STREET_HALF_LEN := 46.0
const ALLEY_Z0 := 4.0
const ALLEY_Z1 := 6.4
const ALLEY_END_X := 20.0
## Church Lane: a gap in the west terrace leading into the St Giles rookery (StGiles).
const WEST_LANE_Z0 := -6.0
const WEST_LANE_Z1 := -2.6

const SHOP_NAMES: Array[String] = [
	"J. PARKER & SONS  TOBACCONIST",
	"DOYLE & CO.  PAWNBROKERS",
	"THE CROWN & ANCHOR",
	"W. HARGREAVES  BAKER",
	"ASHCOMBE RAILWAY COMPANY",
	"E. BATES  CHEMIST",
	"ST GILES COFFEE HOUSE",
	"T. WREN  IRONMONGER",
]

@export var layout_seed: int = 1866:
	set(v):
		layout_seed = v
		if is_inside_tree():
			rebuild()

var _rng := RandomNumberGenerator.new()
var _shop_index := 0


func _ready() -> void:
	add_to_group("navigation_source")
	rebuild()


## World position where Harry starts, facing down the street (-Z).
func get_spawn_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 38.0))


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_rng.seed = layout_seed
	_shop_index = 0
	_build_ground()
	_build_terrace_east()
	_build_terrace_west()
	_build_end_buildings()
	_build_bank_portico()
	_build_alley()
	_build_lamps()
	_build_props()


# ---------------------------------------------------------------------------
# Ground: carriageway, kerbs and pavements
# ---------------------------------------------------------------------------
func _build_ground() -> void:
	var length := STREET_HALF_LEN * 2.0
	var ground := StaticBody3D.new()
	ground.set_meta("surface", "stone")
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	add_child(ground)
	# Solid ground under the street and its terraces, stopping short of the mews (x = 35),
	# where Ashcombe House has its own ground with a sewer beneath, and of St Giles
	# (x < -18), which has its own with the Fleet ditch and the church crypt cut into it.
	_box_collider(ground, Vector3(52, 2, 160), Vector3(8, -1, 0))

	var road := MeshInstance3D.new()
	road.name = "Carriageway"
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROAD_HALF * 2.0, length)
	road.mesh = plane
	road.material_override = MaterialLibrary.get_for_uv_plane("cobblestone", plane.size)
	add_child(road)

	var mb := MeshBuilder.new()
	var granite := MaterialLibrary.get_material("curb_granite")
	var paving := MaterialLibrary.get_material("pavement")
	for side in [-1.0, 1.0]:
		var kerb_x: float = side * (ROAD_HALF + KERB_W * 0.5)
		var pave_w := FACADE_X - ROAD_HALF - KERB_W
		var pave_x: float = side * (ROAD_HALF + KERB_W + pave_w * 0.5)
		var kerb_size := Vector3(KERB_W, PAVE_TOP + 0.2, length)
		var pave_size := Vector3(pave_w, PAVE_TOP + 0.2, length)
		mb.add_box(kerb_size, Vector3(kerb_x, PAVE_TOP - kerb_size.y * 0.5, 0), granite)
		mb.add_box(pave_size, Vector3(pave_x, PAVE_TOP - pave_size.y * 0.5, 0), paving)
		_box_collider(ground, kerb_size, Vector3(kerb_x, PAVE_TOP - kerb_size.y * 0.5, 0))
		_box_collider(ground, pave_size, Vector3(pave_x, PAVE_TOP - pave_size.y * 0.5, 0))
	# Pavement strip in front of the bank at the south end (the north end opens into the
	# market square, Phase 4).
	for side in [1.0]:
		var z: float = side * (STREET_HALF_LEN - 1.25)
		var size := Vector3(ROAD_HALF * 2.0, PAVE_TOP + 0.2, 2.5)
		mb.add_box(size, Vector3(0, PAVE_TOP - size.y * 0.5, z), paving)
		_box_collider(ground, size, Vector3(0, PAVE_TOP - size.y * 0.5, z))
		var kerb := Vector3(ROAD_HALF * 2.0, PAVE_TOP + 0.2, KERB_W)
		var kz: float = side * (STREET_HALF_LEN - 2.5 - KERB_W * 0.5)
		mb.add_box(kerb, Vector3(0, PAVE_TOP - kerb.y * 0.5, kz), granite)
		_box_collider(ground, kerb, Vector3(0, PAVE_TOP - kerb.y * 0.5, kz))
	mb.build_into(self, "Pavements").gi_mode = GeometryInstance3D.GI_MODE_STATIC


# ---------------------------------------------------------------------------
# Terraces
# ---------------------------------------------------------------------------
func _build_terrace_east() -> void:
	# East side (x > 0): facades face -X. Leave a gap for the alley.
	_build_row(-STREET_HALF_LEN, ALLEY_Z0, true, 10.0, ALLEY_END_X - FACADE_X)
	_build_row(ALLEY_Z1, STREET_HALF_LEN, true, ALLEY_END_X - FACADE_X, 10.0)


func _build_terrace_west() -> void:
	# West side, with a gap for Church Lane into St Giles.
	_build_row(-STREET_HALF_LEN, WEST_LANE_Z0, false, 10.0, 10.0)
	_build_row(WEST_LANE_Z1, STREET_HALF_LEN, false, 10.0, 10.0)


## Fills z0..z1 with buildings. first_depth/last_depth let the buildings next to the
## alley run all the way back so the alley has solid walls.
func _build_row(z0: float, z1: float, east: bool, first_depth: float, last_depth: float) -> void:
	var z := z0
	var index := 0
	var prev_height := -1.0
	while z1 - z > 0.01:
		var w := _rng.randf_range(5.4, 8.2)
		if z1 - (z + w) < 5.0:
			w = z1 - z # last building takes the remainder
		var b := BuildingFacade.new()
		b.name = "%s_%02d" % ["East" if east else "West", index]
		b.width = w
		b.depth = first_depth if index == 0 else (last_depth if z + w >= z1 - 0.01 else 10.0)
		_style_building(b)
		if b.depth > 10.0:
			b.upper_floors = 2 # alley buildings: their roofs are reachable from the alley platform
		if east:
			b.rotation.y = -PI * 0.5
			b.position = Vector3(FACADE_X, PAVE_TOP, z)
		else:
			b.rotation.y = PI * 0.5
			b.position = Vector3(-FACADE_X, PAVE_TOP, z + w)
		add_child(b)
		# Where neighbouring roofs differ in height, a drainpipe on the taller building's
		# exposed side wall lets Harry climb from the lower roof to the higher one.
		var h := b.get_facade_height()
		if prev_height > 0.0 and absf(h - prev_height) > 0.5:
			var taller_is_current := h > prev_height
			var pipe_z := z - 0.1 if taller_is_current else z + 0.1
			var pipe_x := (FACADE_X + 0.6) * (1.0 if east else -1.0)
			_add_roof_pipe(Vector3(pipe_x, PAVE_TOP + minf(h, prev_height), pipe_z), absf(h - prev_height))
		prev_height = h
		z += w
		index += 1


## A cast-iron rainwater pipe from `base` rising `height` metres (climbable, layer 5).
func _add_roof_pipe(base: Vector3, height: float) -> void:
	var pipe := StaticBody3D.new()
	pipe.name = "RoofPipe"
	pipe.collision_layer = 1 << 4
	pipe.collision_mask = 0
	pipe.add_to_group("climbable_pipe")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.06
	cyl.height = height
	cs.shape = cyl
	cs.position = base + Vector3.UP * height * 0.5
	pipe.add_child(cs)
	add_child(pipe)
	var mb := MeshBuilder.new()
	var iron := MaterialLibrary.get_material("iron")
	mb.add_cylinder(0.045, 0.045, height, base + Vector3.UP * height * 0.5, iron, 8)
	mb.add_box(Vector3(0.2, 0.22, 0.2), base + Vector3.UP * (height - 0.3), iron)
	mb.build_into(self, "RoofPipeMesh").gi_mode = GeometryInstance3D.GI_MODE_STATIC


func _style_building(b: BuildingFacade) -> void:
	b.variation_seed = _rng.randi()
	b.upper_floors = 2 + int(_rng.randf() > 0.45)
	var roll := _rng.randf()
	b.wall_material = "brick_yellow" if roll < 0.5 else ("brick_red" if roll < 0.75 else "stucco")
	b.door_on_left = _rng.randf() > 0.5
	if _rng.randf() < 0.45 and _shop_index < SHOP_NAMES.size():
		b.ground_floor = BuildingFacade.GroundFloor.SHOP
		b.shop_name = SHOP_NAMES[_shop_index]
		b.has_awning = _rng.randf() > 0.5
		_shop_index += 1
	else:
		b.ground_floor = BuildingFacade.GroundFloor.HOUSE


func _build_end_buildings() -> void:
	var south := BuildingFacade.new()
	south.name = "EndSouth"
	south.width = FACADE_X * 2.0
	south.depth = 12.0
	south.upper_floors = 3
	south.wall_material = "brick_red"
	south.ground_floor = BuildingFacade.GroundFloor.SHOP
	south.shop_name = "LONDON & COUNTY BANK"
	south.variation_seed = 9
	south.rotation.y = PI
	south.position = Vector3(FACADE_X, PAVE_TOP, STREET_HALF_LEN)
	add_child(south)


## A Greek Revival portico on the bank at the south end: six columns with Corinthian-style
## capitals, entablature and pediment, in pale Portland stone.
func _build_bank_portico() -> void:
	var body := StaticBody3D.new()
	body.name = "BankPortico"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	add_child(body)
	var stone := MaterialLibrary.get_tinted("stone_trim", Color(0.95, 0.92, 0.85))
	var mb := MeshBuilder.new()
	var z := STREET_HALF_LEN - 0.7
	var w := FACADE_X * 2.0
	mb.add_box(Vector3(w, 0.3, 1.4), Vector3(0, 0.15, z), stone) # stylobate
	_box_collider(body, Vector3(w, 0.3, 1.4), Vector3(0, 0.15, z))
	var top := 6.6
	for x: float in [-5.9, -3.6, -1.2, 1.2, 3.6, 5.9]:
		mb.add_cylinder(0.34, 0.34, 0.2, Vector3(x, 0.4, z), stone, 16) # base
		mb.add_cylinder(0.26, 0.3, top - 0.8, Vector3(x, 0.5 + (top - 0.8) * 0.5, z), stone, 16) # shaft
		for k in 12:
			var a := TAU * k / 12.0
			mb.add_box(Vector3(0.035, top - 1.0, 0.035), Vector3(x + cos(a) * 0.28, 0.5 + (top - 0.8) * 0.5, z + sin(a) * 0.28), stone) # fluting
		mb.add_cylinder(0.42, 0.3, 0.45, Vector3(x, top - 0.1, z), stone, 12) # capital bell
		mb.add_box(Vector3(0.9, 0.12, 0.9), Vector3(x, top + 0.18, z), stone) # abacus
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.32
		cyl.height = top
		cs.shape = cyl
		cs.position = Vector3(x, top * 0.5, z)
		body.add_child(cs)
	mb.add_box(Vector3(w + 0.4, 1.0, 1.7), Vector3(0, top + 0.74, z), stone) # entablature
	mb.add_box(Vector3(w + 0.7, 0.2, 1.9), Vector3(0, top + 1.34, z), stone) # cornice
	_box_collider(body, Vector3(w + 0.4, 1.2, 1.7), Vector3(0, top + 0.84, z))
	# Pediment: a low triangular gable.
	var ped := PrismMesh.new()
	ped.size = Vector3(w + 0.6, 1.8, 1.6)
	mb.add_mesh(ped, Transform3D(Basis.IDENTITY, Vector3(0, top + 2.34, z)), stone)
	mb.add_box(Vector3(w * 0.72, 0.14, 0.1), Vector3(0, top + 0.74, z - 0.86), MaterialLibrary.get_material("gilt_letters")) # gilt name band
	mb.build_into(self, "BankPorticoMesh").gi_mode = GeometryInstance3D.GI_MODE_STATIC


# ---------------------------------------------------------------------------
# Alley with a timber stair (test for steps, stairs and fall damage)
# ---------------------------------------------------------------------------
func _build_alley() -> void:
	var alley := StaticBody3D.new()
	alley.name = "Alley"
	alley.collision_layer = 1
	alley.collision_mask = 0
	add_child(alley)
	var mb := MeshBuilder.new()
	var wood := MaterialLibrary.get_material("wood_planks")
	var brick := MaterialLibrary.get_material("brick_yellow")
	var width_z := ALLEY_Z1 - ALLEY_Z0
	var zc := (ALLEY_Z0 + ALLEY_Z1) * 0.5

	# Cobbled alley floor (same height as the pavement) and back wall.
	var floor_len := ALLEY_END_X - FACADE_X
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(floor_len, width_z)
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "AlleyFloor"
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = MaterialLibrary.get_for_uv_plane("cobblestone", floor_mesh.size)
	floor_mi.position = Vector3(FACADE_X + floor_len * 0.5, PAVE_TOP, zc)
	add_child(floor_mi)
	_box_collider(alley, Vector3(floor_len, 0.3, width_z), Vector3(FACADE_X + floor_len * 0.5, PAVE_TOP - 0.15, zc))
	mb.add_box(Vector3(0.4, 12.0, width_z), Vector3(ALLEY_END_X + 0.2, 6.0, zc), brick)
	_box_collider(alley, Vector3(0.4, 12.0, width_z), Vector3(ALLEY_END_X + 0.2, 6.0, zc))

	# Flight 1: solid steps from the alley floor up to the 4.5 m landing, along the south wall.
	var steps := 25
	var run := 0.3
	var rise := (4.5 - PAVE_TOP) / steps
	var f1_z0 := ALLEY_Z0 + 0.05
	var f1_w := 1.1
	var x_start := 8.0
	for k in steps:
		var top := PAVE_TOP + (k + 1) * rise
		var size := Vector3(run, top - PAVE_TOP, f1_w)
		var center := Vector3(x_start + (k + 0.5) * run, PAVE_TOP + size.y * 0.5, f1_z0 + f1_w * 0.5)
		_box_collider(alley, size, center, "wood")
		mb.add_box(Vector3(run + 0.03, 0.05, f1_w), Vector3(center.x, top - 0.025, center.z), wood) # tread
		mb.add_box(Vector3(0.03, rise, f1_w), Vector3(center.x - run * 0.5, top - rise * 0.5, center.z), wood) # riser
	var x_land := x_start + steps * run # 15.5
	_add_stringer(mb, wood, Vector3(x_start, PAVE_TOP, f1_z0 + f1_w), Vector3(x_land, 4.5, f1_z0 + f1_w))

	# Landing at 4.5 m spanning the full alley width.
	var land_size := Vector3(2.0, 0.15, width_z)
	var land_c := Vector3(x_land + 1.0, 4.5 - 0.075, zc)
	mb.add_box(land_size, land_c, wood)
	_box_collider(alley, land_size, land_c, "wood")

	# Flight 2: open treads back towards the street, rising to the 9 m platform.
	var f2_z0 := ALLEY_Z0 + 1.25
	var f2_w := 1.1
	var rise2 := (9.0 - 4.5) / steps
	for k in steps:
		var top := 4.5 + (k + 1) * rise2
		var cx := x_land - (k + 0.5) * run
		var size := Vector3(run, 0.18, f2_w)
		var center := Vector3(cx, top - 0.09, f2_z0 + f2_w * 0.5)
		mb.add_box(Vector3(run + 0.03, 0.05, f2_w), Vector3(cx, top - 0.025, center.z), wood)
		_box_collider(alley, size, center, "wood")
	_add_stringer(mb, wood, Vector3(x_land, 4.5, f2_z0 + f2_w), Vector3(x_land - steps * run, 9.0, f2_z0 + f2_w))
	_add_stringer(mb, wood, Vector3(x_land, 4.5, f2_z0), Vector3(x_land - steps * run, 9.0, f2_z0))

	# Top platform at 9 m, over the alley mouth. Jump off it to test heavy fall damage.
	var top_x0 := FACADE_X + 0.2
	var top_x1 := x_land - steps * run
	var top_size := Vector3(top_x1 - top_x0, 0.15, width_z)
	var top_c := Vector3((top_x0 + top_x1) * 0.5, 9.0 - 0.075, zc)
	mb.add_box(top_size, top_c, wood)
	_box_collider(alley, top_size, top_c, "wood")
	# Handrail along the street side of the platform.
	mb.add_box(Vector3(0.08, 1.0, width_z), Vector3(top_x0 + 0.04, 9.5, zc), wood)
	_box_collider(alley, Vector3(0.08, 1.0, width_z), Vector3(top_x0 + 0.04, 9.5, zc))
	# Handrail across the open end of the 4.5 m landing.
	mb.add_box(Vector3(0.08, 1.0, width_z), Vector3(x_land + 1.96, 5.0, zc), wood)
	_box_collider(alley, Vector3(0.08, 1.0, width_z), Vector3(x_land + 1.96, 5.0, zc))

	# Timber posts under the landing and platform.
	for p: Vector3 in [
		Vector3(x_land + 1.9, 0, ALLEY_Z0 + 0.12), Vector3(x_land + 1.9, 0, ALLEY_Z1 - 0.12),
		Vector3(top_x0 + 0.1, 0, ALLEY_Z1 - 0.12), Vector3(top_x1 - 0.1, 0, ALLEY_Z1 - 0.12),
	]:
		var h := 4.35 if p.x > 12.0 else 8.85
		mb.add_box(Vector3(0.16, h, 0.16), Vector3(p.x, PAVE_TOP + h * 0.5, p.z), wood)
		_box_collider(alley, Vector3(0.16, h, 0.16), Vector3(p.x, PAVE_TOP + h * 0.5, p.z))

	mb.build_into(self, "AlleyMesh").gi_mode = GeometryInstance3D.GI_MODE_STATIC

	_build_laundry()

	# The alley is a private yard: anyone seen in it is trespassing.
	var zone := RestrictedZone.new()
	zone.name = "PrivateYard"
	zone.zone_name = "Hargreaves' yard"
	zone.set_box(Vector3(ALLEY_END_X - FACADE_X, 12.0, width_z), Vector3((FACADE_X + ALLEY_END_X) * 0.5, 6.0, zc))
	add_child(zone)


## Washing lines strung across the yard. The linen sways with the wind (global shader
## parameters set by WeatherEffects).
func _build_laundry() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
global uniform float wind_strength;
uniform vec3 cloth_color : source_color = vec3(0.85);
void vertex() {
	float t = TIME * (1.2 + wind_strength * 3.0) + NODE_POSITION_WORLD.z * 1.7 + VERTEX.x * 2.0;
	float sway = sin(t) * 0.6 + sin(t * 2.3 + 1.0) * 0.4;
	VERTEX.z += sway * (0.04 + wind_strength * 0.35) * UV.y;
	VERTEX.x += sin(t * 1.7) * wind_strength * 0.04 * UV.y;
}
void fragment() {
	ALBEDO = cloth_color;
	ROUGHNESS = 0.92;
}
"""
	var line_mat := MaterialLibrary.get_tinted("wood_painted", Color(0.55, 0.5, 0.42))
	var colors: Array[Color] = [Color(0.86, 0.84, 0.78), Color(0.8, 0.8, 0.76), Color(0.55, 0.12, 0.1), Color(0.3, 0.33, 0.45), Color(0.9, 0.88, 0.82)]
	var sizes: Array[Vector2] = [Vector2(0.9, 0.7), Vector2(0.5, 0.75), Vector2(0.6, 0.85), Vector2(0.45, 0.55), Vector2(0.8, 0.6)]
	var laundry := Node3D.new()
	laundry.name = "Laundry"
	add_child(laundry)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for line_x: float in [9.6, 18.4]:
		var y := 3.7 if line_x < 12.0 else 3.1
		var cord := CylinderMesh.new()
		cord.top_radius = 0.006
		cord.bottom_radius = 0.006
		cord.height = ALLEY_Z1 - ALLEY_Z0
		var cmi := MeshInstance3D.new()
		cmi.mesh = cord
		cmi.material_override = line_mat
		cmi.position = Vector3(line_x, y, (ALLEY_Z0 + ALLEY_Z1) * 0.5)
		cmi.rotation_degrees = Vector3(90, 0, 0)
		laundry.add_child(cmi)
		var z := ALLEY_Z0 + 0.25
		while z < ALLEY_Z1 - 0.5:
			var i := rng.randi() % colors.size()
			var q := QuadMesh.new()
			q.size = sizes[i]
			q.center_offset = Vector3(0, -sizes[i].y * 0.5, 0)
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("cloth_color", colors[i])
			var g := MeshInstance3D.new()
			g.mesh = q
			g.material_override = m
			g.position = Vector3(line_x, y, z + sizes[i].x * 0.5)
			g.rotation.y = PI * 0.5
			laundry.add_child(g)
			z += sizes[i].x + rng.randf_range(0.08, 0.2)


func _add_stringer(mb: MeshBuilder, mat: Material, from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var length := dir.length()
	var z_axis := dir.normalized()
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis)
	mb.add_box(Vector3(0.06, 0.22, length), (from + to) * 0.5 + Vector3(0, -0.1, 0), mat, Basis(x_axis, y_axis, z_axis))


# ---------------------------------------------------------------------------
# Lamps, props, landmarks
# ---------------------------------------------------------------------------
func _build_lamps() -> void:
	var lamp_x := ROAD_HALF + KERB_W + 0.35
	var zs_east: Array[float] = [-38.0, -24.0, -10.0, 18.0, 32.0]
	var zs_west: Array[float] = [-31.0, -17.0, -3.0, 11.0, 25.0, 39.0]
	for z in zs_east:
		_add_lamp(Vector3(lamp_x, PAVE_TOP, z))
	for z in zs_west:
		_add_lamp(Vector3(-lamp_x, PAVE_TOP, z))
	_add_lamp(Vector3(FACADE_X + 0.9, PAVE_TOP, ALLEY_Z1 - 0.35)) # one lamp inside the alley mouth


func _add_lamp(pos: Vector3) -> void:
	var lamp := GasLamp.new()
	lamp.position = pos
	lamp.flower_baskets = true
	add_child(lamp)


func _build_props() -> void:
	# Props and landmarks get their own seed, so changing the terraces never moves them.
	_rng.seed = layout_seed + 7919
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	# Stacked crates and barrels outside shops and in the alley.
	var spots: Array[Vector3] = [
		Vector3(5.5, PAVE_TOP, -20.0), Vector3(-5.6, PAVE_TOP, 14.0), Vector3(18.9, PAVE_TOP, 4.7),
		Vector3(18.9, PAVE_TOP, 5.9), Vector3(-5.5, PAVE_TOP, -35.0),
	]
	for i in spots.size():
		var base := spots[i]
		var crate := StreetProps.make_crate(0.6)
		crate.position = base + Vector3(0, 0.3, 0)
		crate.rotation.y = _rng.randf_range(-0.3, 0.3)
		props.add_child(crate)
		if i % 2 == 0:
			var top_crate := StreetProps.make_crate(0.5)
			top_crate.position = base + Vector3(0.03, 0.86, 0.02)
			top_crate.rotation.y = _rng.randf_range(-0.5, 0.5)
			props.add_child(top_crate)
		var barrel := StreetProps.make_barrel()
		var offset := Vector3(-0.8, 0, 0) if base.x > FACADE_X else Vector3(0, 0, 0.8 if i % 2 == 0 else -0.8)
		barrel.position = base + Vector3(0, 0.43, 0) + offset
		props.add_child(barrel)
	# A granite horse trough at the kerb: a classic vault obstacle.
	var trough := StreetProps.make_horse_trough()
	trough.position = Vector3(-3.3, 0.0, 20.0)
	props.add_child(trough)
	# A heap of hay delivered for a nearby stable: crouch inside it to hide.
	var hay := StreetProps.make_hay_heap()
	hay.position = Vector3(-2.7, 0.0, 12.5)
	props.add_child(hay)
	var cart := StreetProps.make_handcart()
	cart.position = Vector3(-2.7, 0.0, -8.0)
	cart.rotation.y = 0.12
	props.add_child(cart)
	var cart2 := StreetProps.make_handcart()
	cart2.position = Vector3(2.9, 0.0, 24.0)
	cart2.rotation.y = PI - 0.08
	props.add_child(cart2)


## A church tower and spire far down the street, visible over the rooftops.
func _box_collider(body: StaticBody3D, size: Vector3, center: Vector3, surface: String = "") -> void:
	var cs := CollisionShape3D.new()
	if surface != "":
		cs.set_meta("surface", surface)
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	body.add_child(cs)
