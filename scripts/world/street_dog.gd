class_name StreetDog
extends Node3D
## A dog out with its owner: trots at their heel, stops when they stop, sniffs about and
## wags its tail. Goes when the owner goes.

var owner_node: Node3D
var ground_fn: Callable

var _legs: Array[Node3D] = []
var _tail: Node3D
var _phase := 0.0
var _yaw := 0.0
var _side := 1.0
var _last := Vector3.ZERO
var _speed := 0.0

static var _meshes := {}


func _ready() -> void:
	add_to_group("dogs")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	_side = 1.0 if rng.randf() < 0.5 else -1.0
	var coats: Array[Color] = [Color(0.3, 0.2, 0.12), Color(0.08, 0.07, 0.06), Color(0.75, 0.7, 0.62), Color(0.5, 0.38, 0.22)]
	var coat := coats[rng.randi() % coats.size()]
	var s := rng.randf_range(0.75, 1.15)
	scale = Vector3(s, s, s)
	var key := coat.to_html(false)
	if not _meshes.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = coat
		m.roughness = 0.9
		var dark := StandardMaterial3D.new()
		dark.albedo_color = coat * 0.5
		var mb := MeshBuilder.new()
		var body := CapsuleMesh.new()
		body.radius = 0.13
		body.height = 0.62
		mb.add_mesh(body, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.4, 0)), m)
		mb.add_box(Vector3(0.14, 0.14, 0.2), Vector3(0, 0.55, -0.34), m) # head
		mb.add_box(Vector3(0.08, 0.07, 0.12), Vector3(0, 0.51, -0.47), dark) # muzzle
		for sx: float in [-0.05, 0.05]:
			mb.add_box(Vector3(0.04, 0.08, 0.03), Vector3(sx, 0.64, -0.3), dark) # ears
		_meshes[key] = mb.build()
		var lb := MeshBuilder.new()
		lb.add_box(Vector3(0.05, 0.3, 0.05), Vector3(0, -0.15, 0), m)
		_meshes[key + "leg"] = lb.build()
		var tb := MeshBuilder.new()
		tb.add_box(Vector3(0.03, 0.03, 0.2), Vector3(0, 0, 0.1), m, Basis(Vector3.RIGHT, -0.6))
		_meshes[key + "tail"] = tb.build()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.visibility_range_end = 80.0
	add_child(mi)
	for i in 4:
		var hip := Node3D.new()
		hip.position = Vector3(-0.07 if i % 2 == 0 else 0.07, 0.3, -0.2 if i < 2 else 0.2)
		add_child(hip)
		var leg := MeshInstance3D.new()
		leg.mesh = _meshes[key + "leg"]
		leg.visibility_range_end = 60.0
		hip.add_child(leg)
		_legs.append(hip)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.45, 0.3)
	add_child(_tail)
	var tm := MeshInstance3D.new()
	tm.mesh = _meshes[key + "tail"]
	tm.visibility_range_end = 60.0
	_tail.add_child(tm)


func _process(delta: float) -> void:
	if owner_node == null or not is_instance_valid(owner_node) or owner_node.is_queued_for_deletion():
		queue_free()
		return
	var o := owner_node.global_position
	var fwd := Vector3.FORWARD
	if owner_node.has_method("get_facing_dir"):
		fwd = owner_node.call("get_facing_dir")
	var side := Vector3(-fwd.z, 0.0, fwd.x) * _side
	var target := o - fwd * 0.9 + side * 0.6
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	var want := 0.0 if dist < 0.3 else clampf(dist * 2.0, 0.0, 3.5)
	_speed = move_toward(_speed, want, delta * 6.0)
	if dist > 6.0:
		global_position = target # caught up (it ran while nobody watched)
	elif dist > 0.05:
		global_position += to.normalized() * minf(_speed * delta, dist)
		_yaw = rotate_toward(_yaw, atan2(-to.x, -to.z), delta * 6.0)
	var gy: float = ground_fn.call(global_position.x, global_position.z) if ground_fn.is_valid() else o.y
	global_position.y = gy
	rotation.y = _yaw
	_phase += delta * (4.0 + _speed * 4.0)
	for i in 4:
		_legs[i].rotation.x = sin(_phase + (0.0 if i in [0, 3] else PI)) * 0.6 * clampf(_speed / 2.0, 0.0, 1.0)
	_tail.rotation.y = sin(_phase * 2.0) * 0.5
