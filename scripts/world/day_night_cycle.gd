class_name DayNightCycle
extends Node
## Drives everything that depends on the time of day (node "DayNight" in main.tscn).
##
##  * Sun: real solar position for London (51.5 N) on the current date. Golden light when
##    low, deep red at sunset, off below the horizon.
##  * Moon: a faint cold blue light at night, with shadows. Stars in the night sky.
##  * Fog and sky tint, Stealth.ambient_light (how dark it is for sneaking).
##  * Gas lamps: lit one after another at dusk (the lamplighter's round), out at dawn.
##    Only the 6 lamps nearest the camera cast shadows (performance).
##  * Windows: warm lamplight in the evening, going dark house by house as people go to bed.

const LATITUDE := 51.5
const LAMP_SHADOW_BUDGET := 6

@export var sun_path: NodePath = ^"../Sun"
@export var environment_path: NodePath = ^"../WorldEnvironment"
@export var max_sun_energy: float = 2.4
@export var moon_energy: float = 0.12

var sun_elevation: float = 0.0 # degrees
var sun_azimuth: float = 0.0 # degrees from north, clockwise

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _day_fog := Color(0.58, 0.54, 0.48)
var _night_fog := Color(0.05, 0.06, 0.09)
var _lamp_timer := 0.0
var _lamp_delays := {}


func _ready() -> void:
	GameClock.bus()
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we:
		_env = we.environment
		if _env and _env.sky and _env.sky.sky_material is PhysicalSkyMaterial:
			(_env.sky.sky_material as PhysicalSkyMaterial).night_sky = _make_starfield()
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.62, 0.72, 0.95)
	_moon.shadow_enabled = true
	_moon.directional_shadow_max_distance = 80.0
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	update_now()


func _process(delta: float) -> void:
	update_now()
	_lamp_timer -= delta
	if _lamp_timer <= 0.0:
		_lamp_timer = 0.5
		_update_lamps()


## Recomputes sun, moon, ambient light, fog and windows for the current clock time.
func update_now() -> void:
	var h := GameClock.hours()
	var sp := solar_position(h, GameClock.day_of_year())
	sun_elevation = sp.x
	sun_azimuth = sp.y
	var to_sun := direction_from(sun_elevation, sun_azimuth)
	if _sun:
		_sun.global_basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
		var e := sun_elevation
		var energy := smoothstep(-2.0, 12.0, e) * max_sun_energy * Weather.sun_factor()
		_sun.light_energy = energy
		_sun.visible = e > -3.0
		var low := Color(1.0, 0.42, 0.18)
		var golden := Color(1.0, 0.72, 0.45)
		var noon := Color(1.0, 0.95, 0.88)
		_sun.light_color = low.lerp(golden, smoothstep(0.0, 8.0, e)).lerp(noon, smoothstep(12.0, 35.0, e))
	# The moon: roughly opposite the sun (a simple full-moon approximation).
	var moon_el := -sun_elevation * 0.8 + 10.0
	var moon_dir := direction_from(moon_el, fposmod(sun_azimuth + 180.0, 360.0))
	_moon.global_basis = Basis.looking_at(-moon_dir, Vector3.UP if absf(moon_dir.y) < 0.99 else Vector3.FORWARD)
	var moon_up := smoothstep(0.0, 10.0, moon_el) * (1.0 - smoothstep(-6.0, 2.0, sun_elevation))
	_moon.light_energy = moon_energy * moon_up
	_moon.visible = moon_up > 0.01

	_moon.light_energy *= 1.0 - Weather.cloud * 0.85
	var daylight := smoothstep(-8.0, 15.0, sun_elevation)
	var overcast := 1.0 - Weather.cloud * 0.3 - Weather.fog * 0.15
	Stealth.ambient_light = clampf((daylight * 0.85 + moon_up * 0.06 * (1.0 - Weather.cloud)) * overcast, 0.03, 0.85)
	Stealth.shade_factor = 0.5
	if _env:
		var fog := _night_fog.lerp(_day_fog, daylight)
		# A touch of warm glow in the haze at sunrise and sunset.
		fog = fog.lerp(Color(0.62, 0.42, 0.3), (1.0 - absf(sun_elevation - 3.0) / 10.0) * 0.35 if absf(sun_elevation - 3.0) < 10.0 else 0.0)
		# A London "pea-souper": thick, yellow-grey coal-smoke fog.
		fog = fog.lerp(Color(0.5, 0.47, 0.35) * maxf(daylight, 0.12), Weather.fog * 0.7)
		_env.fog_light_color = fog
		_env.volumetric_fog_albedo = Color(0.88, 0.84, 0.78).lerp(Color(0.5, 0.55, 0.65), 1.0 - daylight)
		_env.volumetric_fog_density = 0.012 + Weather.fog * 0.1 + Weather.rain * 0.012 + Weather.snow * 0.02
		_env.fog_density = 0.0035 + Weather.fog * 0.028 + Weather.rain * 0.004
		if _env.sky and _env.sky.sky_material is PhysicalSkyMaterial:
			var sky := _env.sky.sky_material as PhysicalSkyMaterial
			sky.energy_multiplier = lerpf(1.0, 0.4, Weather.cloud * Weather.cloud)
			sky.mie_coefficient = 0.012 + Weather.cloud * 0.03 + Weather.fog * 0.05
	_update_windows(h)


## Returns Vector2(elevation, azimuth) in degrees for the given local solar hour.
static func solar_position(hour: float, day_of_year: int) -> Vector2:
	var decl := deg_to_rad(-23.44 * cos(deg_to_rad(360.0 / 365.0 * (day_of_year + 10))))
	var lat := deg_to_rad(LATITUDE)
	var ha := deg_to_rad(15.0 * (hour - 12.0))
	var sin_el := sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)
	var el := asin(clampf(sin_el, -1.0, 1.0))
	var az := atan2(-sin(ha), tan(decl) * cos(lat) - sin(lat) * cos(ha))
	return Vector2(rad_to_deg(el), fposmod(rad_to_deg(az), 360.0))


## World direction towards something at `elevation`/`azimuth` (north = -Z, east = +X).
static func direction_from(elevation: float, azimuth: float) -> Vector3:
	var el := deg_to_rad(elevation)
	var az := deg_to_rad(azimuth)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()


func is_dark() -> bool:
	return sun_elevation < 4.0


# ---------------------------------------------------------------------------
# Lamps and windows
# ---------------------------------------------------------------------------
func _update_lamps() -> void:
	var lamps := get_tree().get_nodes_in_group("gas_lamps")
	# The lamplighter lights them from about half an hour before sunset, one by one along
	# his round, and puts them out again after dawn.
	var want_lit := sun_elevation < 3.0
	for node in lamps:
		var lamp := node as GasLamp
		if sun_elevation > 20.0 and lamp.has_meta("broken"):
			lamp.remove_meta("broken") # mended during the day
		if not _lamp_delays.has(lamp):
			var p := lamp.global_position
			_lamp_delays[lamp] = fposmod(p.z * 0.037 + p.x * 0.011, 1.0) * 2.5 # degrees of sun
		var threshold := 3.0 - float(_lamp_delays[lamp])
		var lit := sun_elevation < threshold if want_lit else sun_elevation < -1.0
		if lamp.lit != lit and not lamp.has_meta("broken"):
			lamp.lit = lit
	# Shadow budget: only the closest lit lamps cast shadows.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var lit_lamps: Array = lamps.filter(func(l: Node) -> bool: return (l as GasLamp).lit)
	lit_lamps.sort_custom(func(a: Node, b: Node) -> bool:
		return (a as Node3D).global_position.distance_squared_to(cam.global_position) < (b as Node3D).global_position.distance_squared_to(cam.global_position))
	for i in lit_lamps.size():
		(lit_lamps[i] as GasLamp).casts_shadows = i < LAMP_SHADOW_BUDGET


func _update_windows(h: float) -> void:
	# Three groups of windows go dark at different hours; shops close at 8 pm.
	var dark := is_dark()
	var evening_on := [h >= 16.0 or h < 0.5, h >= 16.0 and h < 23.0, h >= 17.0 and h < 22.0 or (h >= 5.5 and h < 7.5)]
	for g in 3:
		MaterialLibrary.set_window_lit(g, dark and bool(evening_on[g]))
	MaterialLibrary.set_shop_window_lit(dark and h >= 15.0 and h < 20.0)


func _make_starfield() -> ImageTexture:
	var w := 2048
	var hgt := 1024
	var img := Image.create(w, hgt, false, Image.FORMAT_RGB8)
	img.fill(Color(0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1866
	for i in 2600:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, hgt / 2) # upper hemisphere only
		var b := pow(rng.randf(), 3.0) * 0.9 + 0.05
		var tint := Color(b, b, b * 1.1).lerp(Color(b, b * 0.9, b * 0.8), rng.randf() * 0.4)
		img.set_pixel(x, y, tint)
	return ImageTexture.create_from_image(img)
