class_name Livestock
extends CharacterBody3D
## Sheep and cattle grazing the village pastures (FarmAnimals keeps flocks round the
## player). They drift about their field with their heads down, look up at a noise, and
## trot away from anyone who runs at them - but they are a farmer's, not game.

enum Kind { SHEEP, COW }

var kind: Kind = Kind.SHEEP
var field_center := Vector3.ZERO
var field_radius := 30.0
var gen: TerrainGenerator

var _yaw := 0.0
var _target := Vector3.ZERO
var _timer := 0.0
var _visual: Node3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()

static var _meshes := {}


func _ready() -> void:
	add_to_group("livestock")
	collision_layer = 1 << 2
	collision_mask = 0
	_rng.seed = hash(name) ^ int(field_center.x * 13.0 + field_center.z)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35 if kind == Kind.SHEEP else 0.5
	cap.height = 1.2 if kind == Kind.SHEEP else 2.2
	cs.shape = cap
	cs.rotation.x = PI * 0.5
	cs.position = Vector3(0, 0.55 if kind == Kind.SHEEP else 0.9, 0)
	add_child(cs)
	_visual = MeshInstance3D.new()
	(_visual as MeshInstance3D).mesh = _mesh(kind, _rng.randi() % 3)
	(_visual as MeshInstance3D).visibility_range_end = 260.0
	add_child(_visual)
	_yaw = _rng.randf() * TAU
	_timer = _rng.randf_range(1.0, 8.0)
	_target = global_position


func _physics_process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(global_position) if cam else 0.0
	if d > 140.0 and Engine.get_physics_frames() % 6 != 0:
		return
	var step := delta * (6.0 if d > 140.0 else 1.0)
	_t += step
	_timer -= step
	var harry := get_tree().get_first_node_in_group("player") as Node3D
	var speed := 0.0
	var to := _target - global_position
	to.y = 0.0
	# Someone running at them: trot off the other way.
	if harry and harry.global_position.distance_to(global_position) < 7.0 and (harry as CharacterBody3D).velocity.length() > 3.5:
		var away := global_position - harry.global_position
		away.y = 0.0
		_target = global_position + away.normalized() * 10.0
		_timer = 6.0
		to = _target - global_position
		to.y = 0.0
	if to.length() > 0.5:
		speed = 1.6 if _timer > 4.0 and to.length() > 5.0 else 0.5
		var dir := to.normalized()
		_yaw = rotate_toward(_yaw, atan2(dir.x, dir.z), 2.0 * step)
		global_position += Vector3(sin(_yaw), 0, cos(_yaw)) * speed * step
	elif _timer <= 0.0:
		_timer = _rng.randf_range(4.0, 14.0)
		var a := _rng.randf() * TAU
		_target = field_center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.0, field_radius)
	if gen:
		global_position.y = gen.height(global_position.x, global_position.z)
	_visual.rotation.y = _yaw
	# Heads down grazing; a small bob when walking.
	_visual.rotation.x = 0.06 * sin(_t * 1.3) if speed < 0.1 else 0.0
	_visual.position.y = absf(sin(_t * 6.0)) * 0.04 if speed > 0.1 else 0.0


static func _mesh(k: Kind, variant: int) -> Mesh:
	var key := "%d_%d" % [k, variant]
	if _meshes.has(key):
		return _meshes[key]
	var mb := MeshBuilder.new()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.07, 0.06)
	dark.roughness = 0.9
	if k == Kind.SHEEP:
		var wool := StandardMaterial3D.new()
		wool.albedo_color = [Color(0.86, 0.83, 0.74), Color(0.8, 0.76, 0.66), Color(0.9, 0.88, 0.8)][variant]
		wool.roughness = 1.0
		var body := SphereMesh.new()
		body.radius = 0.5
		body.height = 1.0
		body.radial_segments = 12
		body.rings = 6
		mb.add_mesh(body, Transform3D(Basis.from_scale(Vector3(0.85, 0.72, 1.25)), Vector3(0, 0.62, 0)), wool)
		mb.add_box(Vector3(0.22, 0.26, 0.34), Vector3(0, 0.72, 0.68), dark, Basis(Vector3.RIGHT, 0.5))
		for lx: float in [-0.2, 0.2]:
			for lz: float in [-0.38, 0.38]:
				mb.add_box(Vector3(0.07, 0.42, 0.07), Vector3(lx, 0.21, lz), dark)
	else:
		var hide := StandardMaterial3D.new()
		hide.albedo_color = [Color(0.36, 0.2, 0.1), Color(0.16, 0.12, 0.1), Color(0.55, 0.36, 0.2)][variant]
		hide.roughness = 0.85
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.85, 0.83, 0.78)
		white.roughness = 0.85
		mb.add_box(Vector3(0.75, 0.8, 1.8), Vector3(0, 1.05, 0), hide)
		mb.add_box(Vector3(0.77, 0.4, 0.8), Vector3(0, 0.95, -0.3), white if variant == 1 else hide)
		mb.add_box(Vector3(0.36, 0.42, 0.55), Vector3(0, 1.2, 1.05), hide, Basis(Vector3.RIGHT, 0.35))
		mb.add_box(Vector3(0.5, 0.06, 0.06), Vector3(0, 1.45, 0.95), white)
		for lx: float in [-0.26, 0.26]:
			for lz: float in [-0.7, 0.7]:
				mb.add_box(Vector3(0.14, 0.7, 0.14), Vector3(lx, 0.35, lz), hide)
		mb.add_box(Vector3(0.05, 0.7, 0.05), Vector3(0, 0.9, -0.95), hide, Basis(Vector3.RIGHT, 0.2))
	var m := mb.build()
	_meshes[key] = m
	return m
