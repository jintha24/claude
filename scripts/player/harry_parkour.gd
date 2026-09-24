class_name HarryParkour
extends Node
## Climbing and parkour for Harry: hang, shimmy, climb up, hop up to a higher ledge,
## jump-grab (with a running wall-run for high ledges), drop to hang from an edge,
## drainpipe climbing, vaulting and mantling.
##
## While an action is running this node owns Harry's position (he's moved along a path
## that ParkourSensor has already checked for space), so he can never clip into walls.
## Harry's own script handles everything on the ground, including landing rolls.

enum Action { NONE, GRAB, HANG, CLIMB_UP, PIPE, VAULT }

@export_group("Reach (m above feet)")
## Top of a ledge Harry can grab standing still (with a small jump).
@export var standing_reach: float = 2.95
## Top of a ledge Harry can reach by running up the wall first (needs speed).
@export var wall_run_reach: float = 3.6
@export var wall_run_min_speed: float = 2.8
## Obstacles up to this height are vaulted or mantled instead of grabbed.
@export var vault_max_height: float = 1.3

@export_group("Timing (s)")
@export var climb_up_time: float = 1.1
@export var mantle_time: float = 0.65
@export var grab_time: float = 0.3
@export var hop_time: float = 0.55
@export var vault_time: float = 0.5

@export_group("Speeds (m/s)")
@export var shimmy_speed_max: float = 0.75
@export var pipe_up_speed: float = 0.8
@export var pipe_down_speed: float = 1.4
## Falling faster than this, Harry can no longer hold on to a ledge (about a 4.5 m drop).
@export var max_grab_fall_speed: float = 9.5

var action: Action = Action.NONE
var ledge: Dictionary = {}
var pipe: Dictionary = {}
var progress := 0.0
## Signed sideways speed while hanging (+ = Harry's right). Used by the animator.
var shimmy_speed := 0.0
## Vertical speed on a drainpipe (+ = up). Used by the animator.
var pipe_speed := 0.0
var sensor: ParkourSensor

var _harry: Harry
var _duration := 1.0
var _from := Vector3.ZERO
var _mid := Vector3.ZERO
var _to := Vector3.ZERO
var _then: Action = Action.NONE
var _end_crouched := false
var _exit_velocity := Vector3.ZERO
var _cooldown := 0.0
var _up_hold := 0.0


func setup(harry: Harry, radius: float, stand_h: float, crouch_h: float) -> void:
	_harry = harry
	sensor = ParkourSensor.new(harry, radius, stand_h, crouch_h)


func is_busy() -> bool:
	return action != Action.NONE


func cancel() -> void:
	action = Action.NONE
	shimmy_speed = 0.0
	pipe_speed = 0.0


## World positions for Harry's hands (left, right) when they should be on a ledge or pipe.
## Empty when the hands are free. Used by hand IK.
func get_hand_targets() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if action == Action.HANG or (action == Action.CLIMB_UP and progress < 0.45):
		var e: Vector3 = ledge["edge"]
		var n: Vector3 = ledge["normal"]
		var right := (-n).cross(Vector3.UP)
		out.append(e - right * 0.24 - n * 0.04 + Vector3.UP * 0.02)
		out.append(e + right * 0.24 - n * 0.04 + Vector3.UP * 0.02)
	elif action == Action.PIPE:
		var axis: Vector3 = pipe["axis_bottom"]
		var n2: Vector3 = pipe["normal"]
		var feet := _harry.global_position
		var right2 := (-n2).cross(Vector3.UP)
		var grip := Vector3(axis.x, feet.y, axis.z) + n2 * 0.06
		out.append(grip - right2 * 0.05 + Vector3.UP * 1.95)
		out.append(grip + right2 * 0.05 + Vector3.UP * 1.65)
	return out


func get_action_duration() -> float:
	return _duration


func get_wall_normal() -> Vector3:
	if action == Action.PIPE:
		return pipe["normal"]
	if not ledge.is_empty():
		return ledge["normal"]
	return Vector3.ZERO


# ---------------------------------------------------------------------------
# Triggers (called by Harry)
# ---------------------------------------------------------------------------

## Jump pressed while standing/running: vault, mantle, climb, grab or pipe. False = just jump.
func try_ground_action(wish_dir: Vector3, hspeed: float) -> bool:
	var dir := wish_dir if wish_dir != Vector3.ZERO else _harry.get_facing_dir()
	var feet := _harry.global_position
	if try_pipe(dir):
		return true

	# Low obstacle: vault over it if it's thin and we're moving, otherwise climb onto it.
	var obs := sensor.find_obstacle(feet, dir, 0.6 + hspeed * 0.12)
	if not obs.is_empty():
		var h: float = obs["top"] - feet.y
		if h > 0.3 and h <= vault_max_height:
			if obs.has("landing") and hspeed > 1.0:
				_start_vault(obs, dir, hspeed)
				return true
			var low := sensor.find_ledge(feet, dir, feet.y + 0.3, feet.y + vault_max_height, 0.9)
			if not low.is_empty() and low["can_stand_on_top"]:
				_start_climb(low, false)
				return true

	var reach := wall_run_reach if hspeed >= wall_run_min_speed else standing_reach
	# Running at a wall, Harry takes a stride or two up it, so look further ahead.
	var high := sensor.find_ledge(feet, dir, feet.y + vault_max_height, feet.y + reach, 0.8 + hspeed * 0.25)
	if high.is_empty():
		return false
	var top_h: float = high["top"] - feet.y
	if top_h <= 1.9 and high["can_stand_on_top"]:
		_start_climb(high, false)
		return true
	var hang := ParkourSensor.hang_feet(high)
	if hang.y < feet.y + 0.05:
		return false # too low to hang from without the feet going through the floor
	if not sensor.hang_fits(hang):
		return false
	_start_grab(high, hang, grab_time + 0.1 * top_h)
	return true


## Called every frame while Harry is in the air.
func try_air_grab(wish_dir: Vector3) -> bool:
	if _cooldown > 0.0:
		return false
	var vy := _harry.velocity.y
	if vy > 2.5 or vy < -max_grab_fall_speed:
		return false
	var dir := wish_dir if wish_dir != Vector3.ZERO else _harry.get_facing_dir()
	var feet := _harry.global_position
	if try_pipe(dir, 0.55):
		return true
	var l := sensor.find_ledge(feet, dir, feet.y + 1.5, feet.y + 2.35, 0.6)
	if l.is_empty():
		return false
	var hang := ParkourSensor.hang_feet(l)
	if not sensor.hang_fits(hang):
		return false
	_start_grab(l, hang, 0.18)
	# Catching yourself after a drop hurts the arms a little on big drops.
	if vy < -7.0:
		_harry.apply_damage((absf(vy) - 7.0) * 4.0)
	return true


## Crouch-walking off an edge: turn around and lower into a hang instead of falling.
func try_drop_to_hang(dir: Vector3) -> bool:
	if _cooldown > 0.0:
		return false
	dir.y = 0.0
	dir = dir.normalized()
	var feet := _harry.global_position
	var ahead := feet + dir * 0.45
	if not is_nan(sensor.floor_height(ahead + Vector3.UP * 0.2, 0.8)):
		return false # the floor continues (or it's just a step down)
	var from := ahead + Vector3.DOWN * 0.2 + dir * 0.15
	var hit := sensor.ray(from, feet + Vector3.DOWN * 0.2 - dir * 0.3)
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	n.y = 0.0
	if n.length() < 0.5 or n.normalized().dot(dir) < 0.65:
		return false
	n = n.normalized()
	var p: Vector3 = hit["position"]
	var top := feet.y
	var l := {
		"edge": Vector3(p.x, top, p.z), "normal": n, "top": top,
		"can_stand_on_top": true, "crouch_only": false, "stand_point": feet - dir * 0.1,
	}
	var hang := ParkourSensor.hang_feet(l)
	if not sensor.hang_fits(hang):
		return false
	if _harry.is_crouching:
		_harry.set_crouched(false)
	_start_grab(l, hang, 0.45)
	return true


func try_pipe(dir: Vector3, reach: float = 0.75) -> bool:
	var feet := _harry.global_position
	var p := sensor.find_pipe(feet + Vector3.UP * 1.0, dir, reach)
	if p.is_empty():
		return false
	var bottom: Vector3 = p["axis_bottom"]
	var top: Vector3 = p["axis_top"]
	var n: Vector3 = p["normal"]
	var y := clampf(feet.y + 0.15, bottom.y - 0.05, top.y - 1.7)
	if y < bottom.y - 0.3:
		return false
	pipe = p
	var target := Vector3(bottom.x, y, bottom.z) + n * 0.36
	if _harry.is_crouching:
		_harry.set_crouched(false)
	_begin(Action.GRAB, 0.3)
	_then = Action.PIPE
	_from = feet
	_to = target
	_harry.set_state(Harry.State.GRAB)
	return true


# ---------------------------------------------------------------------------
# Starting actions
# ---------------------------------------------------------------------------
func _begin(a: Action, duration: float) -> void:
	action = a
	progress = 0.0
	_duration = maxf(duration, 0.05)
	_harry.velocity = Vector3.ZERO
	shimmy_speed = 0.0
	pipe_speed = 0.0


func _start_grab(l: Dictionary, hang: Vector3, duration: float) -> void:
	ledge = l
	_begin(Action.GRAB, duration)
	_then = Action.HANG
	_from = _harry.global_position
	_to = hang
	_harry.set_state(Harry.State.GRAB)


func _start_climb(l: Dictionary, from_hang: bool) -> void:
	ledge = l
	var top: float = l["top"]
	var e: Vector3 = l["edge"]
	var n: Vector3 = l["normal"]
	var stand: Vector3 = l["stand_point"]
	var height := top - _harry.global_position.y
	_begin(Action.CLIMB_UP, climb_up_time if from_hang else mantle_time * clampf(height / 1.2, 0.7, 1.4))
	_from = _harry.global_position
	# First straight up in front of the lip, then forward onto the top.
	_mid = Vector3(e.x, top + 0.04, e.z) + n * (ParkourSensor.HANG_WALL_OFFSET if from_hang else 0.3)
	_to = stand + Vector3.UP * 0.02
	_end_crouched = l.get("crouch_only", false)
	_harry.set_state(Harry.State.CLIMB_UP)


func _start_vault(obs: Dictionary, dir: Vector3, hspeed: float) -> void:
	var n: Vector3 = obs["normal"]
	var p: Vector3 = obs["point"]
	var top: float = obs["top"]
	var depth: float = obs["depth"]
	var land: Vector3 = obs["landing"]
	_begin(Action.VAULT, clampf(vault_time * 3.5 / maxf(hspeed, 2.5), 0.35, 0.7))
	_from = _harry.global_position
	_mid = p - n * (depth * 0.5)
	_mid.y = top + 0.12
	_to = land
	_exit_velocity = -n * maxf(hspeed, 3.0)
	_harry.facing_yaw = atan2(n.x, n.z)
	_harry.set_state(Harry.State.VAULT)


# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------
func physics_update(delta: float) -> void:
	var before := _harry.global_position
	match action:
		Action.GRAB:
			_step_grab(delta)
		Action.CLIMB_UP:
			_step_climb(delta)
		Action.VAULT:
			_step_vault(delta)
		Action.HANG:
			_step_hang(delta)
		Action.PIPE:
			_step_pipe(delta)
	if action != Action.NONE:
		_harry.velocity = (_harry.global_position - before) / maxf(delta, 0.0001)
	var n := get_wall_normal()
	if action in [Action.HANG, Action.PIPE, Action.GRAB, Action.CLIMB_UP] and n != Vector3.ZERO:
		_harry.facing_yaw = rotate_toward(_harry.facing_yaw, atan2(n.x, n.z), 12.0 * delta)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func _step_grab(delta: float) -> void:
	progress = minf(progress + delta / _duration, 1.0)
	var s := smoothstep(0.0, 1.0, progress)
	_harry.global_position = _from.lerp(_to, s) + Vector3.UP * sin(s * PI) * 0.12
	if progress >= 1.0:
		action = _then
		progress = 0.0
		_harry.set_state(Harry.State.PIPE if action == Action.PIPE else Harry.State.HANG)


func _step_climb(delta: float) -> void:
	progress = minf(progress + delta / _duration, 1.0)
	var up := smoothstep(0.0, 0.6, progress)
	var fwd := smoothstep(0.5, 1.0, progress)
	var p := _from.lerp(_mid, up)
	p = p.lerp(_to, fwd)
	_harry.global_position = p
	if progress >= 1.0:
		action = Action.NONE
		if _end_crouched:
			_harry.set_crouched(true)
		_harry.velocity = Vector3.ZERO
		_harry.set_state(Harry.State.CROUCH_IDLE if _end_crouched else Harry.State.IDLE)
		_cooldown = 0.3


func _step_vault(delta: float) -> void:
	progress = minf(progress + delta / _duration, 1.0)
	var t := progress
	# Quadratic Bezier through a control point that makes the arc pass over `_mid`.
	var ctrl := _mid * 2.0 - (_from + _to) * 0.5
	var a := _from.lerp(ctrl, t)
	var b := ctrl.lerp(_to, t)
	_harry.global_position = a.lerp(b, t)
	if progress >= 1.0:
		action = Action.NONE
		_harry.velocity = _exit_velocity
		_harry.set_state(Harry.State.RUN)
		_cooldown = 0.2


func _step_hang(delta: float) -> void:
	var n: Vector3 = ledge["normal"]
	var right := (-n).cross(Vector3.UP)
	var wish := _harry.get_wish_dir()
	var lateral := wish.dot(right)
	var toward_wall := wish.dot(-n)
	_up_hold = _up_hold + delta if toward_wall > 0.6 else 0.0

	shimmy_speed = move_toward(shimmy_speed, lateral * shimmy_speed_max, 3.0 * delta)
	if absf(shimmy_speed) > 0.01:
		var new_edge: Vector3 = ledge["edge"] + right * shimmy_speed * delta
		var nl := sensor.follow_ledge(new_edge, n, ledge["top"])
		if not nl.is_empty() and sensor.hang_fits(ParkourSensor.hang_feet(nl)):
			ledge = nl
		else:
			shimmy_speed = 0.0
	_harry.global_position = _harry.global_position.lerp(ParkourSensor.hang_feet(ledge), 1.0 - exp(-20.0 * delta))

	if Input.is_action_just_pressed("crouch"):
		_let_go(n * 0.4, Harry.State.FALL)
		return
	if Input.is_action_just_pressed("jump") or _up_hold > 0.35:
		_up_hold = 0.0
		if wish.dot(n) > 0.5:
			# Push off the wall backwards.
			_let_go(n * 3.0 + Vector3.UP * 3.2, Harry.State.JUMP)
			_harry.facing_yaw = atan2(-n.x, -n.z)
			return
		if ledge["can_stand_on_top"]:
			_start_climb(ledge, true)
			return
		var feet := _harry.global_position
		var top: float = ledge["top"]
		var higher := sensor.find_ledge(feet, -n, top + 0.45, top + 1.35, 0.9)
		if not higher.is_empty():
			var hang := ParkourSensor.hang_feet(higher)
			if sensor.hang_fits(hang):
				_start_grab(higher, hang, hop_time)
				return
		if try_pipe(-n, 0.9):
			return


func _step_pipe(delta: float) -> void:
	var n: Vector3 = pipe["normal"]
	var bottom: Vector3 = pipe["axis_bottom"]
	var top: Vector3 = pipe["axis_top"]
	var v_in := Input.get_axis("move_back", "move_forward")
	var target := v_in * (pipe_up_speed if v_in > 0.0 else pipe_down_speed)
	pipe_speed = move_toward(pipe_speed, target, 4.0 * delta)
	var feet := _harry.global_position
	var max_y := top.y - 1.75
	feet.y = clampf(feet.y + pipe_speed * delta, bottom.y - 0.05, max_y)
	var wanted := Vector3(bottom.x, feet.y, bottom.z) + n * 0.36
	_harry.global_position = wanted

	if Input.is_action_just_pressed("crouch"):
		_let_go(n * 0.3, Harry.State.FALL)
		return
	if Input.is_action_just_pressed("jump"):
		_let_go(n * 2.8 + Vector3.UP * 3.0, Harry.State.JUMP)
		_harry.facing_yaw = atan2(-n.x, -n.z)
		return
	# At the top: climb over onto the roof or ledge above.
	if feet.y >= max_y - 0.01 and v_in > 0.5:
		var l := sensor.find_ledge(feet, -n, top.y - 0.5, top.y + 1.3, 1.0)
		if not l.is_empty() and l["can_stand_on_top"]:
			_start_climb(l, true)
			return
		pipe_speed = 0.0
	# At the bottom: step off onto the ground.
	if v_in < -0.1 and feet.y <= bottom.y + 0.02:
		var fh := sensor.floor_height(feet + n * 0.1, 0.4)
		if not is_nan(fh):
			action = Action.NONE
			_harry.set_state(Harry.State.IDLE)
			_cooldown = 0.4


func _let_go(velocity: Vector3, state: Harry.State) -> void:
	action = Action.NONE
	shimmy_speed = 0.0
	pipe_speed = 0.0
	_cooldown = 0.45
	_harry.velocity = velocity
	_harry.set_state(state)
