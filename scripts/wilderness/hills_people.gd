class_name HillsPeople
extends Node3D
## People out in the country round the player: travellers on the London road and the
## lanes (pedlars, drovers, farm hands, women walking to market, a parson), and hands at
## work in the fields by day. The villages have their own folk (Village).

@export var streamer_path: NodePath = NodePath("../Streamer")
@export var player_path: NodePath = NodePath("../Harry")
@export var max_walkers: int = 9
@export var max_workers: int = 6

const JOBS := [
	["pedlar", NPCBody.Outfit.WORKER], ["drover", NPCBody.Outfit.WORKER], ["farm hand", NPCBody.Outfit.WORKER],
	["market woman", NPCBody.Outfit.LADY], ["parson", NPCBody.Outfit.PRIEST], ["gentleman", NPCBody.Outfit.GENTLEMAN],
	["vagrant", NPCBody.Outfit.RAGGED], ["dairymaid", NPCBody.Outfit.LADY],
]

var _gen: TerrainGenerator
var _player: Node3D
var _walkers: Array[Traveller] = []
var _workers: Array[Traveller] = []
var _paths: Array = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _count := 0


func _ready() -> void:
	add_to_group("hills_people")
	var streamer := get_node_or_null(streamer_path) as WorldStreamer
	_gen = streamer.generator if streamer else TerrainGenerator.new()
	_rng.seed = 99
	for path: Array in [TerrainGenerator.ROAD] + TerrainGenerator.LANES:
		var pts: Array[Vector2] = []
		for k in path.size() - 1:
			var a: Vector2 = path[k]
			var b: Vector2 = path[k + 1]
			var n := maxi(1, int(a.distance_to(b) / 10.0))
			for m in n:
				pts.append(a.lerp(b, float(m) / n))
		pts.append(path[path.size() - 1])
		_paths.append(pts)


func walker_count() -> int:
	return _walkers.size()


func worker_count() -> int:
	return _workers.size()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.8
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node3D
		if _player == null:
			return
	var p := _player.global_position
	for list: Array in [_walkers, _workers]:
		for t: Variant in list.duplicate():
			if not is_instance_valid(t):
				list.erase(t)
				continue
			var tr := t as Traveller
			if tr.global_position.distance_to(p) > 380.0 or tr.finished():
				list.erase(tr)
				tr.queue_free()
	var h := GameClock.hours()
	var day := h > 6.0 and h < 20.5
	var weather := 1.0 - Weather.rain * 0.6 - Weather.snow * 0.5
	var want_walk := int(round(max_walkers * weather * (1.0 if day else 0.25)))
	var want_work := int(round(max_workers * weather)) if h > 6.5 and h < 18.5 else 0
	if _walkers.size() < want_walk:
		_spawn_walker(p)
	if _workers.size() < want_work:
		_spawn_worker(p)


func _make(job: Array) -> Traveller:
	var t := Traveller.new()
	_count += 1
	t.name = "Traveller%d" % _count
	t.job = job[0]
	t.outfit = job[1]
	t.look_seed = _rng.randi() % 100000
	t.gen = _gen
	t.walk_speed = _rng.randf_range(1.1, 1.45)
	return t


func _spawn_walker(p: Vector3) -> void:
	var pp := Vector2(p.x, p.z)
	for attempt in 12:
		var path: Array = _paths[_rng.randi() % _paths.size()]
		var k := _rng.randi_range(0, path.size() - 1)
		var at: Vector2 = path[k]
		var d := at.distance_to(pp)
		if d < 45.0 or d > 300.0:
			continue
		var forward := _rng.randf() < 0.5
		var t := _make(JOBS[_rng.randi() % JOBS.size()])
		var side := 1.6 * (1.0 if _rng.randf() < 0.5 else -1.0)
		var route: Array[Vector3] = []
		var m := k
		while m >= 0 and m < path.size():
			var q: Vector2 = path[m]
			var nxt: Vector2 = path[clampi(m + (1 if forward else -1), 0, path.size() - 1)]
			var dd := (nxt - q).normalized() if nxt != q else Vector2.RIGHT
			var off := Vector2(-dd.y, dd.x) * (TerrainGenerator.ROAD_HALF_WIDTH + 0.4) * signf(side)
			route.append(Vector3(q.x + off.x, 0.0, q.y + off.y))
			m += 1 if forward else -1
		t.route = route
		add_child(t)
		t.global_position = Vector3(route[0].x, _gen.height(route[0].x, route[0].z), route[0].z)
		_walkers.append(t)
		return


func _spawn_worker(p: Vector3) -> void:
	# Hands hoeing and harvesting in the arable fields near the player.
	for attempt in 16:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(40.0, 260.0)
		var q := Vector2(p.x + cos(a) * r, p.z + sin(a) * r)
		var farm := _gen.farm_at(q.x, q.y)
		if farm.x != TerrainGenerator.Field.WHEAT and farm.x != TerrainGenerator.Field.HAY and farm.x != TerrainGenerator.Field.PLOUGHED:
			continue
		var t := _make(["farm hand", NPCBody.Outfit.WORKER] if _rng.randf() < 0.75 else ["dairymaid", NPCBody.Outfit.LADY])
		t.standing = true
		add_child(t)
		t.global_position = Vector3(q.x, _gen.height(q.x, q.y), q.y)
		_workers.append(t)
		return
