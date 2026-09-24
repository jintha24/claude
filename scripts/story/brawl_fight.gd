class_name BrawlFight
extends Node
## A bare-knuckle fight on narrow footing: Harry against Big Tom on the Fleet footbridge.
## Nobody is knocked out: whoever loses his BALANCE goes over the side into the ditch.
##
## Harry (controls while fighting):
##   W / S           step in / back along the bridge
##   Left mouse      jab (quick, light)            - tap
##                   haymaker (slow, heavy)        - hold 0.4 s and let go
##   Right mouse     guard: blocks most of a jab or haymaker, but not a shove
##   A / D           sway aside: dodges anything, but costs a little footing
## The opponent telegraphs: a short draw-back before a jab, a long one before a haymaker
## ("Hraagh!"), a crouch before a shove. Balance recovers while you're not being hit.
## Hits hurt a little too (never fatally: this is a brawl, not a killing).

signal ended(harry_won: bool)

enum Act { GUARD, JAB, HEAVY_WIND, HEAVY, BLOCK, DODGE, STAGGER, FALLEN }
enum FoeAct { GUARD, WINDUP, STRIKE, BLOCK, STAGGER, RECOVER, FALLEN }

const REACH := 1.6
const MIN_GAP := 1.05
const JAB_TIME := 0.3
const HEAVY_HOLD := 0.4
const HEAVY_WIND_TIME := 0.25
const HEAVY_TIME := 0.35
const DODGE_TIME := 0.45
const ATTACKS := {
	# windup (s), balance damage, health damage, knockback (m), blockable
	"jab": [0.42, 9.0, 3.0, 0.15, true],
	"haymaker": [0.95, 27.0, 8.0, 0.55, true],
	"shove": [0.65, 19.0, 1.0, 0.9, false],
}

static var current: BrawlFight = null

var harry: Harry
var foe: StoryNPC
var foe_name: String = "Big Tom"
var line_from: Vector3
var line_to: Vector3
var water_y: float = -1.9
var harry_balance: float = 100.0
var foe_balance: float = 100.0
var harry_act: Act = Act.GUARD
var foe_act: FoeAct = FoeAct.GUARD
var foe_attack: String = ""
var over := false
var harry_won := false
## Seconds into the opponent's current windup, and how long it is.
var foe_t := 0.0
var foe_windup := 0.0
var hits_landed := 0
var hits_taken := 0

var _dir := Vector3.FORWARD
var _len := 7.0
var _harry_s := 2.0
var _foe_s := 5.0
var _harry_t := 0.0
var _fire_held := 0.0
var _fire_was := false
var _dodge_side := 0.0
var _foe_idle := 1.0
var _foe_block_t := 0.0
var _fall_t := -1.0
var _fall_from := Vector3.ZERO
var _fall_side := 1.0
var _rng := RandomNumberGenerator.new()


## Starts the fight between points `a` (Harry's end) and `b` (the opponent's end).
func start(h: Harry, opponent: StoryNPC, a: Vector3, b: Vector3) -> void:
	harry = h
	foe = opponent
	line_from = a
	line_to = b
	_dir = (b - a)
	_dir.y = 0.0
	_len = _dir.length()
	_dir = _dir.normalized()
	_harry_s = maxf(_len * 0.5 - 0.9, 0.0)
	_foe_s = minf(_len * 0.5 + 0.9, _len)
	_rng.randomize()
	current = self
	harry.parkour.cancel()
	harry.combat.cancel()
	harry.interaction.cancel()
	harry.set_crouched(false)
	harry.brawl = self
	harry.set_state(Harry.State.IDLE)
	foe.set_puppet(true)
	_place()


func _exit_tree() -> void:
	if current == self:
		current = null
	if harry and harry.brawl == self:
		harry.brawl = null


func point_at(s: float) -> Vector3:
	return line_from + _dir * s


func gap() -> float:
	return _foe_s - _harry_s


# ---------------------------------------------------------------------------
# Harry's side (called from Harry._physics_process while the fight owns him)
# ---------------------------------------------------------------------------
func harry_physics(delta: float) -> void:
	if _fall_t >= 0.0:
		_update_fall(delta)
		return
	_harry_t += delta
	# Stepping in and out.
	var fwd := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	if harry_act in [Act.GUARD, Act.BLOCK]:
		_harry_s = clampf(_harry_s + fwd * 1.5 * delta, 0.0, maxf(_foe_s - MIN_GAP, 0.0))
	# Guard.
	var blocking := Input.is_action_pressed("aim")
	if harry_act in [Act.GUARD, Act.BLOCK]:
		harry_act = Act.BLOCK if blocking else Act.GUARD
	# Sway aside.
	if harry_act in [Act.GUARD, Act.BLOCK]:
		var side := 0.0
		if Input.is_action_just_pressed("move_left"):
			side = -1.0
		elif Input.is_action_just_pressed("move_right"):
			side = 1.0
		if side != 0.0:
			harry_act = Act.DODGE
			_harry_t = 0.0
			_dodge_side = side
			harry_balance = maxf(harry_balance - 5.0, 1.0)
			AudioDirector.play("swish", harry.global_position, -6.0)
	# Punches: tap for a jab, hold for a haymaker.
	var fire := Input.is_action_pressed("fire")
	if harry_act in [Act.GUARD, Act.BLOCK]:
		if fire:
			_fire_held += delta
			if _fire_held >= HEAVY_HOLD:
				harry_act = Act.HEAVY_WIND
				_harry_t = 0.0
				_fire_held = 0.0
		elif _fire_was and _fire_held < HEAVY_HOLD:
			harry_act = Act.JAB
			_harry_t = 0.0
			_fire_held = 0.0
			_harry_hits(false)
	elif not fire:
		_fire_held = 0.0
	_fire_was = fire
	match harry_act:
		Act.JAB:
			if _harry_t >= JAB_TIME:
				harry_act = Act.GUARD
		Act.HEAVY_WIND:
			if _harry_t >= HEAVY_WIND_TIME:
				harry_act = Act.HEAVY
				_harry_t = 0.0
				_harry_hits(true)
		Act.HEAVY:
			if _harry_t >= HEAVY_TIME:
				harry_act = Act.GUARD
		Act.DODGE:
			if _harry_t >= DODGE_TIME:
				harry_act = Act.GUARD
				_dodge_side = 0.0
		Act.STAGGER:
			if _harry_t >= 0.45:
				harry_act = Act.GUARD
	if harry_act in [Act.GUARD, Act.BLOCK]:
		harry_balance = minf(harry_balance + 4.0 * delta, 100.0)
	_update_foe(delta)
	_place()


## Is Harry out of the way of a blow right now?
func harry_dodging() -> bool:
	return harry_act == Act.DODGE and _harry_t > 0.04 and _harry_t < DODGE_TIME - 0.04


func _harry_hits(heavy: bool) -> void:
	AudioDirector.play("swish", harry.global_position + Vector3.UP * 1.4, -4.0, 1.2 if not heavy else 0.9)
	if gap() > REACH or foe_act == FoeAct.FALLEN:
		return
	var dmg := 22.0 if heavy else 8.0
	if foe_act == FoeAct.BLOCK:
		dmg *= 0.35 if heavy else 0.2
		if heavy:
			_foe_stagger() # a haymaker breaks his guard
	else:
		# A clean hit interrupts his windup.
		if foe_act == FoeAct.WINDUP or not heavy:
			_foe_stagger()
		if heavy:
			_foe_s = minf(_foe_s + 0.45, _len)
	foe_balance -= dmg
	hits_landed += 1
	AudioDirector.play("punch", foe.global_position + Vector3.UP * 1.5, 0.0 if heavy else -3.0)
	if foe_balance <= 0.0:
		foe_balance = 0.0
		_start_fall(false)


func _foe_stagger() -> void:
	if foe_act == FoeAct.FALLEN:
		return
	foe_act = FoeAct.STAGGER
	foe_t = 0.0
	foe_attack = ""


# ---------------------------------------------------------------------------
# The opponent
# ---------------------------------------------------------------------------
func _update_foe(delta: float) -> void:
	foe_t += delta
	var desperate := foe_balance < 35.0
	match foe_act:
		FoeAct.GUARD:
			foe_balance = minf(foe_balance + 3.0 * delta, 100.0)
			# Close the distance.
			if gap() > REACH - 0.15:
				_foe_s = maxf(_foe_s - 1.3 * delta, _harry_s + MIN_GAP)
			# Guard up against a haymaker he sees coming.
			if harry_act == Act.HEAVY_WIND and _rng.randf() < 0.4:
				foe_act = FoeAct.BLOCK
				foe_t = 0.0
				_foe_block_t = 0.9
				return
			_foe_idle -= delta
			if _foe_idle <= 0.0 and gap() <= REACH:
				var r := _rng.randf()
				foe_attack = "jab" if r < 0.4 else ("haymaker" if r < 0.75 else "shove")
				foe_windup = float(ATTACKS[foe_attack][0]) * (0.8 if desperate else 1.0)
				foe_act = FoeAct.WINDUP
				foe_t = 0.0
				if foe_attack == "haymaker":
					foe.say(["Hraagh!", "Here it comes!", "Stand still, you eel!"][_rng.randi() % 3])
		FoeAct.WINDUP:
			if foe_t >= foe_windup:
				foe_act = FoeAct.STRIKE
				foe_t = 0.0
				_foe_hits()
		FoeAct.STRIKE:
			if foe_t >= 0.3:
				foe_act = FoeAct.RECOVER
				foe_t = 0.0
		FoeAct.RECOVER:
			if foe_t >= (0.35 if desperate else 0.55):
				foe_act = FoeAct.GUARD
				foe_t = 0.0
				_foe_idle = _rng.randf_range(0.5, 1.2) * (0.7 if desperate else 1.0)
		FoeAct.BLOCK:
			_foe_block_t -= delta
			if _foe_block_t <= 0.0:
				foe_act = FoeAct.GUARD
				foe_t = 0.0
				_foe_idle = _rng.randf_range(0.2, 0.6)
		FoeAct.STAGGER:
			if foe_t >= 0.5:
				foe_act = FoeAct.GUARD
				foe_t = 0.0
				_foe_idle = _rng.randf_range(0.4, 0.9)


func _foe_hits() -> void:
	AudioDirector.play("swish", foe.global_position + Vector3.UP * 1.5, -3.0, 0.8)
	if gap() > REACH + 0.2 or harry_dodging():
		return
	var a: Array = ATTACKS[foe_attack]
	var bal: float = a[1]
	var hp: float = a[2]
	if harry_act == Act.BLOCK and bool(a[4]):
		bal *= 0.3
		hp *= 0.25
	harry_balance -= bal
	hits_taken += 1
	harry.health = maxf(harry.health - hp, 15.0)
	harry.health_changed.emit(harry.health, harry.max_health)
	_harry_s = maxf(_harry_s - float(a[3]), 0.0)
	if harry_act != Act.BLOCK:
		harry_act = Act.STAGGER
		_harry_t = 0.0
	AudioDirector.play("punch", harry.global_position + Vector3.UP * 1.5, 0.0 if foe_attack != "jab" else -4.0)
	if harry_balance <= 0.0:
		harry_balance = 0.0
		_start_fall(true)


# ---------------------------------------------------------------------------
# Positions, poses and the fall
# ---------------------------------------------------------------------------
func _place() -> void:
	var side := Vector3(-_dir.z, 0.0, _dir.x)
	var sway := 0.0
	if harry_act == Act.DODGE:
		sway = sin(clampf(_harry_t / DODGE_TIME, 0.0, 1.0) * PI) * 0.45 * _dodge_side
	var hp := point_at(_harry_s) + side * sway
	harry.global_position = Vector3(hp.x, line_from.y, hp.z)
	harry.velocity = Vector3.ZERO
	harry.facing_yaw = atan2(-_dir.x, -_dir.z)
	var fp := point_at(_foe_s)
	foe.global_position = Vector3(fp.x, line_to.y, fp.z)
	foe.set_yaw(atan2(_dir.x, _dir.z))
	match foe_act:
		FoeAct.WINDUP:
			foe.pose_override = NPCBody.Pose.WINDUP if foe_attack != "shove" else NPCBody.Pose.GUARD
		FoeAct.STRIKE:
			foe.pose_override = NPCBody.Pose.PUNCH
		FoeAct.STAGGER:
			foe.pose_override = NPCBody.Pose.STUNNED
		FoeAct.FALLEN:
			foe.pose_override = NPCBody.Pose.UNCONSCIOUS
		_:
			foe.pose_override = NPCBody.Pose.GUARD


func _start_fall(harry_falls: bool) -> void:
	harry_won = not harry_falls
	_fall_t = 0.0
	_fall_side = 1.0 if _rng.randf() < 0.5 else -1.0
	if harry_falls:
		harry_act = Act.FALLEN
		_fall_from = harry.global_position
	else:
		foe_act = FoeAct.FALLEN
		_fall_from = foe.global_position
		foe.say("Whoa-!")


func _update_fall(delta: float) -> void:
	_fall_t += delta
	var side := Vector3(-_dir.z, 0.0, _dir.x) * _fall_side
	var t := clampf(_fall_t / 0.9, 0.0, 1.0)
	var p := _fall_from + side * (1.6 * t) + Vector3.UP * (0.6 * sin(t * PI) - (_fall_from.y - water_y + 0.9) * t * t)
	if harry_act == Act.FALLEN:
		harry.global_position = p
		harry.velocity = Vector3.ZERO
	else:
		foe.global_position = p
		_place_harry_only()
	if t >= 1.0 and not over:
		over = true
		AudioDirector.play("splash", p, 2.0)
		Stealth.make_noise(p, 12.0, "splash", false, foe if harry_won else harry)
		harry.brawl = null
		if not harry_won:
			harry.velocity = Vector3.ZERO
		ended.emit(harry_won)
		queue_free()


func _place_harry_only() -> void:
	var hp := point_at(_harry_s)
	harry.global_position = Vector3(hp.x, line_from.y, hp.z)
	harry.velocity = Vector3.ZERO
