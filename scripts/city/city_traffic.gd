class_name CityTraffic
extends Node3D
## Horse-drawn traffic on London's main roads (CityPlan's road lines): cabs, growlers,
## carts, brewers' drays and omnibuses, keeping to the left, turning at the junctions,
## queueing behind each other. Kept up round the player (busiest by day), let go when far.

@export var streamer_path: NodePath = NodePath("../City")
@export var player_path: NodePath = NodePath("../Harry")
@export var max_vehicles: int = 18

const LANE := 2.4
const SPAWN_MIN := 70.0
const SPAWN_MAX := 230.0
const LET_GO := 300.0

var _streamer: CityStreamer
var _player: Node3D
var _plan: CityPlan
var _vehicles: Array[HorseVehicle] = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _count := 0


func _ready() -> void:
	add_to_group("city_traffic")
	_rng.seed = 1866


func vehicle_count() -> int:
	return _vehicles.size()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	if _streamer == null:
		_streamer = get_node_or_null(streamer_path) as CityStreamer
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node3D
	if _streamer == null or _player == null or _streamer.plan == null:
		return
	_plan = _streamer.plan
	var p := _player.global_position
	for v in _vehicles.duplicate():
		if not is_instance_valid(v):
			_vehicles.erase(v)
		elif v.global_position.distance_to(p) > LET_GO:
			_vehicles.erase(v)
			v.queue_free()
	var want := _wanted()
	for k in 2:
		if _vehicles.size() < want:
			_spawn(p)


func _wanted() -> int:
	var h := GameClock.hours()
	var f := 1.0
	if h < 5.0 or h >= 23.5:
		f = 0.15
	elif h < 7.0 or h >= 21.0:
		f = 0.45
	f *= 1.0 - Weather.snow * 0.5 - Weather.fog * 0.3
	# Deep in the old streets the main roads are out of sight: only a few about.
	if _player and CityPlan.CORE.grow(-8.0).has_point(Vector2(_player.global_position.x, _player.global_position.z)):
		f *= 0.25
	return int(round(max_vehicles * f))


# ---------------------------------------------------------------------------
# The road grid
# ---------------------------------------------------------------------------
func _node_ok(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < _plan.xs.size() and j < _plan.zs.size()


func _node_pos(i: int, j: int) -> Vector3:
	return Vector3(_plan.xs[i], 0.0, _plan.zs[j])


## Can you drive from junction (i, j) one step in direction `d` (0 N, 1 E, 2 S, 3 W)?
func _edge_ok(i: int, j: int, d: int) -> bool:
	var ni: int = i + [0, 1, 0, -1][d]
	var nj: int = j + [-1, 0, 1, 0][d]
	if not _node_ok(ni, nj):
		return false
	var a := _node_pos(i, j)
	var b := _node_pos(ni, nj)
	var mid := (a + b) * 0.5
	if CityPlan.CORE.has_point(Vector2(mid.x, mid.z)):
		return false
	# Across the river only on the bridges.
	var z0 := minf(a.z, b.z)
	var z1 := maxf(a.z, b.z)
	if z0 < CityPlan.RIVER_Z0 and z1 > CityPlan.RIVER_Z1:
		return _plan.bridges.has(_plan.xs[i])
	return true


func _nearest(lines: PackedFloat32Array, v: float) -> int:
	var best := 0
	for k in lines.size():
		if absf(lines[k] - v) < absf(lines[best] - v):
			best = k
	return best


func _dir_vec(d: int) -> Vector3:
	return [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][d]


## Left of travel (they keep to the left in England).
func _left(dir: Vector3) -> Vector3:
	return Vector3(dir.z, 0.0, -dir.x)


func _spawn(p: Vector3) -> void:
	# Junctions round the player (the main roads are ~200 m apart).
	var ci := _nearest(_plan.xs, p.x)
	var cj := _nearest(_plan.zs, p.z)
	for attempt in 16:
		var i := clampi(ci + _rng.randi_range(-2, 1), 0, _plan.xs.size() - 1)
		var j := clampi(cj + _rng.randi_range(-2, 1), 0, _plan.zs.size() - 1)
		var d := _rng.randi() % 4
		if not _edge_ok(i, j, d):
			continue
		var a := _node_pos(i, j)
		var b := _node_pos(i + [0, 1, 0, -1][d], j + [-1, 0, 1, 0][d])
		var t := _rng.randf_range(0.2, 0.8)
		var dir := _dir_vec(d)
		var at := a.lerp(b, t) + _left(dir) * LANE
		var dist := Vector2(at.x - p.x, at.z - p.z).length()
		if dist < SPAWN_MIN or dist > SPAWN_MAX:
			continue
		# Not on top of another vehicle.
		var clear := true
		for v in _vehicles:
			if v.global_position.distance_to(at) < 14.0:
				clear = false
		if not clear:
			continue
		var v := HorseVehicle.new()
		_count += 1
		v.name = "Vehicle%d" % _count
		var r := _rng.randf()
		v.kind = HorseVehicle.Kind.HANSOM if r < 0.34 else (HorseVehicle.Kind.GROWLER if r < 0.52 else (HorseVehicle.Kind.CART if r < 0.72 else (HorseVehicle.Kind.DRAY if r < 0.84 else HorseVehicle.Kind.OMNIBUS)))
		v.cruise = _rng.randf_range(3.2, 5.0) if v.kind in [HorseVehicle.Kind.HANSOM, HorseVehicle.Kind.GROWLER] else _rng.randf_range(2.4, 3.4)
		v.driver_outfit = NPCBody.Outfit.GENTLEMAN if _rng.randf() < 0.25 else NPCBody.Outfit.WORKER
		v.set_meta("node", Vector2i(i + [0, 1, 0, -1][d], j + [-1, 0, 1, 0][d]))
		v.set_meta("dir", d)
		add_child(v)
		v.place(at, dir)
		v.waypoints.append(b - dir * 7.0 + _left(dir) * LANE)
		v.needs_waypoints.connect(_route_on)
		_vehicles.append(v)
		return


## At the junction ahead, choose the next road (seldom back the way it came) and add the
## turn and the next stretch to the vehicle's waypoints.
func _route_on(v: HorseVehicle) -> void:
	if not v.has_meta("node") or v.waypoints.size() >= 3:
		return
	var n: Vector2i = v.get_meta("node")
	var d_in: int = v.get_meta("dir")
	var options: Array[int] = []
	for d in 4:
		if d == (d_in + 2) % 4:
			continue
		if _edge_ok(n.x, n.y, d):
			options.append(d)
			if d == d_in:
				options.append(d) # straight on is likelier
	if options.is_empty():
		options.append((d_in + 2) % 4)
	var d_out: int = options[_rng.randi() % options.size()]
	var c := _node_pos(n.x, n.y)
	var din := _dir_vec(d_in)
	var dout := _dir_vec(d_out)
	# A smooth turn through the junction on the left-hand side.
	var p0 := c - din * 7.0 + _left(din) * LANE
	var p2 := c + dout * 7.0 + _left(dout) * LANE
	var p1 := c + (_left(din) + _left(dout)) * LANE * 0.5 if d_out != d_in else c + _left(din) * LANE
	if d_out == (d_in + 2) % 4:
		p1 = c + din * 4.0
	for k in range(1, 5):
		var t := k / 4.0
		v.waypoints.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	var nn := Vector2i(n.x + [0, 1, 0, -1][d_out], n.y + [-1, 0, 1, 0][d_out])
	v.waypoints.append(_node_pos(nn.x, nn.y) - dout * 7.0 + _left(dout) * LANE)
	v.set_meta("node", nn)
	v.set_meta("dir", d_out)
