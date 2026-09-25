class_name MeshBuilder
extends RefCounted
## Merges many small primitive shapes into ONE mesh with one surface per material.
##
## A building is made of hundreds of pieces (bricks walls, sills, frames, glazing bars).
## Drawing each as its own MeshInstance3D would cost hundreds of draw calls; merging them
## here keeps a whole building at roughly one draw call per material.

var _tools: Dictionary = {} # material -> SurfaceTool


func add_box(size: Vector3, center: Vector3, material: Material, basis: Basis = Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	add_mesh(mesh, Transform3D(basis, center), material)


func add_cylinder(radius_bottom: float, radius_top: float, height: float, center: Vector3, material: Material, segments: int = 12, basis: Basis = Basis.IDENTITY) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius_bottom
	mesh.top_radius = radius_top
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	add_mesh(mesh, Transform3D(basis, center), material)


## Adds a flat rectangle (PlaneMesh: X = width, Z = depth, facing +Y before `basis`).
func add_plane(size: Vector2, center: Vector3, material: Material, basis: Basis = Basis.IDENTITY) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	add_mesh(mesh, Transform3D(basis, center), material)


func add_mesh(mesh: Mesh, xform: Transform3D, material: Material) -> void:
	var st: SurfaceTool = _tools.get(material)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[material] = st
	for surface in mesh.get_surface_count():
		st.append_from(mesh, surface, xform)


func is_empty() -> bool:
	return _tools.is_empty()


## Builds the final mesh. Returns null if nothing was added.
func build() -> ArrayMesh:
	if _tools.is_empty():
		return null
	var array_mesh := ArrayMesh.new()
	for material: Material in _tools:
		var st: SurfaceTool = _tools[material]
		st.index()
		st.set_material(material)
		st.commit(array_mesh)
	return array_mesh


static var _shadow_one_sided: StandardMaterial3D
static var _shadow_two_sided: StandardMaterial3D


## A position-only copy of `mesh` in (at most) two surfaces, drawn only into shadow maps:
## one draw call per shadow cascade instead of one per material. Glass
## casts none; meshes with cut-out surfaces (leaves) keep their own shadows.
static func shadow_mesh_for(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() < 2:
		return null
	var groups := [[PackedVector3Array(), PackedInt32Array()], [PackedVector3Array(), PackedInt32Array()]]
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i) as BaseMaterial3D
		if mat == null or mat.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH]:
			return null # cut-out leaves and lace need their own shadows
		if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue # window glass: no shadow
		var g: Array = groups[1 if mat.cull_mode == BaseMaterial3D.CULL_DISABLED else 0]
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base: int = (g[0] as PackedVector3Array).size()
		(g[0] as PackedVector3Array).append_array(verts)
		if idx.is_empty():
			idx = PackedInt32Array(range(verts.size()))
		var shifted := PackedInt32Array()
		shifted.resize(idx.size())
		for k in idx.size():
			shifted[k] = idx[k] + base
		(g[1] as PackedInt32Array).append_array(shifted)
	if _shadow_one_sided == null:
		_shadow_one_sided = StandardMaterial3D.new()
		_shadow_two_sided = StandardMaterial3D.new()
		_shadow_two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	var out := ArrayMesh.new()
	for gi in 2:
		var g: Array = groups[gi]
		if (g[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g[0]
		arr[Mesh.ARRAY_INDEX] = g[1]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, _shadow_two_sided if gi == 1 else _shadow_one_sided)
	return out


## Convenience: builds the mesh into a new MeshInstance3D child of `parent`.
func build_into(parent: Node3D, node_name: String, cast_shadows: bool = true) -> MeshInstance3D:
	var mesh := build()
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if cast_shadows and mesh.get_surface_count() >= 3:
		# Shadows from a merged copy: one or two draw calls per shadow cascade instead of
		# one per material (a building has ten or so).
		var proxy := shadow_mesh_for(mesh)
		if proxy:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var caster := MeshInstance3D.new()
			caster.name = "ShadowCaster"
			caster.mesh = proxy
			caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			mi.add_child(caster)
	return mi
