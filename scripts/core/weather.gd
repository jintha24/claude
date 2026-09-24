class_name Weather
extends Node
## Dynamic weather (self-creating singleton, like GameClock and Stealth).
##
## Six kinds: clear, cloudy, light rain, storm, London fog and snow (winter only). Every
## 1-4 in-game hours the weather moves on (a Markov chain of believable successions: fog
## tends to come on still mornings, storms clear through rain). Every parameter blends
## smoothly over ~12 in-game minutes; nothing ever switches abruptly.
##
## Everything else reads the blended values: WeatherEffects (visuals), DayNightCycle (sun,
## fog), Stealth (hearing and sight), Population (fewer people out), Harry (slippery roofs).

signal kind_changed(kind: Kind)
signal lightning(strength: float)

enum Kind { CLEAR, CLOUDY, LIGHT_RAIN, STORM, FOG, SNOW }

const NAMES := {
	Kind.CLEAR: "Clear", Kind.CLOUDY: "Overcast", Kind.LIGHT_RAIN: "Rain",
	Kind.STORM: "Thunderstorm", Kind.FOG: "London fog", Kind.SNOW: "Snow",
}
## Target values per kind: cloud cover, rain, fog, snow, wind (all 0..1).
const PROFILES := {
	Kind.CLEAR: [0.1, 0.0, 0.0, 0.0, 0.2],
	Kind.CLOUDY: [0.75, 0.0, 0.1, 0.0, 0.35],
	Kind.LIGHT_RAIN: [0.9, 0.45, 0.15, 0.0, 0.4],
	Kind.STORM: [1.0, 1.0, 0.25, 0.0, 0.9],
	Kind.FOG: [0.6, 0.0, 1.0, 0.0, 0.05],
	Kind.SNOW: [0.9, 0.0, 0.2, 0.8, 0.3],
}
## What tends to follow what (weights).
const NEXT := {
	Kind.CLEAR: {Kind.CLEAR: 0.35, Kind.CLOUDY: 0.5, Kind.FOG: 0.15},
	Kind.CLOUDY: {Kind.CLEAR: 0.3, Kind.CLOUDY: 0.25, Kind.LIGHT_RAIN: 0.35, Kind.FOG: 0.1},
	Kind.LIGHT_RAIN: {Kind.CLOUDY: 0.45, Kind.LIGHT_RAIN: 0.4, Kind.STORM: 0.15},
	Kind.STORM: {Kind.LIGHT_RAIN: 0.6, Kind.CLOUDY: 0.4},
	Kind.FOG: {Kind.CLOUDY: 0.4, Kind.CLEAR: 0.4, Kind.FOG: 0.2},
	Kind.SNOW: {Kind.CLOUDY: 0.5, Kind.SNOW: 0.5},
}

static var kind: Kind = Kind.CLEAR
static var cloud: float = 0.1
static var rain: float = 0.0
static var fog: float = 0.0
static var snow: float = 0.0
static var wind: float = 0.2
static var wind_direction: Vector3 = Vector3(0.8, 0.0, 0.6).normalized()
## How wet the ground is (rises quickly in rain, dries slowly afterwards).
static var wetness: float = 0.0
## Standing water in the dips (lags behind wetness).
static var puddles: float = 0.0
## Snow lying on the ground.
static var snow_cover: float = 0.0
## Automatic changes on/off (tests and missions can fix the weather).
static var automatic: bool = true
## In-game minutes to blend from one weather to the next.
static var transition_minutes: float = 12.0
## Chance per real second of a lightning strike at full storm (tests may raise it).
static var lightning_rate: float = 0.08

static var _thunder_left: float = 0.0
static var _bus: Weather
static var _next_change_minute: float = -1.0
static var _rng := RandomNumberGenerator.new()


static func bus() -> Weather:
	if _bus == null or not is_instance_valid(_bus):
		var tree := Engine.get_main_loop() as SceneTree
		_bus = tree.root.get_node_or_null("Weather") as Weather
		if _bus == null:
			_bus = Weather.new()
			_bus.name = "Weather"
			_bus.process_mode = Node.PROCESS_MODE_PAUSABLE
			tree.root.add_child.call_deferred(_bus)
	return _bus


## Change the weather. `instant` skips the blend (missions, loading a save).
static func set_weather(new_kind: Kind, instant: bool = false) -> void:
	# Snow only falls in winter; outside winter it comes down as rain.
	if new_kind == Kind.SNOW and not GameClock.is_winter():
		new_kind = Kind.LIGHT_RAIN
	elif new_kind in [Kind.LIGHT_RAIN, Kind.STORM] and GameClock.is_winter() and _rng.randf() < 0.5:
		new_kind = Kind.SNOW
	kind = new_kind
	if instant:
		var p: Array = PROFILES[kind]
		cloud = p[0]
		rain = p[1]
		fog = p[2]
		snow = p[3]
		wind = p[4]
		wetness = 1.0 if rain > 0.3 else wetness
		puddles = wetness * 0.8
	_next_change_minute = _now() + _rng.randf_range(60.0, 240.0)
	bus().kind_changed.emit(kind)


## A thunderclap drowns out every other sound for a few seconds.
static func thunder(seconds: float) -> void:
	_thunder_left = maxf(_thunder_left, seconds)


static func display_name() -> String:
	return NAMES[kind]


## Multiplier for how many people are out of doors.
static func population_factor() -> float:
	return clampf(1.0 - rain * 0.7 - fog * 0.25 - snow * 0.5, 0.15, 1.0)


## Multiplier for direct sunlight through the clouds.
static func sun_factor() -> float:
	return clampf(1.0 - maxf(cloud - 0.3, 0.0) * 1.1 - fog * 0.35, 0.12, 1.0)


static func _now() -> float:
	return GameClock.day * 1440.0 + GameClock.minutes


func _ready() -> void:
	_rng.randomize()
	if _next_change_minute < 0.0:
		_next_change_minute = Weather._now() + _rng.randf_range(60.0, 240.0)


func _process(delta: float) -> void:
	var game_minutes := 0.0 if GameClock.paused else delta * 1440.0 / (GameClock.real_minutes_per_game_day * 60.0)
	if automatic and Weather._now() >= _next_change_minute:
		Weather.set_weather(_pick_next())
	# Blend towards the target profile.
	var p: Array = PROFILES[kind]
	var step := game_minutes / maxf(transition_minutes, 0.01)
	cloud = move_toward(cloud, p[0], step)
	rain = move_toward(rain, p[1], step)
	fog = move_toward(fog, p[2], step * 0.6) # fog rolls in slowly
	snow = move_toward(snow, p[3], step)
	wind = move_toward(wind, p[4], step)
	# Wind slowly veers.
	wind_direction = wind_direction.rotated(Vector3.UP, sin(Weather._now() * 0.01) * 0.0005 * game_minutes)
	# Ground: wet within ~10 minutes of rain, dries over ~1.5 hours (slower under cloud).
	if rain > 0.05:
		wetness = minf(wetness + rain * game_minutes / 10.0, 1.0)
	else:
		wetness = maxf(wetness - game_minutes / (90.0 * (1.0 + cloud)), 0.0)
	puddles = move_toward(puddles, wetness * (0.3 + 0.7 * rain) if rain > 0.05 else minf(puddles, wetness), game_minutes / (25.0 if rain > 0.05 else 120.0))
	snow_cover = move_toward(snow_cover, snow, game_minutes / (40.0 if snow > 0.1 else 180.0))
	# Weather's effect on the senses.
	Stealth.hearing_multiplier = clampf(1.0 - rain * 0.45 - wind * 0.1, 0.45, 1.0)
	if _thunder_left > 0.0:
		_thunder_left -= delta
		Stealth.hearing_multiplier *= 0.25
	Stealth.visibility_multiplier = clampf((1.0 - rain * 0.3) * (1.0 - fog * 0.7) * (1.0 - snow * 0.25), 0.2, 1.0)
	# Lightning in a proper storm.
	if rain > 0.8 and cloud > 0.9 and _rng.randf() < lightning_rate * delta:
		lightning.emit(_rng.randf_range(0.5, 1.0))


func _pick_next() -> Kind:
	var options: Dictionary = NEXT[kind]
	var r := _rng.randf()
	var acc := 0.0
	for k: Kind in options:
		acc += float(options[k])
		if r <= acc:
			return k
	return Kind.CLOUDY
