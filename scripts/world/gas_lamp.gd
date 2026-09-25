@tool
class_name GasLamp
extends StaticBody3D
## A London cast-iron gas street lamp with a real shadow-casting light.
## Phase 5 (day/night) will switch `lit` on at dusk and off at dawn.

@export var lit: bool = true:
	set(v):
		lit = v
		_apply_lit()
## Only the lamps nearest to Harry should cast shadows (performance). Phase 5 manages this.
@export var casts_shadows: bool = true:
	set(v):
		casts_shadows = v
		if _light:
			_light.shadow_enabled = v

## Hanging baskets of geraniums and trailing ivy from the ladder bar.
@export var flower_baskets: bool = false

const LANTERN_HEIGHT := 3.25

var _light: OmniLight3D
var _glass_instance: MeshInstance3D


func _ready() -> void:
	add_to_group("gas_lamps")
	collision_layer = 1
	collision_mask = 0
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()
	_apply_lit()


## The post, shared by every lamp without flower baskets (built once: there are hundreds).
static var _shared_post: Mesh
static var _shared_shadow: Mesh


func _build() -> void:
	if not flower_baskets and _shared_post != null:
		var shared := MeshInstance3D.new()
		shared.name = "Post"
		shared.mesh = _shared_post
		shared.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		add_child(shared)
		if _shared_shadow:
			shared.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var caster := MeshInstance3D.new()
			caster.name = "ShadowCaster"
			caster.mesh = _shared_shadow
			caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			shared.add_child(caster)
		_build_lantern()
		return
	var iron := MaterialLibrary.get_material("iron")
	var mb := MeshBuilder.new()
	var gilt := MaterialLibrary.get_material("gilt")
	# Moulded base, fluted column, gilded collars (a parish vestry's pride).
	mb.add_cylinder(0.2, 0.2, 0.08, Vector3(0, 0.04, 0), iron, 16)
	mb.add_cylinder(0.16, 0.13, 0.45, Vector3(0, 0.305, 0), iron, 8) # plinth
	mb.add_cylinder(0.14, 0.14, 0.05, Vector3(0, 0.55, 0), gilt, 16)
	mb.add_cylinder(0.1, 0.1, 0.08, Vector3(0, 0.49, 0), iron, 12)
	mb.add_cylinder(0.075, 0.055, 2.45, Vector3(0, 1.75, 0), iron, 12) # shaft
	for k in 8:
		var a := TAU * k / 8.0
		mb.add_box(Vector3(0.018, 1.4, 0.018), Vector3(cos(a) * 0.07, 1.25, sin(a) * 0.07), iron) # flutes
	mb.add_cylinder(0.08, 0.08, 0.06, Vector3(0, 2.2, 0), iron, 12) # collar
	mb.add_cylinder(0.09, 0.09, 0.03, Vector3(0, 2.25, 0), gilt, 12)
	# Scrollwork brackets under the ladder bar.
	for side: float in [-1.0, 1.0]:
		var scroll := TorusMesh.new()
		scroll.inner_radius = 0.07
		scroll.outer_radius = 0.09
		scroll.rings = 12
		scroll.ring_segments = 6
		mb.add_mesh(scroll, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * 0.18, 2.72, 0)), iron)
		mb.add_box(Vector3(0.2, 0.02, 0.02), Vector3(side * 0.1, 2.62, 0), iron, Basis(Vector3.BACK, side * 0.6))
	# Ladder bar: lamplighters rested their ladders on this.
	mb.add_box(Vector3(0.7, 0.035, 0.035), Vector3(0, 2.85, 0), iron)
	mb.add_cylinder(0.02, 0.02, 0.06, Vector3(-0.35, 2.85, 0), iron, 6, Basis(Vector3.FORWARD, PI * 0.5))
	mb.add_cylinder(0.02, 0.02, 0.06, Vector3(0.35, 2.85, 0), iron, 6, Basis(Vector3.FORWARD, PI * 0.5))
	# Lantern: four-sided tapered iron frame with glass, cap and finial.
	mb.add_cylinder(0.12, 0.12, 0.06, Vector3(0, LANTERN_HEIGHT - 0.28, 0), iron, 4)
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var off := Vector3(cos(a), 0, sin(a))
		mb.add_box(Vector3(0.022, 0.52, 0.022), Vector3(0, LANTERN_HEIGHT, 0) + off * 0.19, iron,
			Basis(off.cross(Vector3.UP).normalized(), -0.14))
	mb.add_cylinder(0.3, 0.06, 0.2, Vector3(0, LANTERN_HEIGHT + 0.36, 0), iron, 4)
	mb.add_cylinder(0.03, 0.0, 0.18, Vector3(0, LANTERN_HEIGHT + 0.55, 0), iron, 6)
	if flower_baskets:
		_add_baskets(mb, iron)
	var mi := mb.build_into(self, "Post")
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	if not flower_baskets and not Engine.is_editor_hint():
		_shared_post = mi.mesh
		var caster := mi.get_node_or_null("ShadowCaster") as MeshInstance3D
		_shared_shadow = caster.mesh if caster else null
	_build_lantern()


func _build_lantern() -> void:

	var glass_mesh := CylinderMesh.new()
	glass_mesh.top_radius = 0.24
	glass_mesh.bottom_radius = 0.14
	glass_mesh.height = 0.5
	glass_mesh.radial_segments = 4
	glass_mesh.rings = 1
	_glass_instance = MeshInstance3D.new()
	_glass_instance.name = "Glass"
	_glass_instance.mesh = glass_mesh
	_glass_instance.position = Vector3(0, LANTERN_HEIGHT, 0)
	_glass_instance.rotation.y = PI * 0.25
	_glass_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass_instance)

	_light = OmniLight3D.new()
	_light.name = "GasFlame"
	_light.position = Vector3(0, LANTERN_HEIGHT - 0.05, 0)
	_light.light_color = Color(1.0, 0.7, 0.4) # ~2000 K gas mantle
	_light.light_energy = 2.2
	_light.light_indirect_energy = 1.0
	_light.light_volumetric_fog_energy = 2.0
	_light.light_size = 0.08
	# 1860s street gas lamps were dim: a pool of light a few metres across.
	_light.omni_range = 10.0
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = casts_shadows
	_light.shadow_bias = 0.04
	_light.shadow_normal_bias = 1.5
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 70.0
	_light.distance_fade_length = 20.0
	_light.add_to_group("stealth_lights")
	add_child(_light)

	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.12
	cyl.height = 3.0
	cs.shape = cyl
	cs.position = Vector3(0, 1.5, 0)
	add_child(cs)
	# The lantern itself, so arrows (and the camera) can hit it.
	var lantern_cs := CollisionShape3D.new()
	var lantern := BoxShape3D.new()
	lantern.size = Vector3(0.5, 0.75, 0.5)
	lantern_cs.shape = lantern
	lantern_cs.position = Vector3(0, LANTERN_HEIGHT + 0.08, 0)
	add_child(lantern_cs)


## Broken glass lets the wind blow the gas flame out (a blunt arrow does this).
func extinguish() -> void:
	set_meta("broken", true) # stays dark until it's mended (DayNightCycle, next day)
	lit = false


## Two hanging baskets on chains from the ends of the ladder bar.
func _add_baskets(mb: MeshBuilder, iron: Material) -> void:
	var wicker := MaterialLibrary.get_tinted("wood_planks", Color(0.45, 0.32, 0.18))
	var leaves := MaterialLibrary.get_tinted("grass", Color(0.4, 0.6, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x * 13.0 + global_position.z * 7.0)) if is_inside_tree() else 5
	var blooms: Array[Color] = [Color(0.85, 0.12, 0.15), Color(0.95, 0.45, 0.6), Color(0.98, 0.95, 0.92), Color(0.75, 0.2, 0.55)]
	for side: float in [-1.0, 1.0]:
		var top := Vector3(side * 0.33, 2.83, 0)
		mb.add_box(Vector3(0.01, 0.42, 0.01), top + Vector3(0, -0.21, 0), iron) # chain
		var c := top + Vector3(0, -0.62, 0)
		var bowl := SphereMesh.new()
		bowl.radius = 0.2
		bowl.height = 0.2
		bowl.is_hemisphere = true
		bowl.radial_segments = 12
		bowl.rings = 4
		mb.add_mesh(bowl, Transform3D(Basis(Vector3.RIGHT, PI), c), wicker)
		for k in 9:
			var a := TAU * k / 9.0
			var p := c + Vector3(cos(a) * 0.14, rng.randf_range(0.02, 0.1), sin(a) * 0.14)
			var bloom := SphereMesh.new()
			bloom.radius = rng.randf_range(0.05, 0.075)
			bloom.height = bloom.radius * 1.6
			bloom.radial_segments = 6
			bloom.rings = 3
			var col: Color = blooms[rng.randi() % blooms.size()]
			mb.add_mesh(bloom, Transform3D(Basis.IDENTITY, p), MaterialLibrary.get_tinted("grass", col))
		# Trailing ivy spilling over the rim.
		for k in 5:
			var a := TAU * k / 5.0 + 0.3
			mb.add_box(Vector3(0.05, rng.randf_range(0.2, 0.35), 0.03), c + Vector3(cos(a) * 0.19, -0.18, sin(a) * 0.19), leaves)
		mb.add_mesh(_leaf_ball(0.16), Transform3D(Basis.IDENTITY, c + Vector3(0, 0.02, 0)), leaves)


static func _leaf_ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.2
	s.radial_segments = 8
	s.rings = 4
	return s


func _apply_lit() -> void:
	if _light == null:
		return
	_light.visible = lit
	_glass_instance.material_override = MaterialLibrary.get_material("lamp_glass") if lit else MaterialLibrary.get_material("glass")
