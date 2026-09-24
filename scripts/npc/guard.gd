class_name Guard
extends CharacterBody3D
## A Metropolitan Police constable (or a private house guard) with realistic senses.
##
## Senses (checked 10x a second):
##   * Eyes: a cone (120 deg, sharpest in the central 50 deg), range shrinking with darkness,
##     fog and Harry's posture; needs clear line of sight to Harry's head, chest or hips.
##     Looking up at rooftops is harder than looking ahead.
##   * Ears: hears noises from Stealth.make_noise, muffled by walls.
## Suspicion only grows when what Harry is doing looks wrong (see HarryStealth).
##
## States: PATROL -> WAIT -> SUSPICIOUS -> INVESTIGATE -> SEARCH -> RETURN,
##         CHASE (after sounding his rattle), STUNNED and UNCONSCIOUS (Outlaw's Code:
##         Harry never kills). Guards who find an unconscious colleague raise the alarm.

signal state_changed(guard: Guard, old_state: State, new_state: State)

enum State { PATROL, WAIT, SUSPICIOUS, INVESTIGATE, SEARCH, CHASE, RETURN, STUNNED, UNCONSCIOUS }

const LAYER_NPC := 1 << 2
const MASK_SIGHT := 1 | (1 << 3)

@export var display_name: String = "Constable"
@export var patrol_route_path: NodePath
@export var outfit: NPCBody.Outfit = NPCBody.Outfit.CONSTABLE
@export_file("*.glb", "*.tscn") var body_model_path: String = ""

@export_group("Movement (m/s)")
@export var walk_speed: float = 1.35
@export var brisk_speed: float = 2.1
@export var run_speed: float = 5.2
@export var turn_speed: float = 5.0

@export_group("Eyes")
@export var vision_range: float = 26.0
@export var fov_degrees: float = 120.0
@export var focus_degrees: float = 50.0
@export var close_range: float = 2.2
@export var eye_height: float = 1.65

@export_group("Detection")
## Awareness gained per second when Harry is fully visible and fully suspicious.
@export var detection_rate: float = 1.5
@export var suspicious_at: float = 0.3
@export var investigate_at: float = 0.65
@export var decay_rate: float = 0.2
## Seconds without seeing Harry before a chasing guard loses him.
@export var lose_sight_time: float = 4.0
@export var catch_distance: float = 1.15

@export_group("Searching")
@export var search_duration: float = 25.0
@export var search_radius: float = 8.0
@export var hiding_spot_check_chance: float = 0.6

@export_group("Knocked out")
@export var unconscious_time: float = 240.0
@export var stun_time: float = 1.4

var state: State = State.PATROL
var awareness: float = 0.0
## Stays raised for a while after an incident; guards are sharper when on edge.
var alertness: float = 0.0
var last_known: Vector3 = Vector3.ZERO

var _agent: NavigationAgent3D
var _body: NPCBody
var _harry: Harry
var _route: PatrolRoute
var _route_i := 0
var _route_dir := 1
var _home := Transform3D.IDENTITY
var _yaw := 0.0
var _look_yaw := NAN
var _state_time := 0.0
var _wait_time := 0.0
var _perceive_timer := 0.0
var _unseen := 0.0
var _search_points: Array[Vector3] = []
var _search_timer := 0.0
var _pause := 0.0
var _poking: HidingSpot = null
var _checked_spots: Array[Node] = []
var _safe_velocity := Vector3.ZERO
var _has_safe_velocity := false
var _moving := false
var _speed := 0.0
var _pose: NPCBody.Pose = NPCBody.Pose.NORMAL
var _rattle_time := 0.0
var _chase_speed_mult := 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _bark_cooldown := 0.0
var _found_bodies: Array[Node] = []


func _ready() -> void:
	add_to_group("guards")
	collision_layer = LAYER_NPC
	collision_mask = 1 | (1 << 1) | (1 << 3) | LAYER_NPC
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.76
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	add_child(cs)

	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.radius = 0.35
	_agent.height = 1.8
	_agent.max_speed = run_speed
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = 6.0
	_agent.time_horizon_agents = 1.2
	_agent.velocity_computed.connect(func(v: Vector3) -> void:
		_safe_velocity = v
		_has_safe_velocity = true)
	add_child(_agent)

	_body = NPCBody.new()
	_body.name = "Body"
	_body.outfit = outfit
	_body.model_path = body_model_path
	add_child(_body)

	_yaw = rotation.y
	rotation = Vector3.ZERO
	_home = Transform3D(Basis(Vector3.UP, _yaw), global_position)
	if not patrol_route_path.is_empty():
		_route = get_node_or_null(patrol_route_path) as PatrolRoute
	Stealth.bus().noise_made.connect(_on_noise)
	_perceive_timer = randf() * 0.1
	_enter(State.PATROL if _route and _route.size() > 0 else State.WAIT)


func set_route(route: PatrolRoute) -> void:
	_route = route
	_route_i = route.nearest_index(global_position) if route.size() > 0 else 0
	_enter(State.PATROL)


# ---------------------------------------------------------------------------
# Public API (Harry, arrows, the game)
# ---------------------------------------------------------------------------
func is_down() -> bool:
	return state == State.UNCONSCIOUS or state == State.STUNNED


func get_facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## A takedown works from behind (or the side) on a guard who isn't chasing Harry.
func can_be_taken_down_from(pos: Vector3) -> bool:
	if state in [State.UNCONSCIOUS, State.STUNNED, State.CHASE]:
		return false
	var to_harry := pos - global_position
	to_harry.y = 0.0
	if to_harry.length() > 1.6:
		return false
	return get_facing_dir().dot(to_harry.normalized()) < 0.2


func receive_takedown(duration: float) -> void:
	_enter(State.STUNNED)
	_pause = duration
	_pose = NPCBody.Pose.STUNNED


func knock_out() -> void:
	_enter(State.UNCONSCIOUS)


## Hit by an arrow. Blunt arrows to the head knock an unwary man out; anywhere else they
## just hurt and give away where it came from.
func on_arrow_hit(kind: String, point: Vector3, from_dir: Vector3) -> void:
	if state == State.UNCONSCIOUS:
		return
	var head_y := global_position.y + 1.45
	if kind == "blunt" and point.y >= head_y and state != State.CHASE:
		knock_out()
		return
	last_known = point - from_dir.normalized() * 15.0
	alertness = 1.0
	awareness = maxf(awareness, investigate_at)
	_bark("hit")
	_enter(State.STUNNED)
	_pause = stun_time


## After Harry respawns (arrested or died), everyone goes back to their beat.
func reset_after_player_respawn() -> void:
	if state == State.UNCONSCIOUS:
		return
	awareness = 0.0
	alertness = 0.3
	global_position = _home.origin
	_yaw = _home.basis.get_euler().y
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_enter(State.PATROL if _route and _route.size() > 0 else State.WAIT)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _harry == null:
		_harry = get_tree().get_first_node_in_group("player") as Harry
	_state_time += delta
	_bark_cooldown = maxf(_bark_cooldown - delta, 0.0)
	alertness = move_toward(alertness, 0.0, delta / 120.0)
	_moving = false
	_speed = 0.0
	if state != State.STUNNED:
		_pose = NPCBody.Pose.NORMAL

	if not _nav_ready():
		_apply_movement(delta)
		return

	if state != State.UNCONSCIOUS and state != State.STUNNED:
		_perceive_timer -= delta
		if _perceive_timer <= 0.0:
			_perceive_timer = 0.1
			_perceive(0.1)

	match state:
		State.PATROL:
			_do_patrol(delta)
		State.WAIT:
			_do_wait(delta)
		State.SUSPICIOUS:
			_do_suspicious(delta)
		State.INVESTIGATE:
			_do_investigate(delta)
		State.SEARCH:
			_do_search(delta)
		State.CHASE:
			_do_chase(delta)
		State.RETURN:
			_do_return(delta)
		State.STUNNED:
			_pause -= delta
			if _pause <= 0.0:
				_enter(State.INVESTIGATE if awareness >= suspicious_at else State.SEARCH)
		State.UNCONSCIOUS:
			_pose = NPCBody.Pose.UNCONSCIOUS
			if _state_time >= unconscious_time:
				remove_from_group("unconscious_guards")
				alertness = 1.0
				awareness = suspicious_at
				last_known = global_position
				_bark("wake")
				_enter(State.SEARCH)
	_apply_movement(delta)


func _nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > 0


func _enter(new_state: State) -> void:
	var old := state
	state = new_state
	_state_time = 0.0
	match new_state:
		State.PATROL:
			if _route and _route.size() > 0:
				_agent.target_position = _route.get_point(_route_i)["position"]
		State.WAIT:
			_wait_time = 3.0
			if _route and _route.size() > 0:
				_wait_time = maxf(float(_route.get_point(_route_i)["wait"]), 0.5)
		State.SUSPICIOUS:
			_bark("suspicious")
		State.INVESTIGATE:
			_bark("investigate")
			_agent.target_position = last_known
		State.SEARCH:
			_start_search()
		State.CHASE:
			_unseen = 0.0
			alertness = 1.0
			if old != State.CHASE:
				_bark("chase")
				_rattle_time = 1.0
				Stealth.raise_alarm(global_position, self)
		State.RETURN:
			_bark("give_up")
			if _route and _route.size() > 0:
				_route_i = _route.nearest_index(global_position)
				_agent.target_position = _route.get_point(_route_i)["position"]
			else:
				_agent.target_position = _home.origin
		State.STUNNED:
			_pause = stun_time
		State.UNCONSCIOUS:
			add_to_group("unconscious_guards")
			awareness = 0.0
			velocity = Vector3.ZERO
			Stealth.make_noise(global_position, 5.0, "body_fall", true, self)
	if old != new_state:
		state_changed.emit(self, old, new_state)


# ---------------------------------------------------------------------------
# Senses
# ---------------------------------------------------------------------------
func _perceive(dt: float) -> void:
	_check_for_fallen_colleagues()
	if _harry == null or _harry.is_dead() or _harry.is_arrested():
		awareness = maxf(awareness - decay_rate * dt, 0.0)
		return
	var score := vision_score()
	if state == State.CHASE:
		if score > 0.04:
			last_known = _harry.global_position
			_unseen = 0.0
		return
	var suspicion := _harry.stealth.conspicuousness
	var gain := score * detection_rate * suspicion * (1.0 + alertness * 0.5) * dt
	if score > 0.25 and _harry.stealth.crime_timer > 0.0:
		gain = 1.0 # saw him do it
	if gain > 0.0:
		awareness = minf(awareness + gain, 1.0)
		last_known = _harry.global_position
	else:
		awareness = maxf(awareness - decay_rate * dt, 0.0)

	if awareness >= 1.0:
		_enter(State.CHASE)
	elif awareness >= investigate_at and state in [State.PATROL, State.WAIT, State.RETURN, State.SUSPICIOUS, State.SEARCH]:
		if state != State.SEARCH or gain > 0.0:
			_enter(State.INVESTIGATE)
	elif awareness >= suspicious_at and state in [State.PATROL, State.WAIT, State.RETURN]:
		_enter(State.SUSPICIOUS)


## How clearly this guard can see Harry right now (0 = not at all, 1 = plainly).
func vision_score() -> float:
	if _harry == null:
		return 0.0
	var eye := global_position + Vector3.UP * eye_height
	var fwd := get_facing_dir()
	var points := _harry.stealth.get_sample_points()
	var chest: Vector3 = points[1]
	var to_chest := chest - eye
	var dist := to_chest.length()
	if dist > vision_range:
		return 0.0
	var flat := Vector3(to_chest.x, 0.0, to_chest.z)
	var angle := rad_to_deg(fwd.angle_to(flat)) if flat.length() > 0.01 else 0.0
	if angle > fov_degrees * 0.5 and dist > 0.8:
		return 0.0
	var visible_points := 0
	var exclude: Array[RID] = [get_rid(), _harry.get_rid()]
	var space := get_world_3d().direct_space_state
	for p in points:
		var q := PhysicsRayQueryParameters3D.create(eye, p, MASK_SIGHT, exclude)
		if space.intersect_ray(q).is_empty():
			visible_points += 1
	if visible_points == 0:
		return 0.0
	var angle_factor := 1.0
	if angle > focus_degrees * 0.5:
		angle_factor = lerpf(1.0, 0.3, clampf((angle - focus_degrees * 0.5) / (fov_degrees * 0.5 - focus_degrees * 0.5), 0.0, 1.0))
	# People rarely look up: something high above is noticed less.
	var up_angle := rad_to_deg(asin(clampf(to_chest.y / maxf(dist, 0.01), -1.0, 1.0)))
	var vertical_factor := 1.0 if up_angle < 20.0 else lerpf(1.0, 0.35, clampf((up_angle - 20.0) / 40.0, 0.0, 1.0))
	var vis := _harry.stealth.visibility
	if dist <= close_range and not _harry.stealth.is_hidden():
		vis = maxf(vis, 0.6) # you can't miss someone right next to you
	var eff_range := vision_range * lerpf(0.15, 1.0, vis) * Stealth.visibility_multiplier
	if dist > eff_range:
		return 0.0
	var dist_factor := 1.0 - pow(dist / maxf(eff_range, 0.01), 2.0) * 0.85
	return clampf(angle_factor * vertical_factor * dist_factor * (float(visible_points) / points.size()) * (0.4 + 0.6 * vis), 0.0, 1.0)


func _on_noise(pos: Vector3, radius: float, kind: String, suspicious: bool, source: Node) -> void:
	if source == self or state == State.UNCONSCIOUS or state == State.STUNNED:
		return
	var ear := global_position + Vector3.UP * eye_height
	var d := ear.distance_to(pos)
	if d > radius:
		return
	var exclude: Array[RID] = [get_rid()]
	if _harry:
		exclude.append(_harry.get_rid())
	var q := PhysicsRayQueryParameters3D.create(ear, pos + Vector3.UP * 0.3, MASK_SIGHT, exclude)
	# A police rattle is built to carry over rooftops; everything else is muffled by walls.
	if kind != "rattle" and not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		if d > radius * 0.55:
			return
	if kind == "rattle":
		if state != State.CHASE:
			last_known = pos
			alertness = 1.0
			awareness = maxf(awareness, investigate_at)
			_chase_speed_mult = 1.0
			_bark("assist")
			_enter(State.INVESTIGATE)
		return
	if not suspicious:
		return
	if state == State.CHASE:
		if source == _harry:
			last_known = pos
		return
	last_known = pos
	var closeness := 1.0 - d / radius
	awareness = maxf(awareness, suspicious_at + 0.35 * closeness)
	if (closeness > 0.5 or radius >= 15.0) and state != State.INVESTIGATE:
		awareness = maxf(awareness, investigate_at)
		_enter(State.INVESTIGATE)
	elif state in [State.PATROL, State.WAIT, State.RETURN]:
		_enter(State.SUSPICIOUS)


func _check_for_fallen_colleagues() -> void:
	for node in get_tree().get_nodes_in_group("unconscious_guards"):
		if node == self or _found_bodies.has(node):
			continue
		var other := node as Node3D
		var eye := global_position + Vector3.UP * eye_height
		var target := other.global_position + Vector3.UP * 0.3
		if eye.distance_to(target) > vision_range * 0.7:
			continue
		var flat := Vector3(target.x - eye.x, 0.0, target.z - eye.z)
		if rad_to_deg(get_facing_dir().angle_to(flat)) > fov_degrees * 0.5:
			continue
		var exclude: Array[RID] = [get_rid(), (other as CollisionObject3D).get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target, MASK_SIGHT, exclude)).is_empty():
			continue
		_found_bodies.append(node)
		last_known = other.global_position
		alertness = 1.0
		awareness = maxf(awareness, investigate_at)
		_bark("man_down")
		Stealth.raise_alarm(global_position, self)
		if state != State.CHASE:
			_enter(State.INVESTIGATE)
		return


# ---------------------------------------------------------------------------
# Behaviours
# ---------------------------------------------------------------------------
func _do_patrol(_delta: float) -> void:
	if _route == null or _route.size() == 0:
		_enter(State.WAIT)
		return
	var p: Dictionary = _route.get_point(_route_i)
	if _move_to(p["position"], walk_speed):
		_enter(State.WAIT)


func _do_wait(_delta: float) -> void:
	var yaw: float = NAN
	if _route and _route.size() > 0:
		yaw = float(_route.get_point(_route_i)["yaw"])
	else:
		yaw = _home.basis.get_euler().y
		if global_position.distance_to(_home.origin) > 0.8:
			_move_to(_home.origin, walk_speed)
			return
	if not is_nan(yaw):
		_look_yaw = yaw
	_pose = NPCBody.Pose.LOOK_AROUND if fmod(_state_time, 12.0) > 8.0 else NPCBody.Pose.NORMAL
	if _route and _route.size() > 1 and _state_time >= _wait_time:
		var n := _route.next_index(_route_i, _route_dir)
		_route_i = n.x
		_route_dir = n.y
		_enter(State.PATROL)


func _do_suspicious(_delta: float) -> void:
	_face_point(last_known)
	if awareness < 0.12 and _state_time > 2.5:
		_enter(State.RETURN)


func _do_investigate(_delta: float) -> void:
	var speed := run_speed * 0.8 if alertness >= 1.0 and _state_time < 20.0 else brisk_speed
	if _move_to(last_known, speed) or _state_time > 30.0:
		_enter(State.SEARCH)


func _start_search() -> void:
	_search_timer = search_duration * (1.5 if alertness >= 1.0 else 1.0)
	_search_points.clear()
	_checked_spots.clear()
	_poking = null
	_pause = 2.5
	var map := get_world_3d().navigation_map
	for i in 4:
		var a := randf() * TAU
		var r := randf_range(2.5, search_radius)
		var p := last_known + Vector3(cos(a) * r, 0.0, sin(a) * r)
		_search_points.append(NavigationServer3D.map_get_closest_point(map, p))


func _do_search(delta: float) -> void:
	_search_timer -= delta
	if _search_timer <= 0.0:
		_enter(State.RETURN)
		return
	if _pause > 0.0:
		_pause -= delta
		_pose = NPCBody.Pose.LOOK_AROUND
		return
	# Poke hiding places near the search area.
	if _poking == null:
		for node in get_tree().get_nodes_in_group("hiding_spots"):
			var spot := node as HidingSpot
			if _checked_spots.has(spot) or spot.global_position.distance_to(last_known) > search_radius + 2.0:
				continue
			_checked_spots.append(spot)
			if randf() < hiding_spot_check_chance:
				_poking = spot
				break
	if _poking:
		if _move_to(_poking.global_position, brisk_speed) or global_position.distance_to(_poking.global_position) < 1.6:
			_face_point(_poking.global_position)
			if _poking.is_occupied():
				awareness = 1.0
				last_known = _poking.global_position
				_bark("found")
				_enter(State.CHASE)
				return
			_poking = null
			_pause = 1.5
		return
	if _search_points.is_empty():
		_start_search()
		return
	if _move_to(_search_points[0], brisk_speed):
		_search_points.pop_front()
		_pause = 2.0
		if _bark_cooldown <= 0.0 and randf() < 0.4:
			_bark("searching")


func _do_chase(delta: float) -> void:
	if _rattle_time > 0.0:
		_rattle_time -= delta
		_pose = NPCBody.Pose.RATTLE
		_face_point(last_known)
		return
	_pose = NPCBody.Pose.ALERT
	if _harry == null:
		_enter(State.SEARCH)
		return
	_unseen += delta
	var target := last_known
	var high_up := target.y > global_position.y + 1.8
	if high_up:
		# He's up on the roofs or a ledge: get underneath and keep watching.
		target = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, Vector3(target.x, global_position.y, target.z))
		if _bark_cooldown <= 0.0 and _unseen < 0.5:
			_bark("come_down")
	var flat_dist := Vector2(global_position.x - _harry.global_position.x, global_position.z - _harry.global_position.z).length()
	var vertical := absf(_harry.global_position.y - global_position.y)
	if flat_dist <= catch_distance and vertical < 1.2 and _unseen < 0.5 and not _harry.is_climbing():
		_bark("arrest")
		_harry.arrest(self)
		_enter(State.WAIT)
		return
	if _move_to(target, run_speed) and high_up:
		_face_point(_harry.global_position)
	if _unseen >= lose_sight_time:
		_bark("lost")
		awareness = investigate_at
		_enter(State.INVESTIGATE)


func _do_return(_delta: float) -> void:
	var target := _home.origin
	if _route and _route.size() > 0:
		target = _route.get_point(_route_i)["position"]
	if _move_to(target, walk_speed):
		_enter(State.PATROL if _route and _route.size() > 1 else State.WAIT)


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
## Walks towards `target` along the navmesh. Returns true on arrival.
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
	_agent.max_speed = speed
	_agent.velocity = dir * speed
	_look_yaw = atan2(-dir.x, -dir.z)
	return false


func _face_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		_look_yaw = atan2(-d.x, -d.z)


func _apply_movement(delta: float) -> void:
	var h := Vector3.ZERO
	if _moving:
		h = _safe_velocity if _has_safe_velocity else _agent.velocity
		h.y = 0.0
	if state == State.UNCONSCIOUS or state == State.STUNNED:
		h = Vector3.ZERO
	var cur := Vector3(velocity.x, 0.0, velocity.z)
	cur = cur.move_toward(h, 12.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	if is_on_floor() and h != Vector3.ZERO:
		CharacterMotion.try_step_up(self, velocity, delta, 0.34)
	move_and_slide()
	if not is_nan(_look_yaw) and state != State.UNCONSCIOUS:
		_yaw = rotate_toward(_yaw, _look_yaw, turn_speed * delta)
	_body.rotation.y = _yaw
	_body.update_body(Vector2(velocity.x, velocity.z).length(), _pose, delta)


# ---------------------------------------------------------------------------
# Voice (subtitles; recorded lines arrive with the sound pass in Phase 10)
# ---------------------------------------------------------------------------
const LINES := {
	"suspicious": ["Hullo? Who's there?", "Something moved...", "Oi! Show yourself!"],
	"investigate": ["Hear that? I'll take a look.", "What's all this, then?"],
	"searching": ["Come out, I know you're about.", "No use hiding, lad.", "Check behind there..."],
	"give_up": ["Must've been a cat.", "Rats, most likely.", "Eyes playing tricks on me."],
	"chase": ["Stop, thief!", "You there! Stop, in the name of the law!"],
	"assist": ["That's a rattle! Coming!", "Constable needs assistance!"],
	"lost": ["Where'd he go?", "Lost him, blast it!"],
	"man_down": ["Constable down! Raise the alarm!"],
	"hit": ["Argh! Who threw that?"],
	"wake": ["Ugh... my head... Someone's been here!"],
	"come_down": ["Come down from there!", "You can't stay up there all night!"],
	"arrest": ["Got you, you blighter!"],
	"found": ["Aha! Out you come!"],
}


func _bark(kind: String) -> void:
	if not LINES.has(kind):
		return
	var options: Array = LINES[kind]
	Stealth.bark(self, "%s: \"%s\"" % [display_name, options[randi() % options.size()]])
	_bark_cooldown = 4.0
