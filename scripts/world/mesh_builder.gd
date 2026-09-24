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
	return mi
