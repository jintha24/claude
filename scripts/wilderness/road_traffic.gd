class_name RoadTraffic
extends Node3D
## Carts, carriers' wagons and the odd cab on the London road through the hills (and the
## lanes to the villages), coming and going near the player.

@export var streamer_path: NodePath = NodePath("../Streamer")
@export var player_path: NodePath = NodePath("../Harry")
@export var max_vehicles: int = 4

var _gen: TerrainGenerator
var _player: Node3D
var _vehicles: Array[HorseVehicle] = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _count := 0
var _paths: Array = [] # each a PackedVector2Array, 8 m apart


func _ready() -> void:
	var streamer := get_node_or_null(streamer_path) as WorldStreamer
	_gen = streamer.generator if streamer else TerrainGenerator.new()
	_rng.seed = 42
	for path: Array in [TerrainGenerator.ROAD] + TerrainGenerator.LANES:
		var pts := PackedVector2Array()
		for k in path.size() - 1:
			var a: Vector2 = path[k]
			var b: Vector2 = path[k + 1]
			var n := maxi(1, int(a.distance_to(b) / 8.0))
			for m in n:
				pts.append(a.lerp(b, float(m) / n))
		pts.append(path[path.size() - 1])
		_paths.append(pts)


func vehicle_count() -> int:
	return _vehicles.size()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node3D
		if _player == null:
			return
	var p := _player.global_position
	for v in _vehicles.duplicate():
		if not is_instance_valid(v):
			_vehicles.erase(v)
		elif v.global_position.distance_to(p) > 420.0 or v.waypoints.is_empty():
			_vehicles.erase(v)
			v.queue_free()
	var h := GameClock.hours()
	var want := max_vehicles if h > 6.0 and h < 20.0 else 1
	if _vehicles.size() < want:
		_spawn(p)


func _height(x: float, z: float) -> float:
	return _gen.height(x, z)


func _spawn(p: Vector3) -> void:
	var pp := Vector2(p.x, p.z)
	for attempt in 12:
		var path: PackedVector2Array = _paths[_rng.randi() % _paths.size()]
		var k := _rng.randi_range(1, path.size() - 2)
		var d := pp.distance_to(path[k])
		if d < 90.0 or d > 330.0:
			continue
		var forward := _rng.randf() < 0.5
		var step := 1 if forward else -1
		var v := HorseVehicle.new()
		_count += 1
		v.name = "RoadVehicle%d" % _count
		var r := _rng.randf()
		v.kind = HorseVehicle.Kind.CART if r < 0.5 else (HorseVehicle.Kind.GROWLER if r < 0.75 else (HorseVehicle.Kind.DRAY if r < 0.9 else HorseVehicle.Kind.HANSOM))
		v.cruise = _rng.randf_range(2.4, 3.8)
		v.height_fn = _height
		add_child(v)
		var a := path[k]
		var b := path[k + step]
		var dir := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
		var left := Vector3(dir.z, 0, -dir.x)
		var start := Vector3(a.x, 0, a.y) + left * 1.4
		start.y = _height(start.x, start.z)
		v.place(start, dir)
		var m := k + step
		while m >= 0 and m < path.size():
			var q := path[m]
			var nxt := path[clampi(m + step, 0, path.size() - 1)]
			var dd := Vector3(nxt.x - q.x, 0, nxt.y - q.y)
			var lft := Vector3(dd.z, 0, -dd.x).normalized() * 1.4 if dd.length() > 0.1 else left
			v.waypoints.append(Vector3(q.x, 0, q.y) + lft)
			m += step
		_vehicles.append(v)
		return
