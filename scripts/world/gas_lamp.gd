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


func _build() -> void:
	var iron := MaterialLibrary.get_material("iron")
	var mb := MeshBuilder.new()
	mb.add_cylinder(0.16, 0.13, 0.45, Vector3(0, 0.225, 0), iron, 8) # plinth
	mb.add_cylinder(0.1, 0.1, 0.08, Vector3(0, 0.49, 0), iron, 12)
	mb.add_cylinder(0.075, 0.055, 2.45, Vector3(0, 1.75, 0), iron, 12) # shaft
	mb.add_cylinder(0.08, 0.08, 0.06, Vector3(0, 2.2, 0), iron, 12) # collar
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
	var mi := mb.build_into(self, "Post")
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC

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
	lit = false


func _apply_lit() -> void:
	if _light == null:
		return
	_light.visible = lit
	_glass_instance.material_override = MaterialLibrary.get_material("lamp_glass") if lit else MaterialLibrary.get_material("glass")
