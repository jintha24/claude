@tool
class_name AshcombeHouse
extends Node3D
## Phase 7: Ashcombe House, Lord Ashcombe's town mansion, and its walled grounds.
## The first great house Harry breaks into. Everything is built from code at real scale.
##
## Layout (world metres; the market square's east side is x = 25):
##   * Ashcombe Row: a lane from the market's east side (z -74 .. -68) to the main gate.
##   * The mews: a back lane outside the west wall (x 35 .. 46, z -112 .. -30), with the
##     tradesmen's door and a sewer manhole.
##   * The grounds, walled on every side (x 46 .. 106, z -112 .. -30): a gravel forecourt
##     with the gate lodge, a service yard with kennel, lawns, shrubberies and the garden.
##   * The house (x 62 .. 80, z -86 .. -56), facing west: ground floor (y 0.9) with entrance
##     hall, stair hall, dining room, library and butler's pantry; first floor (y 5.4) with
##     the picture gallery, Lord Ashcombe's study (the safe), his bedroom, Lady Evelyn's
##     room and the linen room. A single-storey servants' wing (kitchen and servants' hall)
##     joins it on the north side.
##
## Ways in: the front gate (open by day, locked at night) past the gatekeeper; the
## tradesmen's door from the mews and the servants' entrance; the drainpipe to the wing
## roof and a first-floor window; over the garden wall; the ground-floor windows and garden
## door; or the old sewer from the mews manhole to a drain in the south lawn.

const EST_X0 := 46.0
const EST_X1 := 106.0
const EST_Z0 := -112.0
const EST_Z1 := -30.0
const LANE_Z0 := -74.0
const LANE_Z1 := -68.0
const MEWS_X0 := 35.0
const MARKET_X1 := 25.0
const HX0 := 62.0
const HX1 := 80.0
const HZ0 := -86.0
const HZ1 := -56.0
const WING_X0 := 64.0
const WING_X1 := 78.0
const WING_Z0 := -100.0
const GF := 0.9
const FF := 5.4
const ROOF := 9.9
const WING_ROOF := 4.8
const WALL_H := 3.2
const SEWER_Y := -4.0
const SHAFT_A := Vector3(40.5, 0.0, -44.0)
const SHAFT_B := Vector3(92.0, 0.0, -44.0)
const RAMP_X0 := 71.0
const RAMP_X1 := 78.0
const RAMP_Z0 := -75.8
const RAMP_Z1 := -73.8

## Spots the staff script and tests use (world positions).
const GATE_POST := Vector3(49.5, 0.0, -65.5)
const KENNEL_YARD := Vector3(50.0, 0.0, -108.0)
const KENNEL_GARDEN := Vector3(101.0, 0.0, -104.0)

var _body: StaticBody3D
var _mb: MeshBuilder
var _mats := {}


func _ready() -> void:
	add_to_group("navigation_source")
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_body = StaticBody3D.new()
	_body.name = "Structure"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_mb = MeshBuilder.new()
	_load_materials()
	_build_ground()
	_build_mews_walls()
	_build_estate_walls()
	_build_gate()
	_build_lodge()
	_build_house_shell()
	_dress_facades()
	_build_house_floors()
	_build_staircase()
	_build_interior_walls()
	_build_wing()
	_build_sewer()
	_build_garden()
	var mi := _mb.build_into(self, "Mesh")
	if mi:
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_build_openings()
	_build_furniture()
	_build_loot()
	_build_lights()
	_build_zones()


func _load_materials() -> void:
	_mats = {
		"stucco": MaterialLibrary.get_tinted("stucco", Color(0.96, 0.93, 0.86)),
		"stone": MaterialLibrary.get_material("stone_trim"),
		"brick": MaterialLibrary.get_material("brick_red"),
		"brick_y": MaterialLibrary.get_material("brick_yellow"),
		"plaster": MaterialLibrary.get_material("plaster"),
		"ceiling": MaterialLibrary.get_tinted("plaster", Color(1.0, 0.98, 0.94)),
		"boards": MaterialLibrary.get_material("floorboards"),
		"marble": MaterialLibrary.get_material("marble"),
		"grass": MaterialLibrary.get_material("grass"),
		"gravel": MaterialLibrary.get_material("gravel"),
		"cobbles": MaterialLibrary.get_material("pavement"),
		"iron": MaterialLibrary.get_material("iron"),
		"gilt": MaterialLibrary.get_material("gilt"),
		"lead": MaterialLibrary.get_tinted("stone_trim", Color(0.36, 0.38, 0.4)),
		"wood": MaterialLibrary.get_tinted("wood_planks", Color(0.5, 0.36, 0.24)),
		"mahogany": MaterialLibrary.get_tinted("wood_painted", Color(0.28, 0.12, 0.07)),
		"paint": MaterialLibrary.get_tinted("wood_painted", Color(0.92, 0.9, 0.84)),
		"carpet": MaterialLibrary.get_material("carpet"),
		"hedge": MaterialLibrary.get_tinted("grass", Color(0.35, 0.5, 0.25)),
		"green_wall": MaterialLibrary.get_tinted("plaster", Color(0.45, 0.55, 0.45)),
		"red_wall": MaterialLibrary.get_tinted("plaster", Color(0.62, 0.3, 0.26)),
		"blue_wall": MaterialLibrary.get_tinted("plaster", Color(0.55, 0.62, 0.72)),
		"flags": MaterialLibrary.get_tinted("pavement", Color(0.8, 0.78, 0.74)),
		"sewer": MaterialLibrary.get_tinted("brick_yellow", Color(0.45, 0.42, 0.36)),
		"water": MaterialLibrary.get_material("water"),
	}


# ---------------------------------------------------------------------------
# Building helpers
# ---------------------------------------------------------------------------
## A box that is both drawn and solid.
func _solid(size: Vector3, center: Vector3, mat_key: String, surface: String = "") -> void:
	_mb.add_box(size, center, _mats[mat_key])
	_collider(size, center, surface)


func _collider(size: Vector3, center: Vector3, surface: String = "") -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	if surface != "":
		cs.set_meta("surface", surface)
	_body.add_child(cs)


## A wall running along Z at x = `line` (axis "z") or along X at z = `line` (axis "x"),
## from a0 to a1, y0 to y1, `t` thick. `openings`: Array of [a_from, a_to, y_bottom, y_top].
func _wall(axis: String, line: float, a0: float, a1: float, y0: float, y1: float, t: float, mat_key: String, openings: Array = [], collide: bool = true, offset: float = 0.0) -> void:
	# Openings in the same column (a ground-floor and a first-floor window one above the
	# other) are grouped, so the solid wall between them is built only once.
	var columns := {}
	for op: Array in openings:
		var k := Vector2(snappedf(float(op[0]), 0.01), snappedf(float(op[1]), 0.01))
		if not columns.has(k):
			columns[k] = []
		(columns[k] as Array).append(Vector2(float(op[2]), float(op[3])))
	var keys := columns.keys()
	keys.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var cursor := a0
	for k: Vector2 in keys:
		_wall_piece(axis, line + offset, cursor, k.x, y0, y1, t, mat_key, collide)
		var spans: Array = columns[k]
		spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		var y := y0
		for sp: Vector2 in spans:
			_wall_piece(axis, line + offset, k.x, k.y, y, sp.x, t, mat_key, collide)
			y = sp.y
		_wall_piece(axis, line + offset, k.x, k.y, y, y1, t, mat_key, collide)
		cursor = k.y
	_wall_piece(axis, line + offset, cursor, a1, y0, y1, t, mat_key, collide)


func _wall_piece(axis: String, line: float, a0: float, a1: float, y0: float, y1: float, t: float, mat_key: String, collide: bool) -> void:
	if a1 - a0 < 0.01 or y1 - y0 < 0.01:
		return
	var size: Vector3
	var center: Vector3
	if axis == "z":
		size = Vector3(t, y1 - y0, a1 - a0)
		center = Vector3(line, (y0 + y1) * 0.5, (a0 + a1) * 0.5)
	else:
		size = Vector3(a1 - a0, y1 - y0, t)
		center = Vector3((a0 + a1) * 0.5, (y0 + y1) * 0.5, line)
	_mb.add_box(size, center, _mats[mat_key])
	if collide:
		_collider(size, center)


## A horizontal slab (x0..x1, z0..z1) with its top at `top`, minus rectangular `holes`
## (Rect2 in x/z).
func _slab(x0: float, x1: float, z0: float, z1: float, top: float, thick: float, mat_key: String, surface: String = "", holes: Array = [], collide: bool = true) -> void:
	var rects: Array[Rect2] = [Rect2(x0, z0, x1 - x0, z1 - z0)]
	for h: Rect2 in holes:
		var next: Array[Rect2] = []
		for r in rects:
			if not r.intersects(h):
				next.append(r)
				continue
			var i := r.intersection(h)
			if i.position.x > r.position.x:
				next.append(Rect2(r.position.x, r.position.y, i.position.x - r.position.x, r.size.y))
			if i.end.x < r.end.x:
				next.append(Rect2(i.end.x, r.position.y, r.end.x - i.end.x, r.size.y))
			if i.position.y > r.position.y:
				next.append(Rect2(i.position.x, r.position.y, i.size.x, i.position.y - r.position.y))
			if i.end.y < r.end.y:
				next.append(Rect2(i.position.x, i.end.y, i.size.x, r.end.y - i.end.y))
		rects = next
	for r in rects:
		if r.size.x < 0.01 or r.size.y < 0.01:
			continue
		var size := Vector3(r.size.x, thick, r.size.y)
		var center := Vector3(r.position.x + r.size.x * 0.5, top - thick * 0.5, r.position.y + r.size.y * 0.5)
		_mb.add_box(size, center, _mats[mat_key])
		if collide:
			_collider(size, center, surface)


## Transform for a door or window in a wall, `outward` = the world direction of local +Z.
static func _xf(pos: Vector3, outward: Vector3) -> Transform3D:
	var yaw := atan2(outward.x, outward.z)
	return Transform3D(Basis(Vector3.UP, yaw), pos)


# ---------------------------------------------------------------------------
# Ground: lane, mews, forecourt, yard, lawns and garden
# ---------------------------------------------------------------------------
func _build_ground() -> void:
	var shaft := 1.0
	var hole_a := Rect2(SHAFT_A.x - shaft * 0.5, SHAFT_A.z - shaft * 0.5, shaft, shaft)
	var hole_b := Rect2(SHAFT_B.x - shaft * 0.5, SHAFT_B.z - shaft * 0.5, shaft, shaft)
	_slab(MARKET_X1, EST_X0, LANE_Z0, LANE_Z1, 0.0, 1.0, "cobbles", "stone") # Ashcombe Row
	_slab(MEWS_X0, EST_X0, EST_Z0, EST_Z1, 0.0, 1.0, "cobbles", "stone", [hole_a]) # the mews
	_slab(EST_X0, HX0, -90.0, HZ1, 0.0, 1.0, "gravel", "gravel") # forecourt
	_slab(EST_X0, WING_X0, EST_Z0, -90.0, 0.0, 1.0, "flags", "stone") # service yard
	_slab(WING_X0, EST_X1, EST_Z0, HZ0, 0.0, 1.0, "grass", "grass") # north garden (under the wing)
	_slab(HX1, EST_X1, HZ0, HZ1, 0.0, 1.0, "grass", "grass") # rear garden
	_slab(EST_X0, EST_X1, HZ1, EST_Z1, 0.0, 1.0, "grass", "grass", [hole_b]) # south lawn
	_slab(HX0 - 0.1, WING_X0, -90.0, HZ0, 0.0, 1.0, "flags", "stone") # passage by the wing
	# Gravel paths across the lawns (visual strips on the grass).
	for p: Array in [[Vector3(90.0, 0.005, -71.0), Vector3(20.0, 0.01, 2.2)], [Vector3(93.0, 0.005, -58.0), Vector3(2.2, 0.01, 50.0)], [Vector3(73.0, 0.005, -40.0), Vector3(50.0, 0.01, 2.2)]]:
		_mb.add_box(p[1], p[0], _mats["gravel"])
	# Cast-iron bollards along Ashcombe Row keep carriages off the footway.
	for x: float in [28.0, 32.5, 37.0, 41.5]:
		for z: float in [LANE_Z0 + 0.45, LANE_Z1 - 0.45]:
			var bollard := StreetProps.make_bollard()
			bollard.position = Vector3(x, 0.0, z)
			add_child(bollard)
	# Carriage drive from the gate to the portico (a strip of darker gravel).
	_mb.add_box(Vector3(14.0, 0.01, 5.0), Vector3(53.0, 0.006, -71.0), MaterialLibrary.get_tinted("gravel", Color(0.8, 0.77, 0.7)))


## Walls closing the mews off from the rest of the town.
func _build_mews_walls() -> void:
	_wall("z", MEWS_X0 - 0.25, EST_Z0, -90.0, 0.0, 4.0, 0.5, "brick_y")
	_wall("z", MEWS_X0 - 0.25, -52.0, EST_Z1, 0.0, 4.0, 0.5, "brick_y")
	_wall("x", EST_Z0 - 0.25, MARKET_X1, EST_X0, 0.0, 4.0, 0.5, "brick_y")
	_wall("x", EST_Z1 + 0.25, MARKET_X1, EST_X0, 0.0, 4.0, 0.5, "brick_y")
	# The block between the market's north-east corner and the mews.
	_solid(Vector3(MEWS_X0 - MARKET_X1, 4.0, -90.0 - EST_Z0), Vector3((MARKET_X1 + MEWS_X0) * 0.5, 2.0, (EST_Z0 - 90.0) * 0.5), "brick_y")


# ---------------------------------------------------------------------------
# Boundary walls, railings and gates
# ---------------------------------------------------------------------------
func _build_estate_walls() -> void:
	var t := 0.5
	var coping := func(axis: String, line: float, a0: float, a1: float) -> void:
		if axis == "z":
			_solid(Vector3(0.65, 0.12, a1 - a0), Vector3(line, WALL_H + 0.06, (a0 + a1) * 0.5), "stone")
		else:
			_solid(Vector3(a1 - a0, 0.12, 0.65), Vector3((a0 + a1) * 0.5, WALL_H + 0.06, line), "stone")
	# West wall (street side): brick, with the tradesmen's door, railings either side of the gate.
	_wall("z", EST_X0, EST_Z0, -86.0, 0.0, WALL_H, t, "brick", [[-101.0, -99.8, 0.0, 2.4]])
	coping.call("z", EST_X0, EST_Z0, -101.0)
	coping.call("z", EST_X0, -99.8, -86.0)
	_railings(-86.0, LANE_Z0 - 0.45)
	_railings(LANE_Z1 + 0.45, HZ1)
	_wall("z", EST_X0, HZ1, EST_Z1, 0.0, WALL_H, t, "brick")
	coping.call("z", EST_X0, HZ1, EST_Z1)
	# North, east and south walls.
	_wall("x", EST_Z0, EST_X0, EST_X1, 0.0, WALL_H, t, "brick")
	coping.call("x", EST_Z0, EST_X0, EST_X1)
	_wall("z", EST_X1, EST_Z0, EST_Z1, 0.0, WALL_H, t, "brick")
	coping.call("z", EST_X1, EST_Z0, EST_Z1)
	_wall("x", EST_Z1, EST_X0, EST_X1, 0.0, WALL_H, t, "brick")
	coping.call("x", EST_Z1, EST_X0, EST_X1)
	# Gate piers with stone balls.
	for z: float in [LANE_Z0 - 0.45, LANE_Z1 + 0.45]:
		_solid(Vector3(0.9, 3.4, 0.9), Vector3(EST_X0, 1.7, z), "stone")
		_mb.add_box(Vector3(1.05, 0.2, 1.05), Vector3(EST_X0, 3.5, z), _mats["stone"])
		var ball := SphereMesh.new()
		ball.radius = 0.32
		ball.height = 0.64
		_mb.add_mesh(ball, Transform3D(Basis.IDENTITY, Vector3(EST_X0, 3.92, z)), _mats["stone"])


## Iron railings on a stone dwarf wall along the west side (see-through, spear-topped).
func _railings(z0: float, z1: float) -> void:
	_solid(Vector3(0.5, 0.6, z1 - z0), Vector3(EST_X0, 0.3, (z0 + z1) * 0.5), "stone")
	var body := StaticBody3D.new()
	body.name = "Railings"
	body.collision_layer = MansionWindow.LAYER_GLASS
	body.collision_mask = 0
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.12, 1.9, z1 - z0)
	cs.shape = box
	cs.position = Vector3(EST_X0, 0.6 + 0.95, (z0 + z1) * 0.5)
	body.add_child(cs)
	var n := int((z1 - z0) / 0.13)
	for i in n:
		var z := z0 + 0.065 + i * 0.13
		_mb.add_cylinder(0.012, 0.012, 1.9, Vector3(EST_X0, 1.55, z), _mats["iron"], 6)
		_mb.add_cylinder(0.0, 0.028, 0.12, Vector3(EST_X0, 2.56, z), _mats["iron"], 6)
	for y: float in [0.75, 2.35]:
		_mb.add_box(Vector3(0.04, 0.04, z1 - z0), Vector3(EST_X0, y, (z0 + z1) * 0.5), _mats["iron"])


func _build_gate() -> void:
	var h := 2.9
	var w := (LANE_Z1 - LANE_Z0) * 0.5 - 0.05
	var a := MansionDoor.new()
	a.name = "GateNorth"
	a.door_name = "gate"
	a.iron_gate = true
	a.width = w
	a.height = h
	a.lock_levers = 4
	a.lock_gate = 0.18
	a.key_id = "gate"
	a.opens_freely_from_inside = false
	a.should_stay_closed = false
	a.start_open = true
	a.transform = _xf(Vector3(EST_X0, 0.0, LANE_Z0 + w * 0.5 + 0.05), Vector3.LEFT)
	add_child(a)
	var b := MansionDoor.new()
	b.name = "GateSouth"
	b.door_name = "gate"
	b.iron_gate = true
	b.width = w
	b.height = h
	b.harry_can_use = false
	b.should_stay_closed = false
	b.start_open = true
	b.start_swing = -1.0
	b.transform = _xf(Vector3(EST_X0, 0.0, LANE_Z1 - w * 0.5 - 0.05), Vector3.RIGHT)
	add_child(b)
	var trade := MansionDoor.new()
	trade.name = "TradesmensDoor"
	trade.door_name = "tradesmen's door"
	trade.width = 1.1
	trade.height = 2.3
	trade.lock_levers = 3
	trade.key_id = "trade_door"
	trade.leaf_color = Color(0.18, 0.22, 0.16)
	trade.transform = _xf(Vector3(EST_X0, 0.0, -100.4), Vector3.LEFT)
	add_child(trade)


# ---------------------------------------------------------------------------
# Gate lodge (the gatekeeper's hut, where the spare keys hang)
# ---------------------------------------------------------------------------
func _build_lodge() -> void:
	var x0 := 47.0
	var x1 := 53.0
	var z0 := -63.0
	var z1 := -57.0
	var top := 3.2
	_slab(x0, x1, z0, z1, 0.15, 0.15, "boards", "wood")
	_wall("x", z0, x0, x1, 0.0, top, 0.3, "brick_y", [[49.9, 51.0, 0.15, 2.35]])
	_wall("x", z1, x0, x1, 0.0, top, 0.3, "brick_y")
	_wall("z", x0, z0, z1, 0.0, top, 0.3, "brick_y", [[-60.6, -59.4, 1.0, 2.4]])
	_wall("z", x1, z0, z1, 0.0, top, 0.3, "brick_y")
	_slab(x0 - 0.3, x1 + 0.3, z0 - 0.3, z1 + 0.3, top + 0.2, 0.2, "lead", "metal")
	_mb.add_box(Vector3(6.2, 0.02, 6.2), Vector3(50.0, top - 0.01, -60.0), _mats["ceiling"])
	# A small table and stool.
	_solid(Vector3(0.9, 0.75, 0.6), Vector3(48.0, 0.525, -61.9), "mahogany")


# ---------------------------------------------------------------------------
# The house: outer walls, cornices, portico, roof
# ---------------------------------------------------------------------------
func _build_house_shell() -> void:
	var t := 0.5
	var top := ROOF + 0.3 # the parapet above this is a stone balustrade (_dress_facades)
	var gf_win := [1.6, 3.8]
	var ff_win := [6.1, 8.4]
	# Front (west): door and windows.
	var front: Array = [[-71.65, -70.35, GF, 3.7]]
	for z: float in [-82.0, -78.0, -64.0, -60.0]:
		front.append([z - 0.55, z + 0.55, gf_win[0], gf_win[1]])
	for z: float in [-82.0, -78.0, -74.0, -68.0, -64.0, -60.0]:
		front.append([z - 0.55, z + 0.55, ff_win[0], ff_win[1]])
	_wall("z", HX0, HZ0 - 0.25, HZ1 + 0.25, 0.0, top, t, "stucco", front)
	# Rear (east): garden door and windows.
	var rear: Array = [[-69.6, -68.4, GF, 3.5]]
	for z: float in [-82.0, -78.0, -64.0, -60.0]:
		rear.append([z - 0.55, z + 0.55, gf_win[0], gf_win[1]])
	for z: float in [-82.0, -78.0, -74.0, -64.0, -60.0]:
		rear.append([z - 0.55, z + 0.55, ff_win[0], ff_win[1]])
	_wall("z", HX1, HZ0 - 0.25, HZ1 + 0.25, 0.0, top, t, "stucco", rear)
	# North: the door to the servants' wing; first-floor windows over the wing roof.
	var north: Array = [[74.4, 75.6, GF, 3.3]]
	for x: float in [67.0, 77.0]:
		north.append([x - 0.55, x + 0.55, ff_win[0], ff_win[1]])
	_wall("x", HZ0, HX0 + 0.25, HX1 - 0.25, 0.0, top, t, "stucco", north)
	# South: dining room, study and bedroom windows.
	var south: Array = []
	for x: float in [65.0, 69.0, 73.0, 77.0]:
		south.append([x - 0.55, x + 0.55, gf_win[0], gf_win[1]])
	for x: float in [65.0, 69.0, 73.0, 77.0]:
		south.append([x - 0.55, x + 0.55, ff_win[0], ff_win[1]])
	_wall("x", HZ1, HX0 + 0.25, HX1 - 0.25, 0.0, top, t, "stucco", south)
	# Plinth (the raised ground floor) and a rusticated base band.
	_solid(Vector3(HX1 - HX0 - 0.5, GF - 0.1, HZ1 - HZ0 - 0.5), Vector3((HX0 + HX1) * 0.5, (GF - 0.1) * 0.5, (HZ0 + HZ1) * 0.5), "stone")
	# Cornices and string courses.
	for y: float in [GF - 0.05, FF + 0.15, ROOF + 0.05]:
		_mb.add_box(Vector3(HX1 - HX0 + 0.3, 0.22, HZ1 - HZ0 + 0.3), Vector3((HX0 + HX1) * 0.5, y, (HZ0 + HZ1) * 0.5), _mats["stone"])
	# Roof (lead flat behind the parapet) and chimney stacks.
	_slab(HX0 + 0.25, HX1 - 0.25, HZ0 + 0.25, HZ1 - 0.25, ROOF, 0.3, "lead", "metal")
	for p: Vector3 in [Vector3(66.0, 0, -85.6), Vector3(76.0, 0, -85.6), Vector3(66.0, 0, -56.4), Vector3(76.0, 0, -56.4)]:
		_solid(Vector3(2.2, 2.6, 0.9), Vector3(p.x, ROOF + 1.3, p.z), "brick")
		for k in 4:
			_mb.add_cylinder(0.14, 0.12, 0.6, Vector3(p.x - 0.75 + k * 0.5, ROOF + 2.9, p.z), _mats["brick"], 8)
	# Portico: steps, landing, four columns and a flat roof (a way up to the front windows).
	for i in 4:
		var top_y := 0.18 * (i + 1)
		_solid(Vector3(HX0 - (59.2 + i * 0.4), top_y, 5.2), Vector3((59.2 + i * 0.4 + HX0) * 0.5, top_y * 0.5, -71.0), "stone", "stone")
	_solid(Vector3(HX0 - 60.8, GF, 5.2), Vector3((60.8 + HX0) * 0.5, GF * 0.5, -71.0), "stone", "stone")
	for z: float in [-73.2, -71.9, -70.1, -68.8]:
		_mb.add_cylinder(0.2, 0.2, 3.7, Vector3(61.1, GF + 1.85, z), _mats["stucco"], 14)
		_collider(Vector3(0.38, 3.7, 0.38), Vector3(61.1, GF + 1.85, z))
	_solid(Vector3(HX0 - 60.6, 0.45, 7.2), Vector3((60.6 + HX0) * 0.5, GF + 3.7 + 0.225, -71.0), "stucco")


## Classical dressing in pale stone: window architraves with sills, pediments over the
## first-floor windows, quoins at the corners, a plinth course and a balustraded parapet
## with urns. Visual only, apart from the balustrade (which stops you walking off the roof).
func _dress_facades() -> void:
	var stone: Material = MaterialLibrary.get_tinted("stone_trim", Color(0.97, 0.95, 0.9))
	var half := 0.25
	# [line, axis, outward sign, centres, sill y, height]
	var faces: Array = [
		[HX0, "z", -1.0, [-82.0, -78.0, -64.0, -60.0], 1.6, 2.2], [HX0, "z", -1.0, [-82.0, -78.0, -74.0, -68.0, -64.0, -60.0], 6.1, 2.3],
		[HX1, "z", 1.0, [-82.0, -78.0, -64.0, -60.0], 1.6, 2.2], [HX1, "z", 1.0, [-82.0, -78.0, -74.0, -64.0, -60.0], 6.1, 2.3],
		[HZ1, "x", 1.0, [65.0, 69.0, 73.0, 77.0], 1.6, 2.2], [HZ1, "x", 1.0, [65.0, 69.0, 73.0, 77.0], 6.1, 2.3],
		[HZ0, "x", -1.0, [67.0, 77.0], 6.1, 2.3],
	]
	for f: Array in faces:
		var line := float(f[0])
		var along_z: bool = f[1] == "z"
		var sgn := float(f[2])
		var sill := float(f[4])
		var h := float(f[5])
		var w := 1.1
		var at := func(a: float, y: float, proud: float) -> Vector3:
			var o := line + sgn * (half + proud)
			return Vector3(o, y, a) if along_z else Vector3(a, y, o)
		var sz := func(across: float, tall: float, depth: float) -> Vector3:
			return Vector3(depth, tall, across) if along_z else Vector3(across, tall, depth)
		for c: float in f[3]:
			for side: float in [-1.0, 1.0]:
				_mb.add_box(sz.call(0.14, h + 0.14, 0.08), at.call(c + side * (w * 0.5 + 0.07), sill + h * 0.5 + 0.07, 0.04), stone)
			_mb.add_box(sz.call(w + 0.28, 0.14, 0.08), at.call(c, sill + h + 0.07, 0.04), stone)
			_mb.add_box(sz.call(w + 0.4, 0.09, 0.2), at.call(c, sill - 0.045, 0.1), stone) # sill
			if sill > 5.0:
				# First floor: a cornice and a triangular pediment over each window.
				_mb.add_box(sz.call(w + 0.5, 0.1, 0.22), at.call(c, sill + h + 0.19, 0.11), stone)
				var ped := PrismMesh.new()
				ped.size = Vector3(w + 0.5, 0.42, 0.18)
				var yaw := PI * 0.5 if along_z else 0.0
				_mb.add_mesh(ped, Transform3D(Basis(Vector3.UP, yaw), at.call(c, sill + h + 0.45, 0.1)), stone)
			else:
				_mb.add_box(sz.call(0.22, 0.26, 0.1), at.call(c, sill + h + 0.07, 0.07), stone) # keystone
	# Quoins: alternating long and short stones up each corner.
	for corner: Vector2 in [Vector2(HX0, HZ0), Vector2(HX0, HZ1), Vector2(HX1, HZ0), Vector2(HX1, HZ1)]:
		var sx := -1.0 if corner.x == HX0 else 1.0
		var sz2 := -1.0 if corner.y == HZ0 else 1.0
		var y := GF
		var k := 0
		while y < ROOF - 0.2:
			var long_x := k % 2 == 0
			var lx := 0.8 if long_x else 0.45
			var lz := 0.45 if long_x else 0.8
			_mb.add_box(Vector3(lx, 0.38, lz), Vector3(corner.x + sx * (half - lx * 0.5 + 0.04), y + 0.2, corner.y + sz2 * (half - lz * 0.5 + 0.04)), stone)
			y += 0.42
			k += 1
	# Plinth course at ground-floor level.
	_mb.add_box(Vector3(HX1 - HX0 + 0.36, 0.25, HZ1 - HZ0 + 0.36), Vector3((HX0 + HX1) * 0.5, GF - 0.3, (HZ0 + HZ1) * 0.5), stone)
	# Balustrade round the roof: plinth, balusters, coping rail, urns on the corners.
	var base := ROOF + 0.3
	var runs: Array = [
		[Vector3(HX0, 0, HZ0), Vector3(HX1, 0, HZ0)], [Vector3(HX1, 0, HZ0), Vector3(HX1, 0, HZ1)],
		[Vector3(HX1, 0, HZ1), Vector3(HX0, 0, HZ1)], [Vector3(HX0, 0, HZ1), Vector3(HX0, 0, HZ0)],
	]
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var d := b - a
		var length := d.length()
		var dir := d / length
		var mid := (a + b) * 0.5
		var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
		_mb.add_box(Vector3(length + 0.4, 0.14, 0.5), Vector3(mid.x, base + 0.07, mid.z), stone, basis)
		_mb.add_box(Vector3(length + 0.4, 0.12, 0.55), Vector3(mid.x, base + 0.78, mid.z), stone, basis)
		_collider(Vector3(absf(d.x) + 0.5, 0.85, absf(d.z) + 0.5), Vector3(mid.x, base + 0.42, mid.z))
		var n := int(length / 0.3)
		for i in n:
			var p := a + dir * (0.15 + i * length / n)
			_mb.add_cylinder(0.055, 0.085, 0.3, Vector3(p.x, base + 0.29, p.z), stone, 8)
			_mb.add_cylinder(0.085, 0.05, 0.28, Vector3(p.x, base + 0.58, p.z), stone, 8)
	for corner: Vector3 in [Vector3(HX0, 0, HZ0), Vector3(HX0, 0, HZ1), Vector3(HX1, 0, HZ0), Vector3(HX1, 0, HZ1)]:
		_mb.add_box(Vector3(0.6, 0.9, 0.6), Vector3(corner.x, base + 0.45, corner.z), stone)
		_mb.add_cylinder(0.14, 0.26, 0.45, Vector3(corner.x, base + 1.12, corner.z), stone, 12) # urn
		var lid := SphereMesh.new()
		lid.radius = 0.2
		lid.height = 0.3
		_mb.add_mesh(lid, Transform3D(Basis.IDENTITY, Vector3(corner.x, base + 1.42, corner.z)), stone)


func _build_house_floors() -> void:
	var ix0 := HX0 + 0.25
	var ix1 := HX1 - 0.25
	var iz0 := HZ0 + 0.25
	var iz1 := HZ1 - 0.25
	# Ground floor finishes: marble in the halls, boards elsewhere, carpets.
	_slab(ix0, ix1, -76.0, -66.0, GF, 0.1, "marble", "stone")
	_slab(ix0, ix1, iz0, -76.0, GF, 0.1, "boards", "wood")
	_slab(ix0, ix1, -66.0, iz1, GF, 0.1, "boards", "wood")
	_slab(63.5, 69.5, -84.5, -77.5, GF + 0.02, 0.02, "carpet", "carpet") # library Turkey carpet
	_slab(64.0, 78.0, -64.5, -57.5, GF + 0.02, 0.02, "carpet", "carpet") # dining room
	# First floor: boards, with a hole for the staircase. Carpet runner along the gallery.
	var well := Rect2(RAMP_X0, RAMP_Z0, RAMP_X1 - RAMP_X0, RAMP_Z1 - RAMP_Z0)
	_slab(ix0, ix1, iz0, iz1, FF, 0.25, "boards", "wood", [well])
	_slab(ix0, 70.8, -73.0, -69.0, FF + 0.02, 0.02, "carpet", "carpet")
	_slab(63.5, 69.5, -65.0, -57.5, FF + 0.02, 0.02, "carpet", "carpet") # study
	_slab(72.0, 79.0, -65.0, -57.5, FF + 0.02, 0.02, "carpet", "carpet") # bedroom
	# Ceilings (plaster, under the floor above and the roof).
	_mb.add_box(Vector3(ix1 - ix0, 0.02, iz1 - iz0), Vector3((ix0 + ix1) * 0.5, FF - 0.26, (iz0 + iz1) * 0.5), _mats["ceiling"])
	_mb.add_box(Vector3(ix1 - ix0, 0.02, iz1 - iz0), Vector3((ix0 + ix1) * 0.5, ROOF - 0.31, (iz0 + iz1) * 0.5), _mats["ceiling"])
	# Balustrade round the stairwell on the first floor.
	_solid(Vector3(76.6 - RAMP_X0, 1.0, 0.08), Vector3((RAMP_X0 + 76.6) * 0.5, FF + 0.5, RAMP_Z1 + 0.04), "mahogany")
	_solid(Vector3(0.08, 1.0, RAMP_Z1 - RAMP_Z0), Vector3(RAMP_X0 - 0.04, FF + 0.5, (RAMP_Z0 + RAMP_Z1) * 0.5), "mahogany")


## The main staircase: a straight flight up the north side of the stair hall to a landing
## against the garden wall. Walked on as a smooth slope (like every stair in the game),
## drawn as 25 carpeted steps.
func _build_staircase() -> void:
	var rise := FF - GF
	var run := RAMP_X1 - RAMP_X0
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(RAMP_X0, GF, RAMP_Z0), Vector3(RAMP_X1, FF, RAMP_Z0), Vector3(RAMP_X1, GF, RAMP_Z0),
		Vector3(RAMP_X0, GF, RAMP_Z1), Vector3(RAMP_X1, FF, RAMP_Z1), Vector3(RAMP_X1, GF, RAMP_Z1),
	])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.set_meta("surface", "carpet")
	_body.add_child(cs)
	var steps := 25
	for k in steps:
		var x0 := RAMP_X0 + run * k / steps
		var x1 := RAMP_X0 + run * (k + 1) / steps
		var y1 := GF + rise * (k + 1) / steps
		_mb.add_box(Vector3(x1 - x0, y1 - GF, RAMP_Z1 - RAMP_Z0), Vector3((x0 + x1) * 0.5, (GF + y1) * 0.5, (RAMP_Z0 + RAMP_Z1) * 0.5), _mats["mahogany"])
		_mb.add_box(Vector3(x1 - x0, 0.015, 1.2), Vector3((x0 + x1) * 0.5, y1 + 0.0075, (RAMP_Z0 + RAMP_Z1) * 0.5), _mats["carpet"])
	# Banister along the open side.
	var ang := atan2(rise, run)
	var len := sqrt(rise * rise + run * run)
	_mb.add_box(Vector3(len, 0.08, 0.08), Vector3((RAMP_X0 + RAMP_X1) * 0.5, (GF + FF) * 0.5 + 0.95, RAMP_Z1 + 0.02), _mats["mahogany"], Basis(Vector3.BACK, ang))
	for k in 9:
		var x := RAMP_X0 + 0.4 + k * (run - 0.8) / 8.0
		var y := GF + rise * (x - RAMP_X0) / run
		_mb.add_box(Vector3(0.04, 0.95, 0.04), Vector3(x, y + 0.47, RAMP_Z1 + 0.02), _mats["mahogany"])


func _build_interior_walls() -> void:
	var gf_top := FF - 0.25
	var ff_top := ROOF - 0.3
	var ix0 := HX0 + 0.25
	var ix1 := HX1 - 0.25
	var door := func(c: float) -> Array: return [c - 0.6, c + 0.6, GF, GF + 2.6]
	var fdoor := func(c: float) -> Array: return [c - 0.6, c + 0.6, FF, FF + 2.6]
	# Ground floor.
	_wall("x", -76.0, ix0, ix1, GF, gf_top, 0.2, "plaster", [door.call(66.0)])
	_wall("x", -66.0, ix0, ix1, GF, gf_top, 0.2, "red_wall", [door.call(66.0), door.call(76.0)])
	_wall("z", 70.0, -75.9, -66.1, GF, gf_top, 0.3, "plaster", [[-74.0, -68.0, GF, GF + 3.4]])
	_wall("z", 71.0, HZ0 + 0.25, -76.1, GF, gf_top, 0.2, "green_wall", [[-81.6, -80.4, GF, GF + 2.6]])
	# First floor.
	_wall("x", -76.0, ix0, RAMP_X0, FF, ff_top, 0.2, "plaster", [fdoor.call(66.0)])
	_wall("x", -76.0, RAMP_X0, ix1, FF - 0.25, ff_top, 0.2, "plaster")
	_wall("x", -66.0, ix0, ix1, FF, ff_top, 0.2, "plaster", [fdoor.call(66.0), fdoor.call(76.0)])
	_wall("z", 71.0, HZ0 + 0.25, -76.1, FF, ff_top, 0.2, "blue_wall", [[-81.6, -80.4, FF, FF + 2.6]])
	_wall("z", 71.0, -65.9, HZ1 + 0.25, FF, ff_top, 0.2, "red_wall")
	# Skirting boards along the gallery (visual).
	_mb.add_box(Vector3(ix1 - ix0, 0.18, 0.03), Vector3((ix0 + ix1) * 0.5, FF + 0.09, -66.12), _mats["paint"])


# ---------------------------------------------------------------------------
# Servants' wing: kitchen and servants' hall, flat roof reachable from the yard
# ---------------------------------------------------------------------------
func _build_wing() -> void:
	var t := 0.4
	var top := WING_ROOF
	_solid(Vector3(WING_X1 - WING_X0 - 0.4, GF - 0.1, HZ0 - WING_Z0 - 0.4), Vector3((WING_X0 + WING_X1) * 0.5, (GF - 0.1) * 0.5, (WING_Z0 + HZ0) * 0.5), "stone")
	_slab(WING_X0 + 0.2, WING_X1 - 0.2, WING_Z0 + 0.2, HZ0 - 0.25, GF, 0.1, "flags", "stone")
	_wall("z", WING_X0, WING_Z0, HZ0 - 0.25, 0.0, top, t, "brick_y", [[-97.1, -95.9, GF, GF + 2.4], [-90.55, -89.45, 1.6, 3.6]])
	_wall("z", WING_X1, WING_Z0, HZ0 - 0.25, 0.0, top, t, "brick_y", [[-93.55, -92.45, 1.6, 3.6]])
	_wall("x", WING_Z0, WING_X0 - 0.2, WING_X1 + 0.2, 0.0, top, t, "brick_y", [[67.45, 68.55, 1.6, 3.6], [73.45, 74.55, 1.6, 3.6]])
	_wall("x", -93.0, WING_X0 + 0.2, WING_X1 - 0.2, GF, WING_ROOF - 0.2, 0.2, "plaster", [[70.4, 71.6, GF, GF + 2.5]])
	_slab(WING_X0 - 0.25, WING_X1 + 0.25, WING_Z0 - 0.25, HZ0 - 0.25, WING_ROOF, 0.2, "lead", "metal")
	_mb.add_box(Vector3(WING_X1 - WING_X0, 0.02, HZ0 - WING_Z0), Vector3((WING_X0 + WING_X1) * 0.5, WING_ROOF - 0.21, (WING_Z0 + HZ0) * 0.5), _mats["ceiling"])
	# Steps up to the servants' entrance.
	for i in 5:
		var top_y := 0.18 * (i + 1)
		_solid(Vector3(WING_X0 - 0.2 - (62.2 + i * 0.36), top_y, 1.6), Vector3((62.2 + i * 0.36 + WING_X0 - 0.2) * 0.5, top_y * 0.5, -96.5), "stone", "stone")
	# Kitchen range and table.
	_solid(Vector3(2.4, 1.0, 0.8), Vector3(71.0, GF + 0.5, WING_Z0 + 0.65), "iron")
	_solid(Vector3(2.8, 0.8, 1.1), Vector3(71.0, GF + 0.4, -96.0), "wood")
	_solid(Vector3(3.5, 0.75, 1.0), Vector3(69.0, GF + 0.375, -89.0), "wood") # servants' hall table
	# Drainpipe in the yard up to the wing roof.
	_pipe(Vector3(WING_X0 - 0.3, 0.0, -92.0), WING_ROOF + 0.05)


## A climbable cast-iron drainpipe.
func _pipe(base: Vector3, height: float) -> void:
	var pipe := StaticBody3D.new()
	pipe.name = "Drainpipe"
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
	_mb.add_cylinder(0.045, 0.045, height, base + Vector3.UP * height * 0.5, _mats["iron"], 8)
	_mb.add_box(Vector3(0.2, 0.22, 0.2), base + Vector3.UP * (height - 0.25), _mats["iron"])


# ---------------------------------------------------------------------------
# The old sewer: mews manhole -> brick tunnel under the wall -> drain in the south lawn
# ---------------------------------------------------------------------------
func _build_sewer() -> void:
	var z0 := SHAFT_A.z - 0.8
	var z1 := SHAFT_A.z + 0.8
	var x0 := SHAFT_A.x - 0.5
	var x1 := SHAFT_B.x + 0.5
	var ceil_top := -1.0
	var ceil_bot := -1.6
	_slab(x0, x1, z0, z1, SEWER_Y, 0.4, "sewer", "stone")
	_mb.add_box(Vector3(x1 - x0, 0.02, 0.5), Vector3((x0 + x1) * 0.5, SEWER_Y + 0.01, SHAFT_A.z), _mats["water"])
	var holes := [Rect2(SHAFT_A.x - 0.5, SHAFT_A.z - 0.5, 1.0, 1.0), Rect2(SHAFT_B.x - 0.5, SHAFT_B.z - 0.5, 1.0, 1.0)]
	_slab(x0, x1, z0, z1, ceil_top, ceil_top - ceil_bot, "sewer", "stone", holes)
	_wall("x", z0 - 0.2, x0 - 0.4, x1 + 0.4, SEWER_Y - 0.4, ceil_top, 0.4, "sewer")
	_wall("x", z1 + 0.2, x0 - 0.4, x1 + 0.4, SEWER_Y - 0.4, ceil_top, 0.4, "sewer")
	_wall("z", x0 - 0.2, z0, z1, SEWER_Y - 0.4, ceil_top, 0.4, "sewer")
	_wall("z", x1 + 0.2, z0, z1, SEWER_Y - 0.4, ceil_top, 0.4, "sewer")
	# Iron ladders (climbed like drainpipes) up both shafts.
	_ladder(Vector3(SHAFT_A.x - 0.38, SEWER_Y, SHAFT_A.z))
	_ladder(Vector3(SHAFT_B.x + 0.38, SEWER_Y, SHAFT_B.z))
	var cover := DrainCover.new()
	cover.name = "MewsManhole"
	cover.cover_name = "sewer manhole cover"
	cover.radius = 0.5
	cover.position = SHAFT_A
	add_child(cover)
	var grate := DrainCover.new()
	grate.name = "LawnDrain"
	grate.cover_name = "drain grating"
	grate.radius = 0.5
	grate.is_open = true # rusted through years ago: it just lifts aside
	grate.position = SHAFT_B
	add_child(grate)


func _ladder(base: Vector3) -> void:
	var h := -base.y
	var pipe := StaticBody3D.new()
	pipe.name = "ShaftLadder"
	pipe.collision_layer = 1 << 4
	pipe.collision_mask = 0
	pipe.add_to_group("climbable_pipe")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.06
	cyl.height = h
	cs.shape = cyl
	cs.position = base + Vector3.UP * h * 0.5
	pipe.add_child(cs)
	add_child(pipe)
	for side: float in [-0.2, 0.2]:
		_mb.add_box(Vector3(0.04, h, 0.04), base + Vector3(0, h * 0.5, side), _mats["iron"])
	for k in int(h / 0.3):
		_mb.add_cylinder(0.015, 0.015, 0.4, base + Vector3(0, 0.25 + k * 0.3, 0), _mats["iron"], 6, Basis(Vector3.RIGHT, PI * 0.5))


# ---------------------------------------------------------------------------
# Garden: shrubberies (hiding places), fountain, kennels
# ---------------------------------------------------------------------------
func _build_garden() -> void:
	var clumps: Array[Vector3] = [
		Vector3(84.0, 0, -84.0), Vector3(84.0, 0, -58.0), Vector3(98.0, 0, -80.0),
		Vector3(103.0, 0, -62.0), Vector3(70.0, 0, -52.0), Vector3(58.0, 0, -52.0),
		Vector3(49.0, 0, -88.0), Vector3(90.0, 0, -35.0), Vector3(66.0, 0, -104.0),
	]
	for i in clumps.size():
		_shrubbery(clumps[i], i)
	# Old plane and lime trees, and a cedar on the south lawn.
	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	var tree_specs: Array = [
		[Vector3(88.0, 0, -100.0), 16.0, Color(0.3, 0.44, 0.17)], [Vector3(102.0, 0, -90.0), 15.0, Color(0.34, 0.46, 0.2)],
		[Vector3(102.0, 0, -52.0), 17.0, Color(0.3, 0.44, 0.17)], [Vector3(80.0, 0, -36.0), 14.0, Color(0.36, 0.48, 0.2)],
		[Vector3(55.0, 0, -36.0), 15.0, Color(0.3, 0.44, 0.17)], [Vector3(64.0, 0, -46.0), 12.0, Color(0.2, 0.3, 0.16)],
		[Vector3(92.0, 0, -80.0), 13.0, Color(0.34, 0.46, 0.2)],
	]
	for i in tree_specs.size():
		var t := StreetProps.make_tree(300 + i, tree_specs[i][1], tree_specs[i][2])
		t.position = tree_specs[i][0]
		trees.add_child(t)
	# Box hedges edging the garden path (low: you can crouch behind them).
	for x: float in [83.0, 86.0, 89.0]:
		_solid(Vector3(2.2, 0.9, 0.6), Vector3(x, 0.45, -73.0), "hedge", "grass")
		_solid(Vector3(2.2, 0.9, 0.6), Vector3(x, 0.45, -69.0), "hedge", "grass")
	# Fountain.
	_mb.add_cylinder(2.2, 2.3, 0.6, Vector3(96.0, 0.3, -71.0), _mats["stone"], 24)
	_collider(Vector3(3.6, 0.6, 3.6), Vector3(96.0, 0.3, -71.0))
	_mb.add_cylinder(1.9, 1.9, 0.02, Vector3(96.0, 0.5, -71.0), _mats["water"], 24)
	_mb.add_cylinder(0.25, 0.4, 1.8, Vector3(96.0, 0.9, -71.0), _mats["stone"], 12)
	# Kennels.
	for k: Vector3 in [KENNEL_YARD, KENNEL_GARDEN]:
		var p := k + Vector3(0, 0, -1.6)
		_solid(Vector3(1.4, 1.0, 1.2), p + Vector3(0, 0.5, 0), "wood")
		_mb.add_box(Vector3(1.6, 0.08, 1.4), p + Vector3(0, 1.1, 0), _mats["lead"])


func _shrubbery(pos: Vector3, seed_value: int) -> void:
	# Leafy shrubs (no collision: Harry can crouch right in among them) over a hiding spot.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 11
	var leaves := MaterialLibrary.get_tinted("grass", Color(0.3, 0.42, 0.2))
	for i in 7:
		var s := SphereMesh.new()
		var r := rng.randf_range(0.6, 0.95)
		s.radius = r
		s.height = r * 1.7
		s.radial_segments = 10
		s.rings = 6
		var off := Vector3(rng.randf_range(-1.0, 1.0), r * 0.8, rng.randf_range(-1.0, 1.0))
		_mb.add_mesh(s, Transform3D(Basis.IDENTITY, pos + off), leaves)
	var spot := HidingSpot.new()
	spot.name = "Shrubbery%d" % seed_value
	spot.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.4, 2.2)
	cs.shape = box
	cs.position = Vector3(0, 0.7, 0)
	spot.add_child(cs)
	add_child(spot)


# ---------------------------------------------------------------------------
# Doors and windows
# ---------------------------------------------------------------------------
func _build_openings() -> void:
	var doors := Node3D.new()
	doors.name = "Doors"
	add_child(doors)
	var d := func(n: String, label: String, pos: Vector3, outward: Vector3, levers: int, key: String, w: float = 1.1, h: float = 2.5) -> MansionDoor:
		var door := MansionDoor.new()
		door.name = n
		door.door_name = label
		door.width = w
		door.height = h
		door.lock_levers = levers
		door.key_id = key
		door.transform = _xf(pos, outward)
		doors.add_child(door)
		return door
	var front: MansionDoor = d.call("FrontDoor", "front door", Vector3(HX0, GF, -71.0), Vector3.LEFT, 5, "front_door", 1.25, 2.75)
	front.lock_gate = 0.16
	front.leaf_color = Color(0.08, 0.08, 0.08)
	d.call("GardenDoor", "garden door", Vector3(HX1, GF, -69.0), Vector3.RIGHT, 3, "garden_door", 1.15, 2.55)
	d.call("ServantsEntrance", "servants' entrance", Vector3(WING_X0, GF, -96.5), Vector3.LEFT, 3, "servants_door", 1.1, 2.35)
	var baize: MansionDoor = d.call("WingDoor", "baize door", Vector3(75.0, GF, HZ0), Vector3.FORWARD, 0, "", 1.1, 2.35)
	baize.leaf_color = Color(0.15, 0.3, 0.15)
	baize.should_stay_closed = false
	d.call("KitchenDoor", "kitchen door", Vector3(71.0, GF, -93.0), Vector3.FORWARD, 0, "").should_stay_closed = false
	d.call("LodgeDoor", "lodge door", Vector3(50.45, 0.15, -63.0), Vector3.FORWARD, 0, "", 1.0, 2.2).should_stay_closed = false
	for spec: Array in [
		["LibraryDoor", "library door", Vector3(66.0, GF, -76.0), 0, ""],
		["DiningDoorHall", "dining room door", Vector3(66.0, GF, -66.0), 0, ""],
		["DiningDoorStairs", "dining room door", Vector3(76.0, GF, -66.0), 0, ""],
		["StudyDoor", "study door", Vector3(66.0, FF, -66.0), 3, "study"],
		["BedroomDoor", "bedroom door", Vector3(76.0, FF, -66.0), 0, ""],
		["EvelynDoor", "bedroom door", Vector3(66.0, FF, -76.0), 0, ""],
	]:
		# "Outside" is the hall or gallery side; the room side counts as inside.
		var interior: MansionDoor = d.call(spec[0], spec[1], spec[2], Vector3.BACK if (spec[2] as Vector3).z < -70.0 else Vector3.FORWARD, spec[3], spec[4])
		interior.opens_freely_from_inside = true
		interior.should_stay_closed = spec[3] > 0
	var pantry: MansionDoor = d.call("PantryDoor", "pantry door", Vector3(71.0, GF, -81.0), Vector3.LEFT, 3, "pantry")
	pantry.should_stay_closed = true
	var linen: MansionDoor = d.call("LinenDoor", "linen room door", Vector3(71.0, FF, -81.0), Vector3.RIGHT, 0, "")
	linen.should_stay_closed = false

	var windows := Node3D.new()
	windows.name = "Windows"
	add_child(windows)
	var w := func(n: String, sill: Vector3, outward: Vector3, latched: bool = true, h: float = 2.2) -> MansionWindow:
		var win := MansionWindow.new()
		win.name = n
		win.latched = latched
		win.height = h
		win.transform = _xf(sill, outward)
		windows.add_child(win)
		return win
	var i := 0
	for z: float in [-82.0, -78.0, -64.0, -60.0]:
		w.call("FrontGF%d" % i, Vector3(HX0, 1.6, z), Vector3.LEFT)
		w.call("RearGF%d" % i, Vector3(HX1, 1.6, z), Vector3.RIGHT)
		i += 1
	i = 0
	for z: float in [-82.0, -78.0, -74.0, -68.0, -64.0, -60.0]:
		w.call("FrontFF%d" % i, Vector3(HX0, 6.1, z), Vector3.LEFT)
		i += 1
	i = 0
	for z: float in [-82.0, -78.0, -74.0, -64.0, -60.0]:
		w.call("RearFF%d" % i, Vector3(HX1, 6.1, z), Vector3.RIGHT)
		i += 1
	# Over the wing roof. The linen-room sash has a broken catch.
	w.call("EvelynWindow", Vector3(67.0, 6.1, HZ0), Vector3.FORWARD)
	w.call("LinenWindow", Vector3(77.0, 6.1, HZ0), Vector3.FORWARD, false)
	i = 0
	for x: float in [65.0, 69.0, 73.0, 77.0]:
		w.call("SouthGF%d" % i, Vector3(x, 1.6, HZ1), Vector3.BACK)
		i += 1
	i = 0
	for x: float in [65.0, 69.0, 73.0, 77.0]:
		w.call("SouthFF%d" % i, Vector3(x, 6.1, HZ1), Vector3.BACK)
		i += 1
	w.call("WingWest", Vector3(WING_X0, 1.6, -90.0), Vector3.LEFT, true, 2.0)
	w.call("WingEast", Vector3(WING_X1, 1.6, -93.0), Vector3.RIGHT, true, 2.0)
	w.call("WingNorth0", Vector3(68.0, 1.6, WING_Z0), Vector3.FORWARD, true, 2.0)
	w.call("WingNorth1", Vector3(74.0, 1.6, WING_Z0), Vector3.FORWARD, true, 2.0)
	w.call("LodgeWindow", Vector3(47.0, 1.0, -60.0), Vector3.LEFT, true, 1.4)
	# Floor-length curtains either side of some windows: stand behind them, crouched, to hide.
	for spec: Array in [
		[Vector3(HX0, GF, -82.0), Vector3.RIGHT], [Vector3(HX0, GF, -60.0), Vector3.RIGHT],
		[Vector3(HX1, GF, -64.0), Vector3.LEFT], [Vector3(65.0, FF, HZ1), Vector3.FORWARD],
		[Vector3(HX1, FF, -60.0), Vector3.LEFT], [Vector3(HX0, FF, -68.0), Vector3.RIGHT],
		[Vector3(HX1, FF, -78.0), Vector3.LEFT],
	]:
		_curtains(spec[0], spec[1])


func _curtains(base: Vector3, inward: Vector3) -> void:
	var node := Node3D.new()
	node.name = "Curtains"
	node.transform = _xf(base + inward * 0.4, inward)
	add_child(node)
	var mb := MeshBuilder.new()
	var cloth := MaterialLibrary.get_material("fabric")
	var h := 3.5
	for side: float in [-0.75, 0.75]:
		for k in 3:
			mb.add_box(Vector3(0.14, h, 0.1), Vector3(side + (k - 1) * 0.12, h * 0.5, -0.05 + k * 0.03), cloth)
	mb.add_box(Vector3(2.0, 0.08, 0.08), Vector3(0, h + 0.05, 0), _mats["gilt"])
	mb.build_into(node, "Drapes")
	var spot := HidingSpot.new()
	spot.name = "BehindCurtain"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 1.6, 0.9)
	cs.shape = box
	cs.position = Vector3(0, 0.8, -0.1)
	spot.add_child(cs)
	node.add_child(spot)


# ---------------------------------------------------------------------------
# Furniture
# ---------------------------------------------------------------------------
func _build_furniture() -> void:
	var fm := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.name = "Furniture"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	add_child(body)
	var solid := func(size: Vector3, center: Vector3, mat: Material) -> void:
		fm.add_box(size, center, mat)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = center
		body.add_child(cs)
	var mahog: Material = _mats["mahogany"]
	var cloth := MaterialLibrary.get_material("fabric")
	var linen := MaterialLibrary.get_tinted("plaster", Color(0.95, 0.94, 0.9))
	# Dining room: long table, sideboard against the east wall.
	solid.call(Vector3(8.0, 0.76, 1.4), Vector3(70.0, GF + 0.38, -61.0), mahog)
	for k in 6:
		for side: float in [-1.0, 1.0]:
			fm.add_box(Vector3(0.45, 1.0, 0.45), Vector3(67.0 + k * 1.2, GF + 0.5, -61.0 + side * 1.0), mahog)
	solid.call(Vector3(0.6, 0.95, 2.0), Vector3(79.35, GF + 0.475, -62.0), mahog)
	# Library: bookcases along the walls, a desk.
	var books := MaterialLibrary.get_tinted("fabric", Color(0.6, 0.35, 0.25))
	for spec: Array in [[Vector3(66.5, 0, -85.55), Vector3(7.0, 3.2, 0.4)], [Vector3(70.7, 0, -78.5), Vector3(0.4, 3.2, 3.0)], [Vector3(70.7, 0, -83.8), Vector3(0.4, 3.2, 3.0)]]:
		var c: Vector3 = spec[0]
		var s: Vector3 = spec[1]
		solid.call(s, Vector3(c.x, GF + s.y * 0.5, c.z), mahog)
		for shelf in 5:
			fm.add_box(Vector3(maxf(s.x - 0.05, 0.36), 0.28, maxf(s.z - 0.05, 0.36)), Vector3(c.x, GF + 0.3 + shelf * 0.6, c.z), books)
	solid.call(Vector3(1.6, 0.78, 0.9), Vector3(66.5, GF + 0.39, -80.0), mahog)
	# Butler's pantry: plate cupboard and table.
	solid.call(Vector3(2.4, 2.2, 0.55), Vector3(78.3, GF + 1.1, -85.45), mahog)
	solid.call(Vector3(1.8, 0.85, 0.8), Vector3(78.5, GF + 0.425, -80.0), _mats["wood"])
	# Entrance hall: console table; gallery: settee.
	solid.call(Vector3(0.5, 0.85, 1.6), Vector3(69.5, GF + 0.425, -74.8), mahog)
	fm.add_box(Vector3(0.7, 0.9, 1.8), Vector3(62.7, FF + 0.45, -71.0), cloth)
	# Study: desk and chair; the safe goes in the corner.
	solid.call(Vector3(1.8, 0.78, 1.0), Vector3(67.0, FF + 0.39, -59.5), mahog)
	fm.add_box(Vector3(0.6, 1.1, 0.6), Vector3(67.0, FF + 0.55, -58.4), cloth)
	# Master bedroom: four-poster, dressing table, wardrobe.
	solid.call(Vector3(2.0, 0.7, 2.3), Vector3(76.5, FF + 0.35, -57.6), mahog)
	fm.add_box(Vector3(1.9, 0.25, 2.2), Vector3(76.5, FF + 0.82, -57.6), linen)
	for px: float in [75.55, 77.45]:
		for pz: float in [-56.5, -58.7]:
			fm.add_box(Vector3(0.1, 2.4, 0.1), Vector3(px, FF + 1.2, pz), mahog)
	fm.add_box(Vector3(2.1, 0.15, 2.4), Vector3(76.5, FF + 2.45, -57.6), cloth)
	solid.call(Vector3(1.4, 0.8, 0.55), Vector3(72.0, FF + 0.4, -65.4), mahog) # dressing table
	solid.call(Vector3(0.6, 2.2, 1.6), Vector3(79.4, FF + 1.1, -62.0), mahog) # wardrobe
	# Lady Evelyn's room: bed, writing table.
	solid.call(Vector3(1.6, 0.7, 2.1), Vector3(64.0, FF + 0.35, -83.8), mahog)
	fm.add_box(Vector3(1.5, 0.25, 2.0), Vector3(64.0, FF + 0.82, -83.8), linen)
	solid.call(Vector3(1.1, 0.75, 0.6), Vector3(69.8, FF + 0.375, -85.3), mahog)
	# Linen room: presses.
	solid.call(Vector3(4.0, 2.2, 0.7), Vector3(75.5, FF + 1.1, -76.45), _mats["wood"])
	# Lodge: key board on the wall.
	fm.add_box(Vector3(0.05, 0.6, 0.9), Vector3(52.8, 1.5, -60.0), _mats["wood"])
	var mi := fm.build_into(self, "FurnitureMesh")
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	# Paintings on the gallery walls (the two best are loot; the rest are too big to carry).
	var pm := MeshBuilder.new()
	for spec: Array in [[Vector3(64.0, FF + 2.2, -75.85), Vector2(1.6, 1.2)], [Vector3(68.5, FF + 2.0, -75.85), Vector2(1.0, 1.3)], [Vector3(66.0, FF + 2.4, -66.15), Vector2(2.4, 1.6)]]:
		if (spec[0] as Vector3).z > -70.0:
			var p: Vector3 = spec[0]
			var s: Vector2 = spec[1]
			pm.add_box(Vector3(s.x + 0.2, s.y + 0.2, 0.06), p, _mats["gilt"])
			pm.add_box(Vector3(s.x, s.y, 0.02), p + Vector3(0, 0, -0.035), MaterialLibrary.get_material("oil_paint"))
	pm.build_into(self, "Pictures")


# ---------------------------------------------------------------------------
# Loot, keys, the safe
# ---------------------------------------------------------------------------
func _build_loot() -> void:
	var loot := Node3D.new()
	loot.name = "Loot"
	add_child(loot)
	var silver := MaterialLibrary.get_tinted("iron", Color(0.85, 0.85, 0.82))
	silver.metallic = 1.0
	silver.roughness = 0.2
	var gold := MaterialLibrary.get_material("gilt")
	var paper := MaterialLibrary.get_tinted("plaster", Color(0.95, 0.92, 0.82))
	var add := func(n: String, item: String, value: int, pos: Vector3, mesh_size: Vector3, mat: Material, secs: float = 0.6, verb: String = "Take", noise: float = 0.0, kind: String = "valuable", key: String = "") -> LootSpot:
		var l := LootSpot.new()
		l.name = n
		l.item_name = item
		l.value = value
		l.kind = kind
		l.key_id = key
		l.verb = verb
		l.take_seconds = secs
		l.work_noise = noise
		l.position = pos
		if kind in ["key", "document"]:
			l.missed_when_gone = false
		var mb := MeshBuilder.new()
		mb.add_box(mesh_size, Vector3(0, mesh_size.y * 0.5, 0), mat)
		mb.build_into(l, "Mesh")
		loot.add_child(l)
		return l
	# Dining room sideboard.
	add.call("Candelabra", "Silver candelabra", 1440, Vector3(79.35, GF + 0.95, -62.6), Vector3(0.18, 0.6, 0.18), silver, 0.8)
	add.call("Epergne", "Silver-gilt epergne", 2400, Vector3(79.35, GF + 0.95, -61.4), Vector3(0.45, 0.4, 0.45), gold, 1.2)
	# Pantry: the canteen of plate rattles as you lift it.
	add.call("SilverCanteen", "Canteen of silver cutlery", 3600, Vector3(78.5, GF + 0.85, -80.0), Vector3(0.6, 0.22, 0.4), _mats["mahogany"], 2.0, "Take", 2.5)
	# Library.
	add.call("BookOfHours", "Illuminated Book of Hours", 3000, Vector3(66.2, GF + 0.78, -80.0), Vector3(0.3, 0.08, 0.22), MaterialLibrary.get_tinted("fabric", Color(0.5, 0.1, 0.1)), 0.8)
	add.call("Diary", "Lord Ashcombe's appointment diary", 0, Vector3(67.0, GF + 0.78, -79.8), Vector3(0.2, 0.05, 0.28), paper, 0.6, "Take", 0.0, "document")
	# Gallery paintings: cut from the frame (slow, and it makes a sound).
	var p1: LootSpot = add.call("PaintingStag", "Small oil by Landseer, 'Stag at Bay'", 7200, Vector3(64.0, FF + 1.55, -75.85), Vector3(1.6, 1.3, 0.04), MaterialLibrary.get_material("oil_paint"), 4.0, "Cut from its frame", 1.5)
	p1.missed_line = "The Landseer! It's been cut from the frame!"
	add.call("PaintingStillLife", "Dutch still life", 4800, Vector3(68.5, FF + 1.3, -75.85), Vector3(1.0, 1.4, 0.04), MaterialLibrary.get_material("oil_paint"), 4.0, "Cut from its frame", 1.5)
	for f: Array in [[Vector3(64.0, FF + 2.2, -75.82), Vector2(1.8, 1.4)], [Vector3(68.5, FF + 2.0, -75.82), Vector2(1.2, 1.5)]]:
		var fr := MeshBuilder.new()
		var s: Vector2 = f[1]
		var c: Vector3 = f[0]
		fr.add_box(Vector3(s.x, 0.1, 0.06), c + Vector3(0, s.y * 0.5, 0), gold)
		fr.add_box(Vector3(s.x, 0.1, 0.06), c - Vector3(0, s.y * 0.5, 0), gold)
		fr.add_box(Vector3(0.1, s.y, 0.06), c + Vector3(s.x * 0.5, 0, 0), gold)
		fr.add_box(Vector3(0.1, s.y, 0.06), c - Vector3(s.x * 0.5, 0, 0), gold)
		fr.build_into(self, "Frame")
	# Study: the safe, and a gold seal on the desk.
	add.call("FobSeal", "Gold fob seal", 720, Vector3(67.5, FF + 0.78, -59.4), Vector3(0.05, 0.08, 0.05), gold, 0.4)
	var safe := IronSafe.new()
	safe.name = "StudySafe"
	safe.safe_name = "safe"
	safe.key_id = "study_safe"
	safe.transform = _xf(Vector3(69.8, FF, -57.2), Vector3(-0.7, 0, -0.7).normalized())
	safe.contents = [
		{"name": "Bank of England notes", "value": 12000, "kind": "coins", "victim_class": "aristocrat"},
		{"name": "Rent book of the St Giles tenements", "value": 0, "kind": "document", "victim_class": "aristocrat"},
		{"name": "Letter from Captain Crowe", "value": 0, "kind": "document", "victim_class": "aristocrat"},
	]
	loot.add_child(safe)
	# Master bedroom: the safe key on the dressing table, studs and a watch.
	add.call("SafeKey", "Chubb safe key", 0, Vector3(71.6, FF + 0.8, -65.4), Vector3(0.1, 0.02, 0.04), MaterialLibrary.get_material("brass"), 0.3, "Take", 0.0, "key", "study_safe")
	add.call("ShirtStuds", "Diamond shirt studs", 1920, Vector3(72.3, FF + 0.8, -65.4), Vector3(0.08, 0.03, 0.06), gold, 0.4)
	add.call("HunterWatch", "Gold hunter watch", 2880, Vector3(75.2, FF + 0.72, -56.7), Vector3(0.06, 0.02, 0.06), gold, 0.4)
	# Lady Evelyn's jewel case.
	add.call("Pearls", "Pearl necklace", 4800, Vector3(69.6, FF + 0.75, -85.3), Vector3(0.2, 0.05, 0.12), MaterialLibrary.get_tinted("plaster", Color(0.96, 0.94, 0.9)), 0.6)
	add.call("Brooch", "Garnet brooch", 960, Vector3(70.1, FF + 0.75, -85.3), Vector3(0.05, 0.02, 0.05), gold, 0.4)
	# Gate lodge key board: spare keys, the gatekeeper's.
	add.call("KeyServants", "Servants' entrance key", 0, Vector3(52.7, 1.45, -60.25), Vector3(0.03, 0.12, 0.05), MaterialLibrary.get_material("iron"), 0.3, "Take", 0.0, "key", "servants_door")
	add.call("KeyTrade", "Tradesmen's door key", 0, Vector3(52.7, 1.45, -59.75), Vector3(0.03, 0.12, 0.05), MaterialLibrary.get_material("iron"), 0.3, "Take", 0.0, "key", "trade_door")
	add.call("KeyPantry", "Pantry key", 0, Vector3(52.7, 1.7, -60.0), Vector3(0.03, 0.1, 0.05), MaterialLibrary.get_material("brass"), 0.3, "Take", 0.0, "key", "pantry")


# ---------------------------------------------------------------------------
# Gasoliers and lamps (switched by AshcombeStaff by the hour)
# ---------------------------------------------------------------------------
func _build_lights() -> void:
	var lights := Node3D.new()
	lights.name = "Lights"
	add_child(lights)
	for spec: Array in [
		["HallGasolier", Vector3(66.0, GF + 3.3, -71.0), 9.0, "evening"],
		["StairGasolier", Vector3(75.0, FF + 2.8, -71.0), 9.0, "evening"],
		["GalleryGasolier", Vector3(66.0, FF + 3.2, -71.0), 7.0, "evening"],
		["DiningGasolier", Vector3(71.0, GF + 3.4, -61.0), 8.0, "evening"],
		["LandingNightLamp", Vector3(77.0, FF + 1.6, -72.0), 3.5, "night"],
		["KitchenFire", Vector3(71.0, GF + 0.8, WING_Z0 + 1.3), 5.0, "always"],
		["LodgeLamp", Vector3(48.0, 1.9, -61.9), 4.5, "always"],
	]:
		var l := OmniLight3D.new()
		l.name = spec[0]
		l.position = spec[1]
		l.omni_range = spec[2]
		l.light_color = Color(1.0, 0.72, 0.42) if spec[0] != "KitchenFire" else Color(1.0, 0.5, 0.2)
		l.light_energy = 1.7 if spec[3] != "night" else 0.6
		l.shadow_enabled = spec[3] == "evening"
		l.add_to_group("stealth_lights")
		l.set_meta("schedule", spec[3])
		lights.add_child(l)
		var bulb := MeshBuilder.new()
		bulb.add_cylinder(0.08, 0.12, 0.2, Vector3.ZERO, MaterialLibrary.get_material("lamp_glass"), 8)
		bulb.build_into(l, "Glow").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------
# Private grounds, indoor light, creaky floorboards
# ---------------------------------------------------------------------------
func _build_zones() -> void:
	var zone := RestrictedZone.new()
	zone.name = "AshcombeGrounds"
	zone.zone_name = "Ashcombe House"
	zone.set_box(Vector3(EST_X1 - EST_X0 - 0.4, 22.0, EST_Z1 - EST_Z0 - 0.4), Vector3((EST_X0 + EST_X1) * 0.5, 10.5, (EST_Z0 + EST_Z1) * 0.5))
	add_child(zone)
	for spec: Array in [
		[Vector3(HX0, 0.0, HZ0), Vector3(HX1 - HX0, ROOF, HZ1 - HZ0), 0.3],
		[Vector3(WING_X0, 0.0, WING_Z0), Vector3(WING_X1 - WING_X0, WING_ROOF, HZ0 - WING_Z0), 0.3],
		[Vector3(47.0, 0.0, -63.0), Vector3(6.0, 3.2, 6.0), 0.35],
		[Vector3(SHAFT_A.x - 0.5, SEWER_Y - 0.5, SHAFT_A.z - 0.8), Vector3(SHAFT_B.x - SHAFT_A.x + 1.0, 2.9, 1.6), 0.0],
	]:
		var v := InteriorVolume.new()
		v.position = spec[0]
		v.size = spec[1]
		v.daylight_factor = spec[2]
		add_child(v)
	for p: Vector3 in [
		Vector3(66.0, FF, -66.9), Vector3(76.0, FF, -66.9), Vector3(78.5, FF, -73.2),
		Vector3(66.0, FF, -75.1), Vector3(71.7, GF, -81.0), Vector3(66.0, GF, -76.9),
		Vector3(70.0, FF, -60.5),
	]:
		var b := CreakyBoard.new()
		b.size = Vector3(1.2, 0.35, 0.9)
		b.position = p
		add_child(b)
