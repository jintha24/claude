class_name WeatherEffects
extends Node3D
## Everything you see of the weather (node "WeatherFX" in main.tscn):
##  * Rain: streaks that stop on roofs, awnings and the road (a height-field collision that
##    follows the camera) and splash where they land.
##  * Snow: slow, drifting flakes.
##  * A cloud layer drifting with the wind, thickening as the weather worsens.
##  * Wet streets: stone, brick, slate and cobbles turn darker and glossy, reflecting the
##    lamps; puddles form in the dips and dry out slowly afterwards.
##  * Wind: chimney smoke and washing lines move with it (global shader parameters).
##  * Lightning flashes in a storm.

const PUDDLE_SPOTS := 36

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _collider: GPUParticlesCollisionHeightField3D
var _clouds: MeshInstance3D
var _cloud_mat: ShaderMaterial
var _flash: DirectionalLight3D
var _flash_energy := 0.0
var _puddles: Array[Decal] = []
var _last_wetness := -1.0
var _last_snow := -1.0
var _cloud_offset := Vector2.ZERO


func _ready() -> void:
	Weather.bus()
	_declare_globals()
	_build_rain()
	_build_snow()
	_build_clouds()
	_build_puddles()
	_flash = DirectionalLight3D.new()
	_flash.name = "Lightning"
	_flash.light_color = Color(0.8, 0.85, 1.0)
	_flash.light_energy = 0.0
	_flash.visible = false
	_flash.rotation_degrees = Vector3(-60, 30, 0)
	add_child(_flash)
	Weather.bus().lightning.connect(_on_lightning)


## Wind values that shaders (washing lines, later trees and grass) read every frame.
## They're declared in project.godot ([shader_globals]); this only adds them if a project
## copy lacks them (querying the list is an editor-only call, so check the setting instead).
static func _declare_globals() -> void:
	if not ProjectSettings.has_setting("shader_globals/wind_strength"):
		RenderingServer.global_shader_parameter_add(&"wind_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.2)
		RenderingServer.global_shader_parameter_add(&"wind_direction", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(1, 0, 0))


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := cam.global_position
		_rain.global_position = Vector3(p.x, p.y + 14.0, p.z) + Weather.wind_direction * Weather.wind * 4.0
		_snow.global_position = Vector3(p.x, p.y + 10.0, p.z)
		_clouds.global_position = Vector3(p.x, 650.0, p.z)
	_rain.amount_ratio = Weather.rain
	_rain.emitting = Weather.rain > 0.01
	_snow.amount_ratio = Weather.snow
	_snow.emitting = Weather.snow > 0.01
	var wind_vec := Weather.wind_direction * Weather.wind
	(_rain.process_material as ParticleProcessMaterial).gravity = Vector3(wind_vec.x * 6.0, -9.8, wind_vec.z * 6.0)
	(_snow.process_material as ParticleProcessMaterial).gravity = Vector3(wind_vec.x * 1.5, -0.8, wind_vec.z * 1.5)
	RenderingServer.global_shader_parameter_set(&"wind_strength", Weather.wind)
	RenderingServer.global_shader_parameter_set(&"wind_direction", Weather.wind_direction)
	for node in get_tree().get_nodes_in_group("chimney_smoke"):
		(node as ChimneySmoke).wind = Vector3(0.1, 0.0, 0.05) + wind_vec * 1.4

	# Clouds drift with the wind.
	_cloud_offset += Vector2(wind_vec.x, wind_vec.z) * delta * 0.004
	# Fair-weather cumulus even on a "clear" day (visual only; gameplay reads Weather.cloud).
	_cloud_mat.set_shader_parameter("coverage", maxf(Weather.cloud, 0.34))
	_cloud_mat.set_shader_parameter("fog_amount", Weather.fog)
	_cloud_mat.set_shader_parameter("offset", _cloud_offset)
	_cloud_mat.set_shader_parameter("darkness", clampf(Weather.rain * 0.6 + maxf(Weather.cloud - 0.6, 0.0), 0.0, 0.85))
	_cloud_mat.set_shader_parameter("daylight", clampf(Stealth.ambient_light / 0.85, 0.02, 1.0))

	# Wet and snowy surfaces, puddles.
	if absf(Weather.wetness - _last_wetness) > 0.02 or absf(Weather.snow_cover - _last_snow) > 0.02:
		_last_wetness = Weather.wetness
		_last_snow = Weather.snow_cover
		MaterialLibrary.set_wetness(Weather.wetness, Weather.snow_cover)
	for d in _puddles:
		d.modulate.a = clampf(Weather.puddles * 1.3 - float(d.get_meta("depth")), 0.0, 1.0)
		d.visible = d.modulate.a > 0.01

	# Lightning flash decays quickly.
	if _flash_energy > 0.0:
		_flash_energy = maxf(_flash_energy - delta * 30.0, 0.0)
		_flash.light_energy = _flash_energy
		_flash.visible = _flash_energy > 0.01


func _on_lightning(strength: float) -> void:
	_flash_energy = 6.0 * strength
	_flash.rotation_degrees = Vector3(randf_range(-80, -40), randf_range(0, 360), 0)
	# Thunder follows a few seconds later and drowns out everything for a moment.
	get_tree().create_timer(randf_range(1.0, 4.0)).timeout.connect(func() -> void:
		Weather.thunder(3.0)
		var harry := get_tree().get_first_node_in_group("player") as Node3D
		if harry:
			Stealth.bark(harry, "*Thunder rolls over the rooftops*"))


# ---------------------------------------------------------------------------
func _build_rain() -> void:
	_collider = GPUParticlesCollisionHeightField3D.new()
	_collider.name = "RainOcclusion"
	_collider.size = Vector3(48, 40, 48)
	_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_collider.follow_camera_enabled = true
	_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_collider)

	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 7000
	_rain.lifetime = 1.4
	_rain.preprocess = 1.4
	_rain.visibility_aabb = AABB(Vector3(-24, -40, -24), Vector3(48, 44, 48))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.collision_base_size = 0.02
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3.DOWN
	pm.spread = 2.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_align_y = true
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 1
	_rain.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.012, 0.55)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = Color(0.75, 0.8, 0.88, 0.28)
	mat.disable_receive_shadows = true
	streak.material = mat
	_rain.draw_pass_1 = streak
	add_child(_rain)

	# Splashes where the drops land.
	var splash := GPUParticles3D.new()
	splash.name = "Splashes"
	splash.amount = 3000
	splash.lifetime = 0.25
	splash.emitting = true
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.UP
	spm.spread = 60.0
	spm.initial_velocity_min = 0.6
	spm.initial_velocity_max = 1.4
	spm.gravity = Vector3(0, -9.8, 0)
	spm.scale_min = 0.5
	spm.scale_max = 1.0
	splash.process_material = spm
	var dot := QuadMesh.new()
	dot.size = Vector2(0.03, 0.03)
	var dmat := mat.duplicate() as StandardMaterial3D
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dmat.albedo_color = Color(0.85, 0.88, 0.95, 0.45)
	dot.material = dmat
	splash.draw_pass_1 = dot
	add_child(splash)
	_rain.sub_emitter = _rain.get_path_to(splash)


func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = 5000
	_snow.lifetime = 12.0
	_snow.preprocess = 12.0
	_snow.visibility_aabb = AABB(Vector3(-24, -24, -24), Vector3(48, 30, 48))
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3.DOWN
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, -0.8, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow.process_material = pm
	var flake := QuadMesh.new()
	flake.size = Vector2(0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1, 1, 1, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	flake.material = mat
	_snow.draw_pass_1 = flake
	add_child(_snow)


func _build_clouds() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D noise_a : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_b : repeat_enable, filter_linear_mipmap;
uniform float coverage = 0.1;
uniform float darkness = 0.0;
uniform float daylight = 1.0;
uniform float fog_amount = 0.0;
uniform vec2 offset = vec2(0.0);
void fragment() {
	vec2 uv = UV * 3.0 + offset;
	float n = texture(noise_a, uv).r * 0.65 + texture(noise_b, uv * 2.7 - offset * 1.7).r * 0.35;
	float threshold = mix(0.78, 0.22, coverage);
	float d = smoothstep(threshold, threshold + 0.35, n);
	// Fade towards the horizon so the layer never shows an edge.
	float edge = 1.0 - smoothstep(0.3, 0.5, length(UV - vec2(0.5)));
	// Sunlit white edges, soft blue-grey bellies where the cloud is thick.
	float core = smoothstep(threshold + 0.1, threshold + 0.6, n);
	vec3 lit = mix(vec3(1.0, 0.98, 0.94), vec3(0.62, 0.66, 0.74), core * 0.7);
	lit = mix(lit, vec3(0.32, 0.33, 0.36), darkness);
	ALBEDO = lit * mix(0.05, 1.05, daylight);
	ALPHA = d * edge * mix(0.6, 0.97, coverage) * (1.0 - fog_amount * 0.95);
}
"""
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = shader
	for key in ["noise_a", "noise_b"]:
		var tex := NoiseTexture2D.new()
		var fnl := FastNoiseLite.new()
		fnl.seed = 7 if key == "noise_a" else 19
		fnl.frequency = 0.006 if key == "noise_a" else 0.016
		fnl.fractal_octaves = 5
		tex.noise = fnl
		tex.seamless = true
		tex.width = 512
		tex.height = 512
		tex.generate_mipmaps = true
		_cloud_mat.set_shader_parameter(key, tex)
	var plane := PlaneMesh.new()
	plane.size = Vector2(5000, 5000)
	plane.flip_faces = false
	_clouds = MeshInstance3D.new()
	_clouds.name = "CloudLayer"
	_clouds.mesh = plane
	_clouds.material_override = _cloud_mat
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.rotation_degrees = Vector3(180, 0, 0) # face down, towards the street
	add_child(_clouds)


func _build_puddles() -> void:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.02
	fnl.fractal_octaves = 3
	for y in 256:
		for x in 256:
			var d := Vector2(x - 128, y - 128).length() / 128.0
			var n := fnl.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.6 + (n - 0.5) * 1.2 - 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.05, 0.05, 0.06, a))
	img.generate_mipmaps()
	var albedo := ImageTexture.create_from_image(img)
	var orm_img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	orm_img.fill(Color(1.0, 0.03, 0.0)) # AO 1, roughness ~0: a mirror of still water
	var orm := ImageTexture.create_from_image(orm_img)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1866
	for i in PUDDLE_SPOTS:
		var d := Decal.new()
		d.name = "Puddle"
		d.texture_albedo = albedo
		d.texture_orm = orm
		d.size = Vector3(rng.randf_range(1.0, 3.2), 0.4, rng.randf_range(0.8, 2.4))
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.cull_mask = 1
		d.set_meta("depth", rng.randf_range(0.0, 0.5)) # deeper dips fill first
		if i < 22:
			d.position = Vector3(rng.randf_range(-3.2, 3.2), 0.0, rng.randf_range(-44.0, 44.0))
		else:
			d.position = Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-86.0, -56.0))
		d.rotation.y = rng.randf() * TAU
		d.visible = false
		add_child(d)
		_puddles.append(d)
