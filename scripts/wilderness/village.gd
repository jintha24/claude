class_name Village
extends Node3D
## A village in the hills (TerrainGenerator.VILLAGES): cottages along the road and round
## the green, the parish church, a coaching inn with its sign, a smithy, barns and ricks,
## a pond and a well on the green, gardens behind picket fences - and the villagers going
## about their day (VillageFolk).
##
## Built once when the hills load, on level ground the terrain keeps for it. Each village is
## a few merged meshes (one draw call per material) with simple box collision.

const INN_NAMES: Array[String] = ["THE BLACK BULL", "THE WHITE HART", "THE PLOUGH", "THE BELL", "THE SPANIARDS INN", "THE FLASK"]

@export var index: int = 0

var gen: TerrainGenerator
var village_name := ""
var centre := Vector2.ZERO
var radius := 60.0
var ground_y := 0.0
## Where villagers go: [position, kind] (door, green, road, inn, church, smithy, field).
var spots: Array = []

var _rng := RandomNumberGenerator.new()
var _mb := MeshBuilder.new()
var _body: StaticBody3D
var _mats := {}
var _footprints: Array[Rect2] = [] # rough, axis-aligned, for keeping buildings apart
var _road_dir := Vector2.RIGHT
## The point of the road (or lane) nearest the village centre: the frontages line up on it.
var _road_c := Vector2.ZERO


func setup(generator: TerrainGenerator, i: int) -> void:
	gen = generator
	index = i
	var v: Array = TerrainGenerator.VILLAGES[i]
	village_name = v[0]
	centre = v[1]
	radius = v[2]
	ground_y = gen.village_height(i)


func _ready() -> void:
	if gen == null:
		return
	name = "Village_" + village_name.replace(" ", "")
	add_to_group("villages")
	_rng.seed = 1866 + index * 101
	_make_materials()
	_body = StaticBody3D.new()
	_body.name = "Solid"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	add_child(_body)
	_road_dir = _find_road_dir()
	_build_green()
	_build_round_green()
	_build_along_road()
	_build_farmyard()
	var mi := _mb.build_into(self, "Buildings")
	if mi:
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = 1400.0
	_spawn_folk()


func _make_materials() -> void:
	_mats["plaster"] = MaterialLibrary.get_tinted("plaster", Color(0.93, 0.91, 0.84))
	_mats["plaster2"] = MaterialLibrary.get_tinted("plaster", Color(0.9, 0.84, 0.7))
	_mats["brick"] = MaterialLibrary.get_material("brick_red")
	_mats["flint"] = MaterialLibrary.get_tinted("rock", Color(0.62, 0.6, 0.56))
	_mats["timber"] = MaterialLibrary.get_tinted("wood_planks", Color(0.26, 0.19, 0.14))
	_mats["wood"] = MaterialLibrary.get_tinted("wood_planks", Color(0.5, 0.4, 0.3))
	_mats["paint"] = MaterialLibrary.get_tinted("wood_painted", Color(0.1, 0.2, 0.14))
	_mats["white"] = MaterialLibrary.get_tinted("wood_painted", Color(0.88, 0.87, 0.82))
	_mats["tiles"] = MaterialLibrary.get_tinted("slate_roof", Color(0.78, 0.42, 0.3))
	_mats["slate"] = MaterialLibrary.get_material("slate_roof")
	_mats["stone"] = MaterialLibrary.get_tinted("stone_trim", Color(0.8, 0.77, 0.7))
	_mats["iron"] = MaterialLibrary.get_material("iron")
	_mats["water"] = MaterialLibrary.get_material("water")
	_mats["gravel"] = MaterialLibrary.get_material("gravel")
	var thatch := StandardMaterial3D.new()
	thatch.resource_name = "thatch"
	if ResourceLoader.exists(StreetProps.HAY_TEX + "hay_diff.jpg"):
		thatch.albedo_texture = load(StreetProps.HAY_TEX + "hay_diff.jpg")
		thatch.albedo_color = Color(0.78, 0.68, 0.5)
	else:
		thatch.albedo_color = Color(0.55, 0.46, 0.3)
	thatch.roughness = 1.0
	thatch.uv1_triplanar = true
	thatch.uv1_world_triplanar = true
	thatch.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_mats["thatch"] = thatch
	for g in 3:
		_mats["glass_%d" % g] = MaterialLibrary.get_material("glass_%d" % g)


## A point on the ground (the village's ground slopes gently with the road).
func _p(local: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(local.x, gen.height(local.x, local.y) + y, local.y)


func _solid(size: Vector3, center: Vector3, mat_key: String, basis := Basis.IDENTITY, collide := true) -> void:
	_mb.add_box(size, center, _mats[mat_key], basis)
	if collide:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.transform = Transform3D(basis, center)
		_body.add_child(cs)


## The direction the road (or lane) runs through the village.
func _find_road_dir() -> Vector2:
	var best := Vector2.RIGHT
	var best_d := INF
	for path: Array in [TerrainGenerator.ROAD] + TerrainGenerator.LANES:
		for k in path.size() - 1:
			var a: Vector2 = path[k]
			var b: Vector2 = path[k + 1]
			var ab := b - a
			var t := clampf((centre - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d := centre.distance_to(a + ab * t)
			if d < best_d:
				best_d = d
				best = ab.normalized()
				_road_c = a + ab * t
	return best


func _free_at(r: Rect2) -> bool:
	for f in _footprints:
		if f.intersects(r):
			return false
	return gen.road_info(r.get_center().x, r.get_center().y).x > TerrainGenerator.ROAD_HALF_WIDTH + 2.0 + minf(r.size.x, r.size.y) * 0.5


# ---------------------------------------------------------------------------
# The green: grass, a pond, the well, a maypole
# ---------------------------------------------------------------------------
var _green := Vector2.ZERO
const GREEN_R := 20.0


func _build_green() -> void:
	var side := Vector2(-_road_dir.y, _road_dir.x)
	_green = centre + side * 26.0
	_footprints.append(Rect2(_green - Vector2(GREEN_R, GREEN_R), Vector2(GREEN_R, GREEN_R) * 2.0))
	# Pond with a low stone kerb (shallow enough to wade).
	var pond := _green + side.rotated(0.9) * 9.0
	var water := CylinderMesh.new()
	water.top_radius = 5.0
	water.bottom_radius = 5.0
	water.height = 0.05
	water.radial_segments = 24
	_mb.add_mesh(water, Transform3D(Basis.IDENTITY, _p(pond, 0.06)), _mats["water"])
	for k in 20:
		var a := TAU * k / 20.0
		_mb.add_box(Vector3(0.5, 0.18, 1.7), _p(pond + Vector2(cos(a), sin(a)) * 5.2, 0.09), _mats["stone"], Basis(Vector3.UP, -a))
	# The well: a round stone wall, a little roof on posts, a windlass.
	var well := _green - side.rotated(0.5) * 8.0
	var wp := _p(well)
	_mb.add_cylinder(0.95, 0.95, 0.8, wp + Vector3(0, 0.4, 0), _mats["stone"], 12)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.95
	cyl.height = 0.8
	cs.shape = cyl
	cs.position = wp + Vector3(0, 0.4, 0)
	_body.add_child(cs)
	for s: float in [-0.8, 0.8]:
		_mb.add_box(Vector3(0.12, 2.2, 0.12), wp + Vector3(s, 1.1, 0), _mats["timber"])
	_mb.add_box(Vector3(2.2, 0.08, 1.4), wp + Vector3(0, 2.35, 0.3), _mats["tiles"], Basis(Vector3.RIGHT, 0.45))
	_mb.add_box(Vector3(2.2, 0.08, 1.4), wp + Vector3(0, 2.35, -0.3), _mats["tiles"], Basis(Vector3.RIGHT, -0.45))
	_mb.add_cylinder(0.1, 0.1, 1.5, wp + Vector3(0, 1.5, 0), _mats["wood"], 8, Basis(Vector3.FORWARD, PI * 0.5))
	# The maypole.
	var pole := _green + side.rotated(-1.2) * 11.0
	_solid(Vector3(0.25, 7.0, 0.25), _p(pole, 3.5), "white")
	spots.append([_p(_green), "green"])
	spots.append([_p(pond + Vector2(6.0, 0.0)), "green"])
	spots.append([_p(well + side * 1.8), "well"])


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
## A building facing `facing` (unit, in the xz plane) with its front centre at `front`.
func _place(front: Vector2, facing: Vector2, w: float, d: float, kind: String, slack: float = 0.0) -> bool:
	var c := front - facing * d * 0.5
	var ext := Vector2(absf(facing.x) * d + absf(facing.y) * w, absf(facing.y) * d + absf(facing.x) * w)
	var r := Rect2(c - ext * 0.5, ext).grow(1.2)
	if not _free_at(r) or c.distance_to(centre) > radius - 4.0 + slack:
		return false
	_footprints.append(r)
	var yaw := atan2(facing.x, facing.y)
	var xf := Transform3D(Basis(Vector3.UP, yaw), _p(front))
	match kind:
		"church":
			_church(xf, w, d)
		"inn":
			_inn(xf, w, d)
		"smithy":
			_smithy(xf, w, d)
		"barn":
			_barn(xf, w, d)
		_:
			_cottage(xf, w, d)
	# Where people come and go: outside the gate (or the door, for the big buildings).
	var door := xf * Vector3(0, 0, 4.8 if kind == "cottage" else 2.5)
	spots.append([door, "door" if kind == "cottage" else kind])
	return true


func _build_along_road() -> void:
	var side := Vector2(-_road_dir.y, _road_dir.x)
	var placed_inn := false
	var placed_smithy := false
	for s: float in [-1.0, 1.0]:
		var t := -radius + 10.0
		while t < radius - 10.0:
			var w := _rng.randf_range(7.0, 10.0)
			var d := _rng.randf_range(5.5, 7.0)
			var kind := "cottage"
			if not placed_inn and absf(t) < 45.0 and (s < 0.0 or t > 0.0):
				kind = "inn"
				w = 15.0
				d = 9.0
			elif not placed_smithy and absf(t) > 25.0 and s > 0.0:
				kind = "smithy"
				w = 9.0
				d = 7.0
			var front := _road_c + _road_dir * (t + w * 0.5) + side * s * (TerrainGenerator.ROAD_HALF_WIDTH + 5.5)
			if _place(front, -side * s, w, d, kind):
				placed_inn = placed_inn or kind == "inn"
				placed_smithy = placed_smithy or kind == "smithy"
				if kind == "inn":
					spots.append([_p(front + side * s * 2.0), "inn"])
				if kind == "smithy":
					spots.append([_p(front + side * s * 1.8), "smithy"])
				t += w + _rng.randf_range(3.0, 9.0)
			else:
				t += 4.0
		spots.append([_p(centre + side * s * 1.0 + _road_dir * _rng.randf_range(-30.0, 30.0)), "road"])


func _build_round_green() -> void:
	# The church on the far side of the green, cottages round the rest.
	var side := Vector2(-_road_dir.y, _road_dir.x)
	# Try the far side of the green first, then either end of it.
	for k in 12:
		var dir := side.rotated(k * TAU / 12.0 * (1.0 if k % 2 == 0 else -1.0) * 0.5)
		var church_front := _green + dir * (GREEN_R + 7.0)
		if _place(church_front, -dir, 12.0, 26.0, "church", 25.0):
			spots.append([_p(church_front - dir * 2.0), "church"])
			break
	for k in 9:
		var a := _rng.randf_range(0.0, TAU)
		var dir := Vector2(cos(a), sin(a))
		if dir.dot(side) > 0.6 or dir.dot(side) < -0.5:
			continue
		var front := _green + dir * (GREEN_R + 5.0)
		_place(front, -dir, _rng.randf_range(7.0, 9.5), _rng.randf_range(5.5, 6.5), "cottage")


func _build_farmyard() -> void:
	# A barn or two and hay ricks at the edge of the village, towards the fields.
	var side := Vector2(-_road_dir.y, _road_dir.x)
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		var p := centre - side * (radius - 18.0) * (0.8 if k == 0 else 0.0) + _road_dir * s * (radius - 20.0)
		var facing := (centre - p).normalized()
		if _place(p, facing, 16.0, 9.0, "barn"):
			for r in 2:
				var rp := p - facing * 14.0 + Vector2(-facing.y, facing.x) * (r * 7.0 - 3.5)
				_rick(rp)
			spots.append([_p(p + facing * 3.0), "farm"])


func _cottage(xf: Transform3D, w: float, d: float) -> void:
	var walls := ["plaster", "plaster", "plaster2", "brick", "flint"][_rng.randi() % 5] as String
	var roof := "thatch" if _rng.randf() < 0.55 else "tiles"
	var h := 2.9 if _rng.randf() < 0.6 else 5.2 # one storey or two
	_house_mass(xf, w, d, h, walls, roof)
	# Front door and small windows (leaded casements).
	var door_x := _rng.randf_range(-w * 0.2, w * 0.2)
	_mb.add_box(Vector3(0.95, 2.0, 0.08), xf * Vector3(door_x, 1.0, 0.0), _mats["paint"], xf.basis)
	_mb.add_box(Vector3(1.4, 0.12, 0.5), xf * Vector3(door_x, 2.25, 0.2), _mats["tiles"], xf.basis)
	for wx: float in [-w * 0.32, w * 0.32]:
		if absf(wx - door_x) < 1.2:
			continue
		_window(xf, wx, 1.0, 0.9, 1.0)
		if h > 4.0:
			_window(xf, wx, 3.4, 0.8, 0.9)
	if h > 4.0:
		_window(xf, door_x, 3.4, 0.8, 0.9)
	if walls in ["plaster", "plaster2"] and _rng.randf() < 0.5:
		# Timber framing on the plaster.
		for k in int(w / 1.1) + 1:
			var x := -w * 0.5 + k * w / int(w / 1.1)
			_mb.add_box(Vector3(0.16, h, 0.06), xf * Vector3(x, h * 0.5, 0.03), _mats["timber"], xf.basis)
		_mb.add_box(Vector3(w, 0.18, 0.06), xf * Vector3(0, h - 0.1, 0.03), _mats["timber"], xf.basis)
	# Front garden with a picket fence and a gate.
	var gz := 3.2
	for s: float in [-1.0, 1.0]:
		var span := w * 0.5 - 0.7
		var cx := s * (0.7 + span * 0.5)
		_picket(xf, cx, gz, span)
	for s: float in [-1.0, 1.0]:
		_mb.add_box(Vector3(0.06, 0.95, gz), xf * Vector3(s * w * 0.5, 0.47, gz * 0.5), _mats["white"], xf.basis)


func _picket(xf: Transform3D, cx: float, z: float, span: float) -> void:
	_mb.add_box(Vector3(span, 0.06, 0.04), xf * Vector3(cx, 0.75, z), _mats["white"], xf.basis)
	_mb.add_box(Vector3(span, 0.06, 0.04), xf * Vector3(cx, 0.3, z), _mats["white"], xf.basis)
	var n := int(span / 0.14)
	for k in n:
		var x := cx - span * 0.5 + (k + 0.5) * span / n
		_mb.add_box(Vector3(0.07, 0.95, 0.02), xf * Vector3(x, 0.47, z + 0.03), _mats["white"], xf.basis)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span, 0.95, 0.1)
	cs.shape = box
	cs.transform = Transform3D(xf.basis, xf * Vector3(cx, 0.47, z))
	_body.add_child(cs)


func _window(xf: Transform3D, x: float, y: float, ww: float, wh: float) -> void:
	_mb.add_box(Vector3(ww, wh, 0.04), xf * Vector3(x, y + wh * 0.5, 0.0), _mats["glass_%d" % (_rng.randi() % 3)], xf.basis)
	_mb.add_box(Vector3(ww + 0.2, 0.1, 0.12), xf * Vector3(x, y + wh + 0.05, 0.05), _mats["timber"], xf.basis)
	_mb.add_box(Vector3(ww + 0.16, 0.08, 0.16), xf * Vector3(x, y - 0.04, 0.07), _mats["timber"], xf.basis)
	_mb.add_box(Vector3(0.05, wh, 0.05), xf * Vector3(x, y + wh * 0.5, 0.03), _mats["timber"], xf.basis)


## Walls, a steep pitched roof (ridge along the front) and a chimney.
func _house_mass(xf: Transform3D, w: float, d: float, h: float, walls: String, roof: String) -> void:
	# The walls go down into the ground so a sloping site never shows a gap underneath.
	_solid(Vector3(w, h + 2.0, d), xf * Vector3(0, h * 0.5 - 1.0, -d * 0.5), walls, xf.basis)
	var pitch := deg_to_rad(50.0 if roof == "thatch" else 40.0)
	var run := d * 0.5 + 0.4
	var rise := run * tan(pitch)
	var slope := run / cos(pitch)
	var thick := 0.35 if roof == "thatch" else 0.08
	for s: float in [-1.0, 1.0]:
		var tilt := Basis(Vector3.RIGHT, s * pitch)
		var c := Vector3(0, h + rise * 0.5, -d * 0.5 + s * run * 0.5)
		_mb.add_box(Vector3(w + 0.5, thick, slope), xf * c, _mats[roof], xf.basis * tilt)
	# Gable ends.
	var prism := PrismMesh.new()
	prism.size = Vector3(d, rise, w - 0.02)
	_mb.add_mesh(prism, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, h + rise * 0.5, -d * 0.5)), _mats[walls])
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([Vector3(-w * 0.5, h, 0.3), Vector3(-w * 0.5, h, -d - 0.3), Vector3(-w * 0.5, h + rise, -d * 0.5),
		Vector3(w * 0.5, h, 0.3), Vector3(w * 0.5, h, -d - 0.3), Vector3(w * 0.5, h + rise, -d * 0.5)])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	cs.set_meta("surface", "wood" if roof == "thatch" else "slate")
	_body.add_child(cs)
	# Chimney at one end.
	var cx := (w * 0.5 - 0.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
	_solid(Vector3(0.8, rise + 1.4, 0.9), xf * Vector3(cx, h + (rise + 1.4) * 0.5, -d * 0.5), "brick", xf.basis)
	_mb.add_cylinder(0.14, 0.11, 0.5, xf * Vector3(cx, h + rise + 1.65, -d * 0.5), MaterialLibrary.get_material("terracotta"), 8)
	if _rng.randf() < 0.6:
		var smoke := ChimneySmoke.new()
		add_child(smoke)
		smoke.global_position = xf * Vector3(cx, h + rise + 1.95, -d * 0.5)


func _church(xf: Transform3D, w: float, d: float) -> void:
	var h := 7.5
	_house_mass(xf, w, d, h, "flint", "slate")
	# Tall pointed windows down the sides.
	for s: float in [-1.0, 1.0]:
		for k in 4:
			var z := -3.0 - k * (d - 6.0) / 3.0
			var p := xf * Vector3(s * (w * 0.5 + 0.02), 3.8, z)
			_mb.add_box(Vector3(0.05, 3.2, 1.1), p, _mats["glass_%d" % (k % 3)], xf.basis)
	# West tower with battlements, over the door.
	var tw := 5.5
	var th := 17.0
	_solid(Vector3(tw, th, tw), xf * Vector3(0, th * 0.5, tw * 0.5 - 0.5), "flint", xf.basis)
	for bx: float in [-1.0, 1.0]:
		for bz: float in [-1.0, 1.0]:
			_mb.add_box(Vector3(0.8, 1.3, 0.8), xf * Vector3(bx * (tw * 0.5 - 0.4), th + 0.65, tw * 0.5 - 0.5 + bz * (tw * 0.5 - 0.4)), _mats["stone"], xf.basis)
	_mb.add_box(Vector3(1.4, 2.6, 0.1), xf * Vector3(0, 1.3, tw), _mats["timber"], xf.basis)
	_mb.add_box(Vector3(1.0, 1.6, 0.06), xf * Vector3(0, 10.5, tw - 0.47), _mats["timber"], xf.basis) # belfry louvre
	# Churchyard stones.
	for k in 14:
		var p := Vector3(_rng.randf_range(-w, w), 0.0, _rng.randf_range(-d - 6.0, -d - 1.0))
		var hs := _rng.randf_range(0.6, 1.0)
		_mb.add_box(Vector3(0.55, hs, 0.12), xf * (p + Vector3(0, hs * 0.5, 0)), _mats["stone"], xf.basis)


func _inn(xf: Transform3D, w: float, d: float) -> void:
	_house_mass(xf, w, d, 5.6, "plaster2", "tiles")
	_mb.add_box(Vector3(1.6, 2.4, 0.08), xf * Vector3(0, 1.2, 0.0), _mats["timber"], xf.basis)
	for wx: float in [-5.0, -2.6, 2.6, 5.0]:
		_window(xf, wx, 0.9, 1.2, 1.2)
		_window(xf, wx, 3.5, 1.0, 1.0)
	# The inn sign on a post by the road, and its name.
	var post := xf * Vector3(w * 0.5 + 1.5, 0, 2.5)
	_solid(Vector3(0.22, 4.2, 0.22), post + Vector3(0, 2.1, 0), "timber")
	_mb.add_box(Vector3(0.1, 0.1, 1.4), post + xf.basis * Vector3(0, 3.9, 0.6), _mats["timber"], xf.basis)
	_mb.add_box(Vector3(0.06, 1.0, 1.2), post + xf.basis * Vector3(0, 3.2, 0.8), _mats["paint"], xf.basis)
	var label := Label3D.new()
	label.text = INN_NAMES[(index * 3 + _rng.randi()) % INN_NAMES.size()]
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.93, 0.8, 0.5)
	label.outline_size = 5
	label.shaded = true
	label.visibility_range_end = 30.0
	add_child(label)
	label.global_transform = Transform3D(xf.basis, xf * Vector3(0, 2.75, 0.06))
	# Horse trough and a bench outside.
	var trough := StreetProps.make_horse_trough()
	add_child(trough)
	trough.global_transform = Transform3D(xf.basis, xf * Vector3(-w * 0.5 - 1.5, 0, 2.2))


func _smithy(xf: Transform3D, w: float, d: float) -> void:
	_house_mass(xf, w, d, 3.4, "brick", "tiles")
	# Wide open front with the forge glowing inside.
	_mb.add_box(Vector3(3.2, 2.6, 0.06), xf * Vector3(0, 1.3, 0.01), MaterialLibrary.get_tinted("wood_planks", Color(0.08, 0.06, 0.05)), xf.basis)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 1.4
	glow.omni_range = 5.0
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 40.0
	add_child(glow)
	glow.global_position = xf * Vector3(0, 1.0, 0.8)
	_solid(Vector3(0.7, 0.8, 0.5), xf * Vector3(1.5, 0.4, 2.0), "iron") # anvil block


func _barn(xf: Transform3D, w: float, d: float) -> void:
	_house_mass(xf, w, d, 4.2, "timber", "tiles")
	_mb.add_box(Vector3(4.0, 3.6, 0.08), xf * Vector3(0, 1.8, 0.01), _mats["wood"], xf.basis)


func _rick(p: Vector2) -> void:
	var hay := MaterialLibrary.get_tinted("canvas", Color(0.85, 0.72, 0.42))
	if _mats.has("thatch"):
		hay = _mats["thatch"]
	_mb.add_cylinder(2.3, 2.3, 3.0, _p(p, 1.5), hay, 12)
	_mb.add_cylinder(2.5, 0.2, 2.2, _p(p, 4.1), hay, 12)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.3
	cyl.height = 3.0
	cs.shape = cyl
	cs.position = _p(p, 1.5)
	_body.add_child(cs)


# ---------------------------------------------------------------------------
# People
# ---------------------------------------------------------------------------
func _spawn_folk() -> void:
	var n := 7 + _rng.randi() % 4
	for k in n:
		var f := VillageFolk.new()
		f.name = "Villager%d" % k
		f.village = self
		f.home = spots[_rng.randi() % spots.size()][0]
		f.look_seed = index * 1000 + k
		f.outfit = [NPCBody.Outfit.WORKER, NPCBody.Outfit.WORKER, NPCBody.Outfit.LADY, NPCBody.Outfit.RAGGED][_rng.randi() % 4]
		add_child(f)
		f.global_position = f.home + Vector3(0, 0.2, 0)
