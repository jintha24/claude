class_name AudioDirector
extends Node
## Plays the game's sound. Put one in each place (London, the hills); it:
##  * voices every noise the game makes (Stealth.make_noise: doors, locks, arrows, the
##    rattle, dogs, hooves...) as a 3D sound where it happened, and Harry's footsteps on
##    whatever he's walking on (stone, wood, grass, gravel, carpet, water, slate);
##  * keeps ambience beds going and mixes them from the weather, the hour and the place:
##    rain, wind, the crowd and the city in London, birdsong by day and crickets at night
##    in the hills, water near the lake (sound zones, see add_zone);
##  * tolls the church bell on the hour in London and rolls thunder after lightning;
##  * music: an uneasy drone while guards are searching, a pulse under it in a chase, a
##    stinger when Harry is first spotted. Files in assets/audio/music/ (explore.ogg,
##    tension.ogg, chase.ogg) replace the drone and pulse when present.
## Buses: SFX (one-shots), Ambience (beds), Music. All sounds come from SoundLibrary.

enum Place { LONDON, HILLS }
enum Mood { CALM, TENSE, CHASE }

const POOL_SIZE := 24
const BEDS: Array[String] = ["rain", "wind", "crowd", "city", "birds", "crickets", "water_lap"]

@export var place: Place = Place.LONDON
## Where the church bell hangs (London): St Giles's tower once that district is built.
@export var bell_position: Vector3 = StGiles.BELL_POSITION

static var _current: AudioDirector

var mood: Mood = Mood.CALM
var bed_levels := {}
var music_levels := {}

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_next := 0
var _beds := {}
var _music := {}
var _zones: Array[Dictionary] = []
var _harry: Harry
var _rng := RandomNumberGenerator.new()
var _bell_left := 0
var _bell_timer := 0.0
var _thunder_queue: Array[Dictionary] = []
var _mood_timer := 0.0
var _was_chased := false
var _warm_task := -1


## The director in the current place (or null).
static func current() -> AudioDirector:
	return _current if is_instance_valid(_current) else null


## Plays a one-shot sound at a point in the world. Safe to call when there's no director.
static func play(sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, max_distance: float = 45.0) -> void:
	var d := current()
	if d:
		d._play_at(sound_name, pos, volume_db, pitch, max_distance)


## A looping sound fixed to `node` (a fire, a fountain). Returns the player.
static func attach_loop(node: Node3D, sound_name: String, volume_db: float = 0.0, max_distance: float = 25.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "Sound_" + sound_name
	p.stream = SoundLibrary.get_stream(sound_name)
	p.bus = "Ambience"
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = max_distance * 0.25
	p.autoplay = true
	p.add_to_group("sound_loops")
	node.add_child(p)
	return p


## A region where an ambience bed swells: `bed` is one of BEDS, loudest within `radius`
## of `center` and fading out over `falloff` metres beyond it.
func add_zone(bed: String, center: Vector3, radius: float, falloff: float = 40.0, level: float = 0.8) -> void:
	_zones.append({"bed": bed, "center": center, "radius": radius, "falloff": falloff, "level": level})


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	if _current == self:
		_current = null
	# Stop everything and let the sounds go (the next place builds what it needs).
	for p in _pool:
		p.stop()
	for b: AudioStreamPlayer in _beds.values():
		b.stop()
	for m: AudioStreamPlayer in _music.values():
		m.stop()
	for n in get_tree().get_nodes_in_group("sound_loops"):
		(n as AudioStreamPlayer3D).stop()
	if _warm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_warm_task)
		_warm_task = -1
	SoundLibrary.clear_cache()


func _ready() -> void:
	_rng.randomize()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_polyphony = 1
		add_child(p)
		_pool.append(p)
	for bed in BEDS:
		var b := AudioStreamPlayer.new()
		b.name = "Bed_" + bed
		b.bus = "Ambience"
		b.volume_db = -80.0
		add_child(b)
		_beds[bed] = b
		bed_levels[bed] = 0.0
	for layer: String in ["calm", "tense", "chase"]:
		var m := AudioStreamPlayer.new()
		m.name = "Music_" + layer
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music[layer] = m
	Stealth.bus().noise_made.connect(_on_noise)
	Weather.bus().lightning.connect(_on_lightning)
	GameClock.bus().hour_passed.connect(_on_hour)
	# Build the common sounds on a worker thread so the first footstep doesn't hitch.
	var names: Array = BEDS.duplicate()
	for s in SoundLibrary.SURFACES:
		names.append("step_" + s)
	names.append_array(["drone", "pulse", "stinger", "bell", "thunder", "hoof", "bow_release", "arrow_hit"])
	_warm_task = WorkerThreadPool.add_task(SoundLibrary.warm_up.bind(names), false, "Warm up sounds")


func _find_harry() -> void:
	if _harry and is_instance_valid(_harry):
		return
	_harry = get_tree().get_first_node_in_group("player") as Harry
	if _harry:
		_harry.stealth.footstep.connect(_on_footstep)
		_harry.inventory.stolen.connect(func(_c: String, _v: int) -> void: _play_at("coin", _harry.global_position, -8.0, 1.0, 12.0))
		_harry.interaction.lock_event.connect(_on_lock_event)


func _play_at(sound_name: String, pos: Vector3, volume_db: float, pitch: float, max_distance: float, variant: int = 0) -> void:
	var p := _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	p.stop()
	p.stream = SoundLibrary.get_stream(sound_name, variant)
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	p.max_distance = max_distance
	p.unit_size = maxf(max_distance * 0.12, 1.0)
	p.play()


func _on_footstep(surface: String, radius: float) -> void:
	if _harry == null:
		return
	var s := "step_" + surface
	if not surface in SoundLibrary.SURFACES:
		s = "step_stone"
	var vol := linear_to_db(clampf(radius / 9.0, 0.12, 1.3))
	_play_at(s, _harry.global_position, vol, 1.0, 30.0, _rng.randi_range(0, SoundLibrary.VARIATIONS - 1))


func _on_lock_event(event: String) -> void:
	if _harry == null:
		return
	match event:
		"lever": _play_at("lock_click", _harry.global_position, -6.0, 1.2, 8.0)
		"opened": _play_at("lock_open", _harry.global_position, -2.0, 1.0, 12.0)
		"pick_broke": _play_at("lock_click", _harry.global_position, 0.0, 0.6, 10.0)
		"slip": _play_at("lock_click", _harry.global_position, -8.0, 0.8, 8.0)


func _on_noise(pos: Vector3, radius: float, kind: String, _suspicious: bool, source: Node) -> void:
	var vol := linear_to_db(clampf(radius / 20.0, 0.25, 1.5))
	match kind:
		"landing":
			var surface := _harry.stealth.surface if _harry and source == _harry else "stone"
			_play_at("step_" + (surface if surface in SoundLibrary.SURFACES else "stone"), pos, vol + 3.0, 0.8, 30.0)
		"bow": _play_at("bow_release", pos, -2.0, 1.0, 30.0)
		"whistle_flight": _play_at("whistle_arrow", pos, 0.0, 1.0, 60.0)
		"thud", "whistle": _play_at("arrow_hit", pos, vol, 1.0, 35.0)
		"glass": _play_at("glass_break", pos, vol, 1.0, 45.0)
		"rattle": _play_at("rattle", pos, 2.0, 1.0, 90.0)
		"dog_bark": _play_at("dog_bark", pos, 0.0, 1.0, 70.0)
		"growl": _play_at("dog_bark", pos, -8.0, 0.55, 25.0)
		"yelp", "whimper": _play_at("dog_bark", pos, -10.0, 1.6, 25.0)
		"hooves": _play_at("hoof", pos, vol, 1.0, 50.0)
		"whistle_call": _play_at("whistle_call", pos, 0.0, 1.0, 90.0)
		"door": _play_at("door_creak", pos, vol, 1.0, 30.0)
		"window": _play_at("door_creak", pos, vol - 3.0, 1.5, 25.0)
		"creak": _play_at("door_creak", pos, vol - 4.0, 0.75, 20.0)
		"iron_scrape": _play_at("door_creak", pos, vol, 0.55, 30.0)
		"lock", "lockpick", "tampering": _play_at("lock_click", pos, vol - 6.0, 1.0, 12.0)
		"safe": _play_at("lock_open", pos, vol, 0.7, 20.0)
		"splash": _play_at("splash", pos, vol, 1.0, 40.0)
		"body_fall": _play_at("punch", pos, vol, 0.55, 25.0)
		"scuffle", "punch": _play_at("punch", pos, vol, 1.0, 25.0)
		"bell": _play_at("bell", pos, 0.0, 1.0, 400.0)


func _on_lightning(strength: float) -> void:
	# Sound travels ~340 m/s: the storm is somewhere between 100 m and 1 km away.
	_thunder_queue.append({"t": _rng.randf_range(0.3, 3.0), "db": linear_to_db(clampf(strength, 0.3, 1.0))})


func _on_hour(hour: int) -> void:
	if place != Place.LONDON:
		return
	_bell_left = hour % 12
	if _bell_left == 0:
		_bell_left = 12
	_bell_timer = 0.0


func _process(delta: float) -> void:
	_find_harry()
	var listener := _listener_position()
	# The church bell tolls the hour, a stroke every 2.4 s.
	if _bell_left > 0:
		_bell_timer -= delta
		if _bell_timer <= 0.0:
			_bell_timer = 2.4
			_bell_left -= 1
			_play_at("bell", bell_position, 4.0, 1.0, 600.0)
	for i in range(_thunder_queue.size() - 1, -1, -1):
		var q: Dictionary = _thunder_queue[i]
		q["t"] = float(q["t"]) - delta
		if float(q["t"]) <= 0.0:
			_thunder_queue.remove_at(i)
			_play_2d("thunder", float(q["db"]))
	_update_beds(listener, delta)
	_mood_timer -= delta
	if _mood_timer <= 0.0:
		_mood_timer = 0.25
		_update_mood()
	_update_music(delta)


func _listener_position() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam:
		return cam.global_position
	return _harry.global_position if _harry else Vector3.ZERO


## Target level (0..1) for each ambience bed right now.
func compute_bed_targets(listener: Vector3) -> Dictionary:
	var h := GameClock.hours()
	var day := clampf(minf(h - 5.0, 20.5 - h), 0.0, 1.0) # fades in at dawn, out at dusk
	var indoors := InteriorVolume.daylight_at(listener) < 1.0
	var shelter := 0.35 if indoors else 1.0
	var t := {}
	t["rain"] = clampf(Weather.rain, 0.0, 1.0) * shelter
	t["wind"] = clampf(0.1 + Weather.wind * 0.7, 0.0, 1.0) * (1.0 if place == Place.HILLS else 0.6) * shelter
	if place == Place.LONDON:
		var people := 0
		for c in get_tree().get_nodes_in_group("civilians"):
			var n := c as Node3D
			if n and n.global_position.distance_squared_to(listener) < 900.0:
				people += 1
		t["crowd"] = clampf(people / 14.0, 0.0, 0.9) * shelter
		t["city"] = (0.25 + 0.2 * day) * shelter
		t["birds"] = 0.12 * day * (1.0 - Weather.rain) * shelter
		t["crickets"] = 0.0
	else:
		t["crowd"] = 0.0
		t["city"] = 0.0
		t["birds"] = 0.7 * day * (1.0 - Weather.rain) * shelter
		t["crickets"] = 0.45 * (1.0 - day) * (1.0 - Weather.rain) * (0.0 if GameClock.is_winter() else 1.0) * shelter
	t["water_lap"] = 0.0
	for z in _zones:
		var dist := listener.distance_to(z["center"])
		var k := 1.0 - clampf((dist - float(z["radius"])) / float(z["falloff"]), 0.0, 1.0)
		t[z["bed"]] = maxf(float(t.get(z["bed"], 0.0)), k * float(z["level"]))
	return t


func _update_beds(listener: Vector3, delta: float) -> void:
	var targets := compute_bed_targets(listener)
	for bed: String in BEDS:
		var level := move_toward(float(bed_levels[bed]), float(targets.get(bed, 0.0)), delta * 0.5)
		bed_levels[bed] = level
		var p: AudioStreamPlayer = _beds[bed]
		if level > 0.005:
			if not p.playing:
				if not SoundLibrary.is_cached(bed):
					continue # still being built on the worker thread
				p.stream = SoundLibrary.get_stream(bed)
				p.play(_rng.randf_range(0.0, 2.0))
			p.volume_db = linear_to_db(level)
		elif p.playing:
			p.stop()


func _update_mood() -> void:
	var chased := false
	var tense := false
	for g in get_tree().get_nodes_in_group("guards"):
		var guard := g as Guard
		if guard == null:
			continue
		if guard.state == Guard.State.CHASE:
			chased = true
		elif guard.state in [Guard.State.INVESTIGATE, Guard.State.SEARCH]:
			tense = true
	if chased and not _was_chased:
		_play_2d("stinger", -4.0, "Music")
	_was_chased = chased
	mood = Mood.CHASE if chased else (Mood.TENSE if tense else Mood.CALM)


func _update_music(delta: float) -> void:
	var want := {"calm": 0.0, "tense": 0.0, "chase": 0.0}
	match mood:
		Mood.CALM: want["calm"] = 0.5
		Mood.TENSE: want["tense"] = 0.55
		Mood.CHASE:
			want["tense"] = 0.45
			want["chase"] = 0.7
	for layer: String in _music:
		var p: AudioStreamPlayer = _music[layer]
		var target: float = want[layer]
		var cur: float = music_levels.get(layer, 0.0)
		var level := move_toward(cur, target, delta * (0.6 if target > cur else 0.25))
		music_levels[layer] = level
		if level > 0.005:
			if not p.playing:
				var s := _music_stream(layer)
				if s == null:
					music_levels[layer] = 0.0 # not ready yet: start from silence when it is
					continue
				p.stream = s
				p.play()
			p.volume_db = linear_to_db(level)
		elif p.playing:
			p.stop()


## The music for a layer: a file from assets/audio/music/ if there is one; otherwise the
## built-in drone (tense) and pulse (chase). Calm has no built-in music: the ambience is it.
func _music_stream(layer: String) -> AudioStream:
	var names := {"calm": "explore", "tense": "tension", "chase": "chase"}
	for ext: String in [".ogg", ".mp3", ".wav"]:
		var path := "res://assets/audio/music/%s%s" % [names[layer], ext]
		if ResourceLoader.exists(path):
			var s := load(path) as AudioStream
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			elif s is AudioStreamMP3:
				(s as AudioStreamMP3).loop = true
			return s
	var built_in := {"tense": "drone", "chase": "pulse"}
	if built_in.has(layer) and SoundLibrary.is_cached(built_in[layer]):
		return SoundLibrary.get_stream(built_in[layer])
	return null # calm has no built-in music (the ambience is it); the others may still be building


func _play_2d(sound_name: String, volume_db: float, bus: String = "Ambience") -> void:
	var p := AudioStreamPlayer.new()
	p.stream = SoundLibrary.get_stream(sound_name)
	p.bus = bus
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Is a bed audible right now (for tests)?
func is_bed_playing(bed: String) -> bool:
	return (_beds[bed] as AudioStreamPlayer).playing


func is_music_playing(layer: String) -> bool:
	return (_music[layer] as AudioStreamPlayer).playing
