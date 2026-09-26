class_name GuardDog
extends CharacterBody3D
## A mastiff loosed in the grounds at night (chained by its kennel during the day).
##
## Senses, checked 7 times a second:
##   * Nose: picks up Harry's scent within ~12 m, much farther downwind of him and much
##     less upwind (Weather.wind_direction), less in rain, less through walls or from a
##     roof. A hiding place doesn't fool a dog for long.
##   * Eyes: movement within ~16 m.
##   * Ears: hears suspicious sounds farther than a man.
## States: KENNEL / PATROL -> ALERT (stiffens, growls) -> TRACK (follows the scent, baying)
##   -> CHASE (sees him: runs faster than any man; bites) -> BAY (he's out of reach up a
##   wall or tree: stands beneath barking for the guards) -> RETURN.
## Every bark is a loud noise that brings the guards. A blunt arrow sends it off yelping
## (the Outlaw's Code: no killing, not even the dogs).

signal state_changed(dog: GuardDog, new_state: State)

enum State { KENNEL, PATROL, ALERT, TRACK, CHASE, BAY, FLEE, RETURN }

const LAYER_NPC := 1 << 2
const MASK_SIGHT := 1 | (1 << 3) | (1 << 7)

@export var display_name: String = "Mastiff"
@export var trot_speed: float = 1.6
@export var track_speed: float = 3.2
## A big dog at full stretch comfortably outruns a sprinting man (~6.4 m/s).
@export var run_speed: float = 7.4
@export var smell_range: float = 12.0
@export var sight_range: float = 16.0
@export var bite_damage: float = 9.0
@export var bite_interval: float = 1.3
@export var bark_radius: float = 32.0
## Chained dogs can't go farther than this from their kennel.
@export var chained: bool = false
@export var chain_length: float = 2.5
@export var flee_time: float = 25.0

var state: State = State.PATROL
## 0..1: how sure the dog is that someone's about.
var scent: float = 0.0
var last_scent: Vector3 = Vector3.ZERO
var sees_harry: bool = false

var _harry: Harry
var _agent: NavigationAgent3D
var _route: PatrolRoute
var _route_i := 0
var _route_dir := 1
var _home := Vector3.ZERO
var _yaw := 0.0
var _look_yaw := NAN
var _state_time := 0.0
var _sense_timer := 0.0
var _bark_timer := 0.0
var _bite_timer := 0.0
var _unseen := 0.0
var _wait := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _moving := false
var _speed := 0.0
var _gait_phase := 0.0
var _visual: Node3D
var _legs: Array[Node3D] = []
var _head: Node3D
var _tail: Node3D


func _ready() -> void:
	add_to_group("guard_dogs")
	collision_layer = LAYER_NPC
	collision_mask = 1 | (1 << 1) | (1 << 3) | LAYER_NPC | (1 << 6) | (1 << 7)
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(46.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 0.85
	cs.shape = cap
	cs.position = Vector3(0, 0.43, 0)
	add_child(cs)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.radius = 0.35
	_agent.height = 0.9
	_agent.max_speed = run_speed
	_agent.avoidance_enabled = false
	add_child(_agent)
	_build_body()
	_yaw = rotation.y
	rotation = Vector3.ZERO
	_home = global_position
	Stealth.bus().noise_made.connect(_on_noise)
	_enter(State.KENNEL if chained else State.PATROL)


func set_route(route: PatrolRoute) -> void:
	_route = route
	_route_i = route.nearest_index(global_position) if route and route.size() > 0 else 0


## Chain the dog at its kennel (day) or loose it in the grounds (night).
func set_chained(on: bool, kennel: Vector3 = Vector3.INF) -> void:
	chained = on
	if kennel != Vector3.INF:
		_home = kennel
	if state in [State.KENNEL, State.PATROL, State.RETURN]:
		_enter(State.RETURN)


func is_down() -> bool:
	return false


func get_facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## Hit by an arrow: yelp and run off for a while. It knows where it came from.
func on_arrow_hit(_kind: String, _point: Vector3, from_dir: Vector3) -> void:
	last_scent = global_position - from_dir.normalized() * 10.0
	Stealth.make_noise(global_position, 14.0, "yelp", true, self)
	Stealth.bark(self, "%s: *yelps*" % display_name)
	_enter(State.FLEE)


func reset_after_player_respawn() -> void:
	scent = 0.0
	global_position = _home
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_enter(State.KENNEL if chained else State.PATROL)


# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _harry == null:
		_harry = get_tree().get_first_node_in_group("player") as Harry
	_state_time += delta
	_bark_timer -= delta
	_bite_timer -= delta
	_moving = false
	_speed = 0.0
	if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) == 0:
		_apply_movement(delta)
		return
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = 0.15
		_sense(0.15)
	match state:
		State.KENNEL:
			_look_yaw = NAN
			if global_position.distance_to(_home) > 0.8:
				_move_to(_home, trot_speed)
		State.PATROL:
			_do_patrol(delta)
		State.ALERT:
			_face(last_scent)
			if scent >= 1.0 or sees_harry:
				_bay_bark()
				_enter(State.CHASE if sees_harry else State.TRACK)
			elif scent < 0.15 and _state_time > 3.0:
				_enter(State.RETURN)
		State.TRACK:
			var close := _harry != null and _harry.global_position.distance_to(global_position) < 2.5 and absf(_harry.global_position.y - global_position.y) < 1.2
			if sees_harry or (close and scent >= 0.8):
				_enter(State.CHASE) # nose to his boots: found him
			elif _move_to(_leash(last_scent), track_speed) or _state_time > 40.0:
				if scent < 0.2 and _state_time > 6.0:
					_enter(State.RETURN)
			if _bark_timer <= 0.0:
				_bay_bark()
		State.CHASE:
			_do_chase(delta)
		State.BAY:
			_do_bay()
		State.FLEE:
			_move_to(_home, run_speed * 0.8)
			if _state_time > 1.0 and _bark_timer <= 0.0:
				_bark_timer = 3.0
				Stealth.make_noise(global_position, 8.0, "whimper", false, self)
			if _state_time > flee_time:
				scent = 0.0
				_enter(State.RETURN)
		State.RETURN:
			var target := _home
			if not chained and _route and _route.size() > 0:
				target = _route.get_point(_route_i)["position"]
			if _move_to(target, trot_speed):
				_enter(State.KENNEL if chained else State.PATROL)
	_apply_movement(delta)


func _enter(s: State) -> void:
	if s == state and _state_time > 0.0:
		return
	state = s
	_state_time = 0.0
	match s:
		State.ALERT:
			Stealth.make_noise(global_position, 6.0, "growl", true, self)
			Stealth.bark(self, "%s: *growls*" % display_name)
		State.CHASE:
			_unseen = 0.0
		State.BAY:
			_bark_timer = 0.0
	state_changed.emit(self, s)


func _bay_bark() -> void:
	_bark_timer = 1.4 if state == State.CHASE or state == State.BAY else 2.4
	# The guards come to the barking (and a dog on a scent is worth following).
	Stealth.make_noise(global_position, bark_radius, "dog_bark", true, self)
	Stealth.bark(self, "%s: *barks furiously*" % display_name)


# ---------------------------------------------------------------------------
# Senses
# ---------------------------------------------------------------------------
func _sense(dt: float) -> void:
	sees_harry = false
	if _harry == null or _harry.is_dead() or _harry.is_arrested() or state == State.FLEE:
		scent = maxf(scent - 0.3 * dt, 0.0)
		return
	var nose := global_position + Vector3.UP * 0.55
	var hp := _harry.global_position + Vector3.UP * 1.0
	var d := nose.distance_to(hp)
	var range_now := scent_range()
	if d < range_now:
		scent = minf(scent + (1.0 - d / range_now) * dt * 2.2, 1.0)
		last_scent = _harry.global_position
	else:
		scent = maxf(scent - 0.25 * dt, 0.0)
	# Sight: movement, or a man plainly visible.
	if d < sight_range * Stealth.visibility_multiplier and not _harry.stealth.is_hidden():
		var flat := Vector3(hp.x - nose.x, 0.0, hp.z - nose.z)
		var in_view := flat.length() < 1.0 or rad_to_deg(get_facing_dir().angle_to(flat)) < 120.0
		var noticeable := _harry.stealth.visibility > 0.12 or _harry.get_horizontal_speed() > 1.0
		if in_view and noticeable and d < sight_range * (0.35 + 0.65 * _harry.stealth.visibility + (0.3 if _harry.get_horizontal_speed() > 1.0 else 0.0)):
			var q := PhysicsRayQueryParameters3D.create(nose, hp, MASK_SIGHT, [get_rid(), _harry.get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				sees_harry = true
				scent = 1.0
				last_scent = _harry.global_position
	if state in [State.KENNEL, State.PATROL, State.RETURN] and (scent >= 0.35 or sees_harry):
		_enter(State.ALERT)


## How far away Harry can be smelt right now.
func scent_range() -> float:
	if _harry == null:
		return 0.0
	var to_dog := global_position - _harry.global_position
	to_dog.y = 0.0
	var r := smell_range
	if to_dog.length() > 0.1:
		# Wind blowing from Harry towards the dog carries the scent; against it, hardly at all.
		var downwind := Weather.wind_direction.dot(to_dog.normalized())
		r *= 1.0 + downwind * clampf(Weather.wind * 1.6, 0.0, 0.85)
	r *= 1.0 - 0.45 * Weather.rain
	if _harry.stealth.is_hidden():
		r *= 0.6
	if _harry.global_position.y - global_position.y > 3.0:
		r *= 0.5 # up on a roof, the scent drifts away overhead
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.55, _harry.global_position + Vector3.UP * 1.0, 1 | (1 << 7), [get_rid(), _harry.get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		r *= 0.4 # walls in between
	return r


func _on_noise(pos: Vector3, radius: float, kind: String, suspicious: bool, source: Node) -> void:
	if source == self or state == State.FLEE or not suspicious:
		return
	if source is GuardDog or kind in ["rattle", "dog_bark", "growl", "yelp"]:
		return
	var d := global_position.distance_to(pos)
	if d > radius * 1.3:
		return
	last_scent = pos
	if state in [State.KENNEL, State.PATROL, State.RETURN, State.ALERT]:
		scent = maxf(scent, 0.5)
		if state != State.ALERT:
			_enter(State.ALERT)
		elif _state_time > 1.0:
			_bay_bark()
			_enter(State.TRACK)


# ---------------------------------------------------------------------------
# Behaviours
# ---------------------------------------------------------------------------
func _do_patrol(delta: float) -> void:
	if _route == null or _route.size() == 0:
		_move_to(_home, trot_speed)
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var p: Dictionary = _route.get_point(_route_i)
	if _move_to(p["position"], trot_speed):
		var n := _route.next_index(_route_i, _route_dir)
		_route_i = n.x
		_route_dir = n.y
		_wait = randf_range(1.0, 4.0) # stops to sniff


func _do_chase(delta: float) -> void:
	if _harry == null:
		_enter(State.RETURN)
		return
	var hp := _harry.global_position
	var dy := hp.y - global_position.y
	if dy > 1.4 or _harry.is_climbing():
		_enter(State.BAY)
		return
	if sees_harry:
		_unseen = 0.0
	else:
		_unseen += delta
	if _bark_timer <= 0.0:
		_bay_bark()
	var target := _leash(hp if _unseen < 1.0 else last_scent)
	var flat := Vector2(hp.x - global_position.x, hp.z - global_position.z).length()
	if flat < 1.15 and absf(dy) < 0.8 and _bite_timer <= 0.0:
		_bite_timer = bite_interval
		_face(hp)
		Stealth.bark(self, "%s: *bites!*" % display_name)
		_harry.apply_damage(bite_damage)
		Stealth.make_noise(global_position, 18.0, "dog_bark", true, self)
	elif flat >= 1.0:
		_move_to(target, run_speed)
	if _unseen > 5.0:
		_enter(State.TRACK)


func _do_bay() -> void:
	if _harry == null:
		_enter(State.RETURN)
		return
	var hp := _harry.global_position
	var below := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, Vector3(hp.x, global_position.y, hp.z))
	_move_to(_leash(below), run_speed * 0.7)
	_face(hp)
	if _bark_timer <= 0.0:
		_bay_bark()
	if hp.y - global_position.y < 1.2 and not _harry.is_climbing():
		_enter(State.CHASE)
	elif not sees_harry and _state_time > 12.0 and scent < 0.5:
		_enter(State.TRACK)
	elif _state_time > 60.0:
		_enter(State.RETURN)


## A chained dog can only reach so far from its kennel.
func _leash(p: Vector3) -> Vector3:
	if not chained:
		return p
	var off := p - _home
	off.y = 0.0
	if off.length() <= chain_length:
		return p
	return _home + off.normalized() * chain_length


func _move_to(target: Vector3, speed: float) -> bool:
	if _agent.target_position.distance_to(target) > 0.3:
		_agent.target_position = target
	var flat := Vector2(target.x - global_position.x, target.z - global_position.z).length()
	if flat < 0.6 or _agent.is_navigation_finished():
		return true
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return false
	dir = dir.normalized()
	_moving = true
	_speed = speed
	_look_yaw = atan2(-dir.x, -dir.z)
	return false


func _face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		_look_yaw = atan2(-d.x, -d.z)


func _apply_movement(delta: float) -> void:
	var want := Vector3.ZERO
	if _moving:
		want = Vector3(-sin(_look_yaw), 0.0, -cos(_look_yaw)) * _speed
	var cur := Vector3(velocity.x, 0.0, velocity.z).move_toward(want, 16.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	if is_on_floor() and want != Vector3.ZERO:
		CharacterMotion.try_step_up(self, velocity, delta, 0.3)
	move_and_slide()
	if chained:
		# The chain pulls taut: it can't go an inch farther, however hard it runs.
		var off := global_position - _home
		off.y = 0.0
		if off.length() > chain_length:
			var back := off.normalized() * chain_length
			global_position = Vector3(_home.x + back.x, global_position.y, _home.z + back.z)
			velocity.x = 0.0
			velocity.z = 0.0
	if not is_nan(_look_yaw):
		_yaw = rotate_toward(_yaw, _look_yaw, 7.0 * delta)
	_animate(delta)


# ---------------------------------------------------------------------------
# Body: a procedural mastiff (swap in a rigged model in Phase 10)
# ---------------------------------------------------------------------------
var _body: AnimalBody


func _build_body() -> void:
	_visual = Node3D.new()
	_visual.name = "Body"
	add_child(_visual)
	if AnimalLook.has_species("mastiff"):
		# The real mastiff: heavy, broad-headed, and it runs like a dog.
		_body = AnimalBody.new()
		_body.species = "mastiff"
		_body.variation_seed = hash(str(get_path()) if is_inside_tree() else name)
		_visual.add_child(_body)
		if _body.is_ok():
			return
		_body.queue_free()
		_body = null
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.2, 0.15, 0.1)
	coat.roughness = 0.9
	var muzzle := StandardMaterial3D.new()
	muzzle.albedo_color = Color(0.07, 0.06, 0.05)
	muzzle.roughness = 0.8
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(0.34, 0.34, 0.8), Vector3(0, 0.62, 0.02), coat) # barrel
	mb.add_box(Vector3(0.38, 0.4, 0.3), Vector3(0, 0.64, -0.28), coat) # deep chest
	mb.add_box(Vector3(0.2, 0.22, 0.25), Vector3(0, 0.78, -0.45), coat, Basis(Vector3.RIGHT, 0.6)) # neck
	mb.build_into(_visual, "Torso")
	_head = Node3D.new()
	_head.position = Vector3(0, 0.88, -0.56)
	_visual.add_child(_head)
	var hb := MeshBuilder.new()
	hb.add_box(Vector3(0.26, 0.24, 0.26), Vector3(0, 0.02, -0.05), coat)
	hb.add_box(Vector3(0.18, 0.14, 0.16), Vector3(0, -0.04, -0.24), muzzle)
	hb.add_box(Vector3(0.06, 0.12, 0.03), Vector3(-0.12, 0.08, 0.02), muzzle, Basis(Vector3.FORWARD, 0.4))
	hb.add_box(Vector3(0.06, 0.12, 0.03), Vector3(0.12, 0.08, 0.02), muzzle, Basis(Vector3.FORWARD, -0.4))
	hb.build_into(_head, "Head")
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.74, 0.42)
	_visual.add_child(_tail)
	var tb := MeshBuilder.new()
	tb.add_box(Vector3(0.05, 0.05, 0.36), Vector3(0, 0, 0.17), coat)
	tb.build_into(_tail, "Tail")
	for i in 4:
		var hip := Node3D.new()
		hip.position = Vector3(-0.12 if i % 2 == 0 else 0.12, 0.5, -0.3 if i < 2 else 0.32)
		_visual.add_child(hip)
		var lb := MeshBuilder.new()
		lb.add_box(Vector3(0.09, 0.5, 0.1), Vector3(0, -0.22, 0), coat)
		lb.add_box(Vector3(0.1, 0.05, 0.13), Vector3(0, -0.47, -0.02), muzzle)
		lb.build_into(hip, "Leg")
		_legs.append(hip)


func _animate(delta: float) -> void:
	_visual.rotation.y = _yaw
	var v := Vector2(velocity.x, velocity.z).length()
	if _body:
		var alert := state in [State.ALERT, State.TRACK, State.CHASE, State.BAY]
		_body.want("alert", 1.0 if alert and state != State.TRACK else 0.0, 3.0)
		# Nose down on a scent; lying by the kennel.
		_body.want("graze", 0.7 if state == State.TRACK else 0.0, 2.0)
		_body.want("lie", 1.0 if state == State.KENNEL and v < 0.1 else 0.0, 1.0)
		var bark := sin(_state_time * 18.0) * 0.08 if state == State.BAY or (state == State.CHASE and _bark_timer > 1.2) else 0.0
		_body.look_at_angle(0.0, bark)
		_body.update_body(delta, v, 0.0, _yaw)
		return
	_gait_phase += delta * (2.0 + v * 2.2)
	var swing := clampf(v / 3.0, 0.0, 1.0) * 0.6
	for i in 4:
		var ph := _gait_phase + (PI if i in [1, 2] else 0.0)
		_legs[i].rotation.x = sin(ph) * swing
	var alert := state in [State.ALERT, State.TRACK, State.CHASE, State.BAY]
	_head.rotation.x = -0.25 if state == State.TRACK else (0.15 if alert else 0.0) # nose down on a scent
	_tail.rotation.x = (0.6 if alert else -0.5) + sin(_gait_phase * 2.0) * (0.15 if v > 0.2 else 0.05)
	if state == State.BAY or (state == State.CHASE and _bark_timer > 1.2):
		_head.rotation.x += sin(_state_time * 18.0) * 0.08
