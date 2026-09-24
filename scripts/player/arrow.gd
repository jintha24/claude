class_name Arrow
extends Node3D
## A longbow arrow in flight. Moved by hand each physics step with gravity and a ray
## between the old and new position, so even a 55 m/s arrow never tunnels through thin
## objects.
##
## Kinds (the Hill Fox never kills):
##   "blunt"   - a padded blunt head. Knocks out an unwary guard hit in the head, stuns
##               elsewhere, and smashes gas-lamp glass to put the light out.
##   "broadhead" - a steel hunting head, for game in the hills (Harry never looses one at a
##               person; see HarryCombat).
##   "whistle" - a bone whistle behind the head. Shrieks in flight and makes a loud noise
##               where it lands: a distraction.
## After landing, arrows lie where they fell and can be picked up again (E).

const MASK_HIT := 1 | (1 << 2) | (1 << 3) | (1 << 6) | (1 << 7) # world, NPCs, props, glass, doors
const GRAVITY := 9.81
const DRAG := 0.004

var kind: String = "blunt"
var velocity: Vector3 = Vector3.ZERO
var shooter: CollisionObject3D
var flying := true
var hit_node: Node = null

var _age := 0.0
var _whistle_timer := 0.0


static func create(arrow_kind: String) -> Arrow:
	var a := Arrow.new()
	a.kind = arrow_kind
	a.name = "Arrow"
	return a


func _ready() -> void:
	add_to_group("arrows")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.42, 0.28)
	wood.roughness = 0.7
	var feather := StandardMaterial3D.new()
	feather.albedo_color = Color(0.85, 0.82, 0.75)
	feather.roughness = 0.9
	var tip := StandardMaterial3D.new()
	tip.albedo_color = Color(0.25, 0.18, 0.12) if kind == "blunt" else (Color(0.55, 0.56, 0.58) if kind == "broadhead" else Color(0.9, 0.87, 0.78))
	tip.roughness = 0.8
	# Arrow points along -Z.
	_add_mesh(_cyl(0.004, 0.004, 0.76), Vector3(0, 0, 0), Vector3(90, 0, 0), wood)
	_add_mesh(_cyl(0.018, 0.012, 0.05) if kind == "blunt" else _cyl(0.011, 0.009, 0.07), Vector3(0, 0, -0.4), Vector3(90, 0, 0), tip)
	for i in 3:
		var fin := BoxMesh.new()
		fin.size = Vector3(0.001, 0.028, 0.11)
		var mi := _add_mesh(fin, Vector3(0, 0, 0.3), Vector3(0, 0, i * 120.0), feather)
		mi.position += mi.basis.y * 0.014


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 6
	m.rings = 1
	return m


func _add_mesh(mesh: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func launch(from: Vector3, initial_velocity: Vector3, by: CollisionObject3D) -> void:
	global_position = from
	velocity = initial_velocity
	shooter = by
	_orient()


func _physics_process(delta: float) -> void:
	_age += delta
	if not flying:
		if _age > 180.0:
			queue_free()
		return
	velocity.y -= GRAVITY * delta
	velocity -= velocity * DRAG * velocity.length() * delta
	var from := global_position
	var to := from + velocity * delta
	var exclude: Array[RID] = []
	if shooter:
		exclude.append(shooter.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK_HIT, exclude)
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_on_hit(hit)
		return
	global_position = to
	_orient()
	if kind == "whistle":
		_whistle_timer -= delta
		if _whistle_timer <= 0.0:
			_whistle_timer = 0.15
			Stealth.make_noise(global_position, 10.0, "whistle_flight", true, self)
	if _age > 8.0 or global_position.y < -50.0:
		queue_free()


func _orient() -> void:
	if velocity.length() > 0.01:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
		look_at(global_position + velocity, up)


func _on_hit(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var collider := hit["collider"] as Node
	global_position = point
	flying = false
	hit_node = collider
	var noise_radius := 22.0 if kind == "whistle" else 6.0
	var noise_kind := "whistle" if kind == "whistle" else "thud"

	var target := _find_arrow_target(collider)
	if target:
		target.call("on_arrow_hit", kind, point, velocity)
	elif collider is GasLamp:
		var lamp := collider as GasLamp
		if point.y > lamp.global_position.y + GasLamp.LANTERN_HEIGHT - 0.4 and lamp.lit:
			lamp.extinguish()
			noise_radius = maxf(noise_radius, 12.0)
			noise_kind = "glass"
	elif collider is RigidBody3D:
		(collider as RigidBody3D).apply_impulse(velocity * 0.06, point - (collider as RigidBody3D).global_position)
	Stealth.make_noise(point, noise_radius, noise_kind, true, self)
	_settle()


## The guard, dog or other creature (anything with on_arrow_hit) that owns `n`.
func _find_arrow_target(n: Node) -> Node:
	while n != null:
		if n.has_method("on_arrow_hit"):
			return n
		n = n.get_parent()
	return null


## Drop to the ground below and lie there as a pick-up.
func _settle() -> void:
	var exclude: Array[RID] = []
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 30.0, 1 | (1 << 3), exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = (hit["position"] as Vector3) + Vector3.UP * 0.02
	var yaw := atan2(-velocity.x, -velocity.z)
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO
	add_to_group("arrow_pickups")
	_age = 0.0
