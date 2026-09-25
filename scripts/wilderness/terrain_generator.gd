class_name TerrainGenerator
extends RefCounted
## The hills north of London where Harry has lived for seven years: a 4 km x 4 km stretch of
## rolling downland and woods, with his cave in a rock outcrop, a lake, the old road that
## winds east towards the city through two villages, lanes to two more, and the farms
## (fields, pasture and hedgerows) round each village.
##
## Everything is a pure function of (x, z) and the seed, so any thread can build any chunk
## and always get the same ground. Make one instance per thread (FastNoiseLite objects
## are not shared between threads).
##
## Heights are in metres above an arbitrary datum; the lake's surface is at WATER_Y.

const HALF_SIZE := 2048.0
const WATER_Y := 24.0
## Harry's cave: the mouth of the rock outcrop faces south (+Z) onto a flat clearing.
const CAVE := Vector2(-120.0, 60.0)
const CLEARING := Vector2(-120.0, 92.0)
const CLEARING_RADIUS := 30.0
## The cave's floor plan (x0, z0, x1, z1): cut level with the clearing into the escarpment.
const CAVE_FLOOR := Rect2(-131.0, 50.0, 22.0, 36.0)
const LAKE := Vector2(170.0, 170.0)
const LAKE_RADIUS := 105.0
## The London road, from the clearing to the east edge of the map.
const ROAD: Array[Vector2] = [
	Vector2(-120.0, 112.0), Vector2(-40.0, 230.0), Vector2(90.0, 330.0), Vector2(300.0, 400.0),
	Vector2(560.0, 470.0), Vector2(800.0, 520.0), Vector2(1010.0, 540.0), Vector2(1260.0, 572.0),
	Vector2(1500.0, 566.0), Vector2(1760.0, 598.0), Vector2(2040.0, 610.0),
]
const ROAD_HALF_WIDTH := 3.0
## Narrow lanes off the London road to the villages away from it.
const LANES: Array = [
	[Vector2(640.0, 486.0), Vector2(660.0, 260.0), Vector2(600.0, -120.0), Vector2(540.0, -520.0), Vector2(480.0, -900.0)],
	[Vector2(-150.0, 125.0), Vector2(-430.0, 262.0), Vector2(-800.0, 380.0), Vector2(-1180.0, 440.0)],
]
const LANE_HALF_WIDTH := 2.2
## The villages: [name, centre, radius of the flat ground they stand on].
const VILLAGES: Array = [
	["Highgate", Vector2(700.0, 505.0), 80.0],
	["Kentish Green", Vector2(1500.0, 566.0), 90.0],
	["Northwold", Vector2(480.0, -925.0), 75.0],
	["Westcombe", Vector2(-1200.0, 445.0), 65.0],
]
## How far the farms reach out from a village's edge.
const FARM_RING := 420.0
## Field kinds (farm_at): none, pasture, wheat, ploughed, hay meadow.
enum Field { NONE, PASTURE, WHEAT, PLOUGHED, HAY }

var _broad := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _road_noise := FastNoiseLite.new()
var _clearing_height := 0.0
var _village_h: Array[float] = []


func _init(world_seed: int = 1866) -> void:
	_broad.seed = world_seed
	_broad.frequency = 0.0016
	_broad.fractal_octaves = 3
	_hills.seed = world_seed + 1
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0052
	_hills.fractal_octaves = 4
	_detail.seed = world_seed + 2
	_detail.frequency = 0.045
	_detail.fractal_octaves = 2
	_road_noise.seed = world_seed
	_road_noise.frequency = 0.0016
	_road_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_forest.seed = world_seed + 3
	_forest.frequency = 0.006
	_forest.fractal_octaves = 3
	_clearing_height = _natural(CLEARING.x, CLEARING.y)
	for v: Array in VILLAGES:
		_village_h.append(road_info(v[1].x, v[1].y).y)


## The broad lie of the land (used for the road so it follows the valleys gently).
func low(x: float, z: float) -> float:
	return 52.0 + _broad.get_noise_2d(x, z) * 38.0


## Ground before the clearing, road and edges are shaped.
func _natural(x: float, z: float) -> float:
	var h := low(x, z) + _hills.get_noise_2d(x, z) * 22.0 + _detail.get_noise_2d(x, z) * 0.9
	# The lake basin.
	var dl := Vector2(x, z).distance_to(LAKE)
	if dl < LAKE_RADIUS * 1.8:
		var t := smoothstep(LAKE_RADIUS * 1.8, LAKE_RADIUS * 0.55, dl)
		var bowl := WATER_Y - 1.4 + (dl / LAKE_RADIUS) * 1.4
		h = lerpf(h, minf(h, bowl), t)
	# The escarpment behind the cave: a steep rise north of the outcrop.
	var dc := Vector2(x, z) - CAVE
	if dc.y < 20.0 and absf(dc.x) < 140.0:
		var along := 1.0 - smoothstep(60.0, 140.0, absf(dc.x))
		var up := smoothstep(20.0, -35.0, dc.y)
		h += 26.0 * along * up
	return h


## Final ground height at (x, z).
func height(x: float, z: float) -> float:
	var h := _natural(x, z)
	# Flat clearing in front of the cave.
	var dcl := Vector2(x, z).distance_to(CLEARING)
	if dcl < CLEARING_RADIUS * 1.8:
		h = lerpf(_clearing_height, h, smoothstep(CLEARING_RADIUS, CLEARING_RADIUS * 1.8, dcl))
	# The cave floor, cut back into the hillside.
	var inside := CAVE_FLOOR.grow(3.0)
	if inside.has_point(Vector2(x, z)):
		var dx := minf(x - inside.position.x, inside.end.x - x)
		var dz := minf(z - inside.position.y, inside.end.y - z)
		h = lerpf(h, _clearing_height, smoothstep(0.0, 3.0, minf(dx, dz)))
	# The road: graded to follow the broad valleys.
	var road := road_info(x, z)
	var rd: float = road.x
	if rd < 14.0:
		var t := smoothstep(ROAD_HALF_WIDTH + 1.0, 14.0, rd)
		h = lerpf(road.y, h, t)
	# The villages stand on smooth, gently sloping ground: the lie the road takes through
	# them (so the road keeps its easy grade from one end of the village to the other).
	for i in VILLAGES.size():
		var v: Array = VILLAGES[i]
		var r: float = v[2]
		var dv := Vector2(x, z).distance_to(v[1])
		if dv < r * 1.7:
			h = lerpf(road.y, h, smoothstep(r, r * 1.7, dv))
	# Hills rise steeply at the map's edges (except where the road leaves to the east).
	var edge := maxf(absf(x), absf(z)) - (HALF_SIZE - 140.0)
	if edge > 0.0:
		var gap := 1.0 - smoothstep(30.0, 60.0, absf(z - ROAD[ROAD.size() - 1].y)) if x > 0.0 and absf(x) > absf(z) else 0.0
		h += pow(edge / 140.0, 2.0) * 90.0 * (1.0 - gap)
	return h


## (distance to the road's centre line, graded road height there). The lanes count too,
## as if they were a road ROAD_HALF_WIDTH wide (they are narrower, so they read as further).
func road_info(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	var best := INF
	var best_pt := ROAD[0]
	for i in ROAD.size() - 1:
		var a: Vector2 = ROAD[i]
		var b: Vector2 = ROAD[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best:
			best = d
			best_pt = q
	var narrower := ROAD_HALF_WIDTH - LANE_HALF_WIDTH
	for lane: Array in LANES:
		for i in lane.size() - 1:
			var a: Vector2 = lane[i]
			var b: Vector2 = lane[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var q := a + ab * t
			var d := p.distance_to(q) + narrower
			if d < best:
				best = d
				best_pt = q
	# Where the road meets the clearing it is at clearing level.
	# Graded along the broad lie of the land only, so it never climbs steeply.
	var rh := 52.0 + _road_noise.get_noise_2d(best_pt.x, best_pt.y) * 38.0
	var into_clearing := smoothstep(CLEARING_RADIUS * 2.5, CLEARING_RADIUS, best_pt.distance_to(CLEARING))
	rh = lerpf(rh, _clearing_height, into_clearing)
	return Vector2(best, maxf(rh, WATER_Y + 0.6))


func clearing_height() -> float:
	return _clearing_height


func normal(x: float, z: float, e: float = 1.0) -> Vector3:
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## 0..1: how thickly wooded the land is here (none on roads, water, clearing, steep rock,
## in the villages or on their farms).
func forest(x: float, z: float) -> float:
	var f := smoothstep(-0.05, 0.35, _forest.get_noise_2d(x, z))
	if road_info(x, z).x < 9.0 or is_water(x, z) or Vector2(x, z).distance_to(CLEARING) < CLEARING_RADIUS + 6.0 or CAVE_FLOOR.grow(8.0).has_point(Vector2(x, z)):
		return 0.0
	if village_at(x, z) >= 0 or farm_at(x, z).x > 0.0:
		return 0.0
	if Vector2(x, z).distance_to(LAKE) < LAKE_RADIUS * 1.1:
		f *= 0.3
	return f


func is_water(x: float, z: float) -> bool:
	return height(x, z) < WATER_Y


## How deep the water is at (x, z) (0 on dry land).
func water_depth(x: float, z: float) -> float:
	return maxf(WATER_Y - height(x, z), 0.0)


## The village whose level ground (x, z) is on (-1 if none).
func village_at(x: float, z: float, margin: float = 0.0) -> int:
	for i in VILLAGES.size():
		var v: Array = VILLAGES[i]
		if Vector2(x, z).distance_to(v[1]) < float(v[2]) + margin:
			return i
	return -1


func village_height(i: int) -> float:
	return _village_h[i]


## The farmland round the villages: (Field kind, 1 on a hedgerow else 0). Fields are laid
## out on a grid turned to suit each village, about 95 m x 130 m, fading out irregularly.
func farm_at(x: float, z: float) -> Vector2:
	for i in VILLAGES.size():
		var v: Array = VILLAGES[i]
		var c: Vector2 = v[1]
		var r: float = v[2]
		var d := Vector2(x, z).distance_to(c)
		if d < r + 8.0 or d > r + FARM_RING:
			continue
		var ang := hash01(i, 7, 3) * PI
		var rel := (Vector2(x, z) - c).rotated(-ang)
		var cu := floori(rel.x / 95.0)
		var cv := floori(rel.y / 130.0)
		var reach := r + FARM_RING * (0.55 + 0.45 * hash01(cu + i * 97, cv, 5))
		if d > reach:
			continue
		var kind := 1 + int(hash01(cu + i * 97, cv, 6) * 4.0) % 4
		var fu := fposmod(rel.x, 95.0)
		var fv := fposmod(rel.y, 130.0)
		var hedge := 1.0 if fu < 1.6 or fv < 1.6 else 0.0
		return Vector2(kind, hedge)
	return Vector2.ZERO


## Points every ~6 m along the hedgerows inside `area` (x, z, w, d).
func hedge_points(area: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in VILLAGES.size():
		var v: Array = VILLAGES[i]
		var c: Vector2 = v[1]
		var outer := float(v[2]) + FARM_RING
		if not area.grow(outer).has_point(c):
			continue
		var ang := hash01(i, 7, 3) * PI
		# Grid lines of the village's fields, in its turned frame.
		for axis in 2:
			var cell := 95.0 if axis == 0 else 130.0
			var n := int(outer / cell) + 1
			for k in range(-n, n + 1):
				var t := -outer
				while t < outer:
					var rel := Vector2(k * cell, t) if axis == 0 else Vector2(t, k * cell)
					var p := c + rel.rotated(ang)
					t += 6.0
					if not area.has_point(p):
						continue
					if farm_at(p.x + 2.0, p.y + 2.0).x == 0.0 and farm_at(p.x - 2.0, p.y - 2.0).x == 0.0:
						continue
					if road_info(p.x, p.y).x < ROAD_HALF_WIDTH + 2.0:
						continue
					out.append(p)
	return out


## Cheap deterministic 0..1 hash for scattering things.
static func hash01(ix: int, iz: int, s: int) -> float:
	var h := (ix * 374761393 + iz * 668265263 + s * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0
