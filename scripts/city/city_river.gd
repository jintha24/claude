class_name CityRiver
extends Node3D
## The Thames through the city: the tidal river between granite embankment walls, the
## riverside walks with their lamps and parapets, four stone bridges on arches, iron
## ladders down the walls, and barges and wherries moving on the water.
##
## Built once (it's long and simple). The water is shallow enough to wade at the edges of
## the channel (WaterVolume), so a fall from a bridge isn't the end of Harry.

var plan: CityPlan

const WALL_TOP := CityPlan.PAVE_TOP
const DECK_Y := 0.0
const LADDER_SPACING := 90.0

var _boats: Array[Node3D] = []
var _boat_speed: Array[float] = []


func _ready() -> void:
	if plan == null:
		plan = CityPlan.new()
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	add_child(body)
	_build_channel(mb, body)
	_build_walks(mb, body)
	for x in plan.bridges:
		_build_bridge(mb, body, x)
	_build_ladders(mb)
	var mi := mb.build_into(self, "River")
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_build_water()
	_build_boats()
	var wv := WaterVolume.new()
	wv.name = "Water"
	wv.position = Vector3(-CityPlan.HALF - 400.0, CityPlan.BED_Y, CityPlan.RIVER_Z0)
	wv.size = Vector3(CityPlan.HALF * 2.0 + 800.0, CityPlan.WATER_Y - CityPlan.BED_Y, CityPlan.RIVER_Z1 - CityPlan.RIVER_Z0)
	add_child(wv)


func _process(delta: float) -> void:
	# Barges drift down on the ebb and are rowed up again; wrap round at the city's edge.
	for i in _boats.size():
		var b := _boats[i]
		b.position.x += _boat_speed[i] * delta
		if b.position.x > CityPlan.HALF + 200.0:
			b.position.x = -CityPlan.HALF - 200.0
		elif b.position.x < -CityPlan.HALF - 200.0:
			b.position.x = CityPlan.HALF + 200.0
		b.position.y = CityPlan.WATER_Y - 0.25 + sin(Time.get_ticks_msec() * 0.001 * 0.8 + i) * 0.04


func _box(mb: MeshBuilder, body: StaticBody3D, size: Vector3, center: Vector3, mat: Material, solid := true) -> void:
	mb.add_box(size, center, mat)
	if solid:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = center
		body.add_child(cs)


## The river bed and the embankment walls, the full width of the city and beyond.
func _build_channel(mb: MeshBuilder, body: StaticBody3D) -> void:
	var granite := MaterialLibrary.get_tinted("stone_trim", Color(0.72, 0.7, 0.66))
	var mud := MaterialLibrary.get_tinted("dirt", Color(0.36, 0.32, 0.26))
	var length := CityPlan.HALF * 2.0 + 800.0
	var z0 := CityPlan.RIVER_Z0
	var z1 := CityPlan.RIVER_Z1
	var depth := WALL_TOP - (CityPlan.BED_Y - 1.0)
	# Walls: 1 m thick, from the bed to the walk.
	_box(mb, body, Vector3(length, depth, 1.0), Vector3(0, WALL_TOP - depth * 0.5, z0 + 0.5), granite)
	_box(mb, body, Vector3(length, depth, 1.0), Vector3(0, WALL_TOP - depth * 0.5, z1 - 0.5), granite)
	# The bed (mud) with a firm floor under it.
	_box(mb, body, Vector3(length, 1.0, z1 - z0), Vector3(0, CityPlan.BED_Y - 0.5, (z0 + z1) * 0.5), mud)


## The riverside walks: pavement, a granite parapet at the water's edge, and gaps for the
## bridges and the steps.
func _build_walks(mb: MeshBuilder, body: StaticBody3D) -> void:
	var paving := MaterialLibrary.get_material("pavement")
	var granite := MaterialLibrary.get_material("curb_granite")
	var parapet := MaterialLibrary.get_tinted("stone_trim", Color(0.78, 0.76, 0.72))
	var cuts: Array[Vector2] = []
	for x in plan.bridges:
		cuts.append(Vector2(x - CityPlan.ART_ROAD * 0.5 - CityPlan.ART_PAVE, x + CityPlan.ART_ROAD * 0.5 + CityPlan.ART_PAVE))
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var spans: Array[Vector2] = []
	var x := -CityPlan.HALF
	for c in cuts:
		spans.append(Vector2(x, c.x))
		x = c.y
	spans.append(Vector2(x, CityPlan.HALF))
	for north: bool in [true, false]:
		var z_road := CityPlan.RIVER_Z0 - CityPlan.WALK if north else CityPlan.RIVER_Z1
		var z_wall := CityPlan.RIVER_Z0 if north else CityPlan.RIVER_Z1
		for s in spans:
			var len := s.y - s.x
			var cx := (s.x + s.y) * 0.5
			var size := Vector3(len, 0.45, CityPlan.WALK)
			_box(mb, body, size, Vector3(cx, WALL_TOP - 0.225, z_road + CityPlan.WALK * 0.5), paving)
			# The kerb on the road side.
			var kz := z_road if north else z_road + CityPlan.WALK
			mb.add_box(Vector3(len, 0.2, 0.3), Vector3(cx, WALL_TOP - 0.1, kz + (0.15 if north else -0.15)), granite)
			# Parapet (1.1 m) along the water side, with piers every 12 m.
			var pz := z_wall - 0.3 if north else z_wall + 0.3
			_box(mb, body, Vector3(len, 1.0, 0.45), Vector3(cx, WALL_TOP + 0.5, pz), parapet)
			mb.add_box(Vector3(len, 0.12, 0.6), Vector3(cx, WALL_TOP + 1.06, pz), parapet)
			var n := int(len / 12.0)
			for k in n + 1:
				var px := s.x + len * float(k) / float(maxi(n, 1))
				mb.add_box(Vector3(0.7, 1.3, 0.7), Vector3(px, WALL_TOP + 0.65, pz), parapet)


## A stone bridge: carriageway, pavements, parapets, and piers with arches between them.
func _build_bridge(mb: MeshBuilder, body: StaticBody3D, x: float) -> void:
	var stone := MaterialLibrary.get_tinted("stone_trim", Color(0.8, 0.78, 0.73))
	var road := MaterialLibrary.get_for_uv_plane("cobblestone", Vector2(CityPlan.ART_ROAD, CityPlan.RIVER_Z1 - CityPlan.RIVER_Z0 + CityPlan.WALK * 2.0))
	var paving := MaterialLibrary.get_material("pavement")
	var z0 := CityPlan.RIVER_Z0 - CityPlan.WALK
	var z1 := CityPlan.RIVER_Z1 + CityPlan.WALK
	var length := z1 - z0
	var cz := (z0 + z1) * 0.5
	var half_w := CityPlan.ART_ROAD * 0.5 + CityPlan.ART_PAVE
	# Deck: carriageway at road level, pavements raised either side.
	var deck := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CityPlan.ART_ROAD, length)
	deck.mesh = plane
	deck.material_override = road
	deck.position = Vector3(x, DECK_Y + 0.01, cz)
	deck.name = "Deck%d" % int(x)
	add_child(deck)
	_box(mb, body, Vector3(CityPlan.ART_ROAD, 1.6, length), Vector3(x, DECK_Y - 0.8, cz), stone, true)
	for side: float in [-1.0, 1.0]:
		var px := x + side * (CityPlan.ART_ROAD * 0.5 + CityPlan.ART_PAVE * 0.5)
		_box(mb, body, Vector3(CityPlan.ART_PAVE, 1.75, length), Vector3(px, CityPlan.PAVE_TOP - 0.875, cz), paving)
		# Balustraded parapet.
		var bx := x + side * (half_w + 0.25)
		_box(mb, body, Vector3(0.5, 1.15, length), Vector3(bx, CityPlan.PAVE_TOP + 0.575, cz), stone)
		mb.add_box(Vector3(0.7, 0.15, length), Vector3(bx, CityPlan.PAVE_TOP + 1.22, cz), stone)
		# The outer face of the deck (the spandrels) down to the arches.
		mb.add_box(Vector3(0.4, 2.4, length), Vector3(x + side * (half_w + 0.3), DECK_Y - 1.2, cz), stone)
	# Low granite piers with cutwaters, and shallow segmental arches between them.
	var spans := 9
	var span_len := (CityPlan.RIVER_Z1 - CityPlan.RIVER_Z0) / spans
	var crown := DECK_Y - 1.6
	var half_angle := 0.35
	var r := span_len * 0.5 / sin(half_angle)
	var spring := crown - r * (1.0 - cos(half_angle))
	for k in range(1, spans):
		var pz := CityPlan.RIVER_Z0 + span_len * k
		var ph := spring + 0.6 - CityPlan.BED_Y
		_box(mb, body, Vector3(half_w * 2.0 + 1.6, ph, 4.0), Vector3(x, CityPlan.BED_Y + ph * 0.5, pz), stone)
		for side: float in [-1.0, 1.0]:
			mb.add_cylinder(2.0, 2.0, ph, Vector3(x + side * (half_w + 0.8), CityPlan.BED_Y + ph * 0.5, pz), stone, 8)
		# The spandrel wall above the pier, up to the deck.
		_box(mb, body, Vector3(half_w * 2.0 + 0.6, crown - spring + 0.2, 4.0), Vector3(x, (crown + spring) * 0.5, pz), stone)
	for k in spans:
		var az := CityPlan.RIVER_Z0 + span_len * (k + 0.5)
		var segs := 8
		for sgm in segs:
			var a0 := lerpf(-half_angle, half_angle, float(sgm) / segs)
			var a1 := lerpf(-half_angle, half_angle, float(sgm + 1) / segs)
			var p0 := Vector2(az + r * sin(a0), crown - r + r * cos(a0))
			var p1 := Vector2(az + r * sin(a1), crown - r + r * cos(a1))
			var mid := (p0 + p1) * 0.5
			var seg_len := p0.distance_to(p1)
			var ang := atan2(-(p1.y - p0.y), p1.x - p0.x)
			# The soffit (underside) spans the bridge's width; the arch ring shows on each face.
			mb.add_box(Vector3(half_w * 2.0 + 0.6, 0.5, seg_len + 0.04), Vector3(x, mid.y - 0.25, mid.x), stone, Basis(Vector3.RIGHT, ang))


## Iron ladders down the embankment walls (climbable, like drainpipes).
func _build_ladders(mb: MeshBuilder) -> void:
	var iron := MaterialLibrary.get_material("iron")
	var n := int(CityPlan.HALF * 2.0 / LADDER_SPACING)
	for north: bool in [true, false]:
		for k in n:
			var x := -CityPlan.HALF + LADDER_SPACING * (k + 0.5)
			var near_bridge := false
			for bx in plan.bridges:
				if absf(x - bx) < 20.0:
					near_bridge = true
			if near_bridge:
				continue
			var z := CityPlan.RIVER_Z0 + 0.12 if north else CityPlan.RIVER_Z1 - 0.12
			var h := WALL_TOP - CityPlan.BED_Y
			var yc := CityPlan.BED_Y + h * 0.5
			for side: float in [-0.22, 0.22]:
				mb.add_box(Vector3(0.05, h, 0.05), Vector3(x + side, yc, z), iron)
			var rungs := int(h / 0.3)
			for r in rungs:
				mb.add_box(Vector3(0.44, 0.03, 0.03), Vector3(x, CityPlan.BED_Y + 0.3 * (r + 0.5), z), iron)
			var pipe := StaticBody3D.new()
			pipe.name = "Ladder"
			pipe.collision_layer = 1 << 4
			pipe.collision_mask = 0
			pipe.add_to_group("climbable_pipe")
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.08
			cyl.height = h
			cs.shape = cyl
			pipe.add_child(cs)
			pipe.position = Vector3(x, yc, z)
			add_child(pipe)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(CityPlan.HALF * 2.0 + 1800.0, CityPlan.RIVER_Z1 - CityPlan.RIVER_Z0)
	plane.subdivide_width = 32
	plane.subdivide_depth = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.14, 0.11, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.15
	mat.metallic_specular = 0.8
	var water := MeshInstance3D.new()
	water.name = "Surface"
	water.mesh = plane
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0, CityPlan.WATER_Y, (CityPlan.RIVER_Z0 + CityPlan.RIVER_Z1) * 0.5)
	add_child(water)


## Sailing barges with their brown sails, lighters and a few wherries.
func _build_boats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1866
	var hull := MaterialLibrary.get_tinted("wood_planks", Color(0.3, 0.22, 0.16))
	var tar := MaterialLibrary.get_tinted("wood_planks", Color(0.12, 0.1, 0.09))
	var sail := MaterialLibrary.get_tinted("canvas", Color(0.55, 0.28, 0.16))
	var sail_mat := sail.duplicate() as StandardMaterial3D
	sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 18:
		var kind := i % 3
		var mb := MeshBuilder.new()
		var boat := Node3D.new()
		boat.name = "Boat%d" % i
		match kind:
			0: # Thames sailing barge
				mb.add_box(Vector3(24.0, 1.8, 5.6), Vector3(0, 0.6, 0), tar)
				mb.add_box(Vector3(22.0, 0.2, 5.0), Vector3(0, 1.55, 0), hull)
				mb.add_box(Vector3(4.0, 0.6, 3.0), Vector3(-8.0, 1.9, 0), hull)
				mb.add_cylinder(0.14, 0.1, 16.0, Vector3(2.0, 9.0, 0), hull, 6)
				mb.add_box(Vector3(9.0, 11.0, 0.05), Vector3(-2.4, 8.0, 0), sail_mat, Basis(Vector3.FORWARD, 0.08))
			1: # lighter (a dumb barge), loaded with sacks
				mb.add_box(Vector3(14.0, 1.4, 4.4), Vector3(0, 0.5, 0), tar)
				for k in 5:
					mb.add_box(Vector3(2.0, 0.6, 3.6), Vector3(-5.0 + k * 2.4, 1.4, 0), MaterialLibrary.get_material("canvas"))
			_: # a waterman's wherry
				mb.add_box(Vector3(6.5, 0.6, 1.4), Vector3(0, 0.3, 0), hull)
				mb.add_box(Vector3(0.3, 0.1, 1.2), Vector3(0.5, 0.65, 0), hull)
		var mi := mb.build_into(boat, "Hull", kind != 2)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var lane := rng.randf_range(0.15, 0.85)
		boat.position = Vector3(rng.randf_range(-CityPlan.HALF, CityPlan.HALF), CityPlan.WATER_Y, lerpf(CityPlan.RIVER_Z0 + 20.0, CityPlan.RIVER_Z1 - 20.0, lane))
		var dir := 1.0 if lane < 0.5 else -1.0
		boat.rotation.y = 0.0 if dir > 0.0 else PI
		add_child(boat)
		_boats.append(boat)
		_boat_speed.append(dir * (rng.randf_range(0.6, 1.4) if kind != 2 else rng.randf_range(1.2, 2.0)))
		if i >= 14:
			# Moored at the walls.
			_boat_speed[-1] = 0.0
			boat.position.z = CityPlan.RIVER_Z0 + 5.0 if i % 2 == 0 else CityPlan.RIVER_Z1 - 5.0
