class_name FishingSession
extends RefCounted
## One cast of the line, from casting to landing (or losing) a fish.
##
##   CAST   - hold E: the rod bends back (power rises and falls); release to cast. A longer
##            cast reaches deeper water and bigger fish.
##   WAIT   - the float sits on the water. Bites come sooner at dawn and dusk and in dull
##            weather, slower at noon and at night. Press E to reel in early.
##   BITE   - the float dips: strike (E) within a second or it's gone.
##   FIGHT  - hold E to reel in (tension rises), let go to give line (tension falls). The fish
##            pulls in surges. Keep the tension in the middle band while reeling and it
##            tires; too tight and the line snaps, too slack for too long and it throws the
##            hook. Pike are strong.
##   LANDED / LOST - done; `message` says what happened.

enum Phase { CAST, WAIT, BITE, FIGHT, LANDED, LOST }

## [name, min lb, max lb, strength, pence per lb]
const SPECIES: Array = [
	["Roach", 0.15, 0.8, 0.8, 10.0],
	["Perch", 0.3, 1.8, 1.1, 14.0],
	["Tench", 0.8, 3.5, 1.4, 12.0],
	["Pike", 2.0, 14.0, 2.2, 8.0],
]
const TENSION_LOW := 0.3
const TENSION_HIGH := 0.82

var phase: Phase = Phase.CAST
var power: float = 0.0
var tension: float = 0.0
var fish_stamina: float = 1.0
var message: String = ""
var fish: Array = []
var weight: float = 0.0
var catch_item: Dictionary = {}

var _rng: RandomNumberGenerator
var _charge_t := 0.0
var _charging := false
var _wait := 0.0
var _bite := 0.0
var _slack := 0.0
var _t := 0.0
var _surge_freq := 1.0


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## How quickly fish bite now (1 = normal, lower = sooner).
static func bite_factor() -> float:
	var h := GameClock.hours()
	var f := 1.0
	if (h >= 5.0 and h < 8.5) or (h >= 17.0 and h < 20.5):
		f = 0.55 # the evening rise and the morning feed
	elif h >= 11.0 and h < 15.0:
		f = 1.3
	elif h >= 22.0 or h < 4.0:
		f = 1.6
	f *= 1.0 - 0.25 * clampf(Weather.cloud, 0.0, 1.0) # a dull day is a good fishing day
	return f


func step(delta: float, pressed: bool, held: bool) -> void:
	_t += delta
	match phase:
		Phase.CAST:
			if held:
				_charging = true
				_charge_t += delta
				power = 0.5 - 0.5 * cos(_charge_t * 2.6)
			elif _charging:
				_charging = false
				phase = Phase.WAIT
				_wait = _rng.randf_range(4.0, 16.0) * bite_factor() * (1.0 - 0.3 * power)
				message = "The float settles. Wait for a bite..."
		Phase.WAIT:
			if pressed:
				_lose("You reel in. Nothing on the hook.")
				return
			_wait -= delta
			if _wait <= 0.0:
				phase = Phase.BITE
				_bite = 1.0
				_choose_fish()
				message = "A bite! Strike!"
		Phase.BITE:
			if pressed:
				phase = Phase.FIGHT
				tension = 0.45
				fish_stamina = 1.0
				_surge_freq = _rng.randf_range(0.8, 1.6)
				message = "Hooked! Reel in, but don't let the line snap."
				return
			_bite -= delta
			if _bite <= 0.0:
				phase = Phase.WAIT
				_wait = _rng.randf_range(3.0, 9.0) * bite_factor()
				message = "Too slow: it took the bait and went. Wait again..."
		Phase.FIGHT:
			var strength: float = fish[3] * (0.6 + 0.4 * clampf(weight / fish[2], 0.0, 1.0))
			var surge := maxf(sin(_t * _surge_freq * TAU), 0.0) * strength * fish_stamina
			tension += (0.55 if held else -0.9) * delta
			tension += surge * 0.55 * delta
			tension = clampf(tension, 0.0, 1.05)
			if tension >= 1.0:
				_lose("The line snaps! The %s is gone." % fish[0].to_lower())
				return
			_slack = _slack + delta if tension < 0.1 else 0.0
			if _slack > 2.5:
				_lose("The line went slack and the %s threw the hook." % fish[0].to_lower())
				return
			if held and tension > TENSION_LOW and tension < TENSION_HIGH:
				fish_stamina -= delta * 0.22 / strength
			if fish_stamina <= 0.0:
				_land()


func _choose_fish() -> void:
	# Bigger fish lie out in deeper water: a long cast raises the odds of tench and pike.
	var r := _rng.randf() + power * 0.35
	var idx := 0 if r < 0.45 else (1 if r < 0.85 else (2 if r < 1.12 else 3))
	fish = SPECIES[idx]
	weight = snappedf(_rng.randf_range(float(fish[1]), float(fish[2])), 0.0625)


func _land() -> void:
	phase = Phase.LANDED
	var lb := int(weight)
	var oz := int(round((weight - lb) * 16.0))
	var value := maxi(int(weight * float(fish[4])), 1)
	catch_item = {"name": "%s (%d lb %d oz)" % [fish[0], lb, oz], "value": value, "kind": "provision", "victim_class": "game", "fish": fish[0], "weight": weight}
	message = "Landed a %s of %d lb %d oz!" % [fish[0].to_lower(), lb, oz]


func _lose(text: String) -> void:
	phase = Phase.LOST
	message = text


func is_over() -> bool:
	return phase == Phase.LANDED or phase == Phase.LOST
