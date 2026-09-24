@tool
class_name ChimneySmoke
extends GPUParticles3D
## Slow, drifting coal smoke from a chimney pot. Self-configuring: just add the node.
## Phase 6 (weather) will drive `wind` so the smoke leans with the wind.

@export var wind: Vector3 = Vector3(0.35, 0.0, 0.15):
	set(v):
		wind = v
		if process_material is ParticleProcessMaterial:
			(process_material as ParticleProcessMaterial).gravity = Vector3(wind.x, 0.12, wind.z)

static var _shared_draw_mesh: QuadMesh


func _init() -> void:
	name = "ChimneySmoke"
	add_to_group("chimney_smoke")
	amount = 28
	lifetime = 9.0
	preprocess = 9.0
	randomness = 0.4
	visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	transparency = 0.0

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(wind.x, 0.12, wind.z)
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.25))
	scale_curve.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = scale_curve
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.16, 0.15, 0.14, 0.0))
	ramp.set_color(1, Color(0.45, 0.44, 0.43, 0.0))
	ramp.add_point(0.08, Color(0.18, 0.17, 0.16, 0.55))
	ramp.add_point(0.6, Color(0.35, 0.34, 0.33, 0.22))
	var grt := GradientTexture1D.new()
	grt.gradient = ramp
	pm.color_ramp = grt
	process_material = pm

	if _shared_draw_mesh == null:
		_shared_draw_mesh = _make_draw_mesh()
	draw_pass_1 = _shared_draw_mesh


static func _make_draw_mesh() -> QuadMesh:
	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	puff.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = puff
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.5

	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	quad.material = mat
	return quad
