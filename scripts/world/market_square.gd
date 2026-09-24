@tool
class_name MarketSquare
extends Node3D
## A Spitalfields-style market square north of the test street (Phase 4).
##
## Layout (world metres): a 7.6 m carriageway passage from the street's north end
## (z = -46) leads into a cobbled square x = -25 .. 25, z = -52 .. -90, ringed by shops and
## a pub, with 16 costermongers' stalls in four rows. The people who fill it (traders,
## shoppers) follow the clock and are managed by Population; the constable by StreetPatrols.

const X0 := -25.0
const X1 := 25.0
const Z_SOUTH := -52.0
const Z_NORTH := -90.0
const PAVE_W := 2.2
const PAVE_TOP := 0.15
const STREET_END := -46.0
const ROAD_HALF := 3.8
const FACADE_X := 6.3

const SHOPS: Array[String] = [
	"THE TEN BELLS", "R. HUGHES  POULTERER", "J. COHEN  TAILOR", "SPITALFIELDS FRUIT EXCHANGE",
	"M. DOYLE  PAWNBROKER", "THE WHITE HART", "H. FOSTER  SADDLER", "A. LEVY  WATCHMAKER",
	"T. BARNES  CHANDLER", "PRICE & SONS  GROCERS",
]
const GOODS: Array[String] = ["fish", "fruit", "vegetables", "bread", "flowers", "cloth", "crockery", "chestnuts"]
const AWNINGS: Array[Color] = [
	Color(0.45, 0.1, 0.08), Color(0.12, 0.25, 0.15), Color(0.15, 0.18, 0.35), Color(0.5, 0.42, 0.25),
]

@export var layout_seed: int = 1866

var _rng := RandomNumberGenerator.new()
var _shop_i := 0
## The stalls, in order. Traders and shoppers are managed by Population (Phase 5).
var stalls: Array[Node3D] = []


func _ready() -> void:
	add_to_group("navigation_source")
	_rng.seed = layout_seed
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build_ground()
	_build_buildings()
	stalls = _build_stalls()
	_build_lamps()


func get_wander_center() -> Vector3:
	return Vector3(0, 0, (Z_SOUTH + Z_NORTH) * 0.5)


func get_wander_extent() -> Vector2:
	return Vector2((X1 - X0) * 0.5 - PAVE_W - 1.0, (Z_SOUTH - Z_NORTH) * 0.5 - PAVE_W - 1.0)


# ---------------------------------------------------------------------------
func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.set_meta("surface", "stone")
	add_child(ground)
	_box_collider(ground, Vector3(80, 2, 60), Vector3(0, -1, -75))

	var cobbles := MeshInstance3D.new()
	cobbles.name = "Cobbles"
	var plane := PlaneMesh.new()
	plane.size = Vector2(X1 - X0, STREET_END - Z_NORTH)
	cobbles.mesh = plane
	cobbles.position = Vector3(0, 0, (STREET_END + Z_NORTH) * 0.5)
	cobbles.material_override = MaterialLibrary.get_for_uv_plane("cobblestone", plane.size)
	add_child(cobbles)

	var mb := MeshBuilder.new()
	var granite := MaterialLibrary.get_material("curb_granite")
	var paving := MaterialLibrary.get_material("pavement")
	# Passage pavements (continuing the street's) between the south-row buildings.
	for side: float in [-1.0, 1.0]:
		_pavement(mb, ground, paving, granite, Vector3(side * (ROAD_HALF + FACADE_X) * 0.5, 0, (STREET_END + Z_SOUTH) * 0.5), Vector3(FACADE_X - ROAD_HALF, 0, STREET_END - Z_SOUTH))
	# Pavements in front of the four sides of the square.
	var inner_x0 := X0 + PAVE_W
	var inner_x1 := X1 - PAVE_W
	_pavement(mb, ground, paving, granite, Vector3(X0 + PAVE_W * 0.5, 0, (Z_SOUTH + Z_NORTH) * 0.5), Vector3(PAVE_W, 0, Z_SOUTH - Z_NORTH))
	_pavement(mb, ground, paving, granite, Vector3(X1 - PAVE_W * 0.5, 0, (Z_SOUTH + Z_NORTH) * 0.5), Vector3(PAVE_W, 0, Z_SOUTH - Z_NORTH))
	_pavement(mb, ground, paving, granite, Vector3(0, 0, Z_NORTH + PAVE_W * 0.5), Vector3(inner_x1 - inner_x0, 0, PAVE_W))
	for side: float in [-1.0, 1.0]:
		var xa := ROAD_HALF
		var xb := inner_x1
		_pavement(mb, ground, paving, granite, Vector3(side * (xa + xb) * 0.5, 0, Z_SOUTH - PAVE_W * 0.5), Vector3(xb - xa, 0, PAVE_W))
	mb.build_into(self, "Pavements").gi_mode = GeometryInstance3D.GI_MODE_STATIC


func _pavement(mb: MeshBuilder, body: StaticBody3D, paving: Material, _granite: Material, center: Vector3, size: Vector3) -> void:
	var s := Vector3(size.x, PAVE_TOP + 0.2, size.z)
	var c := Vector3(center.x, PAVE_TOP - s.y * 0.5, center.z)
	mb.add_box(s, c, paving)
	_box_collider(body, s, c)


func _build_buildings() -> void:
	# South row (facing north, into the square), either side of the passage.
	_row_along_x(X0, -FACADE_X, Z_SOUTH, PI, 6.0)
	_row_along_x(FACADE_X, X1, Z_SOUTH, PI, 6.0)
	# North row (facing south).
	_row_along_x(X0, X1, Z_NORTH, 0.0, 10.0)
	# West row (facing east) and east row (facing west).
	_row_along_z(Z_NORTH, Z_SOUTH, X0, PI * 0.5)
	_row_along_z(Z_NORTH, Z_SOUTH, X1, -PI * 0.5)


## Buildings whose facades lie on the line z = z_line between x0 and x1.
func _row_along_x(x0: float, x1: float, z_line: float, yaw: float, depth: float) -> void:
	var x := x0
	while x1 - x > 0.01:
		var w := _rng.randf_range(5.5, 8.0)
		if x1 - (x + w) < 4.5:
			w = x1 - x
		var b := _make_building(w, depth)
		b.rotation.y = yaw
		# yaw 0 faces +Z (local x runs +X); yaw PI faces -Z (local x runs -X).
		b.position = Vector3(x if yaw == 0.0 else x + w, PAVE_TOP, z_line)
		add_child(b)
		x += w


## Buildings whose facades lie on the line x = x_line between z0 and z1.
func _row_along_z(z0: float, z1: float, x_line: float, yaw: float) -> void:
	var z := z0
	while z1 - z > 0.01:
		var w := _rng.randf_range(5.5, 8.0)
		if z1 - (z + w) < 4.5:
			w = z1 - z
		var b := _make_building(w, 10.0)
		b.rotation.y = yaw
		# yaw +90 deg faces +X (local x runs -Z); yaw -90 deg faces -X (local x runs +Z).
		b.position = Vector3(x_line, PAVE_TOP, z + w if yaw > 0.0 else z)
		add_child(b)
		z += w


func _make_building(width: float, depth: float) -> BuildingFacade:
	var b := BuildingFacade.new()
	b.width = width
	b.depth = depth
	b.upper_floors = 2 + int(_rng.randf() > 0.5)
	var roll := _rng.randf()
	b.wall_material = "brick_yellow" if roll < 0.55 else ("brick_red" if roll < 0.85 else "stucco")
	b.variation_seed = _rng.randi()
	b.door_on_left = _rng.randf() > 0.5
	if _shop_i < SHOPS.size() and _rng.randf() < 0.7:
		b.ground_floor = BuildingFacade.GroundFloor.SHOP
		b.shop_name = SHOPS[_shop_i]
		b.has_awning = _rng.randf() > 0.4
		_shop_i += 1
	return b


## Four rows of four stalls; pairs of rows face each other across a shoppers' aisle.
func _build_stalls() -> Array[Node3D]:
	var stalls: Array[Node3D] = []
	var xs: Array[float] = [-16.5, -10.0, 10.0, 16.5]
	# yaw 0 faces north (-Z), yaw PI faces south: rows -59/-66 and -75/-82 face each other.
	var rows: Array[Array] = [[-59.0, 0.0], [-66.0, PI], [-75.0, 0.0], [-82.0, PI]]
	var i := 0
	for row in rows:
		for x in xs:
			var goods: String = GOODS[i % GOODS.size()]
			var stall := StreetProps.make_market_stall(goods, AWNINGS[i % AWNINGS.size()], layout_seed + i)
			stall.name = "Stall_%02d_%s" % [i, goods]
			stall.position = Vector3(x, 0.0, float(row[0]))
			stall.rotation.y = float(row[1]) + _rng.randf_range(-0.05, 0.05)
			stall.set_meta("goods", goods)
			add_child(stall)
			stalls.append(stall)
			# Places where shoppers stand to browse, in front of the table.
			var front := stall.global_transform.basis * Vector3(0, 0, -1)
			for off: float in [-0.7, 0.7]:
				var m := Marker3D.new()
				m.name = "Browse"
				add_child(m)
				m.global_position = stall.global_position + front * 1.25 + stall.global_transform.basis.x * off
				m.set_meta("look_at", stall.global_position + Vector3.UP * 0.9)
				m.add_to_group("browse_points")
			i += 1
	# A couple of heaps of sacks beside stalls: somewhere to duck out of sight.
	for p: Vector3 in [Vector3(-13.3, 0.0, -70.5), Vector3(13.3, 0.0, -70.5)]:
		var heap := StreetProps.make_hay_heap(Color(0.42, 0.34, 0.24))
		heap.name = "Sacks"
		heap.position = p
		add_child(heap)
	return stalls


func _build_lamps() -> void:
	for p: Vector3 in [
		Vector3(-23.2, PAVE_TOP, -60.0), Vector3(-23.2, PAVE_TOP, -80.0),
		Vector3(23.2, PAVE_TOP, -60.0), Vector3(23.2, PAVE_TOP, -80.0),
		Vector3(-8.0, PAVE_TOP, -88.0), Vector3(8.0, PAVE_TOP, -88.0),
		Vector3(-11.0, PAVE_TOP, -53.9), Vector3(11.0, PAVE_TOP, -53.9),
	]:
		var lamp := GasLamp.new()
		lamp.position = p
		add_child(lamp)


func _box_collider(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	body.add_child(cs)


## Where the trader of stall `i` stands, and where he looks (his customers).
func get_trader_spot(i: int) -> Array[Vector3]:
	var stall := stalls[i]
	var back := stall.global_transform.basis * Vector3(0, 0, 1)
	return [stall.global_position + back * 1.0, stall.global_position - back * 3.0]
