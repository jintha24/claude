class_name SoundLibrary
extends RefCounted
## Every sound in the game, by name. The game ships with no recorded audio, so each sound
## is synthesised in code the first time it's needed (filtered noise, resonant knocks,
## bell partials and so on) and cached. Real recordings replace them without any code
## change: drop a file named after the sound into assets/audio/sfx/ (one-shots) or
## assets/audio/ambience/ (loops), as .ogg or .wav, e.g. assets/audio/sfx/bell.ogg or
## assets/audio/ambience/rain.ogg. Footsteps may have numbered variations:
## assets/audio/footsteps/step_stone_1.ogg ... _4.ogg.
##
## One-shots: step_<surface> (stone, wood, grass, gravel, carpet, water, slate, dirt),
## hoof, bow_draw, bow_release, arrow_hit, whistle_arrow, whistle_call, rattle, bell,
## coin, lock_click, lock_open, door_creak, door_slam, splash, thunder, dog_bark, punch,
## swish, glass_break, crow, chirp, cloth, stinger.
## Loops: rain, wind, crowd, fire, water_lap, birds, crickets, city, drone, pulse.

const RATE := 22050
const LOOPS: Array[String] = ["rain", "wind", "crowd", "fire", "water_lap", "birds", "crickets", "city", "drone", "pulse"]
const VARIATIONS := 4
const SURFACES: Array[String] = ["stone", "wood", "grass", "gravel", "carpet", "water", "slate", "dirt"]

static var _cache := {}
static var _mutex := Mutex.new()


## The sound called `sound_name` (variation `variant` for footsteps). Never null.
static func get_stream(sound_name: String, variant: int = 0) -> AudioStream:
	var key := "%s#%d" % [sound_name, variant]
	_mutex.lock()
	var cached: AudioStream = _cache.get(key)
	_mutex.unlock()
	if cached:
		return cached
	var s := _load_file(sound_name, variant)
	if s == null:
		s = _synthesise(sound_name, variant)
	_mutex.lock()
	_cache[key] = s
	_mutex.unlock()
	return s


## Forgets every sound (they're rebuilt when next needed).
static func clear_cache() -> void:
	_mutex.lock()
	_cache.clear()
	_mutex.unlock()


## True once the sound has been built (or loaded) and can be played without a hitch.
static func is_cached(sound_name: String, variant: int = 0) -> bool:
	_mutex.lock()
	var ok := _cache.has("%s#%d" % [sound_name, variant])
	_mutex.unlock()
	return ok


## True if `sound_name` is one of the built-in sounds (or has a file).
static func has_sound(sound_name: String) -> bool:
	return sound_name in LOOPS or one_shot_names().has(sound_name) or _load_file(sound_name, 0) != null


static func is_loop(sound_name: String) -> bool:
	return sound_name in LOOPS


## Builds the common sounds ahead of time (call from a worker thread to avoid a hitch).
static func warm_up(names: Array) -> void:
	for n: String in names:
		var variants := VARIATIONS if n.begins_with("step_") else 1
		for v in variants:
			get_stream(n, v)


static func one_shot_names() -> Array[String]:
	var names: Array[String] = ["hoof", "bow_draw", "bow_release", "arrow_hit", "whistle_arrow", "whistle_call", "rattle",
		"bell", "coin", "lock_click", "lock_open", "door_creak", "door_slam", "splash", "thunder", "dog_bark", "punch",
		"swish", "glass_break", "crow", "chirp", "cloth", "stinger"]
	for s in SURFACES:
		names.append("step_" + s)
	return names


static func _load_file(sound_name: String, variant: int) -> AudioStream:
	var folders: Array[String] = ["res://assets/audio/ambience/" if sound_name in LOOPS else "res://assets/audio/sfx/"]
	if sound_name.begins_with("step_"):
		folders.push_front("res://assets/audio/footsteps/")
	for folder in folders:
		for base: String in ["%s_%d" % [sound_name, variant + 1], sound_name]:
			for ext: String in [".ogg", ".wav", ".mp3"]:
				var p := folder + base + ext
				if ResourceLoader.exists(p):
					var s := load(p) as AudioStream
					if s:
						if sound_name in LOOPS:
							if s is AudioStreamOggVorbis:
								(s as AudioStreamOggVorbis).loop = true
							elif s is AudioStreamWAV:
								(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
							elif s is AudioStreamMP3:
								(s as AudioStreamMP3).loop = true
						return s
	return null


# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------
static func _synthesise(sound_name: String, variant: int) -> AudioStream:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound_name) + variant * 7919
	var d := PackedFloat32Array()
	if sound_name.begins_with("step_"):
		d = _step(sound_name.substr(5), rng)
	else:
		match sound_name:
			"hoof": d = _hoof(rng)
			"bow_draw": d = _bow_draw(rng)
			"bow_release": d = _bow_release(rng)
			"arrow_hit": d = _arrow_hit(rng)
			"whistle_arrow": d = _whistle(rng, 1.1, 1700.0, 2500.0, 9.0)
			"whistle_call": d = _whistle_call()
			"rattle": d = _rattle(rng)
			"bell": d = _bell(rng)
			"coin": d = _coin(rng)
			"lock_click": d = _click(rng, 0.03, 3200.0)
			"lock_open": d = _lock_open(rng)
			"door_creak": d = _creak(rng)
			"door_slam": d = _slam(rng)
			"splash": d = _splash(rng)
			"thunder": d = _thunder(rng)
			"dog_bark": d = _bark(rng)
			"punch": d = _punch(rng)
			"swish": d = _swish(rng)
			"glass_break": d = _glass(rng)
			"crow": d = _crow(rng)
			"chirp": d = _chirp(rng, 0.0)
			"cloth": d = _cloth(rng)
			"stinger": d = _stinger()
			"rain": d = _loop(_rain(rng))
			"wind": d = _loop(_wind(rng))
			"crowd": d = _loop(_crowd(rng))
			"fire": d = _loop(_fire(rng))
			"water_lap": d = _loop(_water_lap(rng))
			"birds": d = _loop(_birds(rng))
			"crickets": d = _loop(_crickets(rng))
			"city": d = _loop(_city(rng))
			"drone": d = _loop(_drone())
			"pulse": d = _loop(_pulse(rng))
			_: d = _click(rng, 0.02, 2000.0)
	return _to_wav(d, sound_name in LOOPS)


static func _to_wav(d: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for v in d:
		peak = maxf(peak, absf(v))
	var gain := 0.89 / peak
	var bytes := PackedByteArray()
	bytes.resize(d.size() * 2)
	for i in d.size():
		bytes.encode_s16(i * 2, int(clampf(d[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = d.size()
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(int(seconds * RATE))
	return d


## One-pole low-pass coefficient for a cutoff in Hz.
static func _lp_a(hz: float) -> float:
	return 1.0 - exp(-TAU * hz / RATE)


## Makes a seamless loop: the last 0.4 s is cross-faded into the start.
static func _loop(d: PackedFloat32Array) -> PackedFloat32Array:
	var fade := mini(int(0.4 * RATE), d.size() / 3)
	var n := d.size() - fade
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = d[i]
	for i in fade:
		var t := float(i) / fade
		out[i] = d[i] * t + d[n + i] * (1.0 - t)
	return out


## Filtered-noise burst with an attack/decay envelope.
static func _noise_burst(d: PackedFloat32Array, start: int, seconds: float, lp_hz: float, hp_hz: float, amp: float, decay: float, rng: RandomNumberGenerator) -> void:
	var n := int(seconds * RATE)
	var a := _lp_a(lp_hz)
	var ah := _lp_a(hp_hz)
	var lp := 0.0
	var low := 0.0
	for i in n:
		var j := start + i
		if j >= d.size():
			break
		var t := float(i) / RATE
		lp += a * (rng.randf_range(-1.0, 1.0) - lp)
		low += ah * (lp - low)
		var env := minf(t / 0.002, 1.0) * exp(-t * decay)
		d[j] += (lp - low) * amp * env


## A damped resonance (a knock on wood, a hoof on stone).
static func _knock(d: PackedFloat32Array, start: int, hz: float, seconds: float, amp: float, decay: float) -> void:
	var n := int(seconds * RATE)
	for i in n:
		var j := start + i
		if j >= d.size():
			break
		var t := float(i) / RATE
		d[j] += sin(TAU * hz * t * (1.0 + 0.4 * exp(-t * 40.0))) * amp * exp(-t * decay)


static func _step(surface: String, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.32)
	match surface:
		"stone", "slate":
			_knock(d, 0, rng.randf_range(90.0, 120.0), 0.08, 0.5, 60.0)
			_noise_burst(d, int(0.004 * RATE), 0.06, 5000.0, 900.0, 0.9, 70.0, rng)
			_noise_burst(d, int(0.05 * RATE), 0.05, 4000.0, 1200.0, 0.35, 90.0, rng) # heel then toe
		"wood":
			_knock(d, 0, rng.randf_range(140.0, 180.0), 0.14, 0.9, 30.0)
			_knock(d, 0, rng.randf_range(420.0, 520.0), 0.06, 0.25, 60.0)
			_noise_burst(d, 0, 0.05, 2500.0, 300.0, 0.3, 80.0, rng)
		"grass":
			_noise_burst(d, 0, 0.2, 3500.0, 700.0, 0.8, 18.0, rng)
		"dirt":
			_knock(d, 0, 70.0, 0.08, 0.5, 50.0)
			_noise_burst(d, 0, 0.12, 1800.0, 200.0, 0.6, 30.0, rng)
		"gravel":
			for k in 14:
				_noise_burst(d, int(rng.randf_range(0.0, 0.16) * RATE), 0.012, 7000.0, 1500.0, rng.randf_range(0.3, 0.7), 300.0, rng)
			_knock(d, 0, 80.0, 0.06, 0.3, 60.0)
		"carpet":
			_knock(d, 0, 60.0, 0.1, 0.6, 40.0)
			_noise_burst(d, 0, 0.08, 900.0, 80.0, 0.3, 40.0, rng)
		"water":
			_splash_into(d, 0, 0.3, 0.7, rng)
		_:
			_noise_burst(d, 0, 0.08, 3000.0, 400.0, 0.7, 50.0, rng)
	return d


static func _hoof(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.3)
	_knock(d, 0, rng.randf_range(300.0, 360.0), 0.08, 0.8, 70.0)
	_noise_burst(d, 0, 0.04, 6000.0, 1500.0, 0.8, 110.0, rng)
	_knock(d, int(0.09 * RATE), rng.randf_range(260.0, 320.0), 0.08, 0.6, 70.0)
	_noise_burst(d, int(0.09 * RATE), 0.04, 6000.0, 1500.0, 0.6, 110.0, rng)
	return d


static func _bow_draw(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.7)
	var lp := 0.0
	var a := _lp_a(1800.0)
	for i in d.size():
		var t := float(i) / RATE
		lp += a * (rng.randf_range(-1.0, 1.0) - lp)
		var creak := 0.5 + 0.5 * sin(TAU * (28.0 + 20.0 * t) * t)
		d[i] = lp * creak * minf(t / 0.05, 1.0) * clampf((0.7 - t) / 0.1, 0.0, 1.0) * 0.6
	return d


static func _bow_release(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.6)
	for i in d.size():
		var t := float(i) / RATE
		var f := 105.0 * (1.0 + 0.6 * exp(-t * 25.0))
		d[i] = (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.01 * t)) * exp(-t * 9.0) * 0.8
	_noise_burst(d, 0, 0.12, 6000.0, 1800.0, 0.5, 40.0, rng) # the string's slap and the fletching
	return d


static func _arrow_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.3)
	_knock(d, 0, 95.0, 0.2, 1.0, 22.0)
	_noise_burst(d, 0, 0.06, 3500.0, 400.0, 0.7, 60.0, rng)
	return d


static func _whistle(rng: RandomNumberGenerator, seconds: float, f0: float, f1: float, vib: float) -> PackedFloat32Array:
	var d := _buf(seconds)
	var phase := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / seconds) + sin(TAU * vib * t) * 60.0 + rng.randf_range(-15.0, 15.0)
		phase += TAU * f / RATE
		d[i] = sin(phase) * minf(t / 0.05, 1.0) * clampf((seconds - t) / 0.2, 0.0, 1.0) * 0.6
	return d


static func _whistle_call() -> PackedFloat32Array:
	# Two notes, rising then falling: a man's two-finger whistle for his horse.
	var d := _buf(0.9)
	var phase := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var f := 1500.0 + 700.0 * clampf(t / 0.12, 0.0, 1.0) if t < 0.35 else 2200.0 - 500.0 * clampf((t - 0.45) / 0.3, 0.0, 1.0)
		phase += TAU * f / RATE
		var env := minf(t / 0.02, 1.0) * (1.0 if t < 0.32 or t > 0.42 else 0.15) * clampf((0.9 - t) / 0.12, 0.0, 1.0)
		d[i] = sin(phase) * env * 0.7
	return d


static func _rattle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# A police rattle: a wooden ratchet whirled round, ~24 clacks a second.
	var d := _buf(1.4)
	var t := 0.0
	while t < 1.3:
		var j := int(t * RATE)
		_knock(d, j, rng.randf_range(800.0, 950.0), 0.03, 0.6, 180.0)
		_noise_burst(d, j, 0.02, 7000.0, 2000.0, 0.7, 250.0, rng)
		t += 1.0 / 24.0 + rng.randf_range(-0.004, 0.004)
	return d


static func _bell(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# A church bell: the strike note and its partials (hum, prime, tierce, quint, nominal).
	var d := _buf(4.0)
	var f := 196.0 * rng.randf_range(0.99, 1.01)
	var partials := [[0.5, 0.5, 0.6], [1.0, 0.8, 0.9], [1.2, 0.5, 1.2], [1.5, 0.35, 1.5], [2.0, 0.6, 1.8], [2.51, 0.25, 2.6], [3.0, 0.2, 3.2]]
	for i in d.size():
		var t := float(i) / RATE
		var v := 0.0
		for p: Array in partials:
			v += sin(TAU * f * float(p[0]) * t) * float(p[1]) * exp(-t * float(p[2]))
		d[i] = v * minf(t / 0.003, 1.0) * 0.4
	return d


static func _coin(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.45)
	for k in 5:
		var j := int(rng.randf_range(0.0, 0.2) * RATE)
		_knock(d, j, rng.randf_range(2600.0, 4200.0), 0.2, 0.3, 30.0)
		_knock(d, j, rng.randf_range(5200.0, 6800.0), 0.1, 0.15, 50.0)
	return d


static func _click(rng: RandomNumberGenerator, seconds: float, hz: float) -> PackedFloat32Array:
	var d := _buf(seconds + 0.05)
	_knock(d, 0, hz, seconds, 0.6, 200.0)
	_noise_burst(d, 0, seconds, 8000.0, 2500.0, 0.5, 220.0, rng)
	return d


static func _lock_open(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.35)
	_knock(d, 0, 2400.0, 0.04, 0.5, 150.0)
	_knock(d, int(0.12 * RATE), 900.0, 0.12, 0.9, 50.0)
	_noise_burst(d, int(0.12 * RATE), 0.05, 6000.0, 1000.0, 0.6, 90.0, rng)
	return d


static func _creak(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Old hinges: a stick-slip squeal made of quick irregular pulses.
	var d := _buf(1.0)
	var t := 0.0
	while t < 0.9:
		var j := int(t * RATE)
		_knock(d, j, rng.randf_range(500.0, 700.0), 0.02, 0.4 * sin(PI * t / 0.9), 120.0)
		t += 1.0 / lerpf(55.0, 130.0, 0.5 + 0.5 * sin(t * 7.0)) + rng.randf_range(0.0, 0.002)
	return d


static func _slam(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.6)
	_knock(d, 0, 70.0, 0.5, 1.0, 12.0)
	_knock(d, 0, 210.0, 0.2, 0.4, 30.0)
	_noise_burst(d, 0, 0.1, 3000.0, 200.0, 0.8, 40.0, rng)
	return d


static func _splash_into(d: PackedFloat32Array, start: int, seconds: float, amp: float, rng: RandomNumberGenerator) -> void:
	var n := int(seconds * RATE)
	var lp := 0.0
	var low := 0.0
	for i in n:
		var j := start + i
		if j >= d.size():
			break
		var t := float(i) / RATE
		var cut := lerpf(3000.0, 600.0, t / seconds)
		lp += _lp_a(cut) * (rng.randf_range(-1.0, 1.0) - lp)
		low += _lp_a(150.0) * (lp - low)
		d[j] += (lp - low) * amp * minf(t / 0.01, 1.0) * exp(-t * 6.0 / seconds)
	# Droplets
	for k in 8:
		_knock(d, start + int(rng.randf_range(0.05, seconds) * RATE), rng.randf_range(900.0, 1800.0), 0.04, 0.12 * amp, 90.0)


static func _splash(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(1.2)
	_knock(d, 0, 60.0, 0.3, 0.6, 12.0)
	_splash_into(d, 0, 1.1, 1.0, rng)
	return d


static func _thunder(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(5.0)
	var brown := 0.0
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		brown = clampf(brown + rng.randf_range(-0.05, 0.05), -1.0, 1.0)
		lp += _lp_a(180.0) * (brown - lp)
		var rolls := 0.6 + 0.4 * sin(t * 3.1) * sin(t * 1.3 + 1.0)
		d[i] = lp * rolls * minf(t / 0.15, 1.0) * exp(-t * 0.7)
	_noise_burst(d, 0, 0.4, 4000.0, 300.0, 0.4, 8.0, rng) # the crack
	return d


static func _bark(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.8)
	for k in 2:
		var start := int(k * 0.32 * RATE)
		var n := int(0.16 * RATE)
		var phase := 0.0
		for i in n:
			var t := float(i) / RATE
			var f := 420.0 * (1.0 - t * 1.8) + rng.randf_range(-20.0, 20.0)
			phase += TAU * f / RATE
			var saw := fposmod(phase / TAU, 1.0) * 2.0 - 1.0
			d[start + i] += (saw * 0.6 + sin(phase * 2.0) * 0.3) * minf(t / 0.01, 1.0) * exp(-t * 14.0)
		_noise_burst(d, start, 0.12, 2500.0, 500.0, 0.4, 25.0, rng)
	return d


static func _punch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.3)
	_knock(d, 0, 80.0, 0.2, 1.0, 25.0)
	_noise_burst(d, 0, 0.05, 3000.0, 600.0, 0.9, 80.0, rng)
	return d


static func _swish(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.3)
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		lp += _lp_a(lerpf(800.0, 3000.0, sin(PI * t / 0.3))) * (rng.randf_range(-1.0, 1.0) - lp)
		d[i] = lp * sin(PI * t / 0.3) * 0.7
	return d


static func _glass(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.9)
	_noise_burst(d, 0, 0.15, 9000.0, 2500.0, 0.9, 25.0, rng)
	for k in 18:
		_knock(d, int(rng.randf_range(0.0, 0.6) * RATE), rng.randf_range(3000.0, 7000.0), 0.08, rng.randf_range(0.1, 0.35), 60.0)
	return d


static func _crow(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.5)
	var phase := 0.0
	for i in int(0.35 * RATE):
		var t := float(i) / RATE
		var f := 520.0 - 180.0 * t + rng.randf_range(-40.0, 40.0)
		phase += TAU * f / RATE
		var saw := fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		d[i] = saw * sin(PI * t / 0.35) * (0.6 + 0.4 * rng.randf())
	return d


## One bird's call: a few quick upward sweeps.
static func _chirp(rng: RandomNumberGenerator, _unused: float) -> PackedFloat32Array:
	var d := _buf(0.5)
	var notes := rng.randi_range(2, 4)
	var base := rng.randf_range(2800.0, 4200.0)
	for k in notes:
		var start := int(k * 0.1 * RATE)
		var phase := 0.0
		for i in int(0.06 * RATE):
			var t := float(i) / RATE
			phase += TAU * (base + 1800.0 * t / 0.06) / RATE
			d[start + i] += sin(phase) * sin(PI * t / 0.06) * 0.5
	return d


static func _cloth(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(0.25)
	_noise_burst(d, 0, 0.22, 2500.0, 500.0, 0.6, 14.0, rng)
	return d


## A low swell for a tense moment (when a guard first spots Harry).
static func _stinger() -> PackedFloat32Array:
	var d := _buf(2.0)
	for i in d.size():
		var t := float(i) / RATE
		var env := minf(t / 0.08, 1.0) * exp(-t * 1.6)
		d[i] = (sin(TAU * 73.4 * t) + 0.6 * sin(TAU * 110.0 * t) + 0.35 * sin(TAU * 155.6 * t)) * env * 0.5
	return d


# --- Loops ---------------------------------------------------------------------
static func _rain(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(4.0)
	var lp := 0.0
	var low := 0.0
	for i in d.size():
		lp += _lp_a(5000.0) * (rng.randf_range(-1.0, 1.0) - lp)
		low += _lp_a(400.0) * (lp - low)
		d[i] = (lp - low) * 0.5
	for k in 260: # drops on stone and slate
		_knock(d, rng.randi_range(0, d.size() - 400), rng.randf_range(1500.0, 4000.0), 0.02, rng.randf_range(0.05, 0.25), 200.0)
	return d


static func _wind(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(8.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var gust := 0.55 + 0.3 * sin(TAU * t / 8.0) + 0.15 * sin(TAU * t / 2.7 + 1.0)
		lp += _lp_a(250.0 + 500.0 * gust) * (rng.randf_range(-1.0, 1.0) - lp)
		lp2 += _lp_a(300.0 + 500.0 * gust) * (lp - lp2)
		d[i] = lp2 * gust
	return d


## A crowd's murmur: many voices of band-limited noise, each with its own syllable rhythm.
static func _crowd(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(6.0)
	for v in 7:
		var rate := rng.randf_range(3.0, 6.0)
		var formant := rng.randf_range(350.0, 900.0)
		var off := rng.randf() * TAU
		var lp := 0.0
		var low := 0.0
		var talk := rng.randf_range(0.4, 0.8)
		for i in d.size():
			var t := float(i) / RATE
			lp += _lp_a(formant * 1.8) * (rng.randf_range(-1.0, 1.0) - lp)
			low += _lp_a(formant * 0.5) * (lp - low)
			var syll := maxf(sin(TAU * rate * t + off + 0.7 * sin(t * 1.3 + v)), 0.0)
			var phrase := 1.0 if sin(TAU * t / (2.5 + v * 0.4) + off) > -talk else 0.0
			d[i] += (lp - low) * syll * phrase * 0.35
	return d


static func _fire(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(4.0)
	var lp := 0.0
	for i in d.size():
		lp += _lp_a(600.0) * (rng.randf_range(-1.0, 1.0) - lp)
		d[i] = lp * 0.6
	for k in 90: # crackles and pops
		var j := rng.randi_range(0, d.size() - 800)
		_noise_burst(d, j, 0.02, 8000.0, 1500.0, rng.randf_range(0.2, 0.9), 180.0, rng)
	return d


static func _water_lap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(6.0)
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var swell := 0.4 + 0.6 * pow(maxf(sin(TAU * t / 3.0), 0.0), 2.0)
		lp += _lp_a(900.0 * swell + 200.0) * (rng.randf_range(-1.0, 1.0) - lp)
		d[i] = lp * swell * 0.7
	for k in 30:
		_knock(d, rng.randi_range(0, d.size() - 1000), rng.randf_range(500.0, 1100.0), 0.05, 0.08, 60.0)
	return d


static func _birds(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(10.0)
	var lp := 0.0
	for i in d.size():
		lp += _lp_a(300.0) * (rng.randf_range(-1.0, 1.0) - lp)
		d[i] = lp * 0.05 # air
	for k in 16:
		var c := _chirp(rng, 0.0)
		var start := rng.randi_range(0, d.size() - c.size() - 1)
		var amp := rng.randf_range(0.15, 0.6)
		for i in c.size():
			d[start + i] += c[i] * amp
	return d


static func _crickets(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(4.0)
	for v in 3:
		var f := rng.randf_range(4200.0, 4900.0)
		var rate := rng.randf_range(1.2, 2.2)
		var off := rng.randf()
		for i in d.size():
			var t := float(i) / RATE
			var chirp := 1.0 if fposmod(t * rate + off, 1.0) < 0.25 else 0.0
			var trill := 0.5 + 0.5 * sin(TAU * 32.0 * t)
			d[i] += sin(TAU * f * t) * chirp * trill * 0.2
	return d


## The distant city: cart wheels, hooves and a low rumble.
static func _city(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(8.0)
	var brown := 0.0
	var lp := 0.0
	for i in d.size():
		brown = clampf(brown + rng.randf_range(-0.03, 0.03), -1.0, 1.0)
		lp += _lp_a(220.0) * (brown - lp)
		d[i] = lp * 0.8
	var t := rng.randf_range(0.0, 1.0)
	while t < 7.5: # a cab going by somewhere
		var j := int(t * RATE)
		_knock(d, j, rng.randf_range(250.0, 330.0), 0.06, 0.12, 70.0)
		t += rng.randf_range(0.18, 0.3)
	return d


## A low, uneasy pad for when the guards are searching.
static func _drone() -> PackedFloat32Array:
	var d := _buf(8.0)
	for i in d.size():
		var t := float(i) / RATE
		var swell := 0.6 + 0.4 * sin(TAU * t / 8.0)
		d[i] = (sin(TAU * 55.0 * t) + 0.5 * sin(TAU * 82.5 * t + sin(TAU * 0.25 * t)) + 0.25 * sin(TAU * 110.0 * t * 1.003)) * swell * 0.4
	return d


## A chase pulse: a low drum at 120 bpm under the drone.
static func _pulse(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var d := _buf(4.0)
	for k in 8:
		var j := int(k * 0.5 * RATE)
		_knock(d, j, 55.0, 0.35, 1.0, 10.0)
		_noise_burst(d, j, 0.03, 1500.0, 100.0, 0.3, 60.0, rng)
		if k % 2 == 1:
			_knock(d, j + int(0.25 * RATE), 55.0, 0.2, 0.5, 14.0)
	for i in d.size():
		var t := float(i) / RATE
		d[i] += sin(TAU * 41.2 * t) * 0.15
	return d
