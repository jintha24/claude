class_name HarryThievery
extends Node
## Pickpocketing. Child node "Thievery" of Harry. (Lockpicking joins it in Phase 7.)
##
## Approach someone from behind or the side, unseen, and press E. Harry falls into step
## just behind them while his hand works into the pocket: a marker sweeps back and forth
## across a bar and you press E again while it's inside the sweet spot. Rich targets take
## two careful moves (unhook the chain, then lift); a worker's pocket takes one.
##
## The sweet spot is wider in a thick crowd (jostling hides the touch), at night, and with
## better skill; narrower if the victim is walking. The victim's suspicion grows the whole
## time. Miss, dawdle, or let them grow suspicious and they spin round shouting "Thief!".

signal attempt_started(victim: Civilian)
signal attempt_finished(success: bool, loot: Array)

## Improved by upgrades in Phase 9.
@export var skill: float = 1.0
@export var stage_timeout: float = 3.2
@export var suspicion_rate: float = 0.26
@export var base_zone_width: float = 0.24
@export var marker_speed: float = 3.2

var victim: Civilian = null
var prompt_target: Civilian = null
var stage := 0
var stages := 1
var marker := 0.5
var zone_center := 0.5
var zone_width := 0.2
var crowd := 0

var _harry: Harry
var _t := 0.0
var _stage_time := 0.0
var _struggle := 0.0
var _prompt_timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(harry: Harry) -> void:
	_harry = harry
	_rng.randomize()


func is_busy() -> bool:
	return victim != null or _struggle > 0.0


func cancel() -> void:
	victim = null
	_struggle = 0.0


## Refreshes the on-screen "[E] Pick pocket" target (called while Harry is free).
func update_prompt(delta: float) -> void:
	_prompt_timer -= delta
	if _prompt_timer > 0.0:
		return
	_prompt_timer = 0.1
	prompt_target = _find_target()


func try_start() -> bool:
	var target := _find_target()
	if target == null:
		return false
	victim = target
	prompt_target = null
	stage = 0
	stages = 2 if victim.victim_class in ["gentleman", "lady"] else 1
	_t = _rng.randf() * TAU
	_new_stage()
	if _harry.is_crouching:
		_harry.set_crouched(false)
	_harry.set_state(Harry.State.PICKPOCKET)
	attempt_started.emit(victim)
	return true


func physics_update(delta: float) -> void:
	if _struggle > 0.0:
		# Held by a strong victim: wrench free.
		_struggle -= delta
		_harry.velocity = Vector3.ZERO
		if _struggle <= 0.0:
			_harry.set_state(Harry.State.IDLE)
		return
	if victim == null or not is_instance_valid(victim):
		_finish(false, false)
		return
	# Fall into step just behind and to one side of the victim.
	var f := victim.get_facing_dir()
	var right := f.cross(Vector3.UP)
	var want := victim.global_position - f * 0.55 + right * 0.18
	want.y = victim.global_position.y
	var before := _harry.global_position
	_harry.global_position = before.lerp(want, 1.0 - exp(-10.0 * delta))
	_harry.velocity = (_harry.global_position - before) / maxf(delta, 0.0001)
	_harry.facing_yaw = rotate_toward(_harry.facing_yaw, atan2(-f.x, -f.z), 8.0 * delta)

	var moving := victim.is_walking()
	crowd = _count_crowd(victim.global_position, 2.5)
	_t += delta * marker_speed * (1.25 if moving else 1.0)
	marker = 0.5 + 0.5 * sin(_t)
	_stage_time += delta
	var rate := suspicion_rate * (1.2 if moving else 1.0) * maxf(1.0 - 0.12 * crowd, 0.4)
	victim.suspicion = minf(victim.suspicion + rate * delta, 1.0)

	if victim.suspicion >= 1.0 or _stage_time > stage_timeout:
		_finish(false, true)
		return
	if Input.is_action_just_pressed("interact"):
		if absf(marker - zone_center) <= zone_width * 0.5:
			stage += 1
			if stage >= stages:
				_finish(true, false)
			else:
				_new_stage()
		else:
			_finish(false, true)
		return
	# Backing off (move away, jump or crouch) abandons the attempt; if the victim already
	# felt something, they turn round.
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch") or _harry.get_wish_dir().dot(f) < -0.6:
		_finish(false, victim.suspicion > 0.45)


func _new_stage() -> void:
	_stage_time = 0.0
	crowd = _count_crowd(victim.global_position, 2.5)
	var width := base_zone_width * skill
	width *= 1.0 + 0.15 * minf(crowd, 4)
	width *= 1.0 + (1.0 - Stealth.ambient_light) * 0.3
	if victim.is_walking():
		width *= 0.75
	if victim.state == Civilian.State.CHAT:
		width *= 1.3 # deep in conversation, they won't feel a thing
	zone_width = clampf(width, 0.08, 0.5)
	zone_center = _rng.randf_range(0.2 + zone_width * 0.5, 0.8 - zone_width * 0.5)


func _finish(success: bool, caught: bool) -> void:
	var v := victim
	victim = null
	var loot: Array[Dictionary] = []
	if success and v:
		loot = v.take_loot()
		v.suspicion = 0.0
		_harry.inventory.receive_loot(loot)
		_harry.set_state(Harry.State.IDLE)
	elif caught and v:
		if v.catch_thief(_harry):
			_struggle = 1.2
			Stealth.bark(v, "%s: \"Got you, you little sneak!\"" % v.display_name)
		else:
			_harry.set_state(Harry.State.IDLE)
	else:
		_harry.set_state(Harry.State.IDLE)
	attempt_finished.emit(success, loot)


func _find_target() -> Civilian:
	if _harry == null:
		return null
	var best: Civilian = null
	var best_d := INF
	var facing := _harry.get_facing_dir()
	for node in _harry.get_tree().get_nodes_in_group("civilians"):
		var c := node as Civilian
		if c == null or not c.can_be_pickpocketed_from(_harry.global_position):
			continue
		var to_c := c.global_position - _harry.global_position
		to_c.y = 0.0
		var d := to_c.length()
		if d > 0.3 and facing.dot(to_c.normalized()) < 0.2:
			continue
		if d < best_d:
			best_d = d
			best = c
	return best


func _count_crowd(center: Vector3, radius: float) -> int:
	var n := 0
	for node in _harry.get_tree().get_nodes_in_group("civilians"):
		var c := node as Node3D
		if c != victim and c.global_position.distance_to(center) <= radius:
			n += 1
	return n
