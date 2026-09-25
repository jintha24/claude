extends "res://tests/test_base.gd"
## Phase 10 performance: occlusion culling (every building is an occluder), draw
## distances on small props and people, NPC level of detail, the F3 overlay's numbers,
## and a frame-time budget for the whole of London (street, market, Ashcombe House and
## St Giles, with the crowds, constables and sound) running headless.

func _init() -> void:
	keep_guards = true # the constables are part of the load


func run_tests() -> void:
	check("occlusion culling is on", bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)))
	var occluders := main.find_children("*", "OccluderInstance3D", true, false)
	var facades := main.find_children("*", "BuildingFacade", true, false)
	check("every building is an occluder", occluders.size() >= facades.size() and facades.size() > 60, "%d occluders, %d buildings" % [occluders.size(), facades.size()])
	var crates := main.find_children("*", "RigidBody3D", true, false)
	var ranged := crates.filter(func(n: Node) -> bool:
		var meshes := n.find_children("*", "GeometryInstance3D", true, false)
		return not meshes.is_empty() and (meshes[0] as GeometryInstance3D).visibility_range_end > 0.0)
	check("crates and barrels fade out in the distance", not crates.is_empty() and ranged.size() == crates.size(), "%d of %d" % [ranged.size(), crates.size()])
	await wait(30)
	var bodies := main.find_children("*", "NPCBody", true, false)
	var body_ranged := bodies.filter(func(b: Node) -> bool: return b.find_children("*", "MeshInstance3D", true, false).all(func(m: Node) -> bool: return (m as MeshInstance3D).visibility_range_end > 0.0))
	check("people aren't drawn beyond 150 m", not bodies.is_empty() and body_ranged.size() == bodies.size(), "%d of %d" % [body_ranged.size(), bodies.size()])
	# NPC level of detail: people far from the camera stop animating.
	await wait(90)
	var civilians := get_nodes_in_group_safe("civilians")
	var lods := civilians.map(func(c: Node) -> int: return (c as NPCCharacter).lod_level)
	check("distant townsfolk drop to a lower level of detail", lods.has(1) or lods.has(2), str(lods.slice(0, 12)))
	# The F3 overlay.
	var hud := main.get_node("GameHUD")
	_press_event("debug_overlay")
	await wait(5)
	var label := hud.get("_debug_label") as Label
	check("F3 shows frame time, draw calls and NPC count", label.visible and label.text.contains("Draw calls") and label.text.contains("NPCs"), label.text.get_slice("\n", 0))
	_press_event("debug_overlay")
	# Frame budget: average CPU time per frame over ~10 seconds of the whole city, once the
	# game has settled after loading (physics catches up on the loading time for a moment).
	await wait(240)
	var total := 0.0
	var worst := 0.0
	var n := 0
	for i in 600:
		await wait(1)
		var t := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) + Performance.get_monitor(Performance.TIME_PROCESS)
		total += t
		worst = maxf(worst, t)
		n += 1
	var avg_ms := total / n * 1000.0
	print("  London frame time: average %.2f ms, worst %.2f ms (%d civilians, %d constables)" % [avg_ms, worst * 1000.0, get_nodes_in_group_safe("civilians").size(), get_nodes_in_group_safe("guards").size()])
	check("London fits a 60 fps frame budget (CPU, headless)", avg_ms < 16.6, "%.2f ms" % avg_ms)


## Sends a key press through the input system as an event (the HUD listens for events).
func _press_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
