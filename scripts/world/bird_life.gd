class_name BirdLife
extends Node3D
## Birds round the player: flocks of pigeons and starlings wheeling over the rooftops, gulls
## over the river, rooks over the hills - and pigeons (or rooks in the fields) pecking on
## the ground, which clatter up into the air when someone comes too close and settle again
## a little way off. Each flock is one MultiMesh (a single draw call); the wings flap in
## the vertex shader.

@export var player_path: NodePath = NodePath("../Harry")
## "city" or "hills": which birds, and where they land.
@export var place: String = "city"
@export var flying_flocks: int = 4
@export var ground_flocks: int = 5

const GROUND_REACH := 70.0
const SCARE := 6.5

var _player: Node3D
var _flocks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _frame := 0
var _height_fn: Callable
var _plan: CityPlan

static var _bird_mesh: ArrayMesh
static var _shader: Shader


func _ready() -> void:
	add_to_group("bird_life")
	_rng.seed = 1866 + (0 if place == "city" else 7)


## For the hills: ground height at (x, z).
func set_height_fn(fn: Callable) -> void:
	_height_fn = fn


func flock_count() -> int:
	return _flocks.size()


func birds_in_air() -> int:
	var n := 0
	for f in _flocks:
		if f["state"] != "ground":
			n += int(f["count"])
	return n


func _ground_y(x: float, z: float) -> float:
	if _height_fn.is_valid():
		return _height_fn.call(x, z)
	if _plan:
		return _plan.ground_y(x, z)
	return 0.0


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node3D
		if _player == null:
			return
	if _plan == null and place == "city":
		var city := get_tree().get_first_node_in_group("city_streamer") as CityStreamer
		if city:
			_plan = city.plan
	var p := _player.global_position
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_manage(p)
	var t := Time.get_ticks_msec() * 0.001
	_frame += 1
	for f in _flocks:
		# Distant flocks are moved every other frame.
		var c: Vector3 = f["center"]
		if f["state"] == "flying" and c.distance_squared_to(p) > 150.0 * 150.0 and _frame % 2 == 0:
			continue
		_update_flock(f, p, delta * (2.0 if f["state"] == "flying" and c.distance_squared_to(p) > 150.0 * 150.0 else 1.0), t)


func _manage(p: Vector3) -> void:
	# Let go of flocks far away.
	for f in _flocks.duplicate():
		var c: Vector3 = f["center"]
		if Vector2(c.x - p.x, c.z - p.z).length() > (420.0 if f["kind"] == "flying" else 140.0):
			(f["node"] as Node).queue_free()
			_flocks.erase(f)
	var night := GameClock.hours() < 5.5 or GameClock.hours() > 20.5
	var flying := 0
	var ground := 0
	for f in _flocks:
		if f["kind"] == "flying":
			flying += 1
		else:
			ground += 1
	var weather := 1.0 - Weather.rain * 0.7 - Weather.fog * 0.5
	if not night and flying < int(flying_flocks * weather + 0.5):
		_spawn_flying(p)
	if not night and ground < int(ground_flocks * maxf(weather, 0.4) + 0.5):
		_spawn_ground(p)


func _material(color: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 color : source_color = vec3(0.3);
void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2832;
	float fly = INSTANCE_CUSTOM.y;
	float beat = sin(TIME * mix(3.0, 15.0, INSTANCE_CUSTOM.z) + phase);
	float x = abs(VERTEX.x);
	if (x > 0.05) {
		float side = sign(VERTEX.x);
		float span = (x - 0.05) * mix(0.18, 1.0, fly);
		float ang = beat * 0.85 * fly + (1.0 - fly) * -0.2;
		VERTEX.x = side * (0.05 + span * cos(ang));
		VERTEX.y += span * sin(ang) + (1.0 - fly) * 0.02;
	}
	// On the ground, the head bobs as they peck.
	if (fly < 0.5 && VERTEX.z < -0.1) {
		VERTEX.y -= max(sin(TIME * 5.0 + phase * 3.0), 0.0) * 0.06;
	}
}
void fragment() {
	ALBEDO = color;
	ROUGHNESS = 0.85;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("color", color)
	return m


static func _mesh() -> ArrayMesh:
	if _bird_mesh:
		return _bird_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body: an elongated diamond; head at -Z; wings: flat, from the shoulders out.
	var tri := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	var nose := Vector3(0, 0.02, -0.2)
	var tail := Vector3(0, 0.0, 0.2)
	var top := Vector3(0, 0.07, 0.0)
	var bot := Vector3(0, -0.05, 0.0)
	var l := Vector3(-0.05, 0.01, 0.0)
	var r := Vector3(0.05, 0.01, 0.0)
	for pair: Array in [[top, l], [l, bot], [bot, r], [r, top]]:
		tri.call(nose, pair[0], pair[1])
		tri.call(tail, pair[1], pair[0])
	# Wings.
	for s: float in [-1.0, 1.0]:
		var sh := Vector3(0.05 * s, 0.02, -0.04)
		var sh2 := Vector3(0.05 * s, 0.02, 0.07)
		var tip := Vector3(0.36 * s, 0.02, 0.06)
		var mid := Vector3(0.22 * s, 0.02, 0.1)
		tri.call(sh, tip, sh2)
		tri.call(sh2, tip, mid)
	st.generate_normals()
	_bird_mesh = st.commit()
	return _bird_mesh


func _make_node(count: int, color: Color, scale: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh()
	mm.instance_count = count
	for i in count:
		mm.set_instance_custom_data(i, Color(_rng.randf(), 1.0, 0.8, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.multimesh = mm
	mmi.material_override = _material(color)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set_meta("scale", scale)
	# The flock's bounds move with it; keep it from being culled by a stale box.
	mmi.custom_aabb = AABB(Vector3(-400, -100, -400), Vector3(800, 300, 800))
	add_child(mmi)
	return mmi


func _kind_colors() -> Array:
	if place == "hills":
		return [[Color(0.05, 0.05, 0.06), 1.15, "rooks"], [Color(0.18, 0.15, 0.12), 0.7, "starlings"]]
	return [[Color(0.32, 0.34, 0.4), 1.0, "pigeons"], [Color(0.12, 0.11, 0.12), 0.7, "starlings"], [Color(0.85, 0.86, 0.86), 1.5, "gulls"]]


func _spawn_flying(p: Vector3) -> void:
	var kinds := _kind_colors()
	var k: Array = kinds[_rng.randi() % kinds.size()]
	var count := _rng.randi_range(8, 22) if k[2] != "gulls" else _rng.randi_range(4, 9)
	var center := p + Vector3(_rng.randf_range(-250, 250), 0, _rng.randf_range(-250, 250))
	if k[2] == "gulls" and place == "city":
		center = Vector3(p.x + _rng.randf_range(-200, 200), 0, (CityPlan.RIVER_Z0 + CityPlan.RIVER_Z1) * 0.5)
	center.y = _ground_y(center.x, center.z) + _rng.randf_range(28.0, 55.0)
	var node := _make_node(count, k[0], k[1])
	var offsets: Array[Vector3] = []
	for i in count:
		offsets.append(Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-3, 3), _rng.randf_range(-9, 9)))
	_flocks.append({
		"kind": "flying", "state": "flying", "node": node, "count": count, "center": center,
		"anchor": center, "radius": _rng.randf_range(50.0, 130.0), "speed": _rng.randf_range(0.08, 0.16) * (1.0 if _rng.randf() < 0.5 else -1.0),
		"angle": _rng.randf() * TAU, "offsets": offsets, "scale": k[1],
	})


func _ground_spot(p: Vector3) -> Vector3:
	for attempt in 12:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(22.0, GROUND_REACH)
		var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
		if place == "city":
			if _plan == null or not _plan.in_city(q) or CityPlan.CORE.grow(-5.0).has_point(Vector2(q.x, q.z)):
				continue
			if _plan.is_river(q.x, q.z):
				continue
			# On a road or a pavement, not inside a building.
			var inside := false
			for i in _plan.blocks_overlapping(_plan.coord_of(q)):
				var b: Dictionary = _plan.blocks[i]
				if b["kind"] in [CityPlan.Kind.TERRACE, CityPlan.Kind.FILL, CityPlan.Kind.WAREHOUSE, CityPlan.Kind.INFILL, CityPlan.Kind.CHURCH] and _plan.lot_rect(b).has_point(Vector2(q.x, q.z)):
					inside = true
			if inside:
				continue
		q.y = _ground_y(q.x, q.z)
		return q
	return Vector3.INF


func _spawn_ground(p: Vector3) -> void:
	var at := _ground_spot(p)
	if at == Vector3.INF:
		return
	var kinds := _kind_colors()
	var k: Array = kinds[0]
	var count := _rng.randi_range(6, 16)
	var node := _make_node(count, k[0], k[1])
	var offsets: Array[Vector3] = []
	for i in count:
		offsets.append(Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5)))
	var f := {
		"kind": "ground", "state": "ground", "node": node, "count": count, "center": at, "offsets": offsets,
		"timer": 0.0, "scale": k[1], "yaw": [], "vel": Vector3.ZERO,
	}
	var yaws: Array[float] = []
	for i in count:
		yaws.append(_rng.randf() * TAU)
	f["yaw"] = yaws
	_set_flap(f, 0.0)
	_flocks.append(f)


func _set_flap(f: Dictionary, fly: float) -> void:
	var mm := (f["node"] as MultiMeshInstance3D).multimesh
	for i in int(f["count"]):
		var c := mm.get_instance_custom_data(i)
		mm.set_instance_custom_data(i, Color(c.r, fly, 0.8 if fly > 0.5 else 0.2, 0.0))


func _update_flock(f: Dictionary, p: Vector3, delta: float, t: float) -> void:
	var mm := (f["node"] as MultiMeshInstance3D).multimesh
	var s: float = f["scale"]
	var offsets: Array = f["offsets"]
	match f["state"]:
		"flying":
			# Wheel round the anchor, rising and falling a little.
			f["angle"] = float(f["angle"]) + float(f["speed"]) * delta
			var a: float = f["angle"]
			var r: float = f["radius"]
			var anchor: Vector3 = f["anchor"]
			var c := anchor + Vector3(cos(a) * r, sin(a * 2.3) * 6.0, sin(a) * r)
			var dir := Vector3(-sin(a), 0.0, cos(a)) * signf(float(f["speed"]))
			f["center"] = c
			var basis := Basis.looking_at(dir, Vector3.UP).scaled(Vector3(s, s, s))
			for i in int(f["count"]):
				var o: Vector3 = offsets[i]
				var wob := Vector3(sin(t * 0.7 + i), sin(t * 1.1 + i * 2.0) * 0.6, cos(t * 0.9 + i * 1.7))
				mm.set_instance_transform(i, Transform3D(basis, c + o + wob))
		"ground":
			var c: Vector3 = f["center"]
			var scared := Vector2(p.x - c.x, p.z - c.z).length() < SCARE
			if not scared:
				for v in get_tree().get_nodes_in_group("vehicles"):
					if (v as Node3D).global_position.distance_to(c) < 6.0:
						scared = true
			if scared:
				# Clatter up and away from the danger.
				var away := Vector3(c.x - p.x, 0.0, c.z - p.z).normalized()
				if away == Vector3.ZERO:
					away = Vector3.FORWARD
				f["vel"] = away * 7.0 + Vector3(0, 5.0, 0)
				f["state"] = "up"
				f["timer"] = _rng.randf_range(5.0, 9.0)
				_set_flap(f, 1.0)
				return
			if Engine.get_process_frames() % 10 == 0:
				var yaws: Array = f["yaw"]
				for i in int(f["count"]):
					if _rng.randf() < 0.15:
						yaws[i] = float(yaws[i]) + _rng.randf_range(-1.0, 1.0)
					var o: Vector3 = offsets[i]
					mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaws[i]).scaled(Vector3(s, s, s)), c + o + Vector3(0, 0.07 * s, 0)))
		"up":
			f["timer"] = float(f["timer"]) - delta
			var vel: Vector3 = f["vel"]
			vel.y = move_toward(vel.y, 0.5, delta * 1.5)
			f["vel"] = vel
			var c: Vector3 = f["center"] + vel * delta
			f["center"] = c
			var basis := Basis.looking_at(Vector3(vel.x, 0, vel.z).normalized(), Vector3.UP).scaled(Vector3(s, s, s))
			for i in int(f["count"]):
				var o: Vector3 = offsets[i]
				mm.set_instance_transform(i, Transform3D(basis, c + o * 1.6 + Vector3(0, o.x * 0.3, 0)))
			if float(f["timer"]) <= 0.0:
				# Settle somewhere else nearby.
				var spot := _ground_spot(p)
				if spot == Vector3.INF:
					f["timer"] = 2.0
					return
				f["center"] = spot
				f["state"] = "ground"
				_set_flap(f, 0.0)
