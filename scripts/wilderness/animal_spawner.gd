class_name AnimalSpawner
extends Node3D
## Keeps the hills alive around the player: a few herds of red deer and scattered rabbits
## within a few hundred metres, spawned out of sight (80-170 m away) on grass, never on
## the road, water or steep ground, and removed again when he's far off.

@export var deer_herds: int = 3
@export var rabbits: int = 8
@export var spawn_min: float = 80.0
@export var spawn_max: float = 170.0
@export var despawn_distance: float = 300.0

var _streamer: WorldStreamer
var _timer := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 2.0
	if _streamer == null:
		_streamer = get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _streamer == null or player == null:
		return
	var p := player.global_position
	var deer := 0
	var bunnies := 0
	var herds_seen := {}
	for n in get_children():
		var a := n as WildAnimal
		if a == null:
			continue
		if a.global_position.distance_to(p) > despawn_distance:
			a.queue_free()
			continue
		if a.species == WildAnimal.Species.DEER:
			if not a.is_dead():
				herds_seen[a.get_meta("herd", 0)] = true
		elif not a.is_dead():
			bunnies += 1
	deer = herds_seen.size()
	if deer < deer_herds:
		spawn_herd(_find_spot(p), _rng.randi_range(3, 6))
	if bunnies < rabbits:
		spawn_rabbit(_find_spot(p))


func _find_spot(around: Vector3) -> Vector3:
	var gen := _streamer.generator
	for i in 12:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(spawn_min, spawn_max)
		var x := around.x + cos(a) * d
		var z := around.z + sin(a) * d
		if absf(x) > TerrainGenerator.HALF_SIZE - 160.0 or absf(z) > TerrainGenerator.HALF_SIZE - 160.0:
			continue
		if gen.is_water(x, z) or gen.road_info(x, z).x < 10.0 or gen.normal(x, z, 2.0).y < 0.8:
			continue
		return Vector3(x, gen.height(x, z), z)
	return Vector3.INF


## Spawns a herd of hinds (and sometimes a stag) grazing round `center`.
func spawn_herd(center: Vector3, count: int) -> Array[WildAnimal]:
	var out: Array[WildAnimal] = []
	if _streamer == null:
		_streamer = get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	if center == Vector3.INF:
		return out
	var herd_id := _rng.randi()
	for i in count:
		var a := WildAnimal.new()
		a.species = WildAnimal.Species.DEER
		a.is_stag = i == 0 and _rng.randf() < 0.4
		a.set_meta("herd", herd_id)
		a.position = center + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-6.0, 6.0))
		add_child(a)
		a.setup(_streamer, center)
		out.append(a)
	for a in out:
		a.herd = out
	return out


func spawn_rabbit(at: Vector3) -> WildAnimal:
	if at == Vector3.INF:
		return null
	if _streamer == null:
		_streamer = get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	var a := WildAnimal.new()
	a.species = WildAnimal.Species.RABBIT
	a.position = at
	add_child(a)
	a.setup(_streamer, at)
	var alone: Array[WildAnimal] = [a]
	a.herd = alone
	return a
