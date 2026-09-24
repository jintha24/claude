class_name HarryCombat
extends Node
## Harry's non-lethal toolkit (the Outlaw's Code): takedowns from behind and the longbow.
## Child node "Combat" of Harry.
##
## Takedown: E (interact) close behind a guard who isn't chasing you. Harry grabs him in
##   a chokehold; after `takedown_time` the guard is unconscious for several minutes.
## Longbow: hold right mouse / left trigger to aim over the shoulder, hold left mouse /
##   right trigger to draw (a full draw takes ~0.9 s and shoots farther), release to loose.
##   R / D-pad right switches between blunt and whistle arrows.

signal ammo_changed(kind: String, count: int)
signal arrow_type_changed(kind: String)

const KINDS: Array[String] = ["blunt", "whistle"]

@export var blunt_arrows: int = 12
@export var whistle_arrows: int = 5
@export var max_arrows_per_kind: int = 20
@export var draw_time: float = 0.9
## Arrow speed at full draw. A 1860s-style yew longbow launches ~50-55 m/s.
@export var max_arrow_speed: float = 55.0
@export var min_arrow_speed: float = 18.0
@export var takedown_time: float = 1.6

var arrow_kind: String = "blunt"
var draw: float = 0.0
var takedown_target: Guard = null

var _harry: Harry
var _aiming := false
var _busy := false
var _timer := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO


func setup(harry: Harry) -> void:
	_harry = harry


func is_aiming() -> bool:
	return _aiming


func is_busy() -> bool:
	return _busy


func get_ammo(kind: String) -> int:
	return blunt_arrows if kind == "blunt" else whistle_arrows


func add_ammo(kind: String, amount: int) -> void:
	if kind == "blunt":
		blunt_arrows = clampi(blunt_arrows + amount, 0, max_arrows_per_kind)
	else:
		whistle_arrows = clampi(whistle_arrows + amount, 0, max_arrows_per_kind)
	ammo_changed.emit(kind, get_ammo(kind))


func cancel() -> void:
	_aiming = false
	draw = 0.0
	if _busy and takedown_target:
		takedown_target.knock_out()
	_busy = false
	takedown_target = null


## Called every frame Harry is free (on the ground or in the air, not climbing).
func handle_input(delta: float, on_floor: bool) -> void:
	_aiming = Input.is_action_pressed("aim") and on_floor and not _harry.is_dead()
	if Input.is_action_just_pressed("cycle_arrow"):
		arrow_kind = KINDS[(KINDS.find(arrow_kind) + 1) % KINDS.size()]
		arrow_type_changed.emit(arrow_kind)
	if _aiming:
		if Input.is_action_pressed("fire") and get_ammo(arrow_kind) > 0:
			draw = minf(draw + delta / draw_time, 1.0)
		elif draw > 0.0:
			if draw >= 0.2:
				_shoot()
			draw = 0.0
	else:
		draw = 0.0
		if on_floor and Input.is_action_just_pressed("interact"):
			# E does the most useful thing within reach: takedown, pick a pocket, pick up an arrow.
			if not _try_takedown() and not _harry.thievery.try_start():
				_try_pickup()


func physics_update(delta: float) -> void:
	_timer += delta
	var t := clampf(_timer / 0.2, 0.0, 1.0)
	_harry.global_position = _from.lerp(_to, t)
	_harry.velocity = Vector3.ZERO
	if takedown_target:
		var f := takedown_target.get_facing_dir()
		_harry.facing_yaw = rotate_toward(_harry.facing_yaw, atan2(-f.x, -f.z), 10.0 * delta)
	if _timer >= takedown_time:
		_busy = false
		if takedown_target:
			takedown_target.knock_out()
		takedown_target = null
		_harry.set_state(Harry.State.IDLE)


func _try_takedown() -> bool:
	var best: Guard = null
	var best_d := INF
	var facing := _harry.get_facing_dir()
	for node in _harry.get_tree().get_nodes_in_group("guards"):
		var g := node as Guard
		if g == null or not g.can_be_taken_down_from(_harry.global_position):
			continue
		var to_g := g.global_position - _harry.global_position
		to_g.y = 0.0
		var d := to_g.length()
		if d > 1.6 or absf(g.global_position.y - _harry.global_position.y) > 0.6:
			continue
		if d > 0.3 and facing.dot(to_g.normalized()) < 0.2:
			continue
		if d < best_d:
			best_d = d
			best = g
	if best == null:
		return false
	takedown_target = best
	_busy = true
	_timer = 0.0
	_from = _harry.global_position
	_to = best.global_position - best.get_facing_dir() * 0.55
	_to.y = _harry.global_position.y
	if _harry.is_crouching:
		_harry.set_crouched(false)
	best.receive_takedown(takedown_time)
	_harry.stealth.commit_crime(takedown_time + 1.0)
	Stealth.make_noise(best.global_position, 3.5, "scuffle", true, _harry)
	_harry.set_state(Harry.State.TAKEDOWN)
	return true


func _try_pickup() -> bool:
	for node in _harry.get_tree().get_nodes_in_group("arrow_pickups"):
		var a := node as Arrow
		if a and a.global_position.distance_to(_harry.global_position) < 1.8:
			add_ammo(a.kind, 1)
			a.queue_free()
			return true
	return false


func _shoot() -> void:
	if get_ammo(arrow_kind) <= 0:
		return
	var cam: Camera3D = _harry.get_viewport().get_camera_3d()
	var facing := _harry.get_facing_dir()
	var right := facing.cross(Vector3.UP)
	var origin := _harry.global_position + Vector3.UP * 1.5 + facing * 0.45 + right * 0.08
	var aim_point := origin + facing * 100.0
	if cam:
		var exclude: Array[RID] = [_harry.get_rid()]
		var cam_from := cam.global_position
		var cam_dir := -cam.global_basis.z
		var q := PhysicsRayQueryParameters3D.create(cam_from, cam_from + cam_dir * 250.0, Arrow.MASK_HIT, exclude)
		var hit := _harry.get_world_3d().direct_space_state.intersect_ray(q)
		aim_point = hit["position"] if not hit.is_empty() else cam_from + cam_dir * 250.0
	var speed := lerpf(min_arrow_speed, max_arrow_speed, draw)
	var dir := _ballistic_direction(origin, aim_point, speed)
	var arrow := Arrow.create(arrow_kind)
	_harry.get_tree().current_scene.add_child(arrow)
	arrow.launch(origin, dir * speed, _harry)
	add_ammo(arrow_kind, -1)
	Stealth.make_noise(origin, 4.0, "bow", true, _harry)


## Launch direction that makes an arrow at `speed` drop onto `target` (the low, flat arc
## an archer instinctively aims), or a straight line if the target is out of range.
static func _ballistic_direction(origin: Vector3, target: Vector3, speed: float) -> Vector3:
	var d := target - origin
	var flat := Vector3(d.x, 0.0, d.z)
	var x := flat.length()
	if x < 0.5:
		return d.normalized()
	var y := d.y
	var g := Arrow.GRAVITY
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * y * v2)
	if disc < 0.0:
		return (flat.normalized() + Vector3.UP).normalized() # out of range: 45 degrees
	var angle := atan((v2 - sqrt(disc)) / (g * x))
	return (flat.normalized() * cos(angle) + Vector3.UP * sin(angle)).normalized()
