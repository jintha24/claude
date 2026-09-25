extends "res://tests/test_base.gd"
## The hills grown to 4 km x 4 km: villages on the roads and lanes with their people,
## farms with hedgerows and livestock, the London road out to the east edge.

var streamer: WorldStreamer


func make_scene() -> Node:
	return load("res://scenes/wilderness/hills.tscn").instantiate()


func run_tests() -> void:
	streamer = main.get_node("Streamer")
	var gen := streamer.generator
	var km2 := pow(TerrainGenerator.HALF_SIZE * 2.0 / 1000.0, 2.0)
	check("the hills cover at least 10 square km", km2 >= 10.0, "%.1f km2" % km2)
	var villages := get_nodes_in_group_safe("villages")
	check("four villages", villages.size() == 4, str(villages.size()))
	for v: Node in villages:
		var vil := v as Village
		var houses := vil.spots.filter(func(s: Array) -> bool: return s[1] == "door").size()
		check("%s has cottages, a church and an inn" % vil.village_name, houses >= 6 and vil.spots.any(func(s: Array) -> bool: return s[1] == "church") and vil.spots.any(func(s: Array) -> bool: return s[1] == "inn"), "%d cottages" % houses)
	var folk := get_nodes_in_group_safe("villagers")
	check("villagers live in them", folk.size() >= 28, str(folk.size()))
	# Fields round the villages.
	var kinds := {}
	var v0: Array = TerrainGenerator.VILLAGES[0]
	for k in 200:
		var a := TAU * k / 200.0
		var p: Vector2 = v0[1] + Vector2(cos(a), sin(a)) * (float(v0[2]) + 150.0 + (k % 5) * 40.0)
		kinds[int(gen.farm_at(p.x, p.y).x)] = true
	check("pasture, wheat, ploughland and hay meadows round a village", kinds.size() >= 4, str(kinds.keys()))
	check("the farmland has hedgerows", gen.hedge_points(Rect2(v0[1].x + 100.0, v0[1].y - 200.0, 300.0, 300.0)).size() > 20)
	# Go and stand in a village by day.
	var vil0 := villages[0] as Village
	var at := Vector3(vil0.centre.x, 0.0, vil0.centre.y)
	var road_p := at
	await tp(Vector3(at.x, gen.height(at.x, at.z) + 1.0, at.z))
	streamer.prime(harry.global_position)
	await wait(90)
	check("he can walk into a village", harry.is_on_floor(), describe())
	var near := folk.filter(func(f: Node) -> bool: return is_instance_valid(f) and (f as Node3D).global_position.distance_to(road_p) < 140.0 and (f as VillageFolk).visible)
	var starts := {}
	for f in near:
		starts[f] = (f as Node3D).global_position
	await wait(300)
	var moved := near.filter(func(f: Node) -> bool: return (f as Node3D).global_position.distance_to(starts[f]) > 1.0).size()
	check("villagers are out and about", moved >= 2, "%d of %d" % [moved, near.size()])
	# Livestock appear in a nearby pasture.
	var pasture := Vector2.ZERO
	for k in 400:
		var a := TAU * k / 400.0
		var p: Vector2 = v0[1] + Vector2(cos(a), sin(a)) * (float(v0[2]) + 60.0 + (k % 4) * 30.0)
		if gen.farm_at(p.x, p.y).x == TerrainGenerator.Field.PASTURE:
			pasture = p
			break
	check("a pasture near the village", pasture != Vector2.ZERO)
	await tp(Vector3(pasture.x, gen.height(pasture.x, pasture.y) + 1.0, pasture.y))
	streamer.prime(harry.global_position)
	await wait_until(func() -> bool: return not get_nodes_in_group_safe("livestock").is_empty(), 300)
	check("sheep or cattle graze the pastures", get_nodes_in_group_safe("livestock").size() >= 3, str(get_nodes_in_group_safe("livestock").size()))
	var post := main.get_node("ToLondon") as Node3D
	check("the London road runs to the east edge", post.global_position.x > TerrainGenerator.HALF_SIZE - 120.0 and gen.road_info(post.global_position.x, post.global_position.z).x < 5.0)

	await _test_country_life()


func _test_country_life() -> void:
	var people := main.get_node("HillsPeople") as HillsPeople
	var gen := streamer.generator
	var road: Vector2 = TerrainGenerator.ROAD[4]
	await tp(Vector3(road.x, gen.height(road.x, road.y) + 1.0, road.y))
	streamer.prime(harry.global_position)
	await wait_until(func() -> bool: return people.walker_count() >= 4, 900)
	check("travellers on the London road", people.walker_count() >= 4, str(people.walker_count()))
	var traffic := main.get_node("RoadTraffic") as RoadTraffic
	await wait_until(func() -> bool: return traffic.vehicle_count() >= 2, 900)
	check("carts and wagons on the road", traffic.vehicle_count() >= 2, str(traffic.vehicle_count()))
	var birds := main.get_node("Birds") as BirdLife
	await wait_until(func() -> bool: return birds.flock_count() >= 2, 600)
	check("rooks over the hills", birds.flock_count() >= 2)
	var enc := main.get_node("Encounters") as Encounters
	if enc.active != "":
		enc._end("test") # one may have begun by chance during the waits above
	var ok := enc.start("highwayman")
	check("a highwayman holds up a traveller on the road", ok and enc.active == "highwayman")
	if not ok:
		return
	var robber := enc._state["robber"] as StoryNPC
	await tp(robber.global_position + Vector3(6.0, 1.0, 0.0))
	await wait(30)
	check("he bolts when the Fox comes", enc._state["phase"] == "fled", str(enc._state["phase"]))
	var victim := enc._state["victim"] as StoryNPC
	var acts := victim.get_children().filter(func(n: Node) -> bool: return n is EncounterAction)
	var money := harry.inventory.money
	if not acts.is_empty():
		(acts[0] as EncounterAction).interact(harry)
	check("the traveller rewards him", harry.inventory.money == money + 24)

	# Foxes to hunt as well as deer and rabbits.
	var animals := main.get_node("Animals")
	var fox: WildAnimal = animals.call("spawn_fox", harry.global_position + Vector3(25, 0, 0))
	check("red foxes roam the hills", fox != null and fox.species == WildAnimal.Species.FOX)
	var c := Carcass.new()
	c.species = WildAnimal.Species.FOX
	check("a fox gives a pelt worth selling", c.items().size() == 1 and c.items()[0]["name"] == "Fox pelt" and c.get_prompt(harry) == "Skin the fox")
	c.free()
