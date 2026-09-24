class_name StGiles
extends Node3D
## The St Giles rookery (Phase 10): the slum behind the west side of the street, where
## Harry grew up. Through Church Lane (the gap in the west terrace) you come to:
##   * tenement courts: sagging lodging-houses, yards with washing lines, a pump, privies
##     and rubbish heaps to hide in;
##   * the Fleet ditch: the old river, now a stinking open sewer 3 m down between stone
##     walls, crossed by one narrow timber footbridge (where Harry meets Big Tom). Fall in
##     and you wade out by the iron ladders or the steps at the south end;
##   * St Giles-in-the-Fields: Father Bernard's church, with a tower and spire, pews,
##     candles, a churchyard, and a crypt below that becomes Harry's safehouse in town;
##   * Father Bernard's soup kitchen, where the poor queue for their dinner.
## The district gets visibly better as Harry gives to the poor (Progress.wellbeing):
## window boxes of flowers, bunting over the lane, fewer beggars, a longer soup queue.
##
## Layout (world metres): the district spans x = -78 .. -16.3, z = -44 .. 44. Church Lane
## runs west from the street at z = -6 .. -2.6; the ditch is x = -40 .. -34.

const LANE_Z0 := -6.0
const LANE_Z1 := -2.6
const TERRACE_BACK_X := -16.3
const DITCH_X0 := -40.0
const DITCH_X1 := -34.0
const DITCH_Z := 36.0
const DITCH_FLOOR := -3.0
const WATER_TOP := -1.9
const BRIDGE_Z := -4.3
const BRIDGE_TOP := 0.25
const NAVE_X0 := -64.0
const NAVE_X1 := -44.0
const NAVE_Z0 := 8.0
const NAVE_Z1 := 20.0
const WALL_T := 0.7
const NAVE_H := 9.0
const FLOOR_TOP := 0.15
const CRYPT_FLOOR := -3.2
const CRYPT := Rect2(-60.0, 9.0, 7.5, 10.0) # x, z, size
const STAIR := Rect2(-52.5, 17.0, 5.0, 1.8)
const DOOR_X := -54.0
const TOWER := Rect2(-69.0, 11.0, 5.0, 6.0)
const WEST_ROW_X := -72.0
const BELL_POSITION := Vector3(-66.5, 23.0, 14.0)
## Where Father Bernard stands, the crypt bed and the bridge's middle (for missions).
const ALTAR_POINT := Vector3(-46.8, FLOOR_TOP, 14.0)
const CRYPT_BED := Vector3(-58.6, CRYPT_FLOOR, 11.2)
const BRIDGE_MID := Vector3(-37.0, BRIDGE_TOP, BRIDGE_Z)
const SOUP_POINT := Vector3(-47.0, 0.0, -11.0)
const POOR_BOX := Vector3(DOOR_X + 2.2, 0.0, NAVE_Z0 - 0.7)
## The courts where rookery folk work by day: [centre, half-size].
const YARDS: Array = [[Vector3(-25.0, 0.05, 22.0), Vector2(6, 9)], [Vector3(-25.0, 0.05, -25.0), Vector2(6, 8)], [Vector3(-56.0, 0.05, -22.0), Vector2(10, 8)]]
## Beggars sit out in the lanes by day and go to the lodging houses at night.
const BEGGING_HOURS := Vector2(7.0, 21.0)
## The soup kitchen's queue forms before dinner and supper: [from, to] hours.
const SOUP_HOURS: Array[Vector2] = [Vector2(10.0, 14.0), Vector2(16.5, 19.0)]

var _rng := RandomNumberGenerator.new()
var _mb: MeshBuilder
var _body: StaticBody3D
var _flowers: Array[Node3D] = []
var _bunting: Node3D
var _beggars: Array[NPCBody] = []
var _queue: Array[NPCBody] = []


## Inside the church or its crypt (a sanctuary once Father Bernard has taken Harry in).
static func in_church(p: Vector3) -> bool:
	return p.x > NAVE_X0 and p.x < NAVE_X1 and p.z > NAVE_Z0 and p.z < NAVE_Z1 and p.y > CRYPT_FLOOR - 0.5 and p.y < NAVE_H


static func is_sanctuary(p: Vector3) -> bool:
	return in_church(p) and Story.get_flag("st_giles_safehouse")


func _ready() -> void:
	add_to_group("navigation_source")
	add_to_group("st_giles")
	_rng.seed = 1666
	_mb = MeshBuilder.new()
	_body = StaticBody3D.new()
	_body.name = "Solid"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	add_child(_body)
	_build_ground()
	_build_ditch()
	_build_bridge()
	_build_tenements()
	_build_church()
	_build_crypt()
	_build_churchyard()
	_build_soup_kitchen()
	_build_yards()
	_build_lamps()
	_mb.build_into(self, "StGilesMesh").gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_build_people()
	_apply_wellbeing()
	Progress.bus().legend_changed.connect(_on_legend_changed)
	GameClock.bus().hour_passed.connect(func(_h: int) -> void: _apply_wellbeing())
	GameClock.bus().time_jumped.connect(func(_h: float) -> void: _apply_wellbeing())
	# The church door, for Sunday service (Population's residents walk to it).
	var door := Marker3D.new()
	door.name = "ChurchDoor"
	door.position = Vector3(DOOR_X, 0.0, NAVE_Z0 - 1.6)
	door.set_meta("kind", "church")
	door.add_to_group("npc_doors")
	add_child(door)


func _on_legend_changed(_v: float, _d: float, reason: String) -> void:
	if reason == "gave to the poor":
		_apply_wellbeing()


# ---------------------------------------------------------------------------
# Ground: solid everywhere west of the street except the ditch and the crypt
# ---------------------------------------------------------------------------
func _build_ground() -> void:
	var holes: Array[Rect2] = [
		Rect2(DITCH_X0, -DITCH_Z, DITCH_X1 - DITCH_X0, DITCH_Z * 2.0), CRYPT, STAIR,
	]
	_slab(_body, -80.0, -18.0, -80.0, 80.0, holes, 0.0, 2.0)
	# What you see: trodden mud and broken cobbles in the courts, cobbles in the lane.
	var mud := MaterialLibrary.get_tinted("dirt", Color(0.5, 0.45, 0.4))
	for r: Rect2 in [Rect2(-78.0, -44.0, DITCH_X0 + 78.0, 88.0), Rect2(DITCH_X1, -44.0, TERRACE_BACK_X - DITCH_X1, 88.0)]:
		for piece in _free_rects(r, holes):
			_mb.add_box(Vector3(piece.size.x, 0.1, piece.size.y), Vector3(piece.get_center().x, -0.05, piece.get_center().y), mud)
	var lane := MeshInstance3D.new()
	lane.name = "ChurchLane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(-6.3 - DITCH_X1, LANE_Z1 - LANE_Z0)
	lane.mesh = plane
	lane.position = Vector3((-6.3 + DITCH_X1) * 0.5, 0.012, (LANE_Z0 + LANE_Z1) * 0.5)
	lane.material_override = MaterialLibrary.get_for_uv_plane("cobblestone", plane.size)
	add_child(lane)
	var path := MeshInstance3D.new()
	path.name = "ChurchPath"
	var p2 := PlaneMesh.new()
	p2.size = Vector2(DITCH_X0 - DOOR_X + 1.2, 2.6)
	path.mesh = p2
	path.position = Vector3((DITCH_X0 + DOOR_X - 1.2) * 0.5, 0.012, BRIDGE_Z)
	path.material_override = MaterialLibrary.get_for_uv_plane("cobblestone", p2.size)
	add_child(path)
	var path2 := MeshInstance3D.new()
	path2.name = "ChurchPathNorth"
	var p3 := PlaneMesh.new()
	p3.size = Vector2(2.4, NAVE_Z0 - BRIDGE_Z - 1.3)
	path2.mesh = p3
	path2.position = Vector3(DOOR_X, 0.012, (NAVE_Z0 + BRIDGE_Z + 1.3) * 0.5)
	path2.material_override = MaterialLibrary.get_for_uv_plane("cobblestone", p3.size)
	add_child(path2)
	# The world ends at x = -80: an invisible wall so nobody drops off it from the roofs.
	_collider(_body, Vector3(1.0, 40.0, 160.0), Vector3(-80.5, 18.0, 0.0))


## Covers the rectangle with collision boxes (top at `top`, `thick` deep), leaving holes.
func _slab(body: StaticBody3D, x0: float, x1: float, z0: float, z1: float, holes: Array[Rect2], top: float, thick: float) -> void:
	for r in _free_rects(Rect2(x0, z0, x1 - x0, z1 - z0), holes):
		_collider(body, Vector3(r.size.x, thick, r.size.y), Vector3(r.get_center().x, top - thick * 0.5, r.get_center().y))


## Splits `area` (x along position.x, z along position.y) into rectangles that avoid `holes`.
static func _free_rects(area: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var xs: Array[float] = [area.position.x, area.end.x]
	for h in holes:
		for x: float in [h.position.x, h.end.x]:
			if x > area.position.x and x < area.end.x:
				xs.append(x)
	xs.sort()
	var out: Array[Rect2] = []
	for i in xs.size() - 1:
		var a := xs[i]
		var b := xs[i + 1]
		if b - a < 0.01:
			continue
		var mid := (a + b) * 0.5
		var blocked: Array[Vector2] = []
		for h in holes:
			if h.position.x < mid and h.end.x > mid:
				blocked.append(Vector2(h.position.y, h.end.y))
		blocked.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		var z := area.position.y
		for bl in blocked:
			if bl.x > z + 0.01:
				out.append(Rect2(a, z, b - a, minf(bl.x, area.end.y) - z))
			z = maxf(z, bl.y)
		if area.end.y - z > 0.01:
			out.append(Rect2(a, z, b - a, area.end.y - z))
	return out


func _collider(body: StaticBody3D, size: Vector3, center: Vector3, basis: Basis = Basis.IDENTITY) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)
	return cs


## A solid, visible box.
func _solid(size: Vector3, center: Vector3, mat: Material, body: StaticBody3D = null) -> void:
	_mb.add_box(size, center, mat)
	_collider(body if body else _body, size, center)


# ---------------------------------------------------------------------------
# The Fleet ditch
# ---------------------------------------------------------------------------
func _build_ditch() -> void:
	var stone := MaterialLibrary.get_tinted("stone_trim", Color(0.45, 0.43, 0.38))
	var slime := MaterialLibrary.get_tinted("rock", Color(0.28, 0.3, 0.22))
	var w := DITCH_X1 - DITCH_X0
	var depth := 0.0 - DITCH_FLOOR
	# Walls, floor and coping stones.
	_solid(Vector3(0.5, depth + 0.5, DITCH_Z * 2.0), Vector3(DITCH_X1 + 0.25, (DITCH_FLOOR - 0.5) * 0.5, 0.0), slime)
	_solid(Vector3(0.5, depth + 0.5, DITCH_Z * 2.0), Vector3(DITCH_X0 - 0.25, (DITCH_FLOOR - 0.5) * 0.5, 0.0), slime)
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(w + 1.0, depth + 0.5, 0.5), Vector3((DITCH_X0 + DITCH_X1) * 0.5, (DITCH_FLOOR - 0.5) * 0.5, side * (DITCH_Z + 0.25)), slime)
		# Above ground at each end a brick wall closes the gap between the tenement rows,
		# with the culvert's dark arch below where the ditch runs on underground.
		_solid(Vector3(w + 1.0, 5.5, 0.5), Vector3((DITCH_X0 + DITCH_X1) * 0.5, 2.75, side * (DITCH_Z + 0.25)), MaterialLibrary.get_material("brick_red"))
		_mb.add_box(Vector3(w * 0.7, 1.4, 0.05), Vector3((DITCH_X0 + DITCH_X1) * 0.5, DITCH_FLOOR + 0.8, side * (DITCH_Z - 0.02)), MaterialLibrary.get_tinted("rock", Color(0.03, 0.03, 0.03)))
	var floor_body := StaticBody3D.new()
	floor_body.name = "DitchBed"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.set_meta("surface", "water")
	add_child(floor_body)
	_solid(Vector3(w, 0.5, DITCH_Z * 2.0), Vector3((DITCH_X0 + DITCH_X1) * 0.5, DITCH_FLOOR - 0.25, 0.0), MaterialLibrary.get_tinted("dirt", Color(0.2, 0.18, 0.12)), floor_body)
	for x: float in [DITCH_X0 - 0.3, DITCH_X1 + 0.3]:
		_mb.add_box(Vector3(0.7, 0.14, DITCH_Z * 2.0), Vector3(x, 0.07, 0.0), stone) # coping
	# The water: dark, still and filthy.
	var water := WaterVolume.new()
	water.name = "FleetWater"
	water.position = Vector3(DITCH_X0, DITCH_FLOOR, -DITCH_Z)
	water.size = Vector3(w, WATER_TOP - DITCH_FLOOR, DITCH_Z * 2.0)
	add_child(water)
	var wmat := MaterialLibrary.get_material("water").duplicate() as StandardMaterial3D
	wmat.albedo_color = Color(0.13, 0.12, 0.08, 0.92)
	_mb.add_box(Vector3(w, 0.02, DITCH_Z * 2.0), Vector3((DITCH_X0 + DITCH_X1) * 0.5, WATER_TOP, 0.0), wmat)
	# Iron ladders up both walls, and stone steps down at the south end.
	for z: float in [-22.0, 12.0, 27.0]:
		_ladder(Vector3(DITCH_X1 - 0.12, DITCH_FLOOR, z))
		_ladder(Vector3(DITCH_X0 + 0.12, DITCH_FLOOR, z + 4.0))
	var steps := 15
	var rise := -DITCH_FLOOR / steps
	for k in steps:
		var top := -rise * (k + 1)
		var z0 := -DITCH_Z + 0.2 + k * 0.36
		var h := top - DITCH_FLOOR + 0.02
		_solid(Vector3(1.3, h, 0.36), Vector3(DITCH_X1 - 0.65, DITCH_FLOOR + h * 0.5 - 0.02, z0 + 0.18), stone)


## An iron ladder (climbable like a drainpipe) up the ditch wall.
func _ladder(base: Vector3) -> void:
	var height := -DITCH_FLOOR + 0.05
	var pipe := StaticBody3D.new()
	pipe.name = "DitchLadder"
	pipe.add_to_group("climbable_pipe")
	pipe.collision_layer = 1 << 4 # climbable
	pipe.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.08
	cyl.height = height
	cs.shape = cyl
	cs.position = base + Vector3.UP * height * 0.5
	pipe.add_child(cs)
	add_child(pipe)
	var iron := MaterialLibrary.get_material("iron")
	for side: float in [-0.22, 0.22]:
		_mb.add_cylinder(0.02, 0.02, height, base + Vector3(0, height * 0.5, side), iron, 6)
	for k in int(height / 0.3):
		_mb.add_box(Vector3(0.03, 0.03, 0.44), base + Vector3(0, 0.25 + k * 0.3, 0), iron)


# ---------------------------------------------------------------------------
# The footbridge: seven metres of old planks, no rail, three metres above the water
# ---------------------------------------------------------------------------
func _build_bridge() -> void:
	var bridge := StaticBody3D.new()
	bridge.name = "Footbridge"
	bridge.collision_layer = 1
	bridge.collision_mask = 0
	bridge.set_meta("surface", "wood")
	add_child(bridge)
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.5, 0.42, 0.33))
	var x0 := DITCH_X0 - 0.6
	var x1 := DITCH_X1 + 0.6
	var mid_x := (x0 + x1) * 0.5
	_solid(Vector3(x1 - x0, 0.12, 1.2), Vector3(mid_x, BRIDGE_TOP - 0.06, BRIDGE_Z), wood, bridge)
	for k in 12:
		var x := x0 + (k + 0.5) * (x1 - x0) / 12.0
		_mb.add_box(Vector3(0.02, 0.02, 1.22), Vector3(x, BRIDGE_TOP + 0.005, BRIDGE_Z), MaterialLibrary.get_tinted("wood_planks", Color(0.3, 0.25, 0.2)))
	for x: float in [DITCH_X0 + 1.5, DITCH_X1 - 1.5]:
		for side: float in [-0.55, 0.55]:
			_mb.add_cylinder(0.09, 0.1, BRIDGE_TOP - DITCH_FLOOR, Vector3(x, (BRIDGE_TOP + DITCH_FLOOR) * 0.5, BRIDGE_Z + side), wood, 8)
		_mb.add_box(Vector3(0.14, 0.14, 1.3), Vector3(x, BRIDGE_TOP - 0.2, BRIDGE_Z), wood)
	var marker := Marker3D.new()
	marker.name = "BridgeMiddle"
	marker.position = BRIDGE_MID
	add_child(marker)


# ---------------------------------------------------------------------------
# Tenements
# ---------------------------------------------------------------------------
func _build_tenements() -> void:
	# Church Lane, both sides, each with an entry through to the court behind.
	_row_x(DITCH_X1, -26.5, LANE_Z1, PI, 8.0)
	_row_x(-24.0, TERRACE_BACK_X, LANE_Z1, PI, 8.0)
	_row_x(DITCH_X1, -28.5, LANE_Z0, 0.0, 8.0)
	_row_x(-26.0, TERRACE_BACK_X, LANE_Z0, 0.0, 8.0)
	# The north and south edges, either side of the ditch.
	for r: Array in [[DITCH_X1, TERRACE_BACK_X], [WEST_ROW_X, DITCH_X0]]:
		_row_x(r[0], r[1], DITCH_Z, PI, 8.0)
		_row_x(r[0], r[1], -DITCH_Z, 0.0, 8.0)
	# The west edge, behind the church.
	var z := -DITCH_Z
	while DITCH_Z - z > 0.01:
		var w := _rng.randf_range(5.5, 8.0)
		if DITCH_Z - (z + w) < 4.5:
			w = DITCH_Z - z
		var b := _tenement(w, 6.0)
		b.rotation.y = PI * 0.5
		b.position = Vector3(WEST_ROW_X, 0.0, z + w)
		add_child(b)
		_add_window_boxes(b)
		z += w


## Tenements whose fronts lie on z = z_line between x0 and x1 (yaw 0 faces +Z, PI faces -Z).
func _row_x(x0: float, x1: float, z_line: float, yaw: float, depth: float) -> void:
	var x := x0
	while x1 - x > 0.01:
		var w := _rng.randf_range(5.0, 7.5)
		if x1 - (x + w) < 4.0:
			w = x1 - x
		var b := _tenement(w, depth)
		b.rotation.y = yaw
		b.position = Vector3(x if yaw == 0.0 else x + w, 0.0, z_line)
		add_child(b)
		_add_window_boxes(b)
		x += w


## Window boxes of flowers, which appear as the district is cared for. (Added once the
## building has built itself: it clears its children when it does.)
func _add_window_boxes(b: BuildingFacade) -> void:
	var width := b.width
	var flowers := Node3D.new()
	flowers.name = "WindowBoxes"
	var mb := MeshBuilder.new()
	var box_mat := MaterialLibrary.get_tinted("wood_painted", Color(0.3, 0.4, 0.3))
	var bloom := MaterialLibrary.get_tinted("fabric", [Color(0.8, 0.2, 0.25), Color(0.9, 0.75, 0.2), Color(0.7, 0.4, 0.8)][_rng.randi() % 3])
	var n := maxi(int(width / 2.6), 1)
	for i in n:
		var x := (i + 0.5) * width / n
		mb.add_box(Vector3(0.8, 0.18, 0.22), Vector3(x, 3.15, 0.14), box_mat)
		mb.add_box(Vector3(0.7, 0.14, 0.18), Vector3(x, 3.3, 0.14), bloom)
	mb.build_into(flowers, "Boxes", false)
	b.add_child(flowers)
	_flowers.append(flowers)


func _tenement(width: float, depth: float) -> BuildingFacade:
	var b := BuildingFacade.new()
	b.name = "Tenement"
	b.width = width
	b.depth = depth
	b.upper_floors = 2 + int(_rng.randf() > 0.4)
	var roll := _rng.randf()
	b.wall_material = "brick_red" if roll < 0.5 else ("brick_yellow" if roll < 0.85 else "stucco")
	b.variation_seed = _rng.randi()
	b.door_on_left = _rng.randf() > 0.5
	b.ground_floor = BuildingFacade.GroundFloor.HOUSE
	return b


# ---------------------------------------------------------------------------
# St Giles-in-the-Fields
# ---------------------------------------------------------------------------
func _build_church() -> void:
	var church := StaticBody3D.new()
	church.name = "Church"
	church.collision_layer = 1
	church.collision_mask = 0
	church.set_meta("surface", "stone")
	add_child(church)
	var stone := MaterialLibrary.get_tinted("stone_trim", Color(0.86, 0.83, 0.76))
	var dark_glass := MaterialLibrary.get_material("glass_2")
	var h := NAVE_H
	var t := WALL_T
	# Walls, with the south door.
	_solid(Vector3(NAVE_X1 - NAVE_X0, h, t), Vector3((NAVE_X0 + NAVE_X1) * 0.5, h * 0.5, NAVE_Z1 - t * 0.5), stone, church)
	_solid(Vector3(t, h, NAVE_Z1 - NAVE_Z0), Vector3(NAVE_X1 - t * 0.5, h * 0.5, (NAVE_Z0 + NAVE_Z1) * 0.5), stone, church)
	_solid(Vector3(t, h, NAVE_Z1 - NAVE_Z0), Vector3(NAVE_X0 + t * 0.5, h * 0.5, (NAVE_Z0 + NAVE_Z1) * 0.5), stone, church)
	var door_w := 2.4
	var door_h := 3.4
	var left := DOOR_X - door_w * 0.5 - NAVE_X0
	var right := NAVE_X1 - (DOOR_X + door_w * 0.5)
	_solid(Vector3(left, h, t), Vector3(NAVE_X0 + left * 0.5, h * 0.5, NAVE_Z0 + t * 0.5), stone, church)
	_solid(Vector3(right, h, t), Vector3(NAVE_X1 - right * 0.5, h * 0.5, NAVE_Z0 + t * 0.5), stone, church)
	_solid(Vector3(door_w, h - door_h, t), Vector3(DOOR_X, door_h + (h - door_h) * 0.5, NAVE_Z0 + t * 0.5), stone, church)
	# A classical doorcase and pediment over the door.
	for side: float in [-1.0, 1.0]:
		_mb.add_box(Vector3(0.5, door_h + 0.4, 0.25), Vector3(DOOR_X + side * (door_w * 0.5 + 0.25), (door_h + 0.4) * 0.5, NAVE_Z0 - 0.12), stone)
	_mb.add_box(Vector3(door_w + 1.6, 0.35, 0.4), Vector3(DOOR_X, door_h + 0.55, NAVE_Z0 - 0.15), stone)
	# Tall round-headed windows down both sides (dark glass, lit at night by the candles).
	for x: float in [-60.5, -56.5, -49.5, -46.8]:
		for z: float in [NAVE_Z0 - 0.02, NAVE_Z1 + 0.02]:
			_mb.add_box(Vector3(1.4, 4.2, 0.06), Vector3(x, 5.0, z), dark_glass)
			_mb.add_cylinder(0.7, 0.7, 0.06, Vector3(x, 7.1, z), dark_glass, 12, Basis(Vector3.RIGHT, PI * 0.5))
	# Cornice and the slate roof.
	_solid(Vector3(NAVE_X1 - NAVE_X0 + 0.6, 0.4, NAVE_Z1 - NAVE_Z0 + 0.6), Vector3((NAVE_X0 + NAVE_X1) * 0.5, h + 0.2, (NAVE_Z0 + NAVE_Z1) * 0.5), stone, church)
	var roof := PrismMesh.new()
	roof.size = Vector3(NAVE_Z1 - NAVE_Z0 + 0.8, 4.2, NAVE_X1 - NAVE_X0 + 0.4)
	var roof_xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3((NAVE_X0 + NAVE_X1) * 0.5, h + 0.4 + 2.1, (NAVE_Z0 + NAVE_Z1) * 0.5))
	_mb.add_mesh(roof, roof_xf, MaterialLibrary.get_material("slate_roof"))
	var roof_cs := CollisionShape3D.new()
	roof_cs.shape = roof.create_convex_shape()
	roof_cs.transform = roof_xf
	church.add_child(roof_cs)
	# The tower and spire.
	var tx := TOWER.get_center().x
	var tz := TOWER.get_center().y
	_solid(Vector3(TOWER.size.x, 26.0, TOWER.size.y), Vector3(tx, 13.0, tz), stone, church)
	for y: float in [9.6, 17.5, 26.0]:
		_mb.add_box(Vector3(TOWER.size.x + 0.4, 0.35, TOWER.size.y + 0.4), Vector3(tx, y, tz), stone)
	var black := MaterialLibrary.get_tinted("rock", Color(0.05, 0.05, 0.05))
	var dial := MaterialLibrary.get_tinted("plaster", Color(0.95, 0.94, 0.9))
	for f: Array in [[Vector3(1, 0, 0), TOWER.size.x], [Vector3(-1, 0, 0), TOWER.size.x], [Vector3(0, 0, 1), TOWER.size.y], [Vector3(0, 0, -1), TOWER.size.y]]:
		var n: Vector3 = f[0]
		var half: float = (TOWER.size.x if absf(n.x) > 0.5 else TOWER.size.y) * 0.5
		var c := Vector3(tx, 0.0, tz) + n * (half + 0.03)
		var face_basis := Basis.looking_at(n, Vector3.UP)
		# Belfry openings (louvred, dark) and the clock.
		_mb.add_box(Vector3(1.2, 3.0, 0.06), c + Vector3.UP * 22.0, black, face_basis)
		_mb.add_cylinder(0.95, 0.95, 0.05, c + Vector3.UP * 19.2, dial, 20, face_basis * Basis(Vector3.RIGHT, PI * 0.5))
		_mb.add_box(Vector3(0.06, 0.62, 0.03), c + Vector3.UP * 19.4 + n * 0.03, black, face_basis)
		_mb.add_box(Vector3(0.5, 0.06, 0.03), c + Vector3(0, 19.2, 0) + n * 0.03 + face_basis.x * 0.2, black, face_basis)
	_mb.add_cylinder(2.3, 2.3, 1.2, Vector3(tx, 26.8, tz), stone, 8) # octagonal drum
	_mb.add_cylinder(2.0, 0.08, 17.0, Vector3(tx, 35.9, tz), stone, 8) # the spire
	_mb.add_cylinder(0.03, 0.03, 1.4, Vector3(tx, 45.0, tz), MaterialLibrary.get_material("iron"), 6)
	_mb.add_box(Vector3(0.8, 0.25, 0.04), Vector3(tx, 45.4, tz), MaterialLibrary.get_material("gilt")) # weathercock
	# Interior: stone-flagged floor over the crypt, pews, the altar and the pulpit.
	var floor_body := StaticBody3D.new()
	floor_body.name = "NaveFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.set_meta("surface", "stone")
	add_child(floor_body)
	var inner := Rect2(NAVE_X0 + t, NAVE_Z0 + t, NAVE_X1 - NAVE_X0 - t * 2.0, NAVE_Z1 - NAVE_Z0 - t * 2.0)
	var stair_holes: Array[Rect2] = [STAIR]
	_slab(floor_body, inner.position.x, inner.end.x, inner.position.y, inner.end.y, stair_holes, FLOOR_TOP, 0.3)
	var flags := MaterialLibrary.get_tinted("marble", Color(0.7, 0.68, 0.62))
	for r in _free_rects(inner, stair_holes):
		_mb.add_box(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, FLOOR_TOP - 0.15, r.get_center().y), flags)
	var pew := MaterialLibrary.get_tinted("wood_planks", Color(0.35, 0.22, 0.14))
	var pews := StaticBody3D.new()
	pews.name = "Pews"
	pews.collision_layer = 1
	pews.collision_mask = 0
	pews.set_meta("surface", "wood")
	add_child(pews)
	# Pews either side of the central aisle, clear of the cross aisle by the door and of
	# the crypt stair.
	for row in 6:
		var x := -61.0 + row * 1.5
		for side: float in [-1.0, 1.0]:
			var zc := (NAVE_Z0 + NAVE_Z1) * 0.5 + side * 2.5
			_solid(Vector3(0.5, 0.45, 3.0), Vector3(x, FLOOR_TOP + 0.225, zc), pew, pews)
			_mb.add_box(Vector3(0.08, 0.55, 3.0), Vector3(x - 0.25, FLOOR_TOP + 0.72, zc), pew)
	_solid(Vector3(0.9, 1.0, 3.0), Vector3(NAVE_X1 - t - 0.6, FLOOR_TOP + 0.5, 14.0), MaterialLibrary.get_tinted("marble", Color(0.9, 0.88, 0.84)), pews)
	_mb.add_box(Vector3(1.0, 0.05, 3.2), Vector3(NAVE_X1 - t - 0.6, FLOOR_TOP + 1.02, 14.0), MaterialLibrary.get_tinted("fabric", Color(0.55, 0.1, 0.1)))
	_mb.add_cylinder(0.55, 0.45, 1.3, Vector3(-48.8, FLOOR_TOP + 0.65, 10.2), pew, 8) # pulpit
	# Candles on the altar and down the nave.
	for p: Vector3 in [Vector3(NAVE_X1 - t - 0.6, FLOOR_TOP + 1.3, 13.2), Vector3(NAVE_X1 - t - 0.6, FLOOR_TOP + 1.3, 14.8)]:
		_mb.add_cylinder(0.03, 0.03, 0.3, p, MaterialLibrary.get_tinted("plaster", Color(0.95, 0.93, 0.85)), 6)
	var glow := OmniLight3D.new()
	glow.name = "AltarCandles"
	glow.position = Vector3(NAVE_X1 - 2.0, 2.2, 14.0)
	glow.light_color = Color(1.0, 0.72, 0.42)
	glow.light_energy = 1.3
	glow.omni_range = 9.0
	glow.shadow_enabled = true
	add_child(glow)
	var nave_light := OmniLight3D.new()
	nave_light.name = "NaveLamp"
	nave_light.position = Vector3(-56.0, 5.5, 14.0)
	nave_light.light_color = Color(1.0, 0.75, 0.48)
	nave_light.light_energy = 0.8
	nave_light.omni_range = 11.0
	add_child(nave_light)
	var nave := InteriorVolume.new()
	nave.name = "NaveInterior"
	nave.position = Vector3(NAVE_X0 + t, 0.0, NAVE_Z0 + t)
	nave.size = Vector3(inner.size.x, NAVE_H - 0.2, inner.size.y)
	nave.daylight_factor = 0.35
	add_child(nave)
	# Railing round the stair down to the crypt.
	var iron := MaterialLibrary.get_material("iron")
	for z: float in [STAIR.position.y - 0.03, STAIR.end.y + 0.03]:
		_solid(Vector3(STAIR.size.x, 1.0, 0.06), Vector3(STAIR.get_center().x, FLOOR_TOP + 0.5, z), iron, pews)
	_solid(Vector3(0.06, 1.0, STAIR.size.y), Vector3(STAIR.position.x - 0.03, FLOOR_TOP + 0.5, STAIR.get_center().y), iron, pews)
	var sign := Label3D.new()
	sign.name = "ChurchSign"
	sign.text = "ST GILES-IN-THE-FIELDS"
	sign.font_size = 64
	sign.pixel_size = 0.006
	sign.modulate = Color(0.2, 0.16, 0.1)
	sign.position = Vector3(DOOR_X, door_h + 1.1, NAVE_Z0 - 0.37)
	sign.rotation.y = PI
	add_child(sign)


func _build_crypt() -> void:
	var stone := MaterialLibrary.get_tinted("stone_trim", Color(0.5, 0.48, 0.44))
	var crypt := StaticBody3D.new()
	crypt.name = "Crypt"
	crypt.collision_layer = 1
	crypt.collision_mask = 0
	crypt.set_meta("surface", "stone")
	add_child(crypt)
	var wall_h := FLOOR_TOP - CRYPT_FLOOR
	var cy := CRYPT_FLOOR + wall_h * 0.5 - 0.15
	var r := CRYPT
	# Room walls (east wall open where the stair comes in).
	_solid(Vector3(0.4, wall_h, r.size.y + 0.8), Vector3(r.position.x - 0.2, cy, r.get_center().y), stone, crypt)
	_solid(Vector3(r.size.x + 0.8, wall_h, 0.4), Vector3(r.get_center().x, cy, r.position.y - 0.2), stone, crypt)
	_solid(Vector3(r.size.x + 0.8, wall_h, 0.4), Vector3(r.get_center().x, cy, r.end.y + 0.2), stone, crypt)
	var east_len := STAIR.position.y - r.position.y
	_solid(Vector3(0.4, wall_h, east_len), Vector3(r.end.x + 0.2, cy, r.position.y + east_len * 0.5), stone, crypt)
	# The stair well.
	_solid(Vector3(STAIR.size.x, wall_h, 0.4), Vector3(STAIR.get_center().x, cy, STAIR.position.y - 0.2), stone, crypt)
	_solid(Vector3(STAIR.size.x, wall_h, 0.4), Vector3(STAIR.get_center().x, cy, STAIR.end.y + 0.2), stone, crypt)
	_solid(Vector3(0.4, wall_h, STAIR.size.y), Vector3(STAIR.end.x + 0.2, cy, STAIR.get_center().y), stone, crypt)
	_solid(Vector3(r.size.x + STAIR.size.x, 0.3, r.size.y), Vector3(r.position.x + (r.size.x + STAIR.size.x) * 0.5, CRYPT_FLOOR - 0.15, r.get_center().y), MaterialLibrary.get_tinted("pavement", Color(0.55, 0.52, 0.48)), crypt)
	# Sixteen steps down, heading west from the nave.
	var n := 16
	var rise := wall_h / n
	var run := STAIR.size.x / n
	for k in n - 1:
		var top := FLOOR_TOP - rise * (k + 1)
		var x1 := STAIR.end.x - run * k
		var hh := top - CRYPT_FLOOR
		_solid(Vector3(run, hh, STAIR.size.y), Vector3(x1 - run * 0.5, CRYPT_FLOOR + hh * 0.5, STAIR.get_center().y), stone, crypt)
	# Vaulting piers, a table, candles.
	for p: Vector2 in [Vector2(-57.5, 14.0), Vector2(-54.5, 14.0)]:
		_solid(Vector3(0.6, wall_h, 0.6), Vector3(p.x, cy, p.y), stone, crypt)
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.4, 0.3, 0.2))
	_solid(Vector3(1.6, 0.8, 0.9), Vector3(-54.8, CRYPT_FLOOR + 0.4, 10.2), wood, crypt)
	_mb.add_box(Vector3(0.3, 0.05, 0.22), Vector3(-54.6, CRYPT_FLOOR + 0.83, 10.1), MaterialLibrary.get_tinted("fabric", Color(0.3, 0.1, 0.08))) # Bernard's ledger
	for x: float in [-55.3, -54.2]:
		_mb.add_cylinder(0.025, 0.025, 0.22, Vector3(x, CRYPT_FLOOR + 0.91, 10.3), MaterialLibrary.get_tinted("plaster", Color(0.95, 0.93, 0.85)), 6)
	var candle := OmniLight3D.new()
	candle.name = "CryptCandles"
	candle.position = Vector3(-55.0, CRYPT_FLOOR + 1.4, 11.0)
	candle.light_color = Color(1.0, 0.68, 0.38)
	candle.light_energy = 1.0
	candle.omni_range = 7.0
	candle.shadow_enabled = true
	add_child(candle)
	var vol := InteriorVolume.new()
	vol.name = "CryptInterior"
	vol.position = Vector3(r.position.x, CRYPT_FLOOR - 0.2, r.position.y)
	vol.size = Vector3(r.size.x + STAIR.size.x, wall_h + 0.1, r.size.y)
	vol.daylight_factor = 0.0
	add_child(vol)
	# The safehouse: a cot and a strongbox, Harry's once Father Bernard trusts him.
	var bed := SafehouseBed.new()
	bed.name = "CryptBed"
	bed.position = CRYPT_BED
	add_child(bed)
	_mb.add_box(Vector3(1.9, 0.35, 0.8), CRYPT_BED + Vector3(0, 0.3, 0), wood)
	_mb.add_box(Vector3(1.8, 0.1, 0.72), CRYPT_BED + Vector3(0, 0.52, 0), MaterialLibrary.get_tinted("fabric", Color(0.45, 0.4, 0.32)))
	var chest := SafehouseChest.new()
	chest.name = "CryptChest"
	chest.position = CRYPT_BED + Vector3(0.2, 0.0, 2.3)
	add_child(chest)
	_mb.add_box(Vector3(0.9, 0.55, 0.55), chest.position + Vector3(0, 0.275, 0), MaterialLibrary.get_tinted("wood_planks", Color(0.3, 0.2, 0.12)))


func _build_churchyard() -> void:
	var iron := MaterialLibrary.get_material("iron")
	var rail := StaticBody3D.new()
	rail.name = "Railings"
	rail.collision_layer = 1
	rail.collision_mask = 0
	rail.set_meta("surface", "stone")
	add_child(rail)
	var x0 := -70.5
	var x1 := -41.2
	var z0 := 3.0
	var z1 := 24.5
	var gate0 := DOOR_X - 1.5
	var gate1 := DOOR_X + 1.5
	for seg: Array in [[Vector3(x0, 0, z0), Vector3(gate0, 0, z0)], [Vector3(gate1, 0, z0), Vector3(x1, 0, z0)],
			[Vector3(x1, 0, z0), Vector3(x1, 0, z1)], [Vector3(x0, 0, z1), Vector3(x1, 0, z1)]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var len := a.distance_to(b)
		var c := (a + b) * 0.5
		var along_x := absf(b.x - a.x) > absf(b.z - a.z)
		var size := Vector3(len, 1.25, 0.08) if along_x else Vector3(0.08, 1.25, len)
		_collider(rail, size, c + Vector3.UP * 0.625)
		_mb.add_box(Vector3(size.x, 0.05, size.z), c + Vector3.UP * 1.2, iron)
		_mb.add_box(Vector3(size.x, 0.05, size.z), c + Vector3.UP * 0.15, iron)
		for k in int(len / 0.14):
			var p := a.lerp(b, (k + 0.5) / int(len / 0.14))
			_mb.add_box(Vector3(0.022, 1.3, 0.022), p + Vector3.UP * 0.65, iron)
	for side: float in [gate0, gate1]:
		_mb.add_box(Vector3(0.35, 1.9, 0.35), Vector3(side, 0.95, z0), MaterialLibrary.get_tinted("stone_trim", Color(0.8, 0.77, 0.7)))
	# Gravestones, leaning with age.
	var stone := MaterialLibrary.get_tinted("stone_trim", Color(0.55, 0.55, 0.5))
	var graves := StaticBody3D.new()
	graves.name = "Graves"
	graves.collision_layer = 1
	graves.collision_mask = 0
	add_child(graves)
	for i in 22:
		var p := Vector3(_rng.randf_range(x0 + 1.0, x1 - 1.0), 0.0, _rng.randf_range(z1 - 3.8, z1 - 0.8))
		if i >= 14:
			p = Vector3(_rng.randf_range(-44.5, x1 - 0.8), 0.0, _rng.randf_range(z0 + 1.0, z1 - 1.0))
		if in_church(p + Vector3.UP):
			continue
		var h := _rng.randf_range(0.6, 1.1)
		var b := Basis(Vector3.RIGHT, _rng.randf_range(-0.12, 0.12)) * Basis(Vector3.UP, _rng.randf_range(-0.15, 0.15))
		_mb.add_box(Vector3(0.55, h, 0.1), p + Vector3.UP * h * 0.5, stone, b)
		_collider(graves, Vector3(0.55, h, 0.12), p + Vector3.UP * h * 0.5, b)
	# Father Bernard's poor box at the church door.
	var box := AlmsBox.new()
	box.name = "StGilesPoorBox"
	box.position = POOR_BOX
	add_child(box)
	var yew := StreetProps.make_tree(31, 8.0, Color(0.13, 0.22, 0.1))
	yew.position = Vector3(-67.5, 0.0, 5.8)
	add_child(yew)


# ---------------------------------------------------------------------------
# The soup kitchen, the yards and the lamps
# ---------------------------------------------------------------------------
func _build_soup_kitchen() -> void:
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.45, 0.36, 0.26))
	var tables := StaticBody3D.new()
	tables.name = "SoupKitchen"
	tables.collision_layer = 1
	tables.collision_mask = 0
	tables.set_meta("surface", "wood")
	add_child(tables)
	for z: float in [-13.5, -10.0]:
		_solid(Vector3(4.0, 0.08, 0.9), Vector3(-49.0, 0.78, z), wood, tables)
		for x: float in [-50.8, -47.2]:
			_mb.add_box(Vector3(0.08, 0.76, 0.8), Vector3(x, 0.38, z), wood)
		for side: float in [-0.75, 0.75]:
			_solid(Vector3(3.8, 0.45, 0.3), Vector3(-49.0, 0.225, z + side), wood, tables)
	# The cauldron over a brazier.
	var iron := MaterialLibrary.get_material("iron")
	_solid(Vector3(0.9, 0.5, 0.9), Vector3(SOUP_POINT.x + 1.8, 0.25, SOUP_POINT.z + 3.5), iron, tables)
	_mb.add_cylinder(0.55, 0.45, 0.6, Vector3(SOUP_POINT.x + 1.8, 0.8, SOUP_POINT.z + 3.5), iron, 14)
	var fire := OmniLight3D.new()
	fire.name = "Brazier"
	fire.position = Vector3(SOUP_POINT.x + 1.8, 0.7, SOUP_POINT.z + 3.5)
	fire.light_color = Color(1.0, 0.55, 0.25)
	fire.light_energy = 1.6
	fire.omni_range = 7.0
	fire.shadow_enabled = true
	fire.add_to_group("stealth_lights")
	add_child(fire)
	AudioDirector.attach_loop(fire, "fire", -6.0, 18.0)
	var smoke := ChimneySmoke.new()
	smoke.position = fire.position + Vector3.UP * 0.6
	add_child(smoke)


func _build_yards() -> void:
	var props := Node3D.new()
	props.name = "YardProps"
	add_child(props)
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.4, 0.33, 0.25))
	# Privies and a lean-to in each court.
	for p: Vector3 in [Vector3(-31.5, 0, 31.0), Vector3(-31.5, 0, -31.0), Vector3(-43.0, 0, -31.5)]:
		_solid(Vector3(1.4, 2.3, 1.4), p + Vector3.UP * 1.15, wood)
	# The court pump.
	var iron := MaterialLibrary.get_material("iron")
	_solid(Vector3(0.3, 1.4, 0.3), Vector3(-25.0, 0.7, 20.0), iron)
	_mb.add_box(Vector3(0.9, 0.08, 0.08), Vector3(-24.6, 1.3, 20.0), iron)
	_mb.add_box(Vector3(1.2, 0.3, 0.8), Vector3(-25.0, 0.15, 20.8), MaterialLibrary.get_tinted("stone_trim", Color(0.5, 0.5, 0.46)))
	# Rubbish and straw heaps to hide in, crates and barrels.
	for p: Vector3 in [Vector3(-20.5, 0, 30.0), Vector3(-30.0, 0, -24.0), Vector3(-66.0, 0, -30.0)]:
		var heap := StreetProps.make_hay_heap(Color(0.42, 0.36, 0.26))
		heap.position = p
		props.add_child(heap)
	for p: Vector3 in [Vector3(-19.0, 0, 9.0), Vector3(-19.6, 0, -18.0), Vector3(-42.0, 0, 30.0)]:
		var crate := StreetProps.make_crate(0.7)
		crate.position = p + Vector3.UP * 0.35
		props.add_child(crate)
		var barrel := StreetProps.make_barrel()
		barrel.position = p + Vector3(1.0, 0.43, 0.4)
		props.add_child(barrel)
	var cart := StreetProps.make_handcart()
	cart.position = Vector3(-27.0, 0.0, 12.0)
	cart.rotation.y = 0.7
	props.add_child(cart)
	# Washing strung across the courts.
	var cloth := [Color(0.85, 0.83, 0.78), Color(0.6, 0.55, 0.5), Color(0.7, 0.3, 0.25), Color(0.4, 0.45, 0.55)]
	for line: Array in [[Vector3(-17.0, 4.2, 14.0), Vector3(-33.5, 4.6, 14.0)], [Vector3(-17.0, 4.0, -24.0), Vector3(-33.5, 4.3, -21.0)], [Vector3(-40.5, 4.2, -26.0), Vector3(-69.5, 4.5, -24.0)]]:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var len := a.distance_to(b)
		var dir := (b - a).normalized()
		_mb.add_box(Vector3(len, 0.015, 0.015), (a + b) * 0.5, iron, Basis(Vector3.UP, atan2(-dir.z, dir.x)))
		for k in int(len / 1.3):
			var p := a.lerp(b, (k + 0.5) / int(len / 1.3))
			var hh := _rng.randf_range(0.5, 1.0)
			_mb.add_box(Vector3(_rng.randf_range(0.5, 0.9), hh, 0.02), p - Vector3.UP * hh * 0.5, MaterialLibrary.get_tinted("fabric", cloth[_rng.randi() % cloth.size()]), Basis(Vector3.UP, atan2(-dir.z, dir.x)))
	# Bunting across Church Lane, put up once the rookery has something to celebrate.
	_bunting = Node3D.new()
	_bunting.name = "Bunting"
	add_child(_bunting)
	var bmb := MeshBuilder.new()
	for k in 3:
		var x := -20.0 - k * 5.5
		for j in 7:
			var z := LANE_Z0 + 0.3 + j * 0.45
			var col: Color = [Color(0.8, 0.15, 0.15), Color(0.9, 0.9, 0.85), Color(0.15, 0.25, 0.65)][j % 3]
			bmb.add_box(Vector3(0.02, 0.3, 0.25), Vector3(x, 5.6 - absf(j - 3.0) * -0.05, z), MaterialLibrary.get_tinted("fabric", col))
		bmb.add_box(Vector3(0.01, 0.01, LANE_Z1 - LANE_Z0), Vector3(x, 5.75, (LANE_Z0 + LANE_Z1) * 0.5), iron)
	bmb.build_into(_bunting, "Flags", false)


func _build_lamps() -> void:
	for p: Vector3 in [Vector3(-33.3, 0.0, -5.7), Vector3(-41.0, 0.0, -1.6), Vector3(DOOR_X - 2.3, 0.0, 2.2),
			Vector3(-22.0, 0.0, 16.0), Vector3(-22.0, 0.0, -20.0), Vector3(-60.0, 0.0, -20.0)]:
		var lamp := GasLamp.new()
		lamp.position = p
		add_child(lamp)


# ---------------------------------------------------------------------------
# People and how the district is doing
# ---------------------------------------------------------------------------
func _build_people() -> void:
	var folk := Node3D.new()
	folk.name = "Folk"
	add_child(folk)
	# The rookery's own people (Old Meg, Dan Tully...) live in these tenements and keep
	# their daily round from Population: their yards (YARDS), the soup kitchen, home.
	# Beggars sitting in the lane and the soup queue (see _apply_wellbeing).
	# [position, facing yaw] (yaw 0 faces -Z).
	var beg_spots: Array = [[Vector3(-18.2, 0.0, -2.95), 0.0], [Vector3(-30.0, 0.0, -5.65), PI], [Vector3(-41.2, 0.0, -6.6), PI],
		[Vector3(-45.0, 0.0, 2.4), 0.0], [Vector3(-20.0, 0.0, -15.0), 0.0]]
	for i in beg_spots.size():
		var b := NPCBody.new()
		b.name = "Beggar%d" % i
		b.outfit = NPCBody.Outfit.RAGGED
		b.height = 1.7
		b.position = beg_spots[i][0]
		b.rotation.y = beg_spots[i][1]
		folk.add_child(b)
		_beggars.append(b)
	for i in 6:
		var q := NPCBody.new()
		q.name = "SoupQueue%d" % i
		q.outfit = NPCBody.Outfit.RAGGED if i % 2 == 0 else NPCBody.Outfit.WORKER
		q.height = 1.62 + (i % 3) * 0.06
		q.position = Vector3(SOUP_POINT.x + 2.8 + 0.08 * (i % 2), 0.0, SOUP_POINT.z + 2.2 - i * 0.8)
		q.rotation.y = PI # facing the cauldron
		folk.add_child(q)
		_queue.append(q)
	_pose_bodies.call_deferred()


func _pose_bodies() -> void:
	for b in _beggars:
		b.update_body(0.0, NPCBody.Pose.SIT, 0.1)
	for q in _queue:
		q.update_body(0.0, NPCBody.Pose.NORMAL, 0.1)


## Shows how the district is doing (0-100 from Progress.wellbeing), at this hour: beggars
## are out by day, the soup queue forms at dinner and supper time.
func _apply_wellbeing() -> void:
	var h := GameClock.hours()
	var begging := h >= BEGGING_HOURS.x and h < BEGGING_HOURS.y
	var serving := SOUP_HOURS.any(func(w: Vector2) -> bool: return h >= w.x and h < w.y)
	var wb := Progress.wellbeing
	for f in _flowers:
		f.visible = wb >= 15.0
	if _bunting:
		_bunting.visible = wb >= 45.0
	var beggars := 5 - int(wb / 20.0)
	for i in _beggars.size():
		_beggars[i].visible = begging and i < beggars
	var queue := 2 + int(wb / 25.0)
	for i in _queue.size():
		_queue[i].visible = serving and i < queue


## For tests: what the district shows now.
func describe_wellbeing() -> Dictionary:
	return {
		"flowers": _flowers.size() > 0 and _flowers[0].visible,
		"bunting": _bunting.visible,
		"beggars": _beggars.filter(func(b: NPCBody) -> bool: return b.visible).size(),
		"queue": _queue.filter(func(b: NPCBody) -> bool: return b.visible).size(),
	}
