class_name HarryInteraction
extends Node
## Using things in the world with E: doors, windows, valuables, safes, drain covers.
## Child node "Interaction" of Harry.
##
## Every 0.1 s it picks the nearest Interactable in front of Harry and within reach, and
## the HUD shows its prompt ("[E] Pick the lock (3-lever)"). Interactables then start one
## of three kinds of action, which own Harry's body while they run:
##
##  * HOLD      - keep E held for a few seconds (cutting a painting from its frame, lifting
##                a drain cover). Letting go or moving away abandons it.
##  * LOCKPICK  - the lever-lock minigame (see LeverLock). A marker sweeps up and down;
##                press E while it's inside the lit gate to set each lever in turn. A slip
##                drops the last lever and may snap a pick; on a detector lock it jams the
##                lock for good. Move, jump or crouch to give up.
##  * TRAVERSE  - a short scripted move, e.g. climbing in through a sash window.

signal action_started(kind: String)
signal action_finished(kind: String, success: bool)
## "lever", "slip", "pick_broke", "jammed", "opened", "no_picks"
signal lock_event(event: String)

enum Mode { NONE, HOLD, LOCKPICK, TRAVERSE }

## Improved by upgrades in Phase 9.
@export var lock_skill: float = 1.0
@export var marker_speed: float = 2.4
@export_range(0.0, 1.0) var pick_break_chance: float = 0.3
## Seconds before a new press counts after a slip (the pick has to be re-seated).
@export var reseat_time: float = 0.5

var mode: Mode = Mode.NONE
## The interactable whose prompt is showing (null = nothing in reach).
var target: Interactable = null
var prompt: String = ""
## The interactable being used right now.
var active: Interactable = null

# HOLD
var hold_label: String = ""
var hold_time: float = 1.0
var hold_progress: float = 0.0
# LOCKPICK
var lock: LeverLock = null
var lever: int = 0
var marker: float = 0.5
var zone_center: float = 0.5
var zone_width: float = 0.2
var reseat: float = 0.0

var _harry: Harry
var _prompt_timer := 0.0
var _done: Callable
var _noise_radius := 0.0
var _noise_timer := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _duration := 1.0
var _elapsed := 0.0
var _crouch_after := false


func setup(harry: Harry) -> void:
	_harry = harry
	_rng.randomize()


func is_busy() -> bool:
	return mode != Mode.NONE


func is_lockpicking() -> bool:
	return mode == Mode.LOCKPICK


func cancel() -> void:
	if mode != Mode.NONE:
		var kind := _mode_name()
		mode = Mode.NONE
		active = null
		lock = null
		action_finished.emit(kind, false)


## Refreshes the prompt target (called every frame Harry is free and on the ground).
func update_prompt(delta: float) -> void:
	_prompt_timer -= delta
	if _prompt_timer > 0.0:
		return
	_prompt_timer = 0.1
	target = null
	prompt = ""
	var chest := _harry.global_position + Vector3.UP * 1.2
	var facing := _harry.get_facing_dir()
	var best_d := INF
	for node in _harry.get_tree().get_nodes_in_group("interactables"):
		var it := node as Interactable
		if it == null or not it.is_visible_in_tree():
			continue
		var p := it.get_interact_point()
		var d := chest.distance_to(p)
		if d > it.interact_range or d >= best_d:
			continue
		var flat := Vector3(p.x - chest.x, 0.0, p.z - chest.z)
		if flat.length() > 0.5 and facing.dot(flat.normalized()) < 0.25:
			continue
		var text := it.get_prompt(_harry)
		if text == "":
			continue
		best_d = d
		target = it
		prompt = text


## E pressed: use the current target. Returns false if there was nothing to use.
func try_start() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var t := target
	target = null
	prompt = ""
	_prompt_timer = 0.0
	t.interact(_harry)
	return true


# ---------------------------------------------------------------------------
# Starting actions (called by interactables)
# ---------------------------------------------------------------------------
## Keep E held for `seconds`. `on_done` runs on success. `noise_radius` > 0 makes a small
## suspicious sound every second while working.
func begin_hold(who: Interactable, label: String, seconds: float, on_done: Callable, noise_radius: float = 0.0) -> void:
	_start(who, Mode.HOLD)
	hold_label = label
	hold_time = maxf(seconds, 0.1)
	hold_progress = 0.0
	_done = on_done
	_noise_radius = noise_radius
	_noise_timer = 0.5
	_kneel_or_stand(false)


## The lever-lock minigame. `on_open` runs when the last lever is set.
func begin_lockpick(who: Interactable, the_lock: LeverLock, on_open: Callable) -> void:
	if _harry.inventory.lockpicks <= 0:
		lock_event.emit("no_picks")
		return
	_start(who, Mode.LOCKPICK)
	lock = the_lock
	lever = 0
	_done = on_open
	_t = _rng.randf() * TAU
	reseat = 0.3
	_new_lever()
	_kneel_or_stand(true)


## Moves Harry smoothly to `to` over `seconds` (climbing through a window). He ends up
## crouched if `crouch_after`, so he fits under low ceilings and sills.
func begin_traverse(who: Interactable, to: Vector3, seconds: float, on_done: Callable, crouch_after: bool = true) -> void:
	_start(who, Mode.TRAVERSE)
	_from = _harry.global_position
	_to = to
	_duration = maxf(seconds, 0.1)
	_elapsed = 0.0
	_done = on_done
	_crouch_after = crouch_after
	var d := _to - _from
	if Vector2(d.x, d.z).length() > 0.05:
		_harry.facing_yaw = atan2(-d.x, -d.z)
	_harry.set_state(Harry.State.VAULT)


func _start(who: Interactable, m: Mode) -> void:
	active = who
	mode = m
	target = null
	prompt = ""
	_harry.velocity = Vector3.ZERO
	var p := who.get_interact_point()
	var flat := Vector3(p.x - _harry.global_position.x, 0.0, p.z - _harry.global_position.z)
	if flat.length() > 0.05:
		_harry.facing_yaw = atan2(-flat.x, -flat.z)
	action_started.emit(_mode_name())


## Hands busy: kneel at a lock, or work standing (or as he was) for everything else.
func _kneel_or_stand(kneel: bool) -> void:
	if kneel:
		_harry.set_crouched(true)
	_harry.set_state(Harry.State.LOCKPICK)


func _mode_name() -> String:
	return ["none", "hold", "lockpick", "traverse"][mode]


# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------
func physics_update(delta: float) -> void:
	if active == null or not is_instance_valid(active):
		_finish(false)
		return
	if mode in [Mode.HOLD, Mode.LOCKPICK] and _harry.state != Harry.State.LOCKPICK:
		_harry.set_state(Harry.State.LOCKPICK)
	match mode:
		Mode.HOLD:
			_update_hold(delta)
		Mode.LOCKPICK:
			_update_lock(delta)
		Mode.TRAVERSE:
			_update_traverse(delta)


func _wants_out() -> bool:
	return Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch") \
		or _harry.get_wish_dir().length() > 0.6


func _update_hold(delta: float) -> void:
	_harry.velocity = Vector3.ZERO
	if not Input.is_action_pressed("interact") or _wants_out():
		_finish(false)
		return
	hold_progress += delta / hold_time
	_noise_timer -= delta
	if _noise_radius > 0.0 and _noise_timer <= 0.0:
		_noise_timer = 1.0
		Stealth.make_noise(active.get_interact_point(), _noise_radius, "tampering", true, _harry)
	if hold_progress >= 1.0:
		hold_progress = 1.0
		_finish(true)


func _update_lock(delta: float) -> void:
	_harry.velocity = Vector3.ZERO
	if _wants_out():
		_finish(false)
		return
	_t += delta * marker_speed
	# The pick rises and falls; eased at the ends like a lever on its spring.
	marker = 0.5 + 0.5 * sin(_t)
	reseat = maxf(reseat - delta, 0.0)
	if not Input.is_action_just_pressed("interact") or reseat > 0.0:
		return
	if absf(marker - zone_center) <= zone_width * 0.5:
		lever += 1
		lock_event.emit("lever")
		Stealth.make_noise(active.get_interact_point(), 1.5, "lockpick", true, _harry)
		if lever >= lock.levers:
			lock.locked = false
			lock_event.emit("opened")
			_finish(true)
		else:
			_new_lever()
		return
	# Slipped.
	Stealth.make_noise(active.get_interact_point(), 3.0, "lockpick", true, _harry)
	if lock.detector:
		lock.jammed = true
		lock_event.emit("jammed")
		_finish(false)
		return
	lock_event.emit("slip")
	lever = maxi(lever - 1, 0)
	reseat = reseat_time
	if _rng.randf() < pick_break_chance:
		_harry.inventory.add_lockpicks(-1)
		lock_event.emit("pick_broke")
		if _harry.inventory.lockpicks <= 0:
			_finish(false)
			return
	_new_lever()


func _new_lever() -> void:
	zone_width = clampf(lock.gate_width * lock_skill, 0.05, 0.5)
	zone_center = _rng.randf_range(0.1 + zone_width * 0.5, 0.9 - zone_width * 0.5)


func _update_traverse(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	var p := _from.lerp(_to, s)
	p.y += sin(t * PI) * 0.35 # up and over the sill
	_harry.global_position = p
	_harry.velocity = Vector3.ZERO
	if t >= 1.0:
		if _crouch_after:
			_harry.set_crouched(true)
		_finish(true)


func _finish(success: bool) -> void:
	var kind := _mode_name()
	var cb := _done
	mode = Mode.NONE
	active = null
	lock = null
	_done = Callable()
	_harry.reset_physics_interpolation()
	_harry.set_state(Harry.State.CROUCH_IDLE if _harry.is_crouching else Harry.State.IDLE)
	if success and cb.is_valid():
		cb.call()
	action_finished.emit(kind, success)
