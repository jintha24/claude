class_name DrainCover
extends Interactable
## A heavy cast-iron sewer or drain cover. Lifting it takes a few seconds and scrapes
## loudly; after that the shaft below is open.

@export var cover_name: String = "drain cover"
@export var radius: float = 0.4
@export var lift_seconds: float = 2.5
@export var is_open: bool = false

var _body: StaticBody3D
var _mesh: Node3D


func _ready() -> void:
	interact_range = 1.8
	_body = StaticBody3D.new()
	_body.name = "Cover"
	# On the props layer: people can walk on it, but the navmesh leaves a hole for the shaft.
	_body.collision_layer = 1 << 3
	_body.collision_mask = 0
	_body.set_meta("surface", "metal")
	add_child(_body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius * 2.2, 0.06, radius * 2.2)
	cs.shape = box
	cs.position = Vector3(0, -0.03, 0)
	_body.add_child(cs)
	var mb := MeshBuilder.new()
	var iron := MaterialLibrary.get_material("iron")
	mb.add_cylinder(radius, radius, 0.04, Vector3(0, -0.02, 0), iron, 20)
	for i in 5:
		mb.add_box(Vector3(radius * 1.7, 0.012, 0.035), Vector3(0, 0.004, -radius * 0.6 + i * radius * 0.3), iron)
	_mesh = mb.build_into(self, "CoverMesh")
	if is_open:
		_set_open()


func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.1


func get_prompt(_harry: Harry) -> String:
	return "" if is_open else "Lift the %s" % cover_name


func interact(harry: Harry) -> void:
	if is_open:
		return
	harry.interaction.begin_hold(self, "Lifting the %s" % cover_name, lift_seconds, func() -> void:
		_set_open()
		Stealth.make_noise(global_position, 9.0, "iron_scrape", true, harry), 4.0)


func _set_open() -> void:
	is_open = true
	_body.collision_layer = 0
	_mesh.position = Vector3(radius * 2.4, 0.0, 0.2)
	_mesh.rotation.y = 0.4
