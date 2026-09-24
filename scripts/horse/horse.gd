class_name Horse
extends CharacterBody3D
## Cinder: Harry's horse, dark and fast. Ridden, called with a whistle, and able to take
## fences and fallen trees in his stride.
##
## Riding (F to mount/dismount near him):
##   * Move to ride in any direction (relative to the camera); he turns towards it, more
##     tightly the slower he goes. A light touch walks, a firm one trots.
##   * Shift (tap): spur him on, trot -> canter -> gallop. Galloping tires him (stamina);
##     spent, he drops to a canter until he's got his wind back. Ctrl holds him to a walk.
##   * Pull back (stick away from his heading) to slow, stop and rein back.
##   * Jumps: at a canter or gallop he clears anything up to 1.35 m on his own (fences,
##     walls, fallen trees); Space asks for a jump at any pace. Higher obstacles, sheer
##     drops and slopes too steep to climb: he refuses and stops.
##   * Hooves are heard: walking 6 m, trotting 10, cantering 16, galloping 26.
## Unridden: stands and grazes. H whistles for him: he comes at a canter; if he's far off
## or out of sight he trots in from somewhere just out of view, as horses in stories do.

signal mounted(rider: Harry)
signal dismounted(rider: Harry)
signal jumped(height: float)
signal refused(reason: String)

enum Gait { STAND, WALK, TROT, CANTER, GALLOP }

## Metres per second for each gait (a horse's gallop is about 12-14 m/s).
const GAIT_SPEED: Array[float] = [0.0, 1.7, 3.8, 7.2, 13.0]
const TURN_RATE: Array[float] = [2.6, 2.4, 2.0, 1.5, 1.0]
const STRIDE: Array[float] = [9.0, 1.6, 2.4, 3.2, 5.0]
const NOISE: Array[float] = [0.0, 6.0, 10.0, 16.0, 26.0]
const MAX_JUMP := 1.35
const MAX_DROP := 2.6
const SADDLE_HEIGHT := 1.55

@export var horse_name: String = "Cinder"
## A rigged horse model (.glb) to use instead of the built-in stand-in. It's scaled to
## 1.63 m at the withers (16 hands) and faces -Z. See docs/REALISTIC_LOOK.md.
@export_file("*.glb", "*.tscn") var model_path: String = "res://assets/characters/cinder/cinder.glb"
@export var gallop_seconds: float = 18.0
@export var recover_seconds: float = 25.0
@export var acceleration: float = 3.2
@export var braking: float = 6.5

var rider: Harry = null
var gait: Gait = Gait.STAND
var stamina: float = 1.0
## Current forward speed (m/s, negative = reining back).
var speed: float = 0.0
var is_jumping: bool = false
var called: bool = false

var _yaw := 0.0
var _spur := Gait.TROT
var _winded := false
var _stride_acc := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _call_target := Vector3.ZERO
var _refuse_timer := 0.0
var _jump_cooldown := 0.0
var _visual: Node3D
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _neck: Node3D
var _tail: Node3D
var _phase := 0.0
var _rear := 0.0
var _body_shape: CollisionShape3D
var _progress_timer := 0.0
var _progress_dist := INF


func _ready() -> void:
	add_to_group("player_horse")
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 3) | (1 << 6) | (1 << 7)
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(40.0)
	floor_constant_speed = true
	_body_shape = CollisionShape3D.new()
	var body := CapsuleShape3D.new()
	body.radius = 0.42
	body.height = 2.3
	_body_shape.shape = body
	_body_shape.position = Vector3(0, 1.25, 0)
	_body_shape.rotation.x = PI * 0.5
	add_child(_body_shape)
	var legs := CollisionShape3D.new()
	var lc := CapsuleShape3D.new()
	lc.radius = 0.3
	lc.height = 1.3
	legs.shape = lc
	legs.position = Vector3(0, 0.65, 0)
	add_child(legs)
	_yaw = rotation.y
	rotation = Vector3.ZERO
	_build_body()


func get_facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func get_yaw() -> float:
	return _yaw


## Where the rider's feet-origin goes (Harry sits with his hips on the saddle).
func rider_transform() -> Transform3D:
	var t := Transform3D(Basis(Vector3.UP, _yaw), global_position + Vector3.UP * (SADDLE_HEIGHT - Harry.HEIGHT * 0.5 + 0.02))
	if is_jumping:
		t.origin += Vector3.UP * 0.05
	return t


func set_rider(h: Harry) -> void:
	rider = h
	called = false
	if h:
		_spur = Gait.TROT
		mounted.emit(h)


func clear_rider() -> void:
	var h := rider
	rider = null
	speed = minf(speed, GAIT_SPEED[Gait.TROT])
	if h:
		dismounted.emit(h)


## Whistled for: come to `pos`. If far away (or out of the way) he appears nearby first.
func call_to(pos: Vector3, viewer: Node3D = null) -> void:
	if rider:
		return
	_call_target = pos
	called = true
	_progress_timer = 0.0
	_progress_dist = INF
	if global_position.distance_to(pos) > 120.0:
		var back := Vector3.BACK
		if viewer:
			back = viewer.global_basis.z
			back.y = 0.0
			back = back.normalized() if back.length() > 0.01 else Vector3.BACK
		var spot := pos + back * 45.0
		var h := _ground_height(spot)
		if not is_nan(h):
			spot.y = h + 0.1
		global_position = spot
		_yaw = atan2(-(pos - spot).x, -(pos - spot).z)
		velocity = Vector3.ZERO
		reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	_refuse_timer = maxf(_refuse_timer - delta, 0.0)
	_jump_cooldown = maxf(_jump_cooldown - delta, 0.0)
	var wish := Vector3.ZERO
	var target_speed := 0.0
	var want_jump := false
	if rider and is_instance_valid(rider):
		var r := _read_rider(delta)
		wish = r[0]
		target_speed = r[1]
		want_jump = r[2]
	elif called:
		var to := _call_target - global_position
		to.y = 0.0
		if to.length() < 3.0:
			called = false
		else:
			_check_progress(to.length(), delta)
			wish = to.normalized()
			target_speed = GAIT_SPEED[Gait.CANTER] if to.length() > 12.0 else GAIT_SPEED[Gait.WALK]
			wish = _avoid(wish)
	# Stamina.
	if speed > GAIT_SPEED[Gait.CANTER] + 0.5:
		stamina = maxf(stamina - delta / gallop_seconds, 0.0)
		if stamina <= 0.0:
			_winded = true
	else:
		stamina = minf(stamina + delta / recover_seconds, 1.0)
		if stamina > 0.3:
			_winded = false
	if _winded:
		target_speed = minf(target_speed, GAIT_SPEED[Gait.CANTER])
	# Turn towards the wanted heading.
	if wish != Vector3.ZERO:
		var want_yaw := atan2(-wish.x, -wish.z)
		var g := _gait_for(absf(speed))
		_yaw = rotate_toward(_yaw, want_yaw, TURN_RATE[g] * delta)
		# Riding away from where he faces means slow down (or rein back when slow).
		if get_facing_dir().dot(wish) < -0.3:
			target_speed = -1.0 if absf(speed) < 0.8 else 0.0
	# Water drags at his legs.
	var depth := _water_depth()
	if depth > 0.3:
		target_speed = clampf(target_speed, -1.0, lerpf(GAIT_SPEED[Gait.TROT], 1.2, clampf(depth / 1.2, 0.0, 1.0)))
	if _refuse_timer > 0.0:
		target_speed = 0.0
	var rate := acceleration if absf(target_speed) > absf(speed) else braking
	speed = move_toward(speed, target_speed, rate * delta)
	gait = _gait_for(absf(speed))
	# Obstacles ahead: jump or refuse.
	if is_on_floor() and not is_jumping and speed > 0.5:
		_check_ahead(want_jump)
	var fwd := get_facing_dir() * speed
	velocity.x = fwd.x
	velocity.z = fwd.z
	if is_on_floor() and not is_jumping:
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	var was_air := is_jumping
	move_and_slide()
	if is_jumping and is_on_floor() and velocity.y <= 0.0:
		is_jumping = false
	if was_air and not is_jumping:
		Stealth.make_noise(global_position, 14.0, "hooves", false, self)
	_keep_above_ground()
	_hoofbeats(delta)
	_animate(delta)


## [wish direction, target speed, jump requested] from the rider's controls.
func _read_rider(_delta: float) -> Array:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var strength := minf(input.length(), 1.0)
	if Input.is_action_just_pressed("sprint"):
		_spur = mini(maxi(_spur, _gait_for(speed)) + 1, Gait.GALLOP) as Gait
	if strength < 0.1:
		_spur = Gait.TROT
		return [Vector3.ZERO, 0.0, false]
	var cam := get_viewport().get_camera_3d()
	var yaw := cam.global_rotation.y if cam else _yaw
	var wish := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw).normalized()
	var g := Gait.WALK if strength < 0.55 else maxi(_spur, Gait.TROT)
	if Input.is_action_pressed("walk"):
		g = Gait.WALK
	if not Input.is_action_pressed("sprint") and _spur > Gait.TROT and g > Gait.WALK:
		g = _spur # keeps his pace until reined in
	return [wish, GAIT_SPEED[g], Input.is_action_just_pressed("jump")]


func _gait_for(v: float) -> Gait:
	if v < 0.3:
		return Gait.STAND
	if v < 2.6:
		return Gait.WALK
	if v < 5.4:
		return Gait.TROT
	if v < 9.5:
		return Gait.CANTER
	return Gait.GALLOP


## Looks ahead along his path for things to jump, and for drops or climbs to refuse.
func _check_ahead(want_jump: bool) -> void:
	var space := get_world_3d().direct_space_state
	var fwd := get_facing_dir()
	var ex: Array[RID] = [get_rid()]
	if rider:
		ex.append(rider.get_rid())
	var look := 1.6 + speed * 0.28
	var mask := 1 | (1 << 3) | (1 << 6) | (1 << 7)
	var hit := {}
	for hgt: float in [0.3, 0.9]:
		var from := global_position + Vector3.UP * hgt
		hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + fwd * look, mask, ex))
		if not hit.is_empty():
			break
	if not hit.is_empty():
		# How tall is it? Probe down just inside the face (thin rails) and a little beyond
		# it (thick walls); the higher of the two is what he has to clear.
		var h := -1.0
		for into: float in [0.04, 0.3]:
			var probe := (hit["position"] as Vector3) + fwd * into
			var tq := PhysicsRayQueryParameters3D.create(Vector3(probe.x, global_position.y + 2.2, probe.z), Vector3(probe.x, global_position.y - 0.5, probe.z), mask, ex)
			tq.hit_from_inside = true # starting inside a tree trunk counts as "too high"
			var top := space.intersect_ray(tq)
			h = maxf(h, 99.0 if top.is_empty() else (top["position"] as Vector3).y - global_position.y)
		var n: Vector3 = hit["normal"]
		if n.y > 0.55:
			return # just rising ground
		if h <= MAX_JUMP and (speed > GAIT_SPEED[Gait.TROT] + 0.5 or want_jump) and _jump_cooldown <= 0.0:
			_jump(h)
		elif h > MAX_JUMP or speed > 2.0:
			if speed > 1.0:
				_refuse("too high")
		return
	# A drop ahead?
	var ahead := global_position + fwd * (1.8 + speed * 0.2)
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 1.0, ahead + Vector3.DOWN * (MAX_DROP + 1.0), mask, ex))
	if down.is_empty() and _ground_height(ahead) < global_position.y - MAX_DROP:
		_refuse("drop")
	elif not down.is_empty() and (down["position"] as Vector3).y < global_position.y - MAX_DROP:
		_refuse("drop")
	elif not down.is_empty() and (down["normal"] as Vector3).y < 0.62 and (down["position"] as Vector3).y > global_position.y + 0.4:
		_refuse("steep")
	elif want_jump and _jump_cooldown <= 0.0:
		_jump(0.3)


func _jump(h: float) -> void:
	is_jumping = true
	_jump_cooldown = 0.8
	velocity.y = sqrt(2.0 * _gravity * (maxf(h, 0.3) + 0.45))
	speed = maxf(speed, GAIT_SPEED[Gait.TROT])
	jumped.emit(h)


func _refuse(reason: String) -> void:
	if _refuse_timer > 0.0:
		return
	_refuse_timer = 1.2
	speed = 0.0
	_rear = 1.0
	refused.emit(reason)
	Stealth.make_noise(global_position, 12.0, "whinny", false, self)
	if rider:
		Stealth.bark(self, "%s shies and won't go on." % horse_name)


## Coming to a whistle but getting nowhere (a slope too steep, a thicket): like any horse
## in a story, he finds his own way round and turns up close by, out of view.
func _check_progress(dist: float, delta: float) -> void:
	_progress_timer += delta
	if _progress_timer < 3.0:
		return
	_progress_timer = 0.0
	if dist < _progress_dist - 1.0:
		_progress_dist = dist
		return
	_progress_dist = INF
	var cam := get_viewport().get_camera_3d()
	var behind := cam.global_basis.z if cam else Vector3.BACK
	behind.y = 0.0
	behind = behind.normalized() if behind.length() > 0.01 else Vector3.BACK
	for k in 8:
		var dir := behind.rotated(Vector3.UP, [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8, PI][k])
		var spot := _call_target + dir * 6.0
		var h := _ground_height(spot)
		if is_nan(h) or absf(h - _call_target.y) > 1.5:
			continue
		global_position = Vector3(spot.x, h + 0.1, spot.z)
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		return


## Simple look-ahead steering when he's coming to a whistle.
func _avoid(dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	for a: float in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var d := dir.rotated(Vector3.UP, a)
		var from := global_position + Vector3.UP * 0.7
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + d * 4.0, 1 | (1 << 3) | (1 << 6) | (1 << 7), ex)).is_empty():
			return d
	return dir


func _water_depth() -> float:
	var s := get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	if s == null:
		return 0.0
	return s.generator.water_depth(global_position.x, global_position.z)


func _ground_height(p: Vector3) -> float:
	var s := get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	if s:
		return s.generator.height(p.x, p.z)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 40.0, 1))
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


## In the hills, never sink through ground whose collision hasn't streamed in yet.
func _keep_above_ground() -> void:
	var s := get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	if s == null:
		return
	var h := s.generator.height(global_position.x, global_position.z)
	if global_position.y < h - 0.3:
		global_position.y = h
		velocity.y = 0.0


func _hoofbeats(delta: float) -> void:
	if not is_on_floor() or absf(speed) < 0.3:
		_stride_acc = 0.0
		return
	_stride_acc += absf(speed) * delta
	if _stride_acc >= STRIDE[gait]:
		_stride_acc = 0.0
		var suspicious := rider != null and rider.stealth.conspicuousness >= 0.45
		Stealth.make_noise(global_position, NOISE[gait], "hooves", suspicious, rider if rider else self)


# ---------------------------------------------------------------------------
# Body: a procedural dark bay horse, 16 hands (1.63 m at the withers), saddled
# ---------------------------------------------------------------------------
func _build_body() -> void:
	_visual = Node3D.new()
	_visual.name = "Body"
	add_child(_visual)
	if model_path != "" and ResourceLoader.exists(model_path):
		var model := (load(model_path) as PackedScene).instantiate() as Node3D
		_visual.add_child(model)
		# Legs etc. then come from the model's own animations (Phase 10 wires them up).
		_neck = Node3D.new()
		_tail = Node3D.new()
		_visual.add_child(_neck)
		_visual.add_child(_tail)
		for i in 4:
			var d1 := Node3D.new()
			var d2 := Node3D.new()
			_visual.add_child(d1)
			_visual.add_child(d2)
			_legs.append(d1)
			_knees.append(d2)
		return
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.09, 0.06, 0.045)
	coat.roughness = 0.72
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.025, 0.02)
	dark.roughness = 0.7
	var leather := MaterialLibrary.get_tinted("fabric", Color(0.35, 0.2, 0.1))
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.85, 0.83, 0.8)
	var mb := MeshBuilder.new()
	# A deep, narrow barrel (taller than wide), a deep chest and rounded quarters.
	var barrel := CapsuleMesh.new()
	barrel.radius = 0.31
	barrel.height = 1.75
	mb.add_mesh(barrel, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 1.25)), Vector3(0, 1.3, 0.05)), coat)
	var chest := SphereMesh.new()
	chest.radius = 0.33
	chest.height = 0.82
	mb.add_mesh(chest, Transform3D(Basis.IDENTITY.scaled(Vector3(0.95, 1.1, 1.0)), Vector3(0, 1.32, -0.62)), coat)
	for side: float in [-1.0, 1.0]:
		var quarter := SphereMesh.new()
		quarter.radius = 0.2
		quarter.height = 0.5
		mb.add_mesh(quarter, Transform3D(Basis.IDENTITY.scaled(Vector3(0.85, 1.1, 1.25)), Vector3(side * 0.11, 1.34, 0.68)), coat)
	var withers := SphereMesh.new()
	withers.radius = 0.16
	withers.height = 0.3
	mb.add_mesh(withers, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 2.0)), Vector3(0, 1.58, -0.55)), coat)
	# Saddle, girth and saddle cloth.
	mb.add_box(Vector3(0.52, 0.12, 0.62), Vector3(0, 1.68, 0.02), leather)
	mb.add_box(Vector3(0.12, 0.2, 0.16), Vector3(0, 1.78, -0.24), leather) # pommel
	mb.add_box(Vector3(0.8, 0.05, 0.75), Vector3(0, 1.6, 0.02), MaterialLibrary.get_tinted("fabric", Color(0.25, 0.08, 0.07)))
	mb.add_box(Vector3(0.82, 0.08, 0.1), Vector3(0, 1.28, -0.2), leather)
	for side: float in [-1.0, 1.0]:
		mb.add_box(Vector3(0.015, 0.45, 0.03), Vector3(side * 0.33, 1.4, 0.0), leather) # stirrup leathers
	mb.build_into(_visual, "Barrel")
	_neck = Node3D.new()
	_neck.position = Vector3(0, 1.55, -0.85)
	_visual.add_child(_neck)
	var nb := MeshBuilder.new()
	# The neck: deep where it meets the chest, tapering to the poll.
	var neck := CylinderMesh.new()
	neck.bottom_radius = 0.24
	neck.top_radius = 0.12
	neck.height = 1.0
	neck.radial_segments = 12
	nb.add_mesh(neck, Transform3D(Basis(Vector3.RIGHT, -0.72).scaled(Vector3(0.75, 1.0, 1.2)), Vector3(0, 0.32, -0.28)), coat)
	var head := CylinderMesh.new()
	head.bottom_radius = 0.07
	head.top_radius = 0.12
	head.height = 0.62
	head.radial_segments = 10
	nb.add_mesh(head, Transform3D(Basis(Vector3.RIGHT, 1.25).scaled(Vector3(0.8, 1.0, 1.1)), Vector3(0, 0.66, -0.68)), coat)
	var jaw := SphereMesh.new()
	jaw.radius = 0.1
	jaw.height = 0.2
	nb.add_mesh(jaw, Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.5)), coat)
	nb.add_box(Vector3(0.05, 0.35, 0.02), Vector3(0, 0.66, -0.75), white, Basis(Vector3.RIGHT, 1.3)) # blaze
	nb.add_box(Vector3(0.06, 0.8, 0.12), Vector3(0, 0.38, -0.12), dark, Basis(Vector3.RIGHT, -0.75)) # mane
	for side: float in [-1.0, 1.0]:
		nb.add_box(Vector3(0.04, 0.14, 0.05), Vector3(side * 0.08, 0.82, -0.45), coat)
		nb.add_box(Vector3(0.015, 0.015, 0.9), Vector3(side * 0.14, 0.62, -0.1), leather, Basis(Vector3.RIGHT, 0.35)) # reins
	nb.build_into(_neck, "Neck")
	_tail = Node3D.new()
	_tail.position = Vector3(0, 1.5, 1.15)
	_visual.add_child(_tail)
	var tb := MeshBuilder.new()
	tb.add_box(Vector3(0.12, 0.8, 0.12), Vector3(0, -0.38, 0.1), dark, Basis(Vector3.RIGHT, -0.25))
	tb.build_into(_tail, "Tail")
	for i in 4:
		var hip := Node3D.new()
		hip.position = Vector3(-0.2 if i % 2 == 0 else 0.2, 1.15, -0.62 if i < 2 else 0.72)
		_visual.add_child(hip)
		var ub := MeshBuilder.new()
		ub.add_box(Vector3(0.15, 0.55, 0.2), Vector3(0, -0.27, 0), coat)
		ub.build_into(hip, "Upper")
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.55, 0)
		hip.add_child(knee)
		var kb := MeshBuilder.new()
		kb.add_box(Vector3(0.09, 0.55, 0.1), Vector3(0, -0.27, 0), coat)
		kb.add_box(Vector3(0.12, 0.08, 0.14), Vector3(0, -0.56, -0.02), dark) # hoof
		if i >= 2:
			kb.add_box(Vector3(0.1, 0.12, 0.11), Vector3(0, -0.45, 0), white) # white socks behind
		kb.build_into(knee, "Lower")
		_legs.append(hip)
		_knees.append(knee)


func _animate(delta: float) -> void:
	_visual.rotation.y = _yaw
	var v := absf(speed)
	_phase += delta * TAU * (0.0 if v < 0.2 else clampf(v / STRIDE[gait], 0.6, 2.6))
	var amp := [0.0, 0.35, 0.5, 0.65, 0.85][gait] as float
	for i in 4:
		var offs: float
		match gait:
			Gait.WALK:
				offs = [0.0, 0.5, 0.75, 0.25][i] * TAU # four-beat
			Gait.TROT:
				offs = [0.0, 0.5, 0.5, 0.0][i] * TAU # diagonal pairs
			_:
				offs = [0.0, 0.15, 0.55, 0.7][i] * TAU # canter/gallop sequence
		var s := sin(_phase + offs)
		_legs[i].rotation.x = s * amp
		_knees[i].rotation.x = -maxf(-s, 0.0) * amp * 1.4 if i < 2 else maxf(s, 0.0) * amp * 1.2
	if is_jumping:
		for i in 4:
			_legs[i].rotation.x = -0.6 if i < 2 else 0.6
			_knees[i].rotation.x = -1.2 if i < 2 else 1.0
	_rear = move_toward(_rear, 0.0, delta * 1.2)
	_visual.rotation.x = _rear * 0.5
	_neck.rotation.x = lerpf(_neck.rotation.x, (-0.25 if gait >= Gait.CANTER else 0.0) + sin(_phase * 2.0) * 0.05 * amp - (0.6 if gait == Gait.STAND and rider == null and not called else 0.0), delta * 3.0)
	# Negative pitch swings the hanging tail out behind him; it streams at speed.
	_tail.rotation.x = -0.1 - v * 0.05 + sin(_phase) * 0.05
