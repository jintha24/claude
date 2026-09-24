class_name WorldStreamer
extends Node3D
## Streams the hills around the player in 64 m square chunks.
##
## Each chunk's ground mesh, collision heights and the positions of its trees, rocks and
## grass are worked out on background threads (WorkerThreadPool), then turned into nodes
## on the main thread a couple per frame, so the game never stutters.
##
## Three levels of detail by distance (in chunks from the player's chunk):
##   0 (<= near_grass): 1 m ground grid with collision, detailed trees with solid trunks,
##     boulders, and grass tufts that sway in the wind
##   1 (<= near_radius): the same without grass
##   2 (<= far_radius): a 4 m grid and simple trees, no collision (it's too far to reach)
## Chunks beyond far_radius + 1 are freed.

signal chunk_ready(coord: Vector2i, lod: int)

@export var target_path: NodePath
@export var world_seed: int = 1866
@export var chunk_size: float = 64.0
@export var near_grass: int = 1
@export var near_radius: int = 2
@export var far_radius: int = 7
## Results turned into nodes per frame (spreads the main-thread cost).
@export var integrate_per_frame: int = 2
@export var max_tasks: int = 4

## Main-thread generator, for gameplay queries (height, water, road).
var generator: TerrainGenerator

var _chunks := {} # Vector2i -> {"node": Node3D, "lod": int}
var _pending := {} # Vector2i -> lod
var _results: Array[Dictionary] = []
var _mutex := Mutex.new()
var _target: Node3D
var _terrain_mat: ShaderMaterial
var _water: MeshInstance3D
var _tasks: Array[int] = []


func _ready() -> void:
	add_to_group("world_streamer")
	generator = TerrainGenerator.new(world_seed)
	_terrain_mat = _make_terrain_material()
	TreeMeshes.prepare()
	_target = get_node_or_null(target_path) as Node3D
	_build_water()


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


## Height of the ground at (x, z) (in the hills' coordinates).
func height_at(x: float, z: float) -> float:
	return generator.height(x, z)


func coord_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / chunk_size), floori(p.z / chunk_size))


## Builds the chunks with collision around `p` immediately, on this thread (loading and
## spawning: nothing to stand on otherwise).
func prime(p: Vector3) -> void:
	var c := coord_of(p)
	for dz in range(-near_radius, near_radius + 1):
		for dx in range(-near_radius, near_radius + 1):
			var cc := c + Vector2i(dx, dz)
			var lod := _lod_for(cc, c)
			var data := _generate(cc, lod, generator)
			_integrate(data)


## True once the ground under and around `p` is solid.
func is_ready_around(p: Vector3) -> bool:
	var c := coord_of(p)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var e: Dictionary = _chunks.get(c + Vector2i(dx, dz), {})
			if e.is_empty() or int(e["lod"]) > 1:
				return false
	return true


func loaded_count() -> int:
	return _chunks.size()


func chunk_lod(c: Vector2i) -> int:
	var e: Dictionary = _chunks.get(c, {})
	return -1 if e.is_empty() else int(e["lod"])


func _lod_for(c: Vector2i, center: Vector2i) -> int:
	var d := maxi(absi(c.x - center.x), absi(c.y - center.y))
	if d <= near_grass:
		return 0
	if d <= near_radius:
		return 1
	return 2


func _process(_delta: float) -> void:
	if _target == null:
		_target = get_node_or_null(target_path) as Node3D
		if _target == null:
			return
	var center := coord_of(_target.global_position)
	# Collect finished work.
	_mutex.lock()
	var ready: Array[Dictionary] = []
	var n := mini(integrate_per_frame, _results.size())
	for i in n:
		ready.append(_results.pop_front())
	_mutex.unlock()
	for data in ready:
		_pending.erase(data["coord"])
		var want := _lod_for(data["coord"], center)
		var dist := maxi(absi(data["coord"].x - center.x), absi(data["coord"].y - center.y))
		if dist <= far_radius and want == int(data["lod"]):
			_integrate(data)
	var running: Array[int] = []
	for t in _tasks:
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			running.append(t)
	_tasks = running
	# Queue what's missing or at the wrong detail, nearest first.
	var wanted: Array[Vector2i] = []
	for dz in range(-far_radius, far_radius + 1):
		for dx in range(-far_radius, far_radius + 1):
			var c := center + Vector2i(dx, dz)
			if absf(c.x * chunk_size) > TerrainGenerator.HALF_SIZE + chunk_size or absf(c.y * chunk_size) > TerrainGenerator.HALF_SIZE + chunk_size:
				continue
			var lod := _lod_for(c, center)
			var have: Dictionary = _chunks.get(c, {})
			if (have.is_empty() or int(have["lod"]) != lod) and not (_pending.has(c) and _pending[c] == lod):
				wanted.append(c)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - center).length_squared() < (b - center).length_squared())
	for c in wanted:
		if _tasks.size() >= max_tasks:
			break
		var lod := _lod_for(c, center)
		_pending[c] = lod
		_tasks.append(WorkerThreadPool.add_task(_generate_task.bind(c, lod)))
	# Free what's far away.
	for c: Vector2i in _chunks.keys():
		if maxi(absi(c.x - center.x), absi(c.y - center.y)) > far_radius + 1:
			(_chunks[c]["node"] as Node).queue_free()
			_chunks.erase(c)


func _generate_task(c: Vector2i, lod: int) -> void:
	var data := _generate(c, lod, TerrainGenerator.new(world_seed))
	_mutex.lock()
	_results.append(data)
	_mutex.unlock()


# ---------------------------------------------------------------------------
# Generation (any thread): pure data, no nodes
# ---------------------------------------------------------------------------
func _generate(c: Vector2i, lod: int, gen: TerrainGenerator) -> Dictionary:
	var step := 1.0 if lod <= 1 else 4.0
	var res := int(chunk_size / step)
	var x0 := c.x * chunk_size
	var z0 := c.y * chunk_size
	# Heights on a grid with a one-cell border (for normals).
	var hs := PackedFloat32Array()
	var w := res + 3
	hs.resize(w * w)
	for j in w:
		for i in w:
			hs[j * w + i] = gen.height(x0 + (i - 1) * step, z0 + (j - 1) * step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := res + 1
	for j in n:
		for i in n:
			var h := hs[(j + 1) * w + (i + 1)]
			var x := i * step
			var z := j * step
			verts.append(Vector3(x, h, z))
			var hx := hs[(j + 1) * w + i + 2] - hs[(j + 1) * w + i]
			var hz := hs[(j + 2) * w + i + 1] - hs[j * w + i + 1]
			norms.append(Vector3(-hx, 2.0 * step, -hz).normalized())
			var road := 1.0 - smoothstep(TerrainGenerator.ROAD_HALF_WIDTH - 0.5, TerrainGenerator.ROAD_HALF_WIDTH + 1.5, gen.road_info(x0 + x, z0 + z).x)
			cols.append(Color(road, 0.0, 0.0))
	for j in res:
		for i in res:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	# Skirts round the edge hide cracks between chunks of different detail.
	var edge: Array[int] = []
	for i in n:
		edge.append(i)
	for j in range(1, n):
		edge.append(j * n + res)
	for i in range(res - 1, -1, -1):
		edge.append(res * n + i)
	for j in range(res - 1, 0, -1):
		edge.append(j * n)
	edge.append(0)
	var base := verts.size()
	for k in edge.size():
		var v := verts[edge[k]]
		verts.append(v - Vector3(0, 3.0, 0))
		norms.append(norms[edge[k]])
		cols.append(cols[edge[k]])
	for k in edge.size() - 1:
		var a := edge[k]
		var b := edge[k + 1]
		var sa := base + k
		var sb := base + k + 1
		idx.append_array([a, sa, b, b, sa, sb])
	var data := {"coord": c, "lod": lod, "verts": verts, "norms": norms, "cols": cols, "idx": idx}
	if lod <= 1:
		var col := PackedFloat32Array()
		col.resize(n * n)
		for j in n:
			for i in n:
				col[j * n + i] = hs[(j + 1) * w + (i + 1)]
		data["collision"] = col
		data["res"] = res
	_scatter(data, c, lod, gen)
	return data


## Trees, boulders and grass: positions from a jittered grid and hashes (deterministic).
func _scatter(data: Dictionary, c: Vector2i, lod: int, gen: TerrainGenerator) -> void:
	var x0 := c.x * chunk_size
	var z0 := c.y * chunk_size
	var trees: Array = []
	var rocks: Array = []
	var cell := 8.0
	var cells := int(chunk_size / cell)
	for j in cells:
		for i in cells:
			var gx := c.x * cells + i
			var gz := c.y * cells + j
			var px := x0 + (i + TerrainGenerator.hash01(gx, gz, 1)) * cell
			var pz := z0 + (j + TerrainGenerator.hash01(gx, gz, 2)) * cell
			var f := gen.forest(px, pz)
			var r := TerrainGenerator.hash01(gx, gz, 3)
			var nrm := gen.normal(px, pz, 1.5)
			if nrm.y < 0.8:
				if r < 0.08 and nrm.y > 0.55:
					rocks.append([Vector3(px - x0, gen.height(px, pz) - 0.3, pz - z0), 0.6 + r * 10.0])
				continue
			if r < f * 0.75 + 0.03:
				var kind := 1 if TerrainGenerator.hash01(gx, gz, 4) < 0.35 + 0.4 * smoothstep(60.0, 95.0, gen.height(px, pz)) else 0
				var scale := 0.75 + TerrainGenerator.hash01(gx, gz, 5) * 0.6
				trees.append([Vector3(px - x0, gen.height(px, pz) - 0.1, pz - z0), kind, scale, TerrainGenerator.hash01(gx, gz, 6) * TAU])
			elif r > 0.985 and not gen.is_water(px, pz) and gen.road_info(px, pz).x > 6.0:
				rocks.append([Vector3(px - x0, gen.height(px, pz) - 0.3, pz - z0), 0.5 + TerrainGenerator.hash01(gx, gz, 7) * 1.1])
	data["trees"] = trees
	data["rocks"] = rocks if lod <= 1 else []
	if lod == 0:
		var grass := PackedVector3Array()
		var gcell := 1.6
		var gn := int(chunk_size / gcell)
		for j in gn:
			for i in gn:
				var gx := c.x * gn + i
				var gz := c.y * gn + j
				if TerrainGenerator.hash01(gx, gz, 11) > 0.55:
					continue
				var px := x0 + (i + TerrainGenerator.hash01(gx, gz, 12)) * gcell
				var pz := z0 + (j + TerrainGenerator.hash01(gx, gz, 13)) * gcell
				if gen.is_water(px, pz) or gen.road_info(px, pz).x < TerrainGenerator.ROAD_HALF_WIDTH + 0.5 or TerrainGenerator.CAVE_FLOOR.grow(1.0).has_point(Vector2(px, pz)):
					continue
				grass.append(Vector3(px - x0, gen.height(px, pz), pz - z0))
		data["grass"] = grass


# ---------------------------------------------------------------------------
# Integration (main thread): nodes
# ---------------------------------------------------------------------------
func _integrate(data: Dictionary) -> void:
	var c: Vector2i = data["coord"]
	var lod := int(data["lod"])
	if _chunks.has(c):
		(_chunks[c]["node"] as Node).queue_free()
		_chunks.erase(c)
	var node := Node3D.new()
	node.name = "Chunk_%d_%d_L%d" % [c.x, c.y, lod]
	node.position = Vector3(c.x * chunk_size, 0.0, c.y * chunk_size)
	add_child(node)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["verts"]
	arrays[Mesh.ARRAY_NORMAL] = data["norms"]
	arrays[Mesh.ARRAY_COLOR] = data["cols"]
	arrays[Mesh.ARRAY_INDEX] = data["idx"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod <= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	if lod <= 1:
		var body := StaticBody3D.new()
		body.name = "Solid"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", "grass")
		node.add_child(body)
		var res := int(data["res"])
		var shape := HeightMapShape3D.new()
		shape.map_width = res + 1
		shape.map_depth = res + 1
		shape.map_data = data["collision"]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(chunk_size * 0.5, 0.0, chunk_size * 0.5)
		cs.scale = Vector3(chunk_size / res, 1.0, chunk_size / res)
		body.add_child(cs)
		for t: Array in data["trees"]:
			var tc := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.28 * float(t[2])
			cyl.height = 4.0
			tc.shape = cyl
			tc.position = (t[0] as Vector3) + Vector3(0, 2.0, 0)
			body.add_child(tc)
		for r: Array in data["rocks"]:
			var rc := CollisionShape3D.new()
			var sph := SphereShape3D.new()
			sph.radius = float(r[1])
			rc.shape = sph
			rc.position = r[0]
			body.add_child(rc)
		_add_rocks(node, data["rocks"])
	_add_trees(node, data["trees"], lod)
	if lod == 0 and data.has("grass"):
		_add_grass(node, data["grass"])
	_chunks[c] = {"node": node, "lod": lod}
	chunk_ready.emit(c, lod)


func _add_trees(node: Node3D, trees: Array, lod: int) -> void:
	for kind in 2:
		var xforms: Array[Transform3D] = []
		for t: Array in trees:
			if int(t[1]) != kind:
				continue
			var s := float(t[2])
			xforms.append(Transform3D(Basis(Vector3.UP, float(t[3])).scaled(Vector3(s, s, s)), t[0]))
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = TreeMeshes.get_mesh(kind, lod >= 2)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees%d" % kind
		mmi.multimesh = mm
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod <= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)


func _add_rocks(node: Node3D, rocks: Array) -> void:
	if rocks.is_empty():
		return
	var mb := MeshBuilder.new()
	var stone := MaterialLibrary.get_material("rock")
	for r: Array in rocks:
		var s := SphereMesh.new()
		s.radius = float(r[1])
		s.height = float(r[1]) * 1.3
		s.radial_segments = 9
		s.rings = 5
		mb.add_mesh(s, Transform3D(Basis(Vector3.UP, float(r[1]) * 3.0), r[0]), stone)
	mb.build_into(node, "Rocks").gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _add_grass(node: Node3D, grass: PackedVector3Array) -> void:
	if grass.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = TreeMeshes.grass_tuft()
	mm.instance_count = grass.size()
	for i in grass.size():
		var a := float(i * 2.39996)
		var s := 0.8 + fmod(float(i) * 0.618, 0.6)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a).scaled(Vector3(s, s, s)), grass[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.add_child(mmi)


# ---------------------------------------------------------------------------
func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(TerrainGenerator.LAKE_RADIUS * 4.0, TerrainGenerator.LAKE_RADIUS * 4.0)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.16, 0.16, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.04
	mat.metallic = 0.2
	mat.metallic_specular = 0.8
	_water = MeshInstance3D.new()
	_water.name = "Lake"
	_water.mesh = plane
	_water.material_override = mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.position = Vector3(TerrainGenerator.LAKE.x, TerrainGenerator.WATER_Y, TerrainGenerator.LAKE.y)
	add_child(_water)


func _make_terrain_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float water_y = 24.0;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float slope = 1.0 - wnrm.y;
	vec3 g = texture(grass_tex, wpos.xz / 3.0).rgb;
	vec3 g2 = texture(grass_tex, wpos.xz / 17.0).rgb;
	g = mix(g, g2 * vec3(1.05, 1.0, 0.8), 0.35); // break up the tiling
	vec3 d = texture(dirt_tex, wpos.xz / 2.5).rgb;
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 r = texture(rock_tex, wpos.zy / 4.0).rgb * bw.x + texture(rock_tex, wpos.xz / 4.0).rgb * bw.y + texture(rock_tex, wpos.xy / 4.0).rgb * bw.z;
	vec3 c = mix(g, d, COLOR.r);
	float shore = 1.0 - smoothstep(water_y + 0.2, water_y + 1.4, wpos.y);
	c = mix(c, d * 0.75, shore);
	c = mix(c, r, smoothstep(0.26, 0.42, slope));
	ALBEDO = c;
	ROUGHNESS = mix(0.92, 0.75, shore);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("grass_tex", MaterialLibrary.get_material("grass").albedo_texture)
	mat.set_shader_parameter("dirt_tex", MaterialLibrary.get_material("dirt").albedo_texture)
	mat.set_shader_parameter("rock_tex", MaterialLibrary.get_material("rock").albedo_texture)
	mat.set_shader_parameter("water_y", TerrainGenerator.WATER_Y)
	return mat
