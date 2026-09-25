class_name WildAnimal
extends CharacterBody3D
## Game in the hills: red deer (herds of hinds, the odd stag), rabbits and red foxes.
##
## They graze and wander near their herd, and are wary:
##   * eyes: see movement and a man in the open (less if he's crouched, still, in shadow)
##   * ears: every sound, not just suspicious ones (a snapped twig is enough)
##   * nose: deer scent a man ~60 m downwind; the wind carries it (Weather.wind_direction)
## ALERT: head up, facing the danger; if it keeps coming, they FLEE, and the whole herd
## goes with them. Deer run at up to 11 m/s, rabbits bolt at 7 m/s in zigzags.
##
## Hunting: a broadhead brings a deer down after a short dying run (a clean kill); blunt
## arrows are for rabbits (as they were in 1866). A blunt arrow only frightens a deer. The
## carcass can be butchered (hold E) for venison and a hide.
##
## They walk over the streamed ground by sampling its height directly, so they never fall
## through a patch of ground whose collision hasn't streamed in yet.

signal died(animal: WildAnimal)
signal fled(animal: WildAnimal)

enum Species { DEER, RABBIT, FOX }

const STEER: Array[float] = [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.3, -2.3]
enum State { GRAZE, WANDER, ALERT, FLEE, DYING, DEAD }

@export var species: Species = Species.DEER
@export var is_stag: bool = false

var state: State = State.GRAZE
var herd: Array[WildAnimal] = []
var herd_center: Vector3 = Vector3.ZERO
## 0..1: how sure it is that something's wrong.
var alarm: float = 0.0
var threat: Vector3 = Vector3.ZERO

var _streamer: WorldStreamer
var _harry: Harry
var _yaw := 0.0
var _target := Vector3.ZERO
var _timer := 0.0
var _sense_timer := 0.0
var _speed := 0.0
var _flee_dir := Vector3.ZERO
var _zig := 0.0
var _phase := 0.0
var _visual: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []


func _ready() -> void:
	add_to_group("wild_animals")
	collision_layer = 1 << 2
	collision_mask = 0 # moved by hand over the terrain
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	if species == Species.DEER:
		cap.radius = 0.35
		cap.height = 1.5
		cs.position = Vector3(0, 1.0, 0)
		cs.rotation.x = PI * 0.5
	else:
		cap.radius = 0.14
		cap.height = 0.4
		cs.position = Vector3(0, 0.16, 0)
		cs.rotation.x = PI * 0.5
	cs.shape = cap
	add_child(cs)
	_yaw = randf() * TAU
	_build_body()
	_timer = randf_range(2.0, 8.0)
	Stealth.bus().noise_made.connect(_on_noise)


func setup(streamer: WorldStreamer, center: Vector3) -> void:
	_streamer = streamer
	herd_center = center


func is_dead() -> bool:
	return state == State.DEAD or state == State.DYING


func get_facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## Arrows (Arrow._on_hit finds this via on_arrow_hit).
func on_arrow_hit(kind: String, _point: Vector3, from_dir: Vector3) -> void:
	if is_dead():
		return
	threat = global_position - from_dir.normalized() * 20.0
	var lethal := kind == "broadhead" or (kind == "blunt" and species == Species.RABBIT)
	if lethal:
		state = State.DYING
		_timer = 2.5 if species == Species.DEER else 0.3 # a deer runs a few strides first
		_flee_dir = Vector3(from_dir.x, 0.0, from_dir.z).normalized()
		_alarm_herd(threat)
	else:
		alarm = 1.0
		_start_flee(threat)
		_alarm_herd(threat)


# ---------------------------------------------------------------------------
var _lod_frame := randi() % 30
var _far := false


func _physics_process(delta: float) -> void:
	if _harry == null:
		_harry = get_tree().get_first_node_in_group("player") as Harry
	if _streamer == null:
		_streamer = get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
		if _streamer == null:
			return
	# Grazing or ambling far from the camera: every third frame is plenty.
	_lod_frame += 1
	if _lod_frame % 30 == 0:
		var cam := get_viewport().get_camera_3d()
		_far = cam != null and cam.global_position.distance_squared_to(global_position) > 3600.0
	if _far and state in [State.GRAZE, State.WANDER]:
		if _lod_frame % 3 != 0:
			return
		delta *= 3.0
	_timer -= delta
	_speed = 0.0
	if state != State.DEAD and state != State.DYING:
		_sense_timer -= delta
		if _sense_timer <= 0.0:
			_sense_timer = 0.2
			_sense(0.2)
	match state:
		State.GRAZE:
			if _timer <= 0.0:
				state = State.WANDER
				var a := randf() * TAU
				_target = herd_center + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 14.0 if species == Species.DEER else 6.0)
				_timer = 12.0
		State.WANDER:
			if _walk_to(_target, 1.2 if species == Species.DEER else 0.7, delta) or _timer <= 0.0:
				state = State.GRAZE
				_timer = randf_range(4.0, 12.0)
		State.ALERT:
			_face(threat, delta)
			alarm = maxf(alarm - 0.12 * delta, 0.0)
			if alarm <= 0.05 and _timer <= 0.0:
				state = State.GRAZE
				_timer = randf_range(3.0, 6.0)
		State.FLEE:
			var run := 11.0 if species == Species.DEER else (9.5 if species == Species.FOX else 7.0)
			var dir := _flee_dir
			if species == Species.RABBIT:
				_zig += delta * 6.0
				dir = dir.rotated(Vector3.UP, sin(_zig) * 0.6)
			_move(dir, run, delta)
			if _timer <= 0.0:
				state = State.ALERT
				alarm = 0.5
				_timer = 6.0
				herd_center = global_position
		State.DYING:
			_move(_flee_dir, 9.0 if species == Species.DEER else 0.0, delta)
			if _timer <= 0.0:
				_die()
		State.DEAD:
			pass
	_stick_to_ground(delta)
	_animate(delta)


func _sense(dt: float) -> void:
	if _harry == null or _harry.is_dead():
		return
	var to_me := global_position - _harry.global_position
	var d := to_me.length()
	var noticed := 0.0
	# Sight.
	var sight := (48.0 if species == Species.DEER else 14.0) * Stealth.visibility_multiplier
	var vis := _harry.stealth.visibility
	var moving := _harry.get_horizontal_speed()
	var eff := sight * clampf(0.2 + 0.8 * vis + (0.25 if moving > 1.5 else 0.0) - (0.3 if _harry.is_crouching else 0.0), 0.1, 1.2)
	if _harry.is_riding():
		eff *= 0.6 # a horse is just another beast to them, until it's close
	if d < eff and not _harry.stealth.is_hidden():
		noticed = maxf(noticed, 1.0 - d / eff)
	# Scent (deer).
	if species == Species.DEER and d > 0.1:
		var downwind := Weather.wind_direction.dot(Vector3(to_me.x, 0, to_me.z).normalized())
		var smell := 25.0 * (1.0 + 1.4 * maxf(downwind, 0.0) * clampf(Weather.wind * 2.0, 0.0, 1.0)) * (1.0 - 0.4 * Weather.rain)
		if d < smell:
			noticed = maxf(noticed, 0.6 * (1.0 - d / smell))
	if noticed > 0.0:
		alarm = minf(alarm + noticed * dt * 3.0, 1.0)
		threat = _harry.global_position
		if state in [State.GRAZE, State.WANDER]:
			state = State.ALERT
			_timer = 3.0
		if alarm >= 0.75 or d < (9.0 if species == Species.DEER else 3.5):
			_start_flee(threat)
			_alarm_herd(threat)


func _on_noise(pos: Vector3, radius: float, _kind: String, _suspicious: bool, source: Node) -> void:
	if is_dead() or source is WildAnimal:
		return
	var hearing := 1.6 if species == Species.DEER else 1.0
	var d := global_position.distance_to(pos)
	if d > radius * hearing:
		return
	threat = pos
	alarm = minf(alarm + 0.45 * (1.0 - d / (radius * hearing)) + 0.2, 1.0)
	if alarm >= 0.75:
		_start_flee(pos)
		_alarm_herd(pos)
	elif state in [State.GRAZE, State.WANDER]:
		state = State.ALERT
		_timer = 4.0


func _start_flee(from: Vector3) -> void:
	if is_dead() or state == State.FLEE:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.1:
		away = get_facing_dir()
	_flee_dir = away.normalized().rotated(Vector3.UP, randf_range(-0.4, 0.4))
	state = State.FLEE
	_timer = randf_range(6.0, 9.0) if species == Species.DEER else randf_range(2.0, 3.5)
	fled.emit(self)


func _alarm_herd(from: Vector3) -> void:
	for other in herd:
		if other != self and is_instance_valid(other) and not other.is_dead():
			other.threat = from
			other.alarm = 1.0
			other._start_flee(from)


func _die() -> void:
	state = State.DEAD
	collision_layer = 0
	died.emit(self)
	var carcass := Carcass.new()
	carcass.species = species
	carcass.is_stag = is_stag
	carcass.animal = self
	add_child(carcass)


# ---------------------------------------------------------------------------
# Movement over the height field
# ---------------------------------------------------------------------------
func _walk_to(p: Vector3, speed: float, delta: float) -> bool:
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.8:
		return true
	_move(d.normalized(), speed, delta)
	return false


func _move(dir: Vector3, speed: float, delta: float) -> void:
	if speed <= 0.0 or dir == Vector3.ZERO:
		return
	var gen := _streamer.generator
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	var eye := global_position + Vector3.UP * (0.6 if species == Species.DEER else 0.2)
	# Steer round steep ground, deep water, rocks, walls and tree trunks (look a few metres
	# ahead); if every way is blocked, stand still rather than walk through something.
	var best := Vector3.ZERO
	# A fleeing beast never swings back towards what it's running from.
	var tries := 7 if state == State.FLEE or state == State.DYING else STEER.size()
	for k in tries:
		var tryd := dir.rotated(Vector3.UP, STEER[k])
		var ahead := global_position + tryd * 3.0
		var nrm := gen.normal(ahead.x, ahead.z, 1.0)
		if nrm.y <= 0.72 or gen.water_depth(ahead.x, ahead.z) >= 0.4 or absf(ahead.x) >= TerrainGenerator.HALF_SIZE - 150.0 or absf(ahead.z) >= TerrainGenerator.HALF_SIZE - 150.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, eye + tryd * 2.5, 1, ex)
		if not space.intersect_ray(q).is_empty():
			continue
		best = tryd
		break
	if best == Vector3.ZERO:
		if state == State.WANDER:
			_timer = 0.0 # pick somewhere else to wander
		return
	_speed = speed
	var step := best * speed * delta
	global_position += step
	_yaw = rotate_toward(_yaw, atan2(-best.x, -best.z), 6.0 * delta)
	if state == State.FLEE:
		_flee_dir = best


func _face(p: Vector3, delta: float) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		_yaw = rotate_toward(_yaw, atan2(-d.x, -d.z), 3.0 * delta)


func _stick_to_ground(_delta: float) -> void:
	var h := _streamer.generator.height(global_position.x, global_position.z)
	global_position.y = h


# ---------------------------------------------------------------------------
# Body
# ---------------------------------------------------------------------------
func _build_body() -> void:
	_visual = Node3D.new()
	_visual.name = "Body"
	add_child(_visual)
	var coat := StandardMaterial3D.new()
	var pale := StandardMaterial3D.new()
	var dark := StandardMaterial3D.new()
	coat.roughness = 0.95
	pale.roughness = 0.95
	dark.roughness = 0.7
	dark.albedo_color = Color(0.08, 0.06, 0.05)
	if species == Species.DEER:
		coat.albedo_color = Color(0.45, 0.28, 0.16)
		pale.albedo_color = Color(0.8, 0.72, 0.6)
		var mb := MeshBuilder.new()
		mb.add_box(Vector3(0.42, 0.5, 1.3), Vector3(0, 1.05, 0.05), coat) # body
		mb.add_box(Vector3(0.3, 0.3, 0.12), Vector3(0, 1.08, 0.72), pale) # rump patch
		mb.build_into(_visual, "Torso")
		_head = Node3D.new()
		_head.position = Vector3(0, 1.25, -0.55)
		_visual.add_child(_head)
		var hb := MeshBuilder.new()
		hb.add_box(Vector3(0.18, 0.6, 0.2), Vector3(0, 0.25, -0.1), coat, Basis(Vector3.RIGHT, 0.5)) # neck
		hb.add_box(Vector3(0.16, 0.18, 0.36), Vector3(0, 0.55, -0.35), coat) # head
		hb.add_box(Vector3(0.1, 0.1, 0.1), Vector3(0, 0.5, -0.55), dark) # muzzle
		for side: float in [-1.0, 1.0]:
			hb.add_box(Vector3(0.04, 0.16, 0.08), Vector3(side * 0.1, 0.7, -0.25), coat, Basis(Vector3.FORWARD, side * 0.5)) # ears
			if is_stag:
				hb.add_box(Vector3(0.03, 0.55, 0.03), Vector3(side * 0.12, 0.92, -0.3), pale, Basis(Vector3.FORWARD, side * 0.35))
				hb.add_box(Vector3(0.02, 0.25, 0.02), Vector3(side * 0.2, 1.05, -0.4), pale, Basis(Vector3.RIGHT, -0.6))
				hb.add_box(Vector3(0.02, 0.2, 0.02), Vector3(side * 0.24, 1.18, -0.28), pale, Basis(Vector3.RIGHT, 0.4))
		hb.build_into(_head, "Head")
		for i in 4:
			var hip := Node3D.new()
			hip.position = Vector3(-0.13 if i % 2 == 0 else 0.13, 0.85, -0.45 if i < 2 else 0.5)
			_visual.add_child(hip)
			var lb := MeshBuilder.new()
			lb.add_box(Vector3(0.07, 0.85, 0.08), Vector3(0, -0.42, 0), coat)
			lb.add_box(Vector3(0.06, 0.06, 0.07), Vector3(0, -0.84, -0.01), dark)
			lb.build_into(hip, "Leg")
			_legs.append(hip)
	elif species == Species.FOX:
		# A red fox: russet coat, white bib and tail tip, black stockings, a big brush.
		coat.albedo_color = Color(0.62, 0.3, 0.1)
		pale.albedo_color = Color(0.9, 0.87, 0.8)
		var mb := MeshBuilder.new()
		var body := CapsuleMesh.new()
		body.radius = 0.1
		body.height = 0.55
		mb.add_mesh(body, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.32, 0)), coat)
		mb.add_box(Vector3(0.12, 0.1, 0.12), Vector3(0, 0.28, -0.22), pale) # bib
		var brush := CapsuleMesh.new()
		brush.radius = 0.06
		brush.height = 0.42
		mb.add_mesh(brush, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.4), Vector3(0, 0.3, 0.42)), coat)
		mb.add_box(Vector3(0.07, 0.07, 0.07), Vector3(0, 0.22, 0.62), pale) # tip
		mb.build_into(_visual, "Torso")
		_head = Node3D.new()
		_head.position = Vector3(0, 0.4, -0.3)
		_visual.add_child(_head)
		var hb := MeshBuilder.new()
		hb.add_box(Vector3(0.12, 0.11, 0.14), Vector3(0, 0.0, -0.04), coat)
		hb.add_box(Vector3(0.05, 0.05, 0.12), Vector3(0, -0.02, -0.16), coat) # muzzle
		hb.add_box(Vector3(0.02, 0.02, 0.02), Vector3(0, -0.01, -0.22), dark)
		for side: float in [-1.0, 1.0]:
			hb.add_box(Vector3(0.04, 0.08, 0.02), Vector3(side * 0.04, 0.09, 0.0), dark, Basis(Vector3.FORWARD, side * 0.2))
		hb.build_into(_head, "Head")
		for i in 4:
			var hip := Node3D.new()
			hip.position = Vector3(-0.05 if i % 2 == 0 else 0.05, 0.27, -0.2 if i < 2 else 0.2)
			_visual.add_child(hip)
			var lb := MeshBuilder.new()
			lb.add_box(Vector3(0.035, 0.27, 0.04), Vector3(0, -0.13, 0), dark)
			lb.build_into(hip, "Leg")
			_legs.append(hip)
	else:
		coat.albedo_color = Color(0.46, 0.4, 0.32)
		pale.albedo_color = Color(0.9, 0.88, 0.84)
		var mb := MeshBuilder.new()
		var body := SphereMesh.new()
		body.radius = 0.14
		body.height = 0.26
		mb.add_mesh(body, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 1.5)), Vector3(0, 0.16, 0)), coat)
		var tail := SphereMesh.new()
		tail.radius = 0.04
		tail.height = 0.08
		mb.add_mesh(tail, Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0.2)), pale)
		mb.build_into(_visual, "Torso")
		_head = Node3D.new()
		_head.position = Vector3(0, 0.24, -0.18)
		_visual.add_child(_head)
		var hb := MeshBuilder.new()
		var hs := SphereMesh.new()
		hs.radius = 0.07
		hs.height = 0.12
		hb.add_mesh(hs, Transform3D(Basis.IDENTITY, Vector3(0, 0.02, -0.05)), coat)
		for side: float in [-1.0, 1.0]:
			hb.add_box(Vector3(0.03, 0.16, 0.02), Vector3(side * 0.03, 0.14, 0.0), coat, Basis(Vector3.FORWARD, side * 0.15))
		hb.build_into(_head, "Head")


func _animate(delta: float) -> void:
	if state == State.DEAD:
		_visual.rotation = Vector3(0, _yaw, PI * 0.5)
		_visual.position = Vector3(0, 0.3 if species == Species.DEER else 0.05, 0)
		return
	_visual.rotation.y = _yaw
	_phase += delta * (1.5 + _speed * 1.6)
	var swing := clampf(_speed / 4.0, 0.0, 1.0) * 0.7
	for i in _legs.size():
		var ph := _phase + (PI if i in [1, 2] else 0.0)
		if _speed > 6.0:
			ph = _phase + (0.0 if i < 2 else PI * 0.6) # bounding gallop
		_legs[i].rotation.x = sin(ph) * swing
	if species == Species.RABBIT:
		_visual.position.y = absf(sin(_phase)) * 0.12 * clampf(_speed, 0.0, 1.0)
	var grazing := state == State.GRAZE
	# Positive pitch lifts the head: down to graze, up and pricked when alarmed.
	var target := -1.0 if grazing and species == Species.DEER else (0.25 if state == State.ALERT else 0.0)
	_head.rotation.x = lerpf(_head.rotation.x, target, delta * 3.0)
