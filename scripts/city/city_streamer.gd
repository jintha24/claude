class_name CityStreamer
extends Node3D
## Builds Greater London (CityPlan) around the player, 128 m square chunks at a time.
##
## Each chunk is built as plain data on a worker thread (CityBuilder) and turned into nodes
## here, a little per frame. Detail by distance (in chunks from the player's chunk):
##   0 (<= 1): full detail, collision, navigation, gas lamps, shop signs, pipes to climb
##   1 (<= 2): simpler buildings, no collision
##   2 (<= 4): masses, roofs and windows
## Beyond that the whole city is one MultiMesh of terrace blocks (a draw call or two), with
## the blocks of loaded chunks hidden so the two never overlap.

signal chunk_ready(coord: Vector2i, lod: int)

@export var target_path: NodePath
@export var city_seed: int = 1866
@export var near_radius: int = 1
@export var mid_radius: int = 2
@export var far_radius: int = 4
@export var integrate_per_frame: int = 1
@export var max_tasks: int = 1

var plan: CityPlan

var _chunks := {} # Vector2i -> {"node": Node3D, "lod": int, "doors": Array}
var _pending := {} # Vector2i -> lod
var _results: Array[Dictionary] = []
var _mutex := Mutex.new()
var _tasks: Array[int] = []
var _target: Node3D
var _materials := {}
var _distant: MultiMeshInstance3D
var _distant_rows := {} # Vector2i -> PackedInt32Array of instance indices
var _distant_xf: Array[Transform3D] = []
var _last_center := Vector2i(1 << 30, 0)
var _rescan := 0.0
var _lamp_post: Mesh
var _lamp_glass: Mesh
var _lamp_mat: StandardMaterial3D
var _dark := false
var _nav_region: NavigationRegion3D
var _nav_center := Vector2i(1 << 30, 0)
var _nav_task := -1
var _nav_data := {}
var _dark_check := 0.0

static var _hidden_basis := Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001))


func _ready() -> void:
	add_to_group("city_streamer")
	plan = CityPlan.new(city_seed)
	_target = get_node_or_null(target_path) as Node3D
	_make_lamp_meshes()
	_build_distant()
	var landmarks := CityLandmarks.new()
	landmarks.name = "Landmarks"
	add_child(landmarks)
	var river := CityRiver.new()
	river.name = "Thames"
	river.plan = plan
	add_child(river)
	_build_boundary()
	# The navigation map joins the chunks' meshes (and the old streets') edge to edge.
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_edge_connection_margin(map, 1.0)


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
	if _nav_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_nav_task)
		_nav_task = -1


func coord_of(p: Vector3) -> Vector2i:
	return plan.coord_of(p)


func chunk_lod(c: Vector2i) -> int:
	var e: Dictionary = _chunks.get(c, {})
	return -1 if e.is_empty() else int(e["lod"])


func loaded_count() -> int:
	return _chunks.size()


## Door markers ([position, kind]) of the fully built chunks, for CityLife.
func near_doors() -> Array:
	var out := []
	for c: Vector2i in _chunks:
		var e: Dictionary = _chunks[c]
		if int(e["lod"]) == 0:
			out.append_array(e["doors"])
	return out


func is_detailed_at(p: Vector3) -> bool:
	return chunk_lod(coord_of(p)) == 0


## Builds the chunks round `p` at once, on this thread (loading a save, arriving).
func prime(p: Vector3) -> void:
	_update_in_core(p)
	var center := coord_of(p)
	for dz in range(-near_radius, near_radius + 1):
		for dx in range(-near_radius, near_radius + 1):
			var c := center + Vector2i(dx, dz)
			if _in_range(c):
				_integrate(CityBuilder.build_chunk(plan, c, _lod_for(c, center)))
	_nav_now(center)


## Builds every chunk in view of `p` at its proper detail at once, on this thread (for
## loading screens, tests and screenshots: a few seconds).
func build_all_now(p: Vector3) -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()
	_pending.clear()
	_update_in_core(p)
	var center := coord_of(p)
	for c: Vector2i in _chunks.keys():
		if maxi(absi(c.x - center.x), absi(c.y - center.y)) > far_radius:
			(_chunks[c]["node"] as Node).queue_free()
			_chunks.erase(c)
			_show_distant(c, true)
	# Build the chunks' data on every worker thread at once, then turn it into nodes.
	var todo: Array[Vector2i] = []
	for dz in range(-far_radius, far_radius + 1):
		for dx in range(-far_radius, far_radius + 1):
			var c := center + Vector2i(dx, dz)
			if _in_range(c) and chunk_lod(c) != _lod_for(c, center):
				todo.append(c)
	var built: Array = []
	built.resize(todo.size())
	var group := WorkerThreadPool.add_group_task(func(i: int) -> void:
		built[i] = CityBuilder.build_chunk(plan, todo[i], _lod_for(todo[i], center)), todo.size())
	WorkerThreadPool.wait_for_group_task_completion(group)
	for data: Dictionary in built:
		_integrate(data)
	_last_center = center
	_nav_now(center)


func _nav_now(center: Vector2i) -> void:
	if _nav_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_nav_task)
		_nav_task = -1
	_nav_center = center
	_apply_nav(CityBuilder.nav_area(plan, center, near_radius))


func _in_range(c: Vector2i) -> bool:
	var r := plan.chunk_rect(c)
	return r.intersects(Rect2(-CityPlan.HALF, -CityPlan.HALF, CityPlan.HALF * 2.0, CityPlan.HALF * 2.0))


## True while the player is well inside the old streets, walled in by their buildings:
## the city round about is only seen over the rooftops then, so nothing needs its full
## detail (collision, lamps, signs) until he comes near the edge.
var _in_core := false


func _update_in_core(p: Vector3) -> void:
	_in_core = CityPlan.CORE.grow(-8.0).has_point(Vector2(p.x, p.z))


func _lod_for(c: Vector2i, center: Vector2i) -> int:
	var d := maxi(absi(c.x - center.x), absi(c.y - center.y))
	if d <= near_radius:
		return 1 if _in_core else 0
	if d <= mid_radius:
		return 1
	return 2


func _process(delta: float) -> void:
	_update_lamps(delta)
	if _target == null or not is_instance_valid(_target):
		_target = get_node_or_null(target_path) as Node3D
		if _target == null:
			var cam := get_viewport().get_camera_3d()
			if cam == null:
				return
			_target = cam
	var center := coord_of(_target.global_position)
	var was_in_core := _in_core
	_update_in_core(_target.global_position)
	if was_in_core != _in_core:
		_rescan = 0.0
	_update_nav(center)
	_mutex.lock()
	var ready: Array[Dictionary] = []
	for i in mini(integrate_per_frame, _results.size()):
		ready.append(_results.pop_front())
	_mutex.unlock()
	for data in ready:
		var c: Vector2i = data["coord"]
		_pending.erase(c)
		var dist := maxi(absi(c.x - center.x), absi(c.y - center.y))
		if dist <= far_radius and _lod_for(c, center) == int(data["lod"]):
			_integrate(data)
	var running: Array[int] = []
	for t in _tasks:
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			running.append(t)
	var freed := running.size() < _tasks.size()
	_tasks = running
	_rescan -= delta
	if center == _last_center and ready.is_empty() and not freed and _rescan > 0.0:
		return
	_last_center = center
	_rescan = 0.5
	var wanted: Array[Vector2i] = []
	for dz in range(-far_radius, far_radius + 1):
		for dx in range(-far_radius, far_radius + 1):
			var c := center + Vector2i(dx, dz)
			if not _in_range(c):
				continue
			var lod := _lod_for(c, center)
			var have: Dictionary = _chunks.get(c, {})
			if (have.is_empty() or int(have["lod"]) != lod) and not (_pending.has(c) and _pending[c] == lod):
				wanted.append(c)
	# Nearest first; the detailed ring before anything else.
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - center).length_squared() < (b - center).length_squared())
	for c in wanted:
		if _tasks.size() >= max_tasks:
			break
		var lod := _lod_for(c, center)
		_pending[c] = lod
		_tasks.append(WorkerThreadPool.add_task(_generate_task.bind(c, lod)))
	for c: Vector2i in _chunks.keys():
		if maxi(absi(c.x - center.x), absi(c.y - center.y)) > far_radius + 1:
			(_chunks[c]["node"] as Node).queue_free()
			_chunks.erase(c)
			_show_distant(c, true)


func _generate_task(c: Vector2i, lod: int) -> void:
	var data := CityBuilder.build_chunk(plan, c, lod)
	_mutex.lock()
	_results.append(data)
	_mutex.unlock()


# ---------------------------------------------------------------------------
# Turning chunk data into nodes (main thread)
# ---------------------------------------------------------------------------
func _integrate(data: Dictionary) -> void:
	var c: Vector2i = data["coord"]
	var lod := int(data["lod"])
	if _chunks.has(c):
		(_chunks[c]["node"] as Node).queue_free()
		_chunks.erase(c)
	var node := Node3D.new()
	node.name = "Chunk_%d_%d_L%d" % [c.x, c.y, lod]
	add_child(node)
	var mesh := ArrayMesh.new()
	var surfaces: Dictionary = data["surfaces"]
	for key: String in surfaces:
		var s: Array = surfaces[key]
		if (s[0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_TEX_UV] = s[2]
		arrays[Mesh.ARRAY_INDEX] = s[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(key))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.add_child(mi)
	var sh: Array = data["shadow"]
	if lod <= 1 and not (sh[0] as PackedVector3Array).is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = sh[0]
		arrays[Mesh.ARRAY_INDEX] = sh[1]
		var smesh := ArrayMesh.new()
		smesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		smesh.surface_set_material(0, _shadow_material())
		var caster := MeshInstance3D.new()
		caster.name = "ShadowCaster"
		caster.mesh = smesh
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		node.add_child(caster)
	var occ: Array = data["occluder"]
	var occ_v: PackedVector3Array = occ[0]
	if not occ_v.is_empty():
		var ao := ArrayOccluder3D.new()
		ao.set_arrays(occ_v, occ[1])
		var oi := OccluderInstance3D.new()
		oi.name = "Occluder"
		oi.occluder = ao
		node.add_child(oi)
	if lod == 0:
		_add_collision(node, data)
		_add_labels(node, data)
		_add_pipes(node, data)
	_add_lamps(node, data, lod)
	_add_trees(node, data, lod)
	_chunks[c] = {"node": node, "lod": lod, "doors": data["doors"] if lod == 0 else []}
	_show_distant(c, false)
	chunk_ready.emit(c, lod)


func _add_collision(node: Node3D, data: Dictionary) -> void:
	for part: Array in [["solid", "stone"], ["roofs", "slate"]]:
		var faces: PackedVector3Array = data[part[0]]
		if faces.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "Solid" if part[0] == "solid" else "Roofs"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", part[1])
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		node.add_child(body)


## One navigation mesh for the detailed chunks round the player, rebuilt on a worker
## thread whenever he moves into another chunk (see CityBuilder.nav_area).
func _update_nav(center: Vector2i) -> void:
	if _nav_task >= 0:
		if not WorkerThreadPool.is_task_completed(_nav_task):
			return
		WorkerThreadPool.wait_for_task_completion(_nav_task)
		_nav_task = -1
		_mutex.lock()
		var data := _nav_data
		_nav_data = {}
		_mutex.unlock()
		if not data.is_empty():
			_apply_nav(data)
	if center != _nav_center and _nav_task < 0:
		_nav_center = center
		_nav_task = WorkerThreadPool.add_task(func() -> void:
			var d := CityBuilder.nav_area(plan, center, near_radius)
			_mutex.lock()
			_nav_data = d
			_mutex.unlock())


func _apply_nav(nav: Dictionary) -> void:
	if _nav_region == null:
		_nav_region = NavigationRegion3D.new()
		_nav_region.name = "Nav"
		_nav_region.use_edge_connections = false
		add_child(_nav_region)
	var nm := NavigationMesh.new()
	nm.cell_size = ProjectSettings.get_setting("navigation/3d/default_cell_size", 0.25)
	nm.cell_height = ProjectSettings.get_setting("navigation/3d/default_cell_height", 0.25)
	nm.vertices = nav["verts"]
	for p: PackedInt32Array in nav["polys"]:
		nm.add_polygon(p)
	_nav_region.navigation_mesh = nm


func _add_labels(node: Node3D, data: Dictionary) -> void:
	for l: Array in data["labels"]:
		var label := Label3D.new()
		label.text = l[0]
		label.font_size = 72
		label.outline_size = 6
		label.outline_modulate = Color(0.1, 0.07, 0.03)
		label.modulate = Color(0.93, 0.76, 0.42)
		label.shaded = true
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		var est := String(l[0]).length() * 72.0 * 0.62
		label.pixel_size = minf(0.0045, float(l[2]) / est)
		label.transform = l[1]
		label.visibility_range_end = 45.0
		node.add_child(label)


func _add_pipes(node: Node3D, data: Dictionary) -> void:
	for p: Array in data["pipes"]:
		var body := StaticBody3D.new()
		body.name = "Drainpipe"
		body.collision_layer = 1 << 4
		body.collision_mask = 0
		body.add_to_group("climbable_pipe")
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.06
		cyl.height = float(p[1])
		cs.shape = cyl
		body.add_child(cs)
		body.position = p[0]
		node.add_child(body)


func _add_lamps(node: Node3D, data: Dictionary, lod: int) -> void:
	var lamps: Array = data["lamps"]
	if lamps.is_empty():
		return
	if lod == 0:
		# Real gas lamps: lit by the lamplighter, light for the stealth system, collision.
		for p: Vector3 in lamps:
			var lamp := GasLamp.new()
			lamp.casts_shadows = false
			lamp.position = p
			node.add_child(lamp)
		return
	for part: Array in [[_lamp_post, "Posts"], [_lamp_glass, "Lanterns"]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = lamps.size()
		for i in lamps.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, lamps[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mmi.name = part[1]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)


func _add_trees(node: Node3D, data: Dictionary, lod: int) -> void:
	var trees: Array = data["trees"]
	if trees.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = TreeMeshes.get_mesh(0, lod >= 1)
	mm.instance_count = trees.size()
	for i in trees.size():
		var t: Array = trees[i]
		var s: float = t[1]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, t[2]).scaled(Vector3(s, s, s)), t[0]))
	var mmi := MultiMeshInstance3D.new()
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.name = "Trees"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mmi)
	if lod == 0:
		# Trunks to bump into.
		var body := StaticBody3D.new()
		body.name = "Trunks"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", "wood")
		for t: Array in trees:
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.35 * float(t[1])
			cyl.height = 4.0
			cs.shape = cyl
			cs.position = (t[0] as Vector3) + Vector3(0, 2.0, 0)
			body.add_child(cs)
		node.add_child(body)


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
## The material for a key used by CityBuilder.
func material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var mat: Material
	if key.begins_with("paint"):
		mat = MaterialLibrary.get_tinted("wood_painted", CityBuilder.PAINT_COLORS[int(key.substr(5))])
	elif key.begins_with("awning"):
		var awn: Array[Color] = [Color(0.45, 0.1, 0.08), Color(0.12, 0.25, 0.15), Color(0.15, 0.18, 0.35), Color(0.5, 0.42, 0.25)]
		mat = MaterialLibrary.get_tinted("wood_painted", awn[int(key.substr(6))])
	else:
		match key:
			"white":
				mat = MaterialLibrary.get_tinted("wood_painted", BuildingFacade.WINDOW_WHITE)
			"slate":
				mat = _metric("slate_roof")
			"cobble":
				mat = _metric("cobblestone")
			"ridge":
				mat = MaterialLibrary.get_tinted("stone_trim", Color(0.35, 0.33, 0.32))
			"stucco_trim":
				mat = MaterialLibrary.get_tinted("stucco", Color(0.97, 0.95, 0.9))
			"stone_church":
				mat = MaterialLibrary.get_tinted("stone_trim", Color(0.86, 0.84, 0.78))
			"stone_grave":
				mat = MaterialLibrary.get_tinted("stone_trim", Color(0.6, 0.6, 0.58))
			"yard":
				mat = MaterialLibrary.get_tinted("dirt", Color(0.62, 0.58, 0.52))
			"flags":
				mat = MaterialLibrary.get_tinted("pavement", Color(0.92, 0.9, 0.86))
			"lead":
				mat = MaterialLibrary.get_tinted("stone_trim", Color(0.3, 0.31, 0.33))
			"wood_dark":
				mat = MaterialLibrary.get_tinted("wood_planks", Color(0.4, 0.3, 0.22))
			"rope":
				mat = MaterialLibrary.get_tinted("wood_planks", Color(0.55, 0.45, 0.3))
			"bronze":
				var b := StandardMaterial3D.new()
				b.albedo_color = Color(0.22, 0.2, 0.14)
				b.metallic = 0.8
				b.roughness = 0.45
				mat = b
			"city_lamp":
				mat = _lamp_mat
			_:
				mat = MaterialLibrary.get_material(key)
	_materials[key] = mat
	return mat


## A copy of a UV-mapped material for UVs given in metres.
func _metric(key: String) -> StandardMaterial3D:
	var src := MaterialLibrary.get_material(key)
	var mat := src.duplicate() as StandardMaterial3D
	var tile: Vector2 = src.get_meta("tile_size", Vector2.ONE)
	mat.uv1_scale = Vector3(1.0 / tile.x, 1.0 / tile.y, 1.0)
	mat.resource_name = key # still dampened by rain (MaterialLibrary.set_wetness)
	MaterialLibrary.register(key + "@metric", mat)
	return mat


static var _shadow_mat: StandardMaterial3D


func _shadow_material() -> StandardMaterial3D:
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shadow_mat


# ---------------------------------------------------------------------------
# Lamps seen from afar: a post and a lantern that glows after dark
# ---------------------------------------------------------------------------
func _make_lamp_meshes() -> void:
	var iron := MaterialLibrary.get_material("iron")
	var mb := MeshBuilder.new()
	mb.add_cylinder(0.14, 0.12, 0.5, Vector3(0, 0.25, 0), iron, 6)
	mb.add_cylinder(0.07, 0.055, 2.6, Vector3(0, 1.8, 0), iron, 6)
	mb.add_box(Vector3(0.7, 0.035, 0.035), Vector3(0, 2.85, 0), iron)
	mb.add_cylinder(0.3, 0.06, 0.2, Vector3(0, GasLamp.LANTERN_HEIGHT + 0.36, 0), iron, 4)
	_lamp_post = mb.build()
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.25, 0.22, 0.18)
	_lamp_mat.roughness = 0.2
	_lamp_mat.emission = Color(1.0, 0.68, 0.36)
	_lamp_mat.emission_energy_multiplier = 5.0
	var glass := CylinderMesh.new()
	glass.top_radius = 0.24
	glass.bottom_radius = 0.14
	glass.height = 0.5
	glass.radial_segments = 4
	glass.rings = 1
	var gmb := MeshBuilder.new()
	gmb.add_mesh(glass, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, GasLamp.LANTERN_HEIGHT, 0)), _lamp_mat)
	_lamp_glass = gmb.build()


func _update_lamps(delta: float) -> void:
	_dark_check -= delta
	if _dark_check > 0.0:
		return
	_dark_check = 1.0
	var dn := get_tree().get_first_node_in_group("day_night")
	var dark := false
	if dn and dn.has_method("is_dark"):
		dark = dn.call("is_dark")
	if dark != _dark or not _lamp_mat.emission_enabled == dark:
		_dark = dark
		_lamp_mat.emission_enabled = dark
		_lamp_mat.albedo_color = Color(1.0, 0.85, 0.6) if dark else Color(0.25, 0.22, 0.18)


# ---------------------------------------------------------------------------
# The distant city: every terrace as one box in a MultiMesh
# ---------------------------------------------------------------------------
func _build_distant() -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tones := {
		"brick_yellow": Color(0.62, 0.53, 0.39), "brick_red": Color(0.5, 0.27, 0.2), "stucco": Color(0.86, 0.83, 0.75),
	}
	for b: Dictionary in plan.blocks:
		var rows := plan.distant_rows(b)
		if rows.is_empty():
			continue
		var r: Rect2 = b["rect"]
		var owner := plan.coord_of(Vector3(r.get_center().x, 0, r.get_center().y))
		var st := plan._style(b["district"])
		var walls: Array = st[7]
		var ids: PackedInt32Array = _distant_rows.get(owner, PackedInt32Array())
		for row: Array in rows:
			ids.append(xforms.size())
			xforms.append(row[0])
			var wall: String = walls[int(CityPlan.hash01(int(b["seed"]), xforms.size(), 3) * walls.size())]
			colors.append((tones[wall] as Color) * (0.85 + CityPlan.hash01(int(b["seed"]), xforms.size(), 4) * 0.25))
		_distant_rows[owner] = ids
	_distant_xf = xforms
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _terrace_unit_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	_distant = MultiMeshInstance3D.new()
	_distant.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_distant.name = "DistantCity"
	_distant.multimesh = mm
	_distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_distant.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_distant)


func _show_distant(c: Vector2i, show: bool) -> void:
	if not _distant_rows.has(c):
		return
	var mm := _distant.multimesh
	for i in _distant_rows[c]:
		var xf := _distant_xf[i]
		if not show:
			xf = Transform3D(_hidden_basis, xf.origin)
		mm.set_instance_transform(i, xf)


## A unit terrace block (1 x 1 x 1, origin at the ground centre, facade to +Z): walls tinted
## per instance, rows of windows on the long faces, a slate roof and chimney stacks.
func _terrace_unit_mesh() -> ArrayMesh:
	var walls := StandardMaterial3D.new()
	walls.vertex_color_use_as_albedo = true
	walls.albedo_color = Color.WHITE
	walls.roughness = 0.95
	var slate := StandardMaterial3D.new()
	slate.albedo_color = Color(0.25, 0.27, 0.3)
	slate.roughness = 0.7
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(1.0, 1.0, 1.0), Vector3(0, 0.5, 0), walls)
	for side: float in [-1.0, 1.0]:
		for floor_y: float in [0.22, 0.47, 0.72]:
			mb.add_box(Vector3(0.94, 0.09, 0.01), Vector3(0.0, floor_y, side * 0.502), MaterialLibrary.get_material("glass_%d" % (int(floor_y * 10.0) % 3)))
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.16
	var pts := [Vector3(-0.5, 1.0, -0.52), Vector3(0.5, 1.0, -0.52), Vector3(0.5, 1.0 + r, 0.0), Vector3(-0.5, 1.0 + r, 0.0), Vector3(-0.5, 1.0, 0.52), Vector3(0.5, 1.0, 0.52)]
	for tri: Array in [[0, 2, 1], [0, 3, 2], [4, 5, 2], [4, 2, 3]]:
		for k: int in tri:
			roof.add_vertex(pts[k])
	roof.generate_normals()
	mb.add_mesh(roof.commit(), Transform3D.IDENTITY, slate)
	return mb.build()


## Invisible walls round the city's edge (the river leaves it under a low bridge-arch
## that nobody can reach).
func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "CityLimits"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var h := CityPlan.HALF
	for spec: Array in [[Vector3(h * 2.0 + 4.0, 40.0, 2.0), Vector3(0, 10.0, -h - 1.0)], [Vector3(h * 2.0 + 4.0, 40.0, 2.0), Vector3(0, 10.0, h + 1.0)],
			[Vector3(2.0, 40.0, h * 2.0 + 4.0), Vector3(-h - 1.0, 10.0, 0)], [Vector3(2.0, 40.0, h * 2.0 + 4.0), Vector3(h + 1.0, 10.0, 0)]]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[0]
		cs.shape = box
		cs.position = spec[1]
		body.add_child(cs)
