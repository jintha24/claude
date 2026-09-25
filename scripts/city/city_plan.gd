class_name CityPlan
extends RefCounted
## Greater London, 1866: the layout of the whole city around Harry's neighbourhood.
##
## The city is a 3.4 km x 3.4 km square (11.6 square km) centred near the old streets. The
## hand-built neighbourhood (the street, the market, St Giles and Ashcombe House) sits in
## the middle of it inside CORE, ringed by a road; everything else is laid out here, as
## plain data (rectangles and numbers), and built around the player by CityStreamer.
##
##   * Main roads run north-south and east-west roughly every 200-250 m; between them the
##     side streets cut each superblock into blocks of houses and shops.
##   * The Thames crosses the city from west to east (z 575 .. 805), walled in by the new
##     Embankment, with four bridges. South of it lies Southwark and Lambeth.
##   * Districts: the West End (grand stucco terraces, garden squares and the park), the
##     City (St Paul's, banks, shops, Wren churches), the East End (poor brick terraces,
##     workshops and riverside warehouses), the northern suburbs and the south bank.
##   * St Paul's Cathedral and the Palace of Westminster each fill a superblock.
##
## Everything is a pure function of the seed, so any thread can read the plan once it is
## made (it is never changed afterwards).

const HALF := 1700.0
const CHUNK := 128.0
## The hand-built neighbourhood (x, z, width, depth). Nothing is generated inside it except
## the filler blocks in CORE_FILL, which close the gaps between its parts.
const CORE := Rect2(-81.0, -112.5, 188.0, 172.5)
const RIVER_Z0 := 575.0
const RIVER_Z1 := 805.0
## The riverside walk between the Embankment road and the river wall.
const WALK := 5.0
const WATER_Y := -3.0
const BED_Y := -4.2
const ART_ROAD := 10.0
const ART_PAVE := 3.2
const MIN_ROAD := 7.0
const MIN_PAVE := 2.4
const PAVE_TOP := 0.15
const EDGE_LINE := 1600.0
const ST_PAULS := Vector3(-430.0, 0.0, 250.0)
const WESTMINSTER := Vector3(-900.0, 0.0, 520.0)
## The park in the west (like Hyde Park), in whole superblocks.
const PARK_AREA := Rect2(-1700.0, -960.0, 560.0, 1100.0)

enum Kind { TERRACE, SQUARE, CHURCH, WAREHOUSE, PARK, LANDMARK, FILL, INFILL, SLAB, WALK }
enum Side { N, S, E, W }

## Blocks that close the gaps inside CORE: [rect, facade sides, pavement per side (N, S, E, W), kind].
const CORE_FILL: Array = [
	[Rect2(-81.0, -112.5, 45.8, 68.3), [Side.N, Side.W], [0.0, 0.0, 0.0, 0.0], Kind.FILL],
	[Rect2(-35.2, -112.5, 60.2, 12.4), [Side.N], [0.0, 0.0, 0.0, 0.0], Kind.FILL],
	[Rect2(-81.0, 44.3, 64.6, 15.7), [Side.S, Side.W], [0.0, 0.0, 0.0, 0.0], Kind.FILL],
	[Rect2(-16.4, 46.1, 9.8, 13.9), [Side.S], [0.0, 0.0, 0.0, 0.0], Kind.FILL],
	[Rect2(-6.6, 58.2, 13.2, 1.8), [], [0.0, 0.0, 0.0, 0.0], Kind.SLAB],
	[Rect2(6.6, 46.1, 9.8, 13.9), [Side.S], [0.0, 0.0, 0.0, 0.0], Kind.FILL],
	[Rect2(16.5, -46.0, 18.0, 16.5), [], [0.0, 0.0, 0.0, 0.0], Kind.INFILL],
	[Rect2(25.2, -52.0, 9.3, 6.0), [], [0.0, 0.0, 0.0, 0.0], Kind.INFILL],
	[Rect2(16.5, -29.5, 18.5, 33.3), [Side.E], [0.0, 0.0, 2.0, 0.0], Kind.FILL],
	[Rect2(20.8, 3.8, 14.2, 2.8), [Side.E], [0.0, 0.0, 2.0, 0.0], Kind.FILL],
	[Rect2(16.5, 6.6, 18.5, 53.4), [Side.E, Side.S], [0.0, 0.0, 2.0, 0.0], Kind.FILL],
	[Rect2(46.0, -29.5, 61.0, 89.5), [Side.W, Side.S, Side.E], [0.0, 0.0, 0.0, 2.0], Kind.FILL],
]
## The lane that carries the Ashcombe mews on south to the ring road.
const MEWS_STREET := Rect2(35.0, -29.5, 11.0, 89.5)

const SURNAMES: Array[String] = [
	"SMITH", "JONES", "TAYLOR", "BROWN", "WILLIAMS", "WILSON", "JOHNSON", "DAVIES", "ROBINSON",
	"WRIGHT", "THOMPSON", "EVANS", "WALKER", "WHITE", "ROBERTS", "GREEN", "HALL", "WOOD",
	"JACKSON", "CLARKE", "HARRIS", "LEWIS", "COOPER", "KING", "BAKER", "HARRISON", "MORGAN",
	"ALLEN", "JAMES", "SCOTT", "PRICE", "PARKER", "BENNETT", "FOSTER", "MARSH", "HOLLOWAY",
	"FLETCHER", "GODWIN", "PEARCE", "BARLOW", "WEBB", "CRANE", "ASHDOWN", "PENROSE",
]
const TRADES: Array[String] = [
	"GROCER", "BAKER", "BUTCHER", "DRAPER", "TAILOR", "BOOTMAKER", "HATTER", "CHEMIST",
	"IRONMONGER", "STATIONER", "TOBACCONIST", "FISHMONGER", "CHANDLER", "SADDLER",
	"WATCHMAKER", "PAWNBROKER", "COFFEE ROOMS", "DINING ROOMS", "OILMAN", "CHEESEMONGER",
	"BOOKSELLER", "HABERDASHER", "UNDERTAKER", "GLAZIER", "PRINTER", "COOPER",
]
const PUBS: Array[String] = [
	"THE RED LION", "THE KING'S HEAD", "THE GEORGE", "THE ROSE & CROWN", "THE PLOUGH",
	"THE BLACK HORSE", "THE WHEATSHEAF", "THE CROSS KEYS", "THE SWAN", "THE BELL",
	"THE COACH & HORSES", "THE ROYAL OAK", "THE GRAPES", "THE PROSPECT OF WHITBY",
	"THE LAMB & FLAG", "THE SPREAD EAGLE", "THE BLUE ANCHOR", "THE THREE TUNS",
]

## x of each north-south road's centre line, and z of each east-west one.
var xs := PackedFloat32Array()
var zs := PackedFloat32Array()
## x of the roads that cross the river on bridges.
var bridges := PackedFloat32Array()
## Every block: {id, rect, kind, district, seed, pave: [N, S, E, W], facades: [Side...]}.
var blocks: Array[Dictionary] = []
## Road surfaces (cobbles at y = 0) that are not simply "everywhere outside the core".
var extra_roads: Array[Rect2] = [MEWS_STREET]

var _seed := 1866
var _overlap := {} # Vector2i -> PackedInt32Array: blocks whose rect overlaps the chunk
var _owned := {} # Vector2i -> PackedInt32Array: blocks whose centre lies in the chunk


func _init(city_seed: int = 1866) -> void:
	_seed = city_seed
	_make_lines()
	_make_blocks()
	_index_blocks()


static func hash01(a: int, b: int, c: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0x1000000)


func coord_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


func chunk_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * CHUNK, c.y * CHUNK, CHUNK, CHUNK)


func in_city(p: Vector3) -> bool:
	return absf(p.x) < HALF and absf(p.z) < HALF


## Blocks whose centre is in chunk `c` (each block belongs to exactly one chunk).
func blocks_owned(c: Vector2i) -> PackedInt32Array:
	return _owned.get(c, PackedInt32Array())


## Blocks that reach into chunk `c`.
func blocks_overlapping(c: Vector2i) -> PackedInt32Array:
	return _overlap.get(c, PackedInt32Array())


func district(x: float, z: float) -> String:
	if z > RIVER_Z1:
		return "south"
	if x < -620.0:
		return "west"
	if x > 320.0:
		return "east"
	if z < -720.0:
		return "north"
	return "city"


func is_river(x: float, z: float) -> bool:
	return z > RIVER_Z0 and z < RIVER_Z1 and absf(x) < HALF


## True over the carriageways (not pavements, buildings, parks or the river).
func is_road(x: float, z: float) -> bool:
	if not in_city(Vector3(x, 0, z)) or CORE.has_point(Vector2(x, z)):
		for r in extra_roads:
			if r.has_point(Vector2(x, z)):
				return true
		return false
	if z > RIVER_Z0 - WALK and z < RIVER_Z1 + WALK:
		for b in bridges:
			if absf(x - b) < ART_ROAD * 0.5:
				return true
		return false
	var c := coord_of(Vector3(x, 0, z))
	for i in blocks_overlapping(c):
		if (blocks[i]["rect"] as Rect2).has_point(Vector2(x, z)):
			return false
	return true


## Height of the walking surface at (x, z): pavement or carriageway (outside the core).
func ground_y(x: float, z: float) -> float:
	return 0.0 if is_road(x, z) else PAVE_TOP


# ---------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------
func _make_lines() -> void:
	var core_x0 := CORE.position.x - ART_PAVE - ART_ROAD * 0.5
	var core_x1 := CORE.end.x + ART_PAVE + ART_ROAD * 0.5
	var core_z0 := CORE.position.y - ART_PAVE - ART_ROAD * 0.5
	var core_z1 := CORE.end.y + ART_PAVE + ART_ROAD * 0.5
	var emb_n := RIVER_Z0 - WALK - ART_ROAD * 0.5
	var emb_s := RIVER_Z1 + WALK + ART_ROAD * 0.5
	# Anchor lines: round the core, St Paul's and Westminster (pairs that must not be split).
	var x_anchor := [-EDGE_LINE, -1068.0, -732.0, ST_PAULS.x - 105.0, ST_PAULS.x + 105.0, core_x0, core_x1, EDGE_LINE]
	var x_keep := [[-1068.0, -732.0], [ST_PAULS.x - 105.0, ST_PAULS.x + 105.0], [core_x0, core_x1]]
	var z_anchor := [-EDGE_LINE, core_z0, core_z1, ST_PAULS.z - 70.0, ST_PAULS.z + 70.0, 440.0, emb_n, emb_s, EDGE_LINE]
	var z_keep := [[core_z0, core_z1], [ST_PAULS.z - 70.0, ST_PAULS.z + 70.0], [440.0, emb_n], [emb_n, emb_s]]
	xs = _fill_lines(x_anchor, x_keep, 11)
	zs = _fill_lines(z_anchor, z_keep, 23)
	# Bridges where the Victorians had them: Westminster, Blackfriars, London Bridge and one
	# further east.
	for want: float in [-1068.0, ST_PAULS.x + 105.0, 250.0, 900.0]:
		var best := xs[0]
		for x in xs:
			if absf(x - want) < absf(best - want):
				best = x
		if not bridges.has(best):
			bridges.append(best)


func _fill_lines(anchors: Array, keep: Array, salt: int) -> PackedFloat32Array:
	anchors.sort()
	var out := PackedFloat32Array()
	for k in anchors.size():
		var a: float = anchors[k]
		out.append(a)
		if k == anchors.size() - 1:
			break
		var b: float = anchors[k + 1]
		var kept := false
		for pair: Array in keep:
			if is_equal_approx(pair[0], a) and is_equal_approx(pair[1], b):
				kept = true
		if kept:
			continue
		var n := maxi(1, roundi((b - a) / 225.0))
		for m in range(1, n):
			var jitter := (hash01(k, m, salt) - 0.5) * 0.24 * (b - a) / n
			out.append(snappedf(a + (b - a) * m / n + jitter, 0.25))
	return out


## The bounds of superblock column i (between road line i-1 and line i) along one axis,
## after taking off half of each road. Returns [lo, hi, lo_is_road, hi_is_road].
func _span(lines: PackedFloat32Array, i: int, road_w: float) -> Array:
	var lo := -HALF if i == 0 else lines[i - 1] + road_w * 0.5
	var hi := HALF if i == lines.size() else lines[i] - road_w * 0.5
	return [lo, hi, i > 0, i < lines.size()]


# ---------------------------------------------------------------------------
# Blocks
# ---------------------------------------------------------------------------
func _add_block(rect: Rect2, kind: Kind, pave: Array, facades: Array) -> void:
	var c := rect.get_center()
	blocks.append({
		"id": blocks.size(), "rect": rect, "kind": kind, "district": district(c.x, c.y),
		"seed": int(hash01(roundi(c.x * 4.0), roundi(c.y * 4.0), _seed) * 1000000.0),
		"pave": pave, "facades": facades,
	})


func _make_blocks() -> void:
	var emb_n := RIVER_Z0 - WALK - ART_ROAD * 0.5
	for j in zs.size() + 1:
		var zspan := _span(zs, j, ART_ROAD)
		var zc := (float(zspan[0]) + float(zspan[1])) * 0.5
		if zc > RIVER_Z0 - WALK and zc < RIVER_Z1 + WALK:
			continue # the river row is built by CityRiver
		for i in xs.size() + 1:
			var xspan := _span(xs, i, ART_ROAD)
			var cell := Rect2(xspan[0], zspan[0], float(xspan[1]) - float(xspan[0]), float(zspan[1]) - float(zspan[0]))
			var centre := cell.get_center()
			# Pavement on sides that face a road, none on the city's outer edge.
			var pave := [ART_PAVE if zspan[2] else 0.0, ART_PAVE if zspan[3] else 0.0, ART_PAVE if xspan[3] else 0.0, ART_PAVE if xspan[2] else 0.0]
			if CORE.grow(ART_PAVE + 1.0).has_point(centre):
				_make_core_blocks()
				continue
			var near_river := absf(float(zspan[1]) - (emb_n - ART_ROAD * 0.5)) < 1.0 or absf(float(zspan[0]) - (RIVER_Z1 + WALK + ART_ROAD)) < 1.0
			if cell.has_point(Vector2(ST_PAULS.x, ST_PAULS.z)) or cell.has_point(Vector2(WESTMINSTER.x, WESTMINSTER.z)):
				_add_block(cell, Kind.LANDMARK, pave, [])
			elif PARK_AREA.has_point(centre):
				_add_block(cell, Kind.PARK, pave, [])
			else:
				_subdivide(cell, pave, i, j, near_river)


## Side streets through a superblock: blocks of 50-85 m one way and up to ~140 m the other.
func _subdivide(cell: Rect2, pave: Array, i: int, j: int, near_river: bool) -> void:
	var along_x := cell.size.x >= cell.size.y
	if hash01(i, j, 3) < 0.25:
		along_x = not along_x
	var long := cell.size.x if along_x else cell.size.y
	var short := cell.size.y if along_x else cell.size.x
	var n1 := maxi(1, roundi(long / lerpf(62.0, 88.0, hash01(i, j, 4))))
	var n2 := 1 if short < 150.0 else (2 if short < 240.0 else 3)
	var cuts1 := _cuts(long, n1, i * 31 + j, 5)
	var cuts2 := _cuts(short, n2, i * 31 + j, 6)
	for a in n1:
		for b in n2:
			var l0: float = cuts1[a]
			var l1: float = cuts1[a + 1]
			var s0: float = cuts2[b]
			var s1: float = cuts2[b + 1]
			# Half a side street off each inner edge.
			l0 += 0.0 if a == 0 else MIN_ROAD * 0.5
			l1 -= 0.0 if a == n1 - 1 else MIN_ROAD * 0.5
			s0 += 0.0 if b == 0 else MIN_ROAD * 0.5
			s1 -= 0.0 if b == n2 - 1 else MIN_ROAD * 0.5
			var r: Rect2
			var p := pave.duplicate()
			if along_x:
				r = Rect2(cell.position.x + l0, cell.position.y + s0, l1 - l0, s1 - s0)
				if a > 0: p[Side.W] = MIN_PAVE
				if a < n1 - 1: p[Side.E] = MIN_PAVE
				if b > 0: p[Side.N] = MIN_PAVE
				if b < n2 - 1: p[Side.S] = MIN_PAVE
			else:
				r = Rect2(cell.position.x + s0, cell.position.y + l0, s1 - s0, l1 - l0)
				if a > 0: p[Side.N] = MIN_PAVE
				if a < n1 - 1: p[Side.S] = MIN_PAVE
				if b > 0: p[Side.W] = MIN_PAVE
				if b < n2 - 1: p[Side.E] = MIN_PAVE
			r = Rect2(snappedf(r.position.x, 0.25), snappedf(r.position.y, 0.25), snappedf(r.size.x, 0.25), snappedf(r.size.y, 0.25))
			# Buildings on every side (on the city's outer edge too, closing the yards off).
			var facades := [Side.N, Side.S, Side.E, Side.W]
			var c := r.get_center()
			var d := district(c.x, c.y)
			var roll := hash01(roundi(c.x), roundi(c.y), 7)
			var big := r.size.x > 44.0 and r.size.y > 44.0
			var kind := Kind.TERRACE
			var river_side: bool = near_river and (p[Side.S] == ART_PAVE and c.y < RIVER_Z0 or p[Side.N] == ART_PAVE and c.y > RIVER_Z1)
			if river_side and ((d == "east" or d == "south") and roll < 0.8 or d == "city" and roll < 0.45):
				kind = Kind.WAREHOUSE
			elif big and roll < {"west": 0.13, "north": 0.07, "city": 0.04, "east": 0.03, "south": 0.04}[d]:
				kind = Kind.SQUARE
			elif big and roll > 0.965:
				kind = Kind.CHURCH
			_add_block(r, kind, p, facades)


func _cuts(length: float, n: int, key: int, salt: int) -> Array:
	var out := [0.0]
	for m in range(1, n):
		var jitter := (hash01(key, m, salt) - 0.5) * 0.3 * length / n
		out.append(length * m / n + jitter)
	out.append(length)
	return out


func _make_core_blocks() -> void:
	if blocks.any(func(b: Dictionary) -> bool: return b["kind"] == Kind.SLAB and b.get("ring", false)):
		return
	# The pavement all round the core.
	var o := CORE.grow(ART_PAVE)
	for r: Rect2 in [
		Rect2(o.position.x, o.position.y, o.size.x, ART_PAVE), Rect2(o.position.x, CORE.end.y, o.size.x, ART_PAVE),
		Rect2(o.position.x, CORE.position.y, ART_PAVE, CORE.size.y), Rect2(CORE.end.x, CORE.position.y, ART_PAVE, CORE.size.y),
	]:
		_add_block(r, Kind.SLAB, [0.0, 0.0, 0.0, 0.0], [])
		blocks[-1]["ring"] = true
	for f: Array in CORE_FILL:
		_add_block(f[0], f[3], f[2], f[1])
		blocks[-1]["core"] = true


func _index_blocks() -> void:
	var tmp_overlap := {}
	var tmp_owned := {}
	for b in blocks:
		var r: Rect2 = b["rect"]
		var c0 := coord_of(Vector3(r.position.x, 0, r.position.y))
		var c1 := coord_of(Vector3(r.end.x - 0.01, 0, r.end.y - 0.01))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var k := Vector2i(cx, cz)
				if not tmp_overlap.has(k):
					tmp_overlap[k] = PackedInt32Array()
				var list: PackedInt32Array = tmp_overlap[k]
				list.append(b["id"])
		var oc := coord_of(Vector3(r.get_center().x, 0, r.get_center().y))
		if not tmp_owned.has(oc):
			tmp_owned[oc] = PackedInt32Array()
		var owned: PackedInt32Array = tmp_owned[oc]
		owned.append(b["id"])
	_overlap = tmp_overlap
	_owned = tmp_owned


# ---------------------------------------------------------------------------
# Lots: the buildings along a block's frontages
# ---------------------------------------------------------------------------
## The lot rectangle (inside the pavement) of a block.
func lot_rect(b: Dictionary) -> Rect2:
	var r: Rect2 = b["rect"]
	var p: Array = b["pave"]
	return Rect2(r.position.x + p[Side.W], r.position.y + p[Side.N], r.size.x - p[Side.W] - p[Side.E], r.size.y - p[Side.N] - p[Side.S])


## Style numbers for a district: [min lot w, max lot w, min upper floors, max upper floors,
## depth min, depth max, shop chance, walls, ground floor h, floor h].
func _style(d: String) -> Array:
	match d:
		"west":
			return [6.5, 9.5, 3, 4, 12.0, 16.0, 0.2, ["stucco", "stucco", "stucco", "brick_yellow"], 3.8, 3.3]
		"east":
			return [4.5, 6.5, 1, 2, 8.0, 11.0, 0.3, ["brick_yellow", "brick_yellow", "brick_red"], 3.1, 2.8]
		"south":
			return [4.8, 7.0, 1, 3, 9.0, 12.0, 0.3, ["brick_yellow", "brick_red", "brick_red"], 3.2, 2.9]
		"north":
			return [5.5, 7.5, 2, 3, 10.0, 13.0, 0.25, ["brick_yellow", "brick_yellow", "stucco", "brick_red"], 3.4, 3.0]
	return [5.5, 9.0, 2, 4, 11.0, 14.0, 0.5, ["brick_yellow", "brick_red", "stucco", "brick_red"], 3.6, 3.1]


## Lots for a block: each {xf: Transform3D (facade-left corner at pavement height, local +Z
## out to the street), w, d, upper, gh, fh, wall, shop, name, door_left, seed, kind}.
func lots(b: Dictionary) -> Array:
	var kind: Kind = b["kind"]
	if kind not in [Kind.TERRACE, Kind.FILL, Kind.WAREHOUSE]:
		return []
	var f := lot_rect(b)
	var rng := RandomNumberGenerator.new()
	rng.seed = b["seed"]
	var st := _style(b["district"])
	var facades: Array = b["facades"]
	var warehouse := kind == Kind.WAREHOUSE
	var depth := rng.randf_range(st[4], st[5])
	if warehouse:
		depth = rng.randf_range(14.0, 20.0)
	var has := func(s: int) -> bool: return facades.has(s)
	var d_n := minf(depth, f.size.y * (0.5 if has.call(Side.S) else 1.0) - 1.0) if has.call(Side.N) else 0.0
	var d_s := minf(depth, f.size.y * (0.5 if has.call(Side.N) else 1.0) - 1.0) if has.call(Side.S) else 0.0
	var d_e := minf(depth, f.size.x * (0.5 if has.call(Side.W) else 1.0) - 1.0) if has.call(Side.E) else 0.0
	var d_w := minf(depth, f.size.x * (0.5 if has.call(Side.E) else 1.0) - 1.0) if has.call(Side.W) else 0.0
	var out := []
	var alley_side := rng.randi() % 4 if rng.randf() < 0.55 and not warehouse else -1
	for row: Array in _rows(f, d_n, d_s, d_e, d_w):
		_row(out, b, rng, st, row[0], row[1], row[2], row[3], alley_side == int(row[4]), warehouse)
	return out


## The frontage rows of a lot rect: [start (facade-left corner), yaw, length, depth, side].
## North and south rows run the full width; east and west rows fit between them.
static func _rows(f: Rect2, d_n: float, d_s: float, d_e: float, d_w: float) -> Array:
	var rows := []
	if d_n > 2.0:
		rows.append([Vector3(f.end.x, PAVE_TOP, f.position.y), PI, f.size.x, d_n, Side.N])
	if d_s > 2.0:
		rows.append([Vector3(f.position.x, PAVE_TOP, f.end.y), 0.0, f.size.x, d_s, Side.S])
	var z0 := f.position.y + d_n
	var z1 := f.end.y - d_s
	if d_e > 2.0 and z1 - z0 > 4.0:
		rows.append([Vector3(f.end.x, PAVE_TOP, z1), PI * 0.5, z1 - z0, d_e, Side.E])
	if d_w > 2.0 and z1 - z0 > 4.0:
		rows.append([Vector3(f.position.x, PAVE_TOP, z0), -PI * 0.5, z1 - z0, d_w, Side.W])
	return rows


## For the distant city: each frontage row of a block as one box, [Transform3D of a unit
## box (origin at the ground centre), height]. Same depths as lots() uses.
func distant_rows(b: Dictionary) -> Array:
	var kind: Kind = b["kind"]
	if kind not in [Kind.TERRACE, Kind.FILL, Kind.WAREHOUSE]:
		return []
	var f := lot_rect(b)
	var rng := RandomNumberGenerator.new()
	rng.seed = b["seed"]
	var st := _style(b["district"])
	var facades: Array = b["facades"]
	var warehouse := kind == Kind.WAREHOUSE
	var depth := rng.randf_range(st[4], st[5])
	if warehouse:
		depth = rng.randf_range(14.0, 20.0)
	var d_n := minf(depth, f.size.y * (0.5 if facades.has(Side.S) else 1.0) - 1.0) if facades.has(Side.N) else 0.0
	var d_s := minf(depth, f.size.y * (0.5 if facades.has(Side.N) else 1.0) - 1.0) if facades.has(Side.S) else 0.0
	var d_e := minf(depth, f.size.x * (0.5 if facades.has(Side.W) else 1.0) - 1.0) if facades.has(Side.E) else 0.0
	var d_w := minf(depth, f.size.x * (0.5 if facades.has(Side.E) else 1.0) - 1.0) if facades.has(Side.W) else 0.0
	var h: float = float(st[8]) + (float(st[2]) + float(st[3])) * 0.5 * float(st[9])
	if warehouse:
		h = 4.0 + 4.0 * 3.2
	var out := []
	for row: Array in _rows(f, d_n, d_s, d_e, d_w):
		var basis := Basis(Vector3.UP, float(row[1]))
		var length: float = row[2]
		var d: float = row[3]
		var centre: Vector3 = row[0] + basis * Vector3(length * 0.5, -PAVE_TOP, -d * 0.5)
		var hh := h * (0.9 + hash01(roundi(centre.x), roundi(centre.z), 9) * 0.25)
		out.append([Transform3D(basis.scaled(Vector3(length, hh, d)), centre), hh])
	return out


func _row(out: Array, b: Dictionary, rng: RandomNumberGenerator, st: Array, start: Vector3, yaw: float, length: float, depth: float, alley: bool, warehouse: bool) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var dir := basis.x # along the row (local +X)
	var arterial := false
	var pave: Array = b["pave"]
	for v: float in pave:
		if v >= ART_PAVE:
			arterial = true
	var alley_at := rng.randf_range(0.3, 0.7) * length if alley and length > 30.0 else -1.0
	var x := 0.0
	var first := true
	while length - x > 0.01:
		var w := rng.randf_range(15.0, 28.0) if warehouse else rng.randf_range(st[0], st[1])
		if length - (x + w) < (8.0 if warehouse else float(st[0]) * 0.8):
			w = length - x
		if alley_at > 0.0 and x + w > alley_at and x < alley_at:
			# A covered way through to the back yards.
			w = maxf(alley_at - x, 0.0)
			if w > 3.0:
				out.append(_lot(b, rng, st, Transform3D(basis, start + dir * x), w, depth, false, arterial, warehouse))
			x += w + 2.6
			alley_at = -1.0
			continue
		var last := length - (x + w) < 0.01
		var lot := _lot(b, rng, st, Transform3D(basis, start + dir * x), w, depth, first or last, arterial, warehouse)
		# The ends of the north and south rows stand on street corners: windows there too.
		if is_equal_approx(yaw, 0.0) or is_equal_approx(yaw, PI):
			lot["side_open"] = (1 if first else 0) | (2 if last else 0)
		out.append(lot)
		first = false
		x += w


func _lot(b: Dictionary, rng: RandomNumberGenerator, st: Array, xf: Transform3D, w: float, depth: float, corner: bool, arterial: bool, warehouse: bool) -> Dictionary:
	var walls: Array = st[7]
	var lot := {
		"xf": xf, "w": w, "d": depth, "upper": rng.randi_range(st[2], st[3]), "gh": st[8], "fh": st[9],
		"wall": walls[rng.randi() % walls.size()], "shop": false, "name": "", "door_left": rng.randf() < 0.5,
		"seed": rng.randi(), "kind": "house",
	}
	if warehouse:
		lot["kind"] = "warehouse"
		lot["upper"] = rng.randi_range(3, 5)
		lot["gh"] = 4.0
		lot["fh"] = 3.2
		lot["wall"] = "brick_yellow" if rng.randf() < 0.6 else "brick_red"
		return lot
	var shop_chance: float = st[6] + (0.3 if arterial else 0.0)
	if corner and rng.randf() < 0.45:
		lot["shop"] = true
		lot["kind"] = "pub"
		lot["name"] = PUBS[rng.randi() % PUBS.size()]
	elif rng.randf() < shop_chance:
		lot["shop"] = true
		lot["kind"] = "shop"
		var who: String = SURNAMES[rng.randi() % SURNAMES.size()]
		var what: String = TRADES[rng.randi() % TRADES.size()]
		lot["name"] = ("%s & SONS  %s" if rng.randf() < 0.35 else "%s  %s") % [who, what]
	return lot
