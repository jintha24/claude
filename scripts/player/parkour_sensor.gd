class_name ParkourSensor
extends RefCounted
## Geometry queries for climbing and parkour: finds walls, ledges, vaultable obstacles,
## drainpipes and free space for Harry's body. Pure queries: it never moves anything.
##
## Terminology:
##   edge   - the point on the lip of a ledge where Harry's hands go (world space)
##   normal - horizontal direction pointing OUT of the wall, towards Harry
##   top    - world-space height of the ledge's upper surface

const MASK_SOLID := 1 | (1 << 3) | (1 << 6) | (1 << 7) # world, props, glass, doors
const MASK_CLIMBABLE := 1 << 4

## Height of Harry's hands above his feet while hanging (arms slightly bent), for a 1.88 m man.
const HANG_HAND_HEIGHT := 2.05
## Distance from the wall face to the centre of Harry's capsule while hanging or climbing.
const HANG_WALL_OFFSET := 0.36

var _body: CharacterBody3D
var _exclude: Array[RID] = []
var _stand_shape: CapsuleShape3D
var _crouch_shape: CapsuleShape3D
var _hang_shape: CapsuleShape3D


func _init(body: CharacterBody3D, radius: float, stand_height: float, crouch_height: float) -> void:
	_body = body
	_exclude = [body.get_rid()]
	_stand_shape = CapsuleShape3D.new()
	_stand_shape.radius = radius - 0.02
	_stand_shape.height = stand_height - 0.04
	_crouch_shape = CapsuleShape3D.new()
	_crouch_shape.radius = radius - 0.02
	_crouch_shape.height = crouch_height - 0.04
	_hang_shape = CapsuleShape3D.new()
	_hang_shape.radius = radius - 0.06
	_hang_shape.height = stand_height - 0.3


func ray(from: Vector3, to: Vector3, mask: int = MASK_SOLID) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, _exclude)
	q.hit_from_inside = false
	return _body.get_world_3d().direct_space_state.intersect_ray(q)


## True if a capsule with its FEET at `feet` would not overlap anything solid.
func body_fits(feet: Vector3, crouched: bool = false) -> bool:
	var shape := _crouch_shape if crouched else _stand_shape
	# Lifted 10 cm so a capsule standing on a 32-degree slate roof isn't counted as overlapping it.
	return _shape_free(shape, feet + Vector3.UP * (shape.height * 0.5 + 0.1))


## Space check for a hanging body (slimmer, legs may brush the wall).
func hang_fits(feet: Vector3) -> bool:
	return _shape_free(_hang_shape, feet + Vector3.UP * (_hang_shape.height * 0.5 + 0.2))


func _shape_free(shape: Shape3D, center: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = MASK_SOLID
	q.exclude = _exclude
	return _body.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Height of the walkable floor below `pos` (searching `depth` metres down), or NAN.
func floor_height(pos: Vector3, depth: float = 3.0) -> float:
	var hit := ray(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * depth)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.6:
		return NAN
	return (hit["position"] as Vector3).y


## Finds a wall in front of `origin` along horizontal `dir`. Returns {point, normal} or {}.
func find_wall(origin: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var hit := ray(origin, origin + dir * reach)
	if hit.is_empty():
		return {}
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.35:
		return {}
	n.y = 0.0
	return {"point": hit["position"], "normal": n.normalized()}


## Searches for a grabbable ledge in front of Harry whose top lies between min_top and
## max_top (world heights). `feet` is Harry's feet position, `dir` his horizontal facing.
## Returns {edge, normal, top, can_stand_on_top, stand_point, crouch_only} or {}.
func find_ledge(feet: Vector3, dir: Vector3, min_top: float, max_top: float, reach: float = 0.85) -> Dictionary:
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return {}
	dir = dir.normalized()
	# Probe for a wall at several heights (a ledge may overhang a recessed wall or glass).
	var wall := {}
	for h: float in [1.0, 1.5, 0.5, 2.0]:
		var y := feet.y + h
		if y > max_top + 0.3:
			continue
		wall = find_wall(Vector3(feet.x, y, feet.z), dir, reach + 0.3)
		if not wall.is_empty():
			break
	if wall.is_empty():
		return {}
	var n: Vector3 = wall["normal"]
	var p: Vector3 = wall["point"]
	# Look down onto the ledge from above: first just outside the wall face (sills,
	# cornices, string courses), then just inside it (tops of walls, crates, roof eaves).
	var best := {}
	for inset: float in [-0.07, 0.14, 0.3]:
		var col := p - n * inset
		var hit := ray(Vector3(col.x, max_top + 0.35, col.z), Vector3(col.x, min_top - 0.05, col.z))
		if hit.is_empty():
			continue
		var top_n: Vector3 = hit["normal"]
		var top: float = (hit["position"] as Vector3).y
		if top_n.y < 0.75 or top < min_top or top > max_top:
			continue
		# The lip: shoot back towards the wall just under the ledge top to find its face.
		var lip := ray(Vector3(col.x, top - 0.04, col.z) + n * 0.8, Vector3(col.x, top - 0.04, col.z) - n * 0.2)
		if lip.is_empty():
			continue
		var lip_n: Vector3 = lip["normal"]
		lip_n.y = 0.0
		if lip_n.length() < 0.5 or lip_n.normalized().dot(n) < 0.7:
			continue
		lip_n = lip_n.normalized()
		var edge := Vector3((lip["position"] as Vector3).x, top, (lip["position"] as Vector3).z)
		# Room for the hands: nothing directly above the lip.
		if not ray(edge + Vector3.UP * 0.05 + lip_n * 0.05, edge + Vector3.UP * 0.45 + lip_n * 0.05).is_empty():
			continue
		# Prefer the outermost lip (the one Harry's hands reach first), then the higher one.
		if not best.is_empty():
			var out_new := edge.dot(n)
			var out_best := (best["edge"] as Vector3).dot(n)
			if out_new < out_best - 0.05 or (absf(out_new - out_best) <= 0.05 and top <= float(best["top"])):
				continue
		best = {"edge": edge, "normal": lip_n, "top": top}
	if best.is_empty():
		return {}
	var e: Vector3 = best["edge"]
	var en: Vector3 = best["normal"]
	var stand := e - en * 0.45
	stand.y = float(best["top"])
	var fh := floor_height(stand + Vector3.UP * 0.6, 0.9)
	if not is_nan(fh):
		stand.y = fh
	var can_stand := not is_nan(fh) and body_fits(stand)
	var crouch_only := not can_stand and not is_nan(fh) and body_fits(stand, true)
	best["can_stand_on_top"] = can_stand or crouch_only
	best["crouch_only"] = crouch_only
	best["stand_point"] = stand
	return best


## Feet position for hanging from a ledge.
static func hang_feet(ledge: Dictionary) -> Vector3:
	var e: Vector3 = ledge["edge"]
	var n: Vector3 = ledge["normal"]
	return Vector3(e.x, float(ledge["top"]) - HANG_HAND_HEIGHT, e.z) + n * HANG_WALL_OFFSET


## Re-finds the same ledge at a new edge position (used while shimmying).
func follow_ledge(edge: Vector3, normal: Vector3, top: float) -> Dictionary:
	var feet := Vector3(edge.x, top - HANG_HAND_HEIGHT, edge.z) + normal * 0.9
	var found := find_ledge(feet, -normal, top - 0.2, top + 0.2, 1.2)
	if found.is_empty():
		return {}
	if (found["normal"] as Vector3).dot(normal) < 0.85:
		return {} # an outside corner: stop rather than wrap around
	return found


## Low obstacle in front (for vaulting/mantling): returns {top, point, normal, depth, landing} or {}.
## `landing` is the feet position on the far side (only when the obstacle is thin enough to vault).
func find_obstacle(feet: Vector3, dir: Vector3, reach: float) -> Dictionary:
	dir.y = 0.0
	dir = dir.normalized()
	var wall := {}
	for h: float in [0.35, 0.7]:
		wall = find_wall(feet + Vector3.UP * h, dir, reach)
		if not wall.is_empty():
			break
	if wall.is_empty():
		return {}
	var n: Vector3 = wall["normal"]
	var p: Vector3 = wall["point"]
	var col := p - n * 0.1
	var hit := ray(Vector3(col.x, feet.y + 1.6, col.z), Vector3(col.x, feet.y + 0.2, col.z))
	if hit.is_empty():
		return {}
	var top: float = (hit["position"] as Vector3).y
	# How deep is it? Step along the far direction until the top surface ends.
	var depth := 0.1
	while depth < 1.6:
		var q := p - n * (depth + 0.1)
		var h2 := ray(Vector3(q.x, top + 0.3, q.z), Vector3(q.x, top - 0.25, q.z))
		if h2.is_empty():
			break
		depth += 0.1
	var result := {"top": top, "point": p, "normal": n, "depth": depth}
	if depth < 1.2:
		var land := p - n * (depth + 0.55)
		var fh := floor_height(Vector3(land.x, top + 0.2, land.z), top - feet.y + 2.5)
		if not is_nan(fh) and fh < top - 0.2:
			land.y = fh
			if body_fits(land):
				result["landing"] = land
	return result


## Nearest drainpipe within `reach` of `center`. Returns {axis_bottom, axis_top, normal} or {}.
func find_pipe(center: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = reach
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = MASK_CLIMBABLE
	q.collide_with_areas = false
	var hits := _body.get_world_3d().direct_space_state.intersect_shape(q, 4)
	for h in hits:
		var body := h["collider"] as StaticBody3D
		if body == null or not body.is_in_group("climbable_pipe"):
			continue
		var cs := body.get_child(0) as CollisionShape3D
		var cyl := cs.shape as CylinderShape3D
		if cyl == null:
			continue
		var c := cs.global_position
		var to_harry := Vector3(center.x - c.x, 0.0, center.z - c.z)
		if to_harry.length() < 0.05:
			continue
		# Harry must be roughly facing the pipe.
		if dir != Vector3.ZERO and (-to_harry.normalized()).dot(dir.normalized()) < 0.3:
			continue
		# Climb on the side of the pipe facing away from the wall behind it.
		var n := to_harry.normalized()
		var wall := find_wall(Vector3(c.x, center.y, c.z) + n * 0.1, -n, 0.4)
		if not wall.is_empty():
			n = wall["normal"]
		return {
			"axis_bottom": Vector3(c.x, c.y - cyl.height * 0.5, c.z),
			"axis_top": Vector3(c.x, c.y + cyl.height * 0.5, c.z),
			"normal": n,
		}
	return {}
