class_name TerrainGenerator
extends RefCounted
## The hills north of London where Harry has lived for seven years: a 2 km x 2 km stretch of
## rolling downland and woods, with his cave in a rock outcrop, a lake, and the old road
## that winds east towards the city.
##
## Everything is a pure function of (x, z) and the seed, so any thread can build any chunk
## and always get the same ground. Make one instance per thread (FastNoiseLite objects
## are not shared between threads).
##
## Heights are in metres above an arbitrary datum; the lake's surface is at WATER_Y.

const HALF_SIZE := 1024.0
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
	Vector2(560.0, 470.0), Vector2(800.0, 520.0), Vector2(1010.0, 540.0),
]
const ROAD_HALF_WIDTH := 3.0

var _broad := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _road_noise := FastNoiseLite.new()
var _clearing_height := 0.0


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
	# Hills rise steeply at the map's edges (except where the road leaves to the east).
	var edge := maxf(absf(x), absf(z)) - (HALF_SIZE - 140.0)
	if edge > 0.0:
		var gap := 1.0 - smoothstep(30.0, 60.0, absf(z - 540.0)) if x > 0.0 and absf(x) > absf(z) else 0.0
		h += pow(edge / 140.0, 2.0) * 90.0 * (1.0 - gap)
	return h


## (distance to the road's centre line, graded road height there).
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


## 0..1: how thickly wooded the land is here (none on roads, water, clearing, steep rock).
func forest(x: float, z: float) -> float:
	var f := smoothstep(-0.05, 0.35, _forest.get_noise_2d(x, z))
	if road_info(x, z).x < 9.0 or is_water(x, z) or Vector2(x, z).distance_to(CLEARING) < CLEARING_RADIUS + 6.0 or CAVE_FLOOR.grow(8.0).has_point(Vector2(x, z)):
		return 0.0
	if Vector2(x, z).distance_to(LAKE) < LAKE_RADIUS * 1.1:
		f *= 0.3
	return f


func is_water(x: float, z: float) -> bool:
	return height(x, z) < WATER_Y


## How deep the water is at (x, z) (0 on dry land).
func water_depth(x: float, z: float) -> float:
	return maxf(WATER_Y - height(x, z), 0.0)


## Cheap deterministic 0..1 hash for scattering things.
static func hash01(ix: int, iz: int, s: int) -> float:
	var h := (ix * 374761393 + iz * 668265263 + s * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0
