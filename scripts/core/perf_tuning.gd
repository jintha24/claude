class_name PerfTuning
extends RefCounted
## Performance helpers (Phase 10):
##  * visibility ranges: small things (crates, barrels, carts, people) stop being drawn
##    beyond a sensible distance, fading out rather than popping;
##  * occluders: solid buildings hide what's behind them from the renderer (occlusion
##    culling is switched on in the project settings);
##  * the numbers shown in the F3 overlay.

## Draw distances (m) by kind of thing.
const RANGE_SMALL_PROP := 70.0   # crates, barrels, bollards, hay
const RANGE_PROP := 120.0        # carts, stalls, troughs
const RANGE_PERSON := 150.0      # townsfolk and constables
const RANGE_NEAR := 25.0         # people: all their pieces nearer, the one-piece far body beyond
const RANGE_SMALL_DETAIL := 45.0 # collars, cravats, belts, hat bands on people
const RANGE_FACE := 20.0         # eyes, lashes and teeth


## Stops every mesh under `node` being drawn beyond `end` metres (fading over the last 10%).
static func set_visibility_range(node: Node, end: float) -> void:
	var list: Array[Node] = [node]
	list.append_array(node.find_children("*", "GeometryInstance3D", true, false))
	for n in list:
		var g := n as GeometryInstance3D
		if g == null:
			continue
		g.visibility_range_end = end
		g.visibility_range_end_margin = end * 0.1
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Adds a box occluder filling most of a solid block (local `center`, `size`), a little
## smaller than the walls so it never hides anything that should show round the edges.
static func add_box_occluder(parent: Node3D, size: Vector3, center: Vector3) -> OccluderInstance3D:
	var occ := OccluderInstance3D.new()
	occ.name = "Occluder"
	var box := BoxOccluder3D.new()
	box.size = Vector3(maxf(size.x - 0.4, 0.1), maxf(size.y - 0.4, 0.1), maxf(size.z - 0.4, 0.1))
	occ.occluder = box
	occ.position = center
	parent.add_child(occ)
	return occ


## One line of numbers for the F3 overlay.
static func stats_text() -> String:
	return "Frame %.1f ms (physics %.1f)  Draw calls %d  Objects %d  Primitives %dk\nNodes %d  NPCs %d  Video mem %d MB  Static mem %d MB" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		(Engine.get_main_loop() as SceneTree).get_nodes_in_group("civilians").size() + (Engine.get_main_loop() as SceneTree).get_nodes_in_group("guards").size(),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
	]
