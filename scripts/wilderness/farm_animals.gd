class_name FarmAnimals
extends Node3D
## Keeps the pastures round the villages stocked near the player: a flock of sheep or a few
## cows in each grazing field within reach, the same beasts in the same field every time
## you pass (their numbers come from the field). Flocks well out of sight are let go.

@export var streamer_path: NodePath = NodePath("../Streamer")
@export var player_path: NodePath = NodePath("../Harry")
@export var reach := 260.0

var _gen: TerrainGenerator
var _player: Node3D
var _flocks := {} # Vector3i (village, field u, field v) -> Array[Livestock]
var _timer := 0.0


func _ready() -> void:
	var streamer := get_node_or_null(streamer_path) as WorldStreamer
	_gen = streamer.generator if streamer else TerrainGenerator.new()


func flock_count() -> int:
	return _flocks.size()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node3D
		if _player == null:
			return
	var p := Vector2(_player.global_position.x, _player.global_position.z)
	var near := {}
	for i in TerrainGenerator.VILLAGES.size():
		var v: Array = TerrainGenerator.VILLAGES[i]
		var c: Vector2 = v[1]
		var outer := float(v[2]) + TerrainGenerator.FARM_RING
		if p.distance_to(c) > outer + reach:
			continue
		var ang := TerrainGenerator.hash01(i, 7, 3) * PI
		var n := int(outer / 95.0) + 1
		for cu in range(-n, n + 1):
			for cv in range(-int(outer / 130.0) - 1, int(outer / 130.0) + 2):
				var centre := c + Vector2((cu + 0.5) * 95.0, (cv + 0.5) * 130.0).rotated(ang)
				if centre.distance_to(p) > reach:
					continue
				var farm := _gen.farm_at(centre.x, centre.y)
				if farm.x != TerrainGenerator.Field.PASTURE:
					continue
				var key := Vector3i(i, cu, cv)
				near[key] = true
				if not _flocks.has(key):
					_flocks[key] = _spawn_flock(key, centre)
	for key: Vector3i in _flocks.keys():
		if not near.has(key):
			for a: Livestock in _flocks[key]:
				if is_instance_valid(a):
					a.queue_free()
			_flocks.erase(key)


func _spawn_flock(key: Vector3i, centre: Vector2) -> Array:
	var h := TerrainGenerator.hash01(key.x * 31 + key.y, key.z, 41)
	var cows := h < 0.35
	var count := 3 + int(h * 10.0) % 4 if cows else 6 + int(h * 100.0) % 7
	var out := []
	for k in count:
		var a := Livestock.new()
		a.name = "%s%d_%d_%d_%d" % ["Cow" if cows else "Sheep", key.x, key.y, key.z, k]
		a.kind = Livestock.Kind.COW if cows else Livestock.Kind.SHEEP
		a.gen = _gen
		a.field_center = Vector3(centre.x, 0, centre.y)
		a.field_radius = 32.0
		var ang := TerrainGenerator.hash01(key.y * 7 + k, key.z, 43) * TAU
		var r := TerrainGenerator.hash01(key.y + k, key.z * 3, 44) * 18.0
		var pos := centre + Vector2(cos(ang), sin(ang)) * r
		a.position = Vector3(pos.x, _gen.height(pos.x, pos.y), pos.y)
		add_child(a)
		out.append(a)
	return out
