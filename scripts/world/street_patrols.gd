class_name StreetPatrols
extends Node3D
## The Metropolitan Police presence on the test street (1866):
##   * Constable Bates walks the beat: down the west pavement, across, up the east side.
##   * Constable Wren stands guard outside the London & County Bank.
##   * Constable Pike walks the carriageway and looks into the private yard (the alley).
## Routes are PatrolRoute nodes, so they can also be moved or edited in the editor.

const PAVE := 0.15


func _ready() -> void:
	var bates_route := _route("BatesBeat", [
		[Vector3(-4.6, PAVE, 40.0), 4.0, -PI * 0.5], [Vector3(-4.6, PAVE, 0.0), 0.0, NAN],
		[Vector3(-4.6, PAVE, -40.0), 4.0, -PI * 0.5], [Vector3(4.6, PAVE, -40.0), 4.0, PI * 0.5],
		[Vector3(4.6, PAVE, 0.0), 0.0, NAN], [Vector3(4.6, PAVE, 40.0), 4.0, PI * 0.5],
	], true)
	_guard("ConstableBates", "Constable Bates", Vector3(-4.6, PAVE, 30.0), 0.0, bates_route)

	_guard("ConstableWren", "Constable Wren", Vector3(1.8, PAVE, 43.4), 0.0, null)

	var pike_route := _route("PikeBeat", [
		[Vector3(0.0, 0.0, 30.0), 3.0, 0.0], [Vector3(1.0, 0.0, 6.0), 0.0, NAN],
		[Vector3(7.4, PAVE, 5.2), 5.0, -PI * 0.5], [Vector3(0.0, 0.0, -30.0), 3.0, PI],
	], false)
	_guard("ConstablePike", "Constable Pike", Vector3(0.0, 0.0, -25.0), PI, pike_route)


func _route(route_name: String, pts: Array, loop: bool) -> PatrolRoute:
	var r := PatrolRoute.new()
	r.name = route_name
	r.loop = loop
	for p in pts:
		r.add_point(p[0], p[1], p[2])
	add_child(r)
	return r


func _guard(node_name: String, display: String, pos: Vector3, yaw: float, route: PatrolRoute) -> Guard:
	var g := Guard.new()
	g.name = node_name
	g.display_name = display
	g.position = pos
	g.rotation.y = yaw
	add_child(g)
	if route:
		g.set_route(route)
	return g
