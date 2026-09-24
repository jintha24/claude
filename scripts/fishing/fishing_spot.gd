class_name FishingSpot
extends Interactable
## A place to fish from (the end of the jetty, a spot on the lake shore). `cast_dir` is the
## direction out over the water; the float lands 6-18 m out depending on the cast.

signal caught(item: Dictionary)

@export var cast_dir: Vector3 = Vector3.FORWARD
@export var spot_name: String = "Fish here"

var float_mesh: MeshInstance3D
var _float_t := 0.0


func _ready() -> void:
	interact_range = 2.4
	add_to_group("fishing_spots")
	float_mesh = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.14
	float_mesh.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.15, 0.1)
	float_mesh.material_override = m
	float_mesh.visible = false
	float_mesh.top_level = true
	add_child(float_mesh)


func get_prompt(_harry: Harry) -> String:
	return spot_name


func interact(harry: Harry) -> void:
	harry.interaction.begin_fishing(self)


## Where the float sits for a cast of `power` (0..1).
func float_point(power: float) -> Vector3:
	var d := cast_dir
	d.y = 0.0
	d = d.normalized()
	return Vector3(global_position.x, TerrainGenerator.WATER_Y, global_position.z) + d * lerpf(6.0, 18.0, power)


func show_float(session: FishingSession, delta: float) -> void:
	_float_t += delta
	var on := session != null and session.phase in [FishingSession.Phase.WAIT, FishingSession.Phase.BITE, FishingSession.Phase.FIGHT]
	float_mesh.visible = on
	if not on:
		return
	var p := float_point(session.power)
	var bob := sin(_float_t * 2.0) * 0.015
	if session.phase == FishingSession.Phase.BITE:
		bob = -0.08 + sin(_float_t * 18.0) * 0.03
	elif session.phase == FishingSession.Phase.FIGHT:
		bob = -0.12
		p = p.lerp(Vector3(global_position.x, TerrainGenerator.WATER_Y, global_position.z), 1.0 - session.fish_stamina)
	float_mesh.global_position = p + Vector3.UP * (0.03 + bob)
