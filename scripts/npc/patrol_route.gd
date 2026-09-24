@tool
class_name PatrolRoute
extends Node3D
## A guard's beat: an ordered list of points. Add Marker3D children in the editor (their
## order is the walking order); a Marker3D's Y rotation is the way the guard faces while
## waiting there, and its metadata "wait_time" (seconds) how long he stands there.
## Or build routes from code with add_point().

@export var loop: bool = true
@export var default_wait: float = 0.0

var points: Array[Dictionary] = []


func _ready() -> void:
	if points.is_empty():
		for child in get_children():
			if child is Marker3D:
				var m := child as Marker3D
				points.append({"position": m.global_position, "wait": float(m.get_meta("wait_time", default_wait)), "yaw": m.global_rotation.y})


func add_point(pos: Vector3, wait: float = 0.0, yaw: float = NAN) -> void:
	points.append({"position": pos, "wait": wait, "yaw": yaw})


func size() -> int:
	return points.size()


func get_point(i: int) -> Dictionary:
	return points[i]


## Index after `i`, looping or ping-ponging (direction stored in `dir`, +1 / -1).
func next_index(i: int, dir: int) -> Vector2i:
	if points.size() <= 1:
		return Vector2i(0, dir)
	var n := i + dir
	if n >= points.size() or n < 0:
		if loop:
			n = posmod(n, points.size())
		else:
			dir = -dir
			n = i + dir
	return Vector2i(n, dir)


func nearest_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d := pos.distance_squared_to(points[i]["position"])
		if d < best_d:
			best_d = d
			best = i
	return best
