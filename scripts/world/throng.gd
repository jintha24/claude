class_name Throng
extends Node3D
## The London crowd: hundreds of people walking every pavement beyond the real, thinking
## townsfolk (CityLife, Population), so that a street reads as busy right down to its far
## end. Each walker is one MultiMesh instance of a look's one-piece far body, walked and
## animated entirely on the GPU (assets/characters/crowd.gdshader): no bones, no physics,
## no pathfinding, no CPU per frame. They fade in beyond 13 m (nearer than that it's the
## real people you can talk to, rob or bump into) and out past 150 m.
##
## Where they walk: along the middle of every block's pavements (CityPlan) in the 3 x 3
## chunks round the player, and along straight, clear lines of the navigation mesh in the
## old streets. How many are out follows the hour and the weather (`busy`).

const LOOKS: Array[String] = ["gentleman", "lady", "worker", "ragged", "child", "constable"]
const MESH_DIR := "res://assets/characters/crowd/"
const SHADER := "res://assets/characters/crowd.gdshader"
## Share of each look, by district.
const MIX := {
	"west": [0.3, 0.34, 0.18, 0.03, 0.11, 0.04],
	"city": [0.26, 0.24, 0.28, 0.08, 0.1, 0.04],
	"north": [0.16, 0.28, 0.3, 0.1, 0.13, 0.03],
	"east": [0.06, 0.2, 0.4, 0.2, 0.12, 0.02],
	"south": [0.08, 0.22, 0.38, 0.17, 0.13, 0.02],
	"core": [0.2, 0.28, 0.28, 0.1, 0.11, 0.03],
}
## Which far-body part group each hat code puts on, per look (0 none; 4 top hat,
## 5 bowler, 6 cap, 7 bonnet).
const HATS := {
	"gentleman": Vector4i(4, 4, 5, 0), "lady": Vector4i(0, 7, 7, 0), "worker": Vector4i(0, 6, 6, 6),
	"ragged": Vector4i(0, 6, 6, 0), "child": Vector4i(0, 6, 6, 0), "constable": Vector4i(0, 0, 0, 0),
}
const CELL := 64.0
const BEARDED: Array[String] = ["gentleman", "worker", "ragged", "constable"]
## Metres of pavement per walker (both directions together).
@export var spacing := 1.3
@export var core_spacing := 1.6
@export var player_path: NodePath = ^"../Harry"

var busy := 1.0
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _groups: Dictionary = {} # key -> Node3D holding its MultiMeshInstance3Ds
var _plan: CityPlan
var _player: Node3D
var _timer := 0.0
var _core_done := false


func _ready() -> void:
	add_to_group("throng")
	for look in LOOKS:
		var path := MESH_DIR + look + ".res"
		if ResourceLoader.exists(path):
			_meshes[look] = load(path)
			_materials[look] = _make_material(look)
	var city := get_node_or_null("../City") as CityStreamer
	_plan = city.plan if city else CityPlan.new()


## Starts again (the graphics settings changed how many there should be).
func rebuild() -> void:
	for key: Variant in _groups:
		(_groups[key] as Node).queue_free()
	_groups.clear()
	_core_done = false
	_timer = 0.0


## How many walkers are placed (whether or not the hour has them out).
func walker_count() -> int:
	var n := 0
	for key: Variant in _groups:
		for mmi in (_groups[key] as Node3D).get_children():
			n += (mmi as MultiMeshInstance3D).multimesh.instance_count
	return n


## How many are out walking at this hour.
func out_count() -> int:
	return int(walker_count() * busy)


func group_count() -> int:
	return _groups.size()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	if _meshes.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node3D
		if _player == null:
			_player = get_viewport().get_camera_3d()
			if _player == null:
				return
	_set_busy(_busyness())
	if not _core_done and NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > 0:
		_core_done = true
		_add_core()
	var c := _plan.coord_of(_player.global_position)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := c + Vector2i(dx, dz)
			if not _groups.has(k):
				_add_chunk(k)
	for k: Variant in _groups.keys():
		if k is Vector2i and maxi(absi((k as Vector2i).x - c.x), absi((k as Vector2i).y - c.y)) > 2:
			(_groups[k] as Node).queue_free()
			_groups.erase(k)


## How full the streets are at this hour, in this weather (1 = the busiest).
func _busyness() -> float:
	var h := GameClock.hours()
	var b := 0.85
	if h >= 1.0 and h < 5.0:
		b = 0.08
	elif h < 1.0 or h >= 23.0:
		b = 0.22
	elif h < 7.0:
		b = 0.35
	elif h < 10.0 or (h >= 17.0 and h < 19.5):
		b = 1.0
	elif h >= 19.5:
		b = 0.55
	if Weather.rain > 0.5:
		b *= 0.4
	elif Weather.rain > 0.2:
		b *= 0.7
	if Weather.snow > 0.4:
		b *= 0.55
	if Weather.fog > 0.6:
		b *= 0.8
	return b


func _set_busy(b: float) -> void:
	busy = b
	for look: String in _materials:
		(_materials[look] as ShaderMaterial).set_shader_parameter("busy", b)


# ---------------------------------------------------------------------------
# Where they walk
# ---------------------------------------------------------------------------
## Along the middle of each block's pavements.
func _add_chunk(k: Vector2i) -> void:
	var segs: Array = []
	for bi in _plan.blocks_owned(k):
		var b: Dictionary = _plan.blocks[bi]
		var r: Rect2 = b["rect"]
		if CityPlan.CORE.grow(-2.0).intersects(r):
			continue # the old streets: see _add_core
		var pave: Array = b["pave"]
		var pn := float(pave[CityPlan.Side.N])
		var ps := float(pave[CityPlan.Side.S])
		var pe := float(pave[CityPlan.Side.E])
		var pw := float(pave[CityPlan.Side.W])
		var x0 := r.position.x + pw
		var x1 := r.end.x - pe
		var z0 := r.position.y + pn
		var z1 := r.end.y - ps
		if pn > 0.0:
			segs.append([Vector3(x0, 0, r.position.y + pn * 0.5), Vector3(x1, 0, r.position.y + pn * 0.5), pn])
		if ps > 0.0:
			segs.append([Vector3(x0, 0, r.end.y - ps * 0.5), Vector3(x1, 0, r.end.y - ps * 0.5), ps])
		if pw > 0.0:
			segs.append([Vector3(r.position.x + pw * 0.5, 0, z0), Vector3(r.position.x + pw * 0.5, 0, z1), pw])
		if pe > 0.0:
			segs.append([Vector3(r.end.x - pe * 0.5, 0, z0), Vector3(r.end.x - pe * 0.5, 0, z1), pe])
	for s: Array in segs:
		for i in 2:
			var p: Vector3 = s[i]
			p.y = _plan.ground_y(p.x, p.z)
			s[i] = p
	var rect := _plan.chunk_rect(k)
	var mid := rect.get_center()
	_build(k, segs, _plan.district(mid.x, mid.y), spacing, hash(k))


## The old streets: straight, clear runs of the navigation mesh (so nobody walks through
## a stall or a wall), across the market and along the streets.
func _add_core() -> void:
	var map := get_world_3d().navigation_map
	var rng := RandomNumberGenerator.new()
	rng.seed = 1866
	var core := CityPlan.CORE
	var segs: Array = []
	var axes: Array[Vector3] = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	var diag: Array[Vector3] = [Vector3(1, 0, 1).normalized(), Vector3(-1, 0, -1).normalized(), Vector3(1, 0, -1).normalized(), Vector3(-1, 0, 1).normalized()]
	var market := Rect2(MarketSquare.X0, MarketSquare.Z_NORTH, MarketSquare.X1 - MarketSquare.X0, MarketSquare.Z_SOUTH - MarketSquare.Z_NORTH)
	var in_square := 0
	for attempt in 6000:
		if segs.size() >= 400:
			break
		var p := Vector3(rng.randf_range(core.position.x, core.end.x), 0.2, rng.randf_range(core.position.y, core.end.y))
		var a := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(a.x - p.x, a.z - p.z).length() > 1.0 or absf(a.y) > 0.6:
			continue
		# On the pavements (raised a kerb above the road) and across the market square;
		# in the carriageway only to cross it.
		var on_pave := _ground_at(a) > 0.08
		var in_market := market.has_point(Vector2(a.x, a.z))
		if in_market and in_square >= 140:
			continue # the square has its share; the streets need theirs
		if not on_pave and not in_market and rng.randf() > 0.15:
			continue
		# Along the pavement whichever way it runs; anywhere across the square.
		var tries: Array[Vector3] = axes.duplicate()
		tries.shuffle()
		if in_market:
			tries.append_array(diag)
		for dir in tries:
			var length := rng.randf_range(14.0, 45.0) if on_pave or in_market else rng.randf_range(8.0, 12.0)
			var b := _clear_run(map, a, dir, length, on_pave and not in_market)
			if b != Vector3.INF:
				segs.append([a, b, 1.0])
				in_square += 1 if in_market else 0
				break
			if not on_pave and not in_market:
				break
	_build("core", segs, "core", core_spacing, 1866)


## Where a straight walk from `a` along `dir` ends, if nothing's in the way (and, on a
## pavement, it doesn't step off the kerb); INF if it won't do. Tries shorter if need be.
func _clear_run(map: RID, a: Vector3, dir: Vector3, length: float, keep_to_pave: bool) -> Vector3:
	for shrink: float in [1.0, 0.6, 0.35]:
		var want := a + dir * length * shrink
		if length * shrink < 8.0:
			break
		var b := NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(b.x - want.x, b.z - want.z).length() > 0.4 or absf(b.y - a.y) > 0.3:
			continue
		if keep_to_pave and (_ground_at(b) < 0.08 or _ground_at((a + b) * 0.5) < 0.08):
			continue # would step off the kerb and walk down the road
		var path := NavigationServer3D.map_get_path(map, a, b, true)
		var run := 0.0
		for i in path.size() - 1:
			run += path[i].distance_to(path[i + 1])
		if path.size() < 2 or run > a.distance_to(b) * 1.01 + 0.05:
			continue # something in the way
		return b
	return Vector3.INF


## The height of whatever's underfoot at `p` (pavements stand a kerb above the road).
func _ground_at(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 3.0, p.z), Vector3(p.x, -2.0, p.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


# ---------------------------------------------------------------------------
# The walkers
# ---------------------------------------------------------------------------
func _build(key: Variant, segs: Array, district: String, space: float, seed: int) -> void:
	# Fewer on the lower graphics presets (view distance 4 on Low to 9 on Ultra).
	var vd := float(GameSettings.get_value("graphics/view_distance")) if GameSettings.values.has("graphics/view_distance") else 7.0
	space /= clampf((vd - 3.0) / 4.0, 0.35, 1.25)
	var holder := Node3D.new()
	holder.name = "Crowd_%s" % str(key).replace(",", "_").replace(" ", "").replace("(", "").replace(")", "")
	add_child(holder)
	_groups[key] = holder
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mix: Array = MIX.get(district, MIX["city"])
	# Grouped in 64 m cells, so a cell off-screen or far off is skipped whole.
	var cells: Dictionary = {} # Vector2i -> {look -> [[transform, custom], ...]}
	for s: Array in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var width: float = s[2]
		var length := a.distance_to(b)
		if length < 6.0:
			continue
		var along := (b - a) / length
		var side := along.cross(Vector3.UP)
		var n := int(length / space)
		for i in n:
			var look := _pick(rng, mix)
			if not _meshes.has(look):
				continue
			var back := rng.randf() < 0.5
			var start := b if back else a
			var dir := -along if back else along
			var off := side * rng.randf_range(-1.0, 1.0) * maxf(width * 0.5 - 0.8, 0.15)
			var basis := Basis.looking_at(dir, Vector3.UP)
			var scale := rng.randf_range(0.93, 1.04) * (0.94 if look == "lady" else 1.0)
			var xf := Transform3D(basis.scaled(Vector3.ONE * scale), start + off)
			var speed := rng.randf_range(1.05, 1.55)
			var packed := _pack(rng, look)
			var mid := start + dir * length * 0.5
			var cell := Vector2i(floori(mid.x / CELL), floori(mid.z / CELL))
			if not cells.has(cell):
				cells[cell] = {}
			var by_look: Dictionary = cells[cell]
			if not by_look.has(look):
				by_look[look] = []
			(by_look[look] as Array).append([xf, Color(length, speed, rng.randf() * length, float(packed)), start, start + dir * length])
	for cell: Vector2i in cells:
		var by_look: Dictionary = cells[cell]
		for look: String in by_look:
			_add_multimesh(holder, look, by_look[look])


func _add_multimesh(holder: Node3D, look: String, list: Array) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for w: Array in list:
		lo = lo.min((w[2] as Vector3).min(w[3]))
		hi = hi.max((w[2] as Vector3).max(w[3]))
	# The node sits in the middle of its walkers (the visibility range is measured from it).
	var centre := (lo + hi) * 0.5
	var aabb := AABB(lo - centre - Vector3(2, 1, 2), (hi - lo) + Vector3(4, 4, 4))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _meshes[look]
	mm.instance_count = list.size()
	for i in list.size():
		var xf: Transform3D = list[i][0]
		xf.origin -= centre
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, list[i][1])
	mm.custom_aabb = aabb
	var mmi := MultiMeshInstance3D.new()
	mmi.name = look
	mmi.multimesh = mm
	mmi.material_override = _materials[look]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# (The walkers fade out by 150 m: don't even run the shader for a far block.)
	mmi.visibility_range_end = 190.0
	holder.add_child(mmi)
	mmi.position = centre


func _pick(rng: RandomNumberGenerator, mix: Array) -> String:
	var r := rng.randf()
	for i in mix.size():
		r -= float(mix[i])
		if r <= 0.0:
			return LOOKS[i]
	return LOOKS[0]


## See crowd.gdshader for the bits.
func _pack(rng: RandomNumberGenerator, look: String) -> int:
	var need := rng.randi_range(0, 62)
	var prim := rng.randi() % 16
	var sec := rng.randi() % 8
	var legs := rng.randi() % 8
	var skin := 0 if rng.randf() < 0.55 else (1 if rng.randf() < 0.7 else (2 if rng.randf() < 0.8 else 3))
	var hair := rng.randi() % 4
	var hat := rng.randi() % 4
	var beard := 0
	if look in BEARDED and rng.randf() < 0.6:
		beard = 1 + rng.randi() % 3
	return need | (prim << 6) | (sec << 10) | (legs << 13) | (skin << 16) | (hair << 18) | (hat << 20) | (beard << 22)


func _make_material(look: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	var pal: Dictionary = CharacterLook.PALETTES.get(look, {})
	var tone := CharacterLook.CLOTH_TONE
	var fallback: Array = [Color(0.25, 0.22, 0.2), Color(0.3, 0.28, 0.24), Color(0.2, 0.2, 0.2), Color(0.28, 0.24, 0.18)]
	var prim := _list(pal, ["coat", "dress", "cassock", "greatcoat"], fallback)
	var sec := _list(pal, ["waistcoat", "shawl"], [Color(0.3, 0.3, 0.3)])
	var legs := _list(pal, ["trousers", "dress"], [Color(0.2, 0.2, 0.2)])
	m.set_shader_parameter("primary", _vecs(prim, 16, tone))
	m.set_shader_parameter("secondary", _vecs(sec, 8, tone))
	m.set_shader_parameter("legs", _vecs(legs, 8, tone))
	var hat := _list(pal, ["hat", "cap", "helmet", "bonnet"], [Color(0.05, 0.05, 0.05)])
	m.set_shader_parameter("hat_col", Vector3(hat[0].r, hat[0].g, hat[0].b) * tone)
	var lin := _list(pal, ["shirt", "collar"], [Color(0.9, 0.88, 0.84)])
	m.set_shader_parameter("linen", Vector3(lin[0].r, lin[0].g, lin[0].b) * tone)
	var acc := _list(pal, ["cravat", "trim", "buttons", "badge"], [Color(0.4, 0.1, 0.1)])
	m.set_shader_parameter("accent", Vector3(acc[0].r, acc[0].g, acc[0].b) * tone)
	m.set_shader_parameter("hat_group", HATS.get(look, Vector4i.ZERO))
	return m


func _list(pal: Dictionary, slots: Array, fallback: Array) -> Array:
	for s: String in slots:
		if pal.has(s):
			return pal[s]
	return fallback


func _vecs(cols: Array, n: int, tone: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var c: Color = cols[i % cols.size()]
		out.append(Vector3(c.r, c.g, c.b) * tone)
	return out
