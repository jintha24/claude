extends "res://tests/test_base.gd"
## Greater London: the whole city streamed round the old streets (CityPlan, CityStreamer,
## CityBuilder, CityRiver, CityLandmarks, CityLife).

var city: CityStreamer
var life: CityLife


func run_tests() -> void:
	city = main.get_node("City")
	life = main.get_node("CityLife")
	_test_plan()
	await _test_way_out()
	await _test_streets()
	await _test_people()
	await _test_river()
	await _test_far_side()


func _test_plan() -> void:
	var plan := city.plan
	var km2 := pow(CityPlan.HALF * 2.0 / 1000.0, 2.0)
	check("the city covers at least 10 square km", km2 >= 10.0, "%.1f km2" % km2)
	check("over a thousand blocks of streets", plan.blocks.size() > 1000, str(plan.blocks.size()))
	var districts := {}
	var kinds := {}
	for b: Dictionary in plan.blocks:
		districts[b["district"]] = true
		kinds[b["kind"]] = kinds.get(b["kind"], 0) + 1
	check("West End, City, East End, north and south of the river", districts.size() == 5, str(districts.keys()))
	check("garden squares, churches, parks and warehouses", kinds.get(CityPlan.Kind.SQUARE, 0) > 20 and kinds.get(CityPlan.Kind.CHURCH, 0) > 5 and kinds.get(CityPlan.Kind.PARK, 0) > 5 and kinds.get(CityPlan.Kind.WAREHOUSE, 0) > 10, str(kinds))
	check("St Paul's and Westminster have their grounds", kinds.get(CityPlan.Kind.LANDMARK, 0) == 2)
	check("four bridges over the Thames", plan.bridges.size() == 4, str(plan.bridges))
	var lots := 0
	for b: Dictionary in plan.blocks.slice(0, 50):
		lots += plan.lots(b).size()
	check("blocks are lined with houses and shops", lots > 500, str(lots))
	check("the same city every time", CityPlan.new().blocks.size() == plan.blocks.size())
	var distant := city.get_node("DistantCity") as MultiMeshInstance3D
	check("the far city is drawn as one multimesh of terraces", distant != null and distant.multimesh.instance_count > 3000, str(distant.multimesh.instance_count if distant else 0))
	check("St Paul's stands on its hill", city.get_node_or_null("Landmarks/StPauls") != null)


## Out of the old streets through the Ashcombe mews and onto the ring road.
func _test_way_out() -> void:
	var space := (main as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(40.5, 1.2, -100.0), Vector3(40.5, 1.2, -130.0), 1)
	check("the mews is open at its north end", space.intersect_ray(q).is_empty())
	await tp(Vector3(40.5, 0.4, -114.2))
	await wait_until(func() -> bool: return city.chunk_lod(city.coord_of(harry.global_position)) == 0, 900)
	await wait(30)
	check("the streets round Harry are built in full", city.chunk_lod(city.coord_of(harry.global_position)) == 0)
	check("he stands on the ring road's pavement", harry.is_on_floor() and absf(harry.global_position.y - CityPlan.PAVE_TOP) < 0.2, describe())


func _test_streets() -> void:
	var plan := city.plan
	# Find a terrace near Harry and check its buildings are solid, with roofs to walk on.
	var c := city.coord_of(harry.global_position)
	var lot: Dictionary = {}
	for i in plan.blocks_owned(c):
		var b: Dictionary = plan.blocks[i]
		if b["kind"] == CityPlan.Kind.TERRACE or b["kind"] == CityPlan.Kind.FILL:
			var ls := plan.lots(b)
			if not ls.is_empty():
				lot = ls[0]
				break
	check("a terrace in the chunk", not lot.is_empty())
	if lot.is_empty():
		return
	var xf: Transform3D = lot["xf"]
	var mid := xf * Vector3(float(lot["w"]) * 0.5, 0.0, -float(lot["d"]) * 0.5)
	var space := (main as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(mid + Vector3(0, 60, 0), mid - Vector3(0, 5, 0), 1)
	var hit := space.intersect_ray(q)
	check("houses have solid roofs", not hit.is_empty() and float(hit["position"].y) > 5.0, str(hit.get("position", "none")))
	check("the roofs are slate underfoot", not hit.is_empty() and (hit["collider"] as Node).get_meta("surface", "") == "slate")
	var pipes := 0
	var lamps := 0
	var signs := 0
	var occluders := 0
	for chunk: Node in city.get_children():
		if not String(chunk.name).begins_with("Chunk_") or not String(chunk.name).contains("_L0"):
			continue
		for n in chunk.get_children():
			pipes += 1 if n.is_in_group("climbable_pipe") else 0
			lamps += 1 if n is GasLamp else 0
			signs += 1 if n is Label3D else 0
			occluders += 1 if n is OccluderInstance3D else 0
	check("drainpipes to climb", pipes > 20, str(pipes))
	check("gas lamps along the pavements", lamps > 20, str(lamps))
	check("shop signs over the shopfronts", signs > 10, str(signs))
	check("the city can hide what's behind its buildings", occluders > 0)
	# A walk along the pavements: the navigation mesh joins up.
	var map := (main as Node3D).get_world_3d().navigation_map
	var a := NavigationServer3D.map_get_closest_point(map, Vector3(60.0, 0.1, -114.2))
	var b := NavigationServer3D.map_get_closest_point(map, Vector3(-40.0, 0.1, -114.2))
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	check("people can walk the pavements from chunk to chunk", path.size() >= 2 and path[path.size() - 1].distance_to(b) < 1.0 and a.distance_to(Vector3(60.0, 0.1, -114.2)) < 1.0, "%d points, a=%s" % [path.size(), a])


func _test_people() -> void:
	await wait_until(func() -> bool: return life.people_count() >= 12, 900)
	check("passers-by fill the streets", life.people_count() >= 12, str(life.people_count()))
	var folk := get_nodes_in_group_safe("civilians").filter(func(n: Node) -> bool: return n.name.begins_with("CityFolk"))
	check("they can have their pockets picked", not folk.is_empty() and (folk[0] as Civilian).pockets.size() > 0)
	await wait_until(func() -> bool: return life.constable_count() >= 1, 600)
	check("constables walk their beats", life.constable_count() >= 1)
	var walking := folk.filter(func(n: Node) -> bool: return is_instance_valid(n) and (n as Civilian).state == Civilian.State.TRAVEL)
	var moved := 0
	var starts := {}
	for n in walking:
		starts[n] = (n as Node3D).global_position
	await wait(120)
	for n in walking:
		if is_instance_valid(n) and (n as Node3D).global_position.distance_to(starts[n]) > 1.5:
			moved += 1
	check("they walk somewhere", moved >= 3, "%d of %d" % [moved, walking.size()])
	var old_hour := GameClock.minutes
	GameClock.minutes = 3.0 * 60.0
	var night := life._wanted_people(harry.global_position)
	GameClock.minutes = old_hour
	check("the streets empty at night", night < life._wanted_people(harry.global_position) / 3, str(night))


func _test_river() -> void:
	var plan := city.plan
	var bx := plan.bridges[1]
	await tp(Vector3(bx - 6.0, 0.5, CityPlan.RIVER_Z0 - 20.0))
	city.build_all_now(harry.global_position)
	await wait(30)
	var space := (main as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(bx, 20.0, (CityPlan.RIVER_Z0 + CityPlan.RIVER_Z1) * 0.5), Vector3(bx, -20.0, (CityPlan.RIVER_Z0 + CityPlan.RIVER_Z1) * 0.5), 1)
	var hit := space.intersect_ray(q)
	check("a bridge carries the road over the Thames", not hit.is_empty() and absf(float(hit["position"].y)) < 0.3, str(hit.get("position", "none")))
	var water := WaterVolume.depth_at(self, Vector3(bx + 40.0, CityPlan.BED_Y + 0.1, CityPlan.RIVER_Z0 + 30.0))
	check("the river can be waded at low tide", water > 0.5 and water < 1.6, "%.2f" % water)
	check("barges on the river", city.get_node("Thames").find_children("Boat*", "", false, false).size() >= 10)


func _test_far_side() -> void:
	# A long way from the old streets: Southwark, then the edge of the city.
	var far := Vector3(700.0, 0.5, 1150.0)
	var plan := city.plan
	for i in plan.blocks_owned(plan.coord_of(far)):
		var r: Rect2 = plan.blocks[i]["rect"]
		far = Vector3(r.position.x + 1.0, 0.6, r.position.y + 1.0) # on a pavement corner
		break
	await tp(far)
	city.build_all_now(harry.global_position)
	await wait(40)
	check("across the river the streets go on", harry.is_on_floor() and harry.global_position.y > 0.0 and harry.global_position.y < 0.5, describe())
	check("south of the river is Southwark and Lambeth", plan.district(far.x, far.z) == "south")
	var space := (main as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(CityPlan.HALF - 5.0, 1.0, 0.0), Vector3(CityPlan.HALF + 5.0, 1.0, 0.0), 1)
	check("the city has an edge you can't walk off", not space.intersect_ray(q).is_empty())
