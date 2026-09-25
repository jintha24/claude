class_name HorseVehicle
extends AnimatableBody3D
## A horse-drawn vehicle: a hansom cab, a four-wheeled "growler", a carrier's cart, a
## brewer's dray or a horse omnibus, with its horse(s) trotting, wheels turning and a
## driver up on the box.
##
## It drives along a queue of waypoints (the traffic manager keeps it topped up), slows for
## anything in front - another vehicle, Harry, a person in the road - and is solid (it's an
## AnimatableBody, so it pushes people aside rather than passing through them).

enum Kind { HANSOM, GROWLER, CART, DRAY, OMNIBUS }

signal needs_waypoints(vehicle: HorseVehicle)

var kind: Kind = Kind.HANSOM
var cruise := 4.2
## Optional: ground height at (x, z) (the hills' road); otherwise flat at y = 0.
var height_fn: Callable
var waypoints: Array[Vector3] = []
var speed := 0.0
var driver_outfit: NPCBody.Outfit = NPCBody.Outfit.WORKER

var _yaw := 0.0
var _horses: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _wheels: Array[Node3D] = []
var _wheel_r: Array[float] = []
var _phase := 0.0
var _driver: NPCBody
var _check := 0.0
var _blocked := false
var _shout := 0.0
var _rng := RandomNumberGenerator.new()
var _near := false

static var _mesh_cache := {}


func _ready() -> void:
	add_to_group("vehicles")
	_rng.seed = hash(name)
	collision_layer = 1 | (1 << 3)
	collision_mask = 0
	sync_to_physics = false
	_build()


func get_facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## Places it at `p`, facing `dir`.
func place(p: Vector3, dir: Vector3) -> void:
	_yaw = atan2(-dir.x, -dir.z)
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), p)


var _far_frame := 0


func _physics_process(delta: float) -> void:
	# Far off, a vehicle only needs moving every third frame.
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_squared_to(global_position) > 110.0 * 110.0
	_far_frame += 1
	if far:
		if _far_frame % 3 != 0:
			return
		delta *= 3.0
	_near = not far and cam != null and cam.global_position.distance_squared_to(global_position) < 55.0 * 55.0
	if waypoints.size() < 3:
		needs_waypoints.emit(self)
	if waypoints.is_empty():
		speed = move_toward(speed, 0.0, delta * 3.0)
		_animate(delta)
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.2
		_blocked = _something_ahead()
	var target := waypoints[0]
	var pos := global_position
	var to := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	if to.length() < 1.2:
		waypoints.pop_front()
		_animate(delta)
		return
	# Slow for corners.
	var want := cruise
	if waypoints.size() > 1:
		var nxt := waypoints[1] - target
		nxt.y = 0.0
		if nxt.length() > 0.1 and to.normalized().dot(nxt.normalized()) < 0.7:
			want = minf(want, 2.2)
	if _blocked:
		want = 0.0
	speed = move_toward(speed, want, delta * (4.0 if want < speed else 1.2))
	var dir := to.normalized()
	_yaw = rotate_toward(_yaw, atan2(-dir.x, -dir.z), delta * (1.4 + speed * 0.2))
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	pos += fwd * speed * delta
	pos.y = height_fn.call(pos.x, pos.z) if height_fn.is_valid() else 0.0
	var basis := Basis(Vector3.UP, _yaw)
	if height_fn.is_valid():
		# Follow the slope of the road.
		var ahead: float = height_fn.call(pos.x + fwd.x * 2.0, pos.z + fwd.z * 2.0)
		basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, atan2(ahead - pos.y, 2.0))
	global_transform = Transform3D(basis, pos)
	_animate(delta)


func _something_ahead() -> bool:
	var fwd := get_facing_dir()
	var p := global_position
	for n in get_tree().get_nodes_in_group("vehicles"):
		if n == self:
			continue
		var o := (n as Node3D).global_position - p
		o.y = 0.0
		var ahead := o.dot(fwd)
		if ahead > 0.0 and ahead < 11.0 and absf(o.cross(fwd).y) < 2.2:
			return true
	var harry := get_tree().get_first_node_in_group("player") as Node3D
	if harry:
		var o := harry.global_position - p
		o.y = 0.0
		var ahead := o.dot(fwd)
		if ahead > 0.0 and ahead < 7.5 and absf(o.cross(fwd).y) < 1.8:
			_shout -= 0.2
			if _shout <= 0.0 and speed > 1.0 and o.length() < 7.0:
				_shout = 8.0
				var lines := ["Mind yerself!", "Out the road, you!", "Oi! Look sharp!", "Way there, way!"]
				Stealth.bark(self, "Driver: \"%s\"" % lines[_rng.randi() % lines.size()])
			return true
	for n in get_tree().get_nodes_in_group("civilians"):
		var o := (n as Node3D).global_position - p
		if absf(o.x) > 8.0 or absf(o.z) > 8.0:
			continue
		o.y = 0.0
		var ahead := o.dot(fwd)
		if ahead > 0.0 and ahead < 5.5 and absf(o.cross(fwd).y) < 1.4:
			return true
	return false


func _animate(delta: float) -> void:
	_phase += delta * speed * 1.6
	var trot := clampf(speed / 3.0, 0.0, 1.0)
	for i in _legs.size():
		var offs := 0.0 if i % 4 in [0, 3] else PI # diagonal pairs at the trot
		_legs[i].rotation.x = sin(_phase + offs) * 0.55 * trot
	for i in _wheels.size():
		_wheels[i].rotation.x -= delta * speed / _wheel_r[i]
	for h in _horses:
		h.position.y = absf(sin(_phase)) * 0.05 * trot
	if _driver and _near and _far_frame % 6 == 0:
		_driver.update_body(0.0, NPCBody.Pose.SIT, delta * 6.0)


# ---------------------------------------------------------------------------
# Building the vehicle (meshes shared between vehicles of a kind)
# ---------------------------------------------------------------------------
func _mat(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _build() -> void:
	var paint_colors: Array[Color] = [Color(0.05, 0.05, 0.06), Color(0.2, 0.05, 0.05), Color(0.06, 0.12, 0.08), Color(0.12, 0.1, 0.06), Color(0.08, 0.08, 0.16)]
	var paint := paint_colors[_rng.randi() % paint_colors.size()]
	var horses := 2 if kind in [Kind.DRAY, Kind.OMNIBUS] else 1
	var coats: Array[Color] = [Color(0.09, 0.06, 0.045), Color(0.3, 0.17, 0.08), Color(0.03, 0.025, 0.02), Color(0.45, 0.4, 0.36), Color(0.2, 0.12, 0.07)]
	var shape_len := 0.0
	# Horses in front (-Z), the vehicle behind.
	for hi in horses:
		var coat := coats[_rng.randi() % coats.size()]
		var hx := 0.0 if horses == 1 else (-0.55 if hi == 0 else 0.55)
		_add_horse(Vector3(hx, 0, -1.7), coat)
	match kind:
		Kind.HANSOM:
			_hansom(paint)
			shape_len = 5.2
		Kind.GROWLER:
			_growler(paint)
			shape_len = 5.8
		Kind.CART:
			_cart(false)
			shape_len = 5.4
		Kind.DRAY:
			_cart(true)
			shape_len = 6.2
		Kind.OMNIBUS:
			_omnibus(paint)
			shape_len = 7.6
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9 if horses == 1 else 2.3, 2.4, shape_len)
	cs.shape = box
	cs.position = Vector3(0, 1.2, shape_len * 0.5 - 3.0)
	add_child(cs)
	# Fade out in the distance (the driver's own body sets its own ranges).
	for n in find_children("*", "GeometryInstance3D", true, false):
		if _driver == null or not _driver.is_ancestor_of(n):
			(n as GeometryInstance3D).visibility_range_end = 260.0


func _add_horse(at: Vector3, coat: Color) -> void:
	var horse := Node3D.new()
	horse.position = at
	add_child(horse)
	_horses.append(horse)
	var key := "horse_%s" % coat.to_html(false)
	if not _mesh_cache.has(key):
		var c := _mat(coat, 0.72)
		var dark := _mat(Color(0.03, 0.025, 0.02), 0.7)
		var harness := _mat(Color(0.06, 0.04, 0.03), 0.45)
		var mb := MeshBuilder.new()
		var barrel := CapsuleMesh.new()
		barrel.radius = 0.3
		barrel.height = 1.7
		mb.add_mesh(barrel, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 1.25)), Vector3(0, 1.3, 0.0)), c)
		var chest := SphereMesh.new()
		chest.radius = 0.32
		chest.height = 0.8
		mb.add_mesh(chest, Transform3D(Basis.IDENTITY.scaled(Vector3(0.95, 1.1, 1.0)), Vector3(0, 1.32, -0.62)), c)
		var neck := CylinderMesh.new()
		neck.bottom_radius = 0.23
		neck.top_radius = 0.12
		neck.height = 1.0
		neck.radial_segments = 10
		mb.add_mesh(neck, Transform3D(Basis(Vector3.RIGHT, -0.62).scaled(Vector3(0.75, 1.0, 1.2)), Vector3(0, 1.85, -1.05)), c)
		var head := CylinderMesh.new()
		head.bottom_radius = 0.07
		head.top_radius = 0.12
		head.height = 0.6
		head.radial_segments = 8
		mb.add_mesh(head, Transform3D(Basis(Vector3.RIGHT, 1.1).scaled(Vector3(0.8, 1.0, 1.1)), Vector3(0, 2.15, -1.45)), c)
		mb.add_box(Vector3(0.07, 0.75, 0.12), Vector3(0, 1.95, -0.95), dark, Basis(Vector3.RIGHT, -0.6)) # mane
		mb.add_box(Vector3(0.12, 0.75, 0.12), Vector3(0, 1.15, 0.95), dark, Basis(Vector3.RIGHT, -0.25)) # tail
		# Collar and harness, blinkers.
		var collar := TorusMesh.new()
		collar.inner_radius = 0.2
		collar.outer_radius = 0.3
		collar.rings = 12
		collar.ring_segments = 6
		mb.add_mesh(collar, Transform3D(Basis(Vector3.RIGHT, 1.0), Vector3(0, 1.6, -0.85)), harness)
		mb.add_box(Vector3(0.66, 0.08, 0.3), Vector3(0, 1.55, 0.1), harness)
		mb.add_box(Vector3(0.64, 0.06, 1.6), Vector3(0, 1.3, 0.2), harness, Basis(Vector3.FORWARD, 0.0))
		for s: float in [-1.0, 1.0]:
			mb.add_box(Vector3(0.03, 0.1, 0.12), Vector3(s * 0.12, 2.25, -1.4), harness)
			mb.add_box(Vector3(0.03, 0.03, 2.4), Vector3(s * 0.34, 1.35, 0.9), harness) # traces
		_mesh_cache[key] = mb.build()
		var lb := MeshBuilder.new()
		lb.add_box(Vector3(0.13, 1.1, 0.16), Vector3(0, -0.55, 0), c)
		lb.add_box(Vector3(0.14, 0.1, 0.16), Vector3(0, -1.1, -0.01), dark)
		_mesh_cache[key + "_leg"] = lb.build()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_cache[key]
	horse.add_child(mi)
	for i in 4:
		var hip := Node3D.new()
		hip.position = Vector3(-0.18 if i % 2 == 0 else 0.18, 1.15, -0.6 if i < 2 else 0.62)
		horse.add_child(hip)
		var leg := MeshInstance3D.new()
		leg.mesh = _mesh_cache[key + "_leg"]
		hip.add_child(leg)
		_legs.append(hip)


func _wheel(at: Vector3, r: float, spokes: int, col: Color) -> void:
	var key := "wheel_%.2f_%d_%s" % [r, spokes, col.to_html(false)]
	if not _mesh_cache.has(key):
		var wood := _mat(col, 0.55)
		var iron := _mat(Color(0.05, 0.05, 0.05), 0.4, 0.6)
		var mb := MeshBuilder.new()
		var rim := TorusMesh.new()
		rim.inner_radius = r - 0.06
		rim.outer_radius = r
		rim.rings = 24
		rim.ring_segments = 4
		mb.add_mesh(rim, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), iron)
		for k in spokes:
			var a := TAU * k / spokes
			mb.add_box(Vector3(0.04, r * 2.0 - 0.1, 0.04), Vector3.ZERO, wood, Basis(Vector3.RIGHT, a))
		mb.add_cylinder(0.09, 0.09, 0.2, Vector3.ZERO, iron, 10, Basis(Vector3.FORWARD, PI * 0.5))
		_mesh_cache[key] = mb.build()
	var w := MeshInstance3D.new()
	w.mesh = _mesh_cache[key]
	w.position = at
	add_child(w)
	_wheels.append(w)
	_wheel_r.append(r)


func _driver_at(at: Vector3) -> void:
	_driver = NPCBody.new()
	_driver.name = "Driver"
	_driver.outfit = driver_outfit
	_driver.height = 1.74
	_driver.variation_seed = _rng.randi() % 100000
	_driver.position = at
	add_child(_driver)


func _box(size: Vector3, at: Vector3, m: Material, basis := Basis.IDENTITY) -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.add_box(size, at, m, basis)
	return mb


func _hansom(paint: Color) -> void:
	var p := _mat(paint, 0.3)
	var trim := _mat(Color(0.55, 0.45, 0.2), 0.35, 0.8)
	var glass := MaterialLibrary.get_material("glass")
	var mb := MeshBuilder.new()
	# The cab: a box on two tall wheels, open at the front with folding doors, the driver's
	# seat high at the back, the shafts running forward to the horse.
	mb.add_box(Vector3(1.3, 1.5, 1.3), Vector3(0, 1.55, 0.9), p)
	mb.add_box(Vector3(1.36, 0.08, 1.4), Vector3(0, 2.34, 0.9), p)
	mb.add_box(Vector3(1.2, 0.5, 0.04), Vector3(0, 1.3, 0.24), p) # apron doors
	mb.add_box(Vector3(1.0, 0.55, 0.02), Vector3(0, 1.95, 0.26), glass)
	mb.add_box(Vector3(0.6, 0.12, 0.5), Vector3(0, 2.55, 1.75), p) # driver's seat
	mb.add_box(Vector3(0.08, 0.9, 0.08), Vector3(0, 2.05, 1.62), p)
	for s: float in [-1.0, 1.0]:
		mb.add_box(Vector3(0.06, 0.06, 3.2), Vector3(s * 0.4, 1.1, -0.9), p) # shafts
		mb.add_box(Vector3(0.03, 0.8, 0.03), Vector3(s * 0.66, 1.6, 0.4), trim) # lamps' brackets
		mb.add_box(Vector3(0.14, 0.18, 0.14), Vector3(s * 0.7, 2.05, 0.35), MaterialLibrary.get_material("lamp_glass"))
	mb.build_into(self, "Body")
	for s: float in [-1.0, 1.0]:
		_wheel(Vector3(s * 0.8, 1.2, 1.0), 1.2, 12, paint * 1.6)
	_driver_at(Vector3(0, 2.1, 1.8))


func _growler(paint: Color) -> void:
	var p := _mat(paint, 0.35)
	var glass := MaterialLibrary.get_material("glass")
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(1.5, 1.4, 2.0), Vector3(0, 1.7, 1.4), p)
	mb.add_box(Vector3(1.55, 0.1, 2.1), Vector3(0, 2.45, 1.4), p)
	for s: float in [-1.0, 1.0]:
		mb.add_box(Vector3(0.02, 0.55, 0.7), Vector3(s * 0.76, 1.95, 1.4), glass)
	mb.add_box(Vector3(0.9, 0.12, 0.5), Vector3(0, 1.75, 0.1), p) # box seat
	mb.add_box(Vector3(0.9, 0.5, 0.06), Vector3(0, 1.45, -0.1), p)
	mb.add_box(Vector3(0.8, 0.5, 0.5), Vector3(0, 2.75, 1.4), MaterialLibrary.get_tinted("canvas", Color(0.4, 0.33, 0.25))) # luggage
	for s: float in [-1.0, 1.0]:
		mb.add_box(Vector3(0.06, 0.06, 2.6), Vector3(s * 0.4, 1.0, -0.9), p)
	mb.build_into(self, "Body")
	for s: float in [-1.0, 1.0]:
		_wheel(Vector3(s * 0.78, 0.55, 0.4), 0.55, 10, paint * 1.6)
		_wheel(Vector3(s * 0.8, 0.75, 2.3), 0.75, 12, paint * 1.6)
	_driver_at(Vector3(0, 1.3, 0.1))


func _cart(dray: bool) -> void:
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.55, 0.42, 0.3))
	var mb := MeshBuilder.new()
	var length := 3.4 if dray else 2.6
	mb.add_box(Vector3(1.6, 0.12, length), Vector3(0, 1.0, 0.4 + length * 0.5), wood)
	for s: float in [-1.0, 1.0]:
		mb.add_box(Vector3(0.06, 0.45, length), Vector3(s * 0.78, 1.27, 0.4 + length * 0.5), wood)
		mb.add_box(Vector3(0.07, 0.07, 2.8), Vector3(s * 0.4, 0.95, -0.9), wood)
	mb.add_box(Vector3(1.0, 0.1, 0.4), Vector3(0, 1.5, 0.5), wood) # the driver's bench
	if dray:
		# Barrels of porter.
		var barrel := MaterialLibrary.get_tinted("wood_planks", Color(0.5, 0.33, 0.2))
		for k in 6:
			var z := 1.2 + (k % 3) * 0.95
			var x := -0.38 if k < 3 else 0.38
			mb.add_cylinder(0.36, 0.36, 0.8, Vector3(x, 1.43, z), barrel, 10, Basis(Vector3.FORWARD, PI * 0.5))
	else:
		var sack := MaterialLibrary.get_tinted("canvas", Color(0.72, 0.64, 0.5))
		for k in 5:
			mb.add_box(Vector3(0.55, 0.35, 0.8), Vector3(-0.35 + (k % 2) * 0.7, 1.25 + (k / 2) * 0.3, 1.2 + (k % 3) * 0.5), sack, Basis(Vector3.UP, k * 0.3))
	mb.build_into(self, "Body")
	for s: float in [-1.0, 1.0]:
		_wheel(Vector3(s * 0.9, 0.8, 0.4 + length * 0.55), 0.8, 12, Color(0.45, 0.2, 0.1))
	_driver_at(Vector3(0, 1.05, 0.5))


func _omnibus(paint: Color) -> void:
	var p := _mat(Color(0.5, 0.12, 0.08) if _rng.randf() < 0.5 else Color(0.08, 0.18, 0.1), 0.35)
	var cream := _mat(Color(0.86, 0.8, 0.62), 0.4)
	var glass := MaterialLibrary.get_material("glass_1")
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(2.0, 1.9, 4.4), Vector3(0, 1.95, 2.0), p)
	mb.add_box(Vector3(2.04, 0.5, 4.44), Vector3(0, 2.7, 2.0), cream) # the advertisement boards
	for s: float in [-1.0, 1.0]:
		for k in 4:
			mb.add_box(Vector3(0.02, 0.6, 0.8), Vector3(s * 1.01, 1.9, 0.6 + k * 1.0), glass)
	# The "knifeboard" seat along the roof, rail and the passengers' backs.
	mb.add_box(Vector3(0.4, 0.5, 4.0), Vector3(0, 3.2, 2.0), p)
	for s: float in [-1.0, 1.0]:
		mb.add_box(Vector3(0.04, 0.4, 4.3), Vector3(s * 0.98, 3.15, 2.0), _mat(Color(0.05, 0.05, 0.05), 0.4, 0.5))
	mb.add_box(Vector3(0.9, 0.12, 0.5), Vector3(0, 2.3, -0.2), p) # box seat
	for s: float in [-1.0, 1.0]:
		mb.add_box(Vector3(0.07, 0.07, 2.6), Vector3(s * 0.25, 1.0, -1.1), p)
	mb.build_into(self, "Body")
	for s: float in [-1.0, 1.0]:
		_wheel(Vector3(s * 1.0, 0.6, 0.6), 0.6, 10, Color(0.6, 0.45, 0.15))
		_wheel(Vector3(s * 1.0, 0.8, 3.6), 0.8, 12, Color(0.6, 0.45, 0.15))
	for s: float in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = ["PEARS' SOAP", "LONDON GENERAL OMNIBUS", "COLMAN'S MUSTARD", "BOVRIL"][_rng.randi() % 4]
		label.font_size = 64
		label.pixel_size = 0.004
		label.modulate = Color(0.12, 0.1, 0.08)
		label.outline_size = 0
		label.shaded = true
		label.double_sided = false
		label.visibility_range_end = 50.0
		label.position = Vector3(s * 1.03, 2.7, 2.0)
		label.rotation.y = s * PI * 0.5
		add_child(label)
	_driver_at(Vector3(0, 1.85, -0.2))
