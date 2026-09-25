extends "res://tests/test_base.gd"
## A living city: horse-drawn traffic, birds, dogs, crowds, and a sky with clouds and
## weather (CityTraffic, HorseVehicle, BirdLife, StreetDog, CityLife, london_sky.gdshader).

var city: CityStreamer
var traffic: CityTraffic
var birds: BirdLife
var life: CityLife


func run_tests() -> void:
	city = main.get_node("City")
	traffic = main.get_node("Traffic")
	birds = main.get_node("Birds")
	life = main.get_node("CityLife")
	await _test_sky()
	await tp(Vector3(330.0, 0.4, -150.0))
	city.build_all_now(harry.global_position)
	await wait(20)
	await _test_traffic()
	await _test_birds()
	await _test_crowds()


func _test_sky() -> void:
	var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := env.sky.sky_material as ShaderMaterial
	check("the sky is drawn by the London sky shader", sky != null and sky.shader.resource_path.ends_with("london_sky.gdshader"))
	if sky == null:
		return
	Weather.set_weather(Weather.Kind.CLEAR, true)
	await wait(12)
	var clear_cov: float = sky.get_shader_parameter("coverage")
	check("a clear day still has fair-weather clouds", clear_cov > 0.25 and clear_cov < 0.5, "%.2f" % clear_cov)
	Weather.set_weather(Weather.Kind.STORM, true)
	await wait(12)
	var storm_cov: float = sky.get_shader_parameter("coverage")
	var storm_dark: float = sky.get_shader_parameter("darkness")
	check("storm clouds cover the sky, dark", storm_cov > 0.9 and storm_dark > 0.5, "%.2f / %.2f" % [storm_cov, storm_dark])
	var off_a: Vector2 = sky.get_shader_parameter("wind_offset")
	await wait(60)
	var off_b: Vector2 = sky.get_shader_parameter("wind_offset")
	check("the clouds drift with the wind", off_a.distance_to(off_b) > 0.0001)
	Weather.set_weather(Weather.Kind.CLEAR, true)
	GameClock.minutes = 12.0 * 60.0
	await wait(12)
	check("by day the sky is lit and starless", float(sky.get_shader_parameter("day")) > 0.9 and float(sky.get_shader_parameter("stars")) < 0.05)


func _test_traffic() -> void:
	await wait_until(func() -> bool: return traffic.vehicle_count() >= 10, 900)
	check("horse-drawn traffic fills the main roads", traffic.vehicle_count() >= 10, str(traffic.vehicle_count()))
	var vs := get_nodes_in_group_safe("vehicles")
	var kinds := {}
	for v: Node in vs:
		kinds[(v as HorseVehicle).kind] = true
	check("cabs, growlers, carts, drays and omnibuses", kinds.size() >= 3, str(kinds.keys()))
	var starts := {}
	for v: Node in vs:
		starts[v] = (v as Node3D).global_position
	await wait(180)
	var moved := 0
	for v: Node in vs:
		if is_instance_valid(v) and (v as Node3D).global_position.distance_to(starts[v]) > 4.0:
			moved += 1
	check("they drive along", moved >= vs.size() / 2, "%d of %d" % [moved, vs.size()])
	# Keeping to the left: each is left of its road's centre line for its direction.
	var left_ok := 0
	var counted := 0
	for v: Node in vs:
		if not is_instance_valid(v):
			continue
		var hv := v as HorseVehicle
		if hv.speed < 1.0:
			continue
		var fwd := hv.get_facing_dir()
		var p := hv.global_position
		var line := traffic._nearest(city.plan.xs, p.x) if absf(fwd.z) > 0.9 else traffic._nearest(city.plan.zs, p.z)
		var off := p.x - city.plan.xs[line] if absf(fwd.z) > 0.9 else p.z - city.plan.zs[line]
		var left := Vector3(fwd.z, 0, -fwd.x)
		var side := off * (left.x if absf(fwd.z) > 0.9 else left.z)
		if absf(fwd.x) > 0.9 or absf(fwd.z) > 0.9:
			counted += 1
			left_ok += 1 if side > 0.5 else 0
	check("they keep to the left", counted == 0 or left_ok >= counted * 0.7, "%d of %d" % [left_ok, counted])
	# A vehicle stops for Harry standing in the road.
	var v0: HorseVehicle = null
	for v: Node in get_nodes_in_group_safe("vehicles"):
		if (v as HorseVehicle).speed > 2.0:
			v0 = v
			break
	if v0:
		var ahead := v0.global_position + v0.get_facing_dir() * 5.0
		await tp(Vector3(ahead.x, 0.3, ahead.z))
		var pos0 := v0.global_position
		await wait(90)
		check("a driver pulls up rather than run Harry down", v0.speed < 0.5 and v0.global_position.distance_to(harry.global_position) > 2.0, "speed %.1f, %.1f m" % [v0.speed, v0.global_position.distance_to(harry.global_position)])
		await tp(Vector3(330.0, 0.4, -150.0))


func _test_birds() -> void:
	await wait_until(func() -> bool: return birds.flock_count() >= 5, 900)
	check("birds over the rooftops and in the streets", birds.flock_count() >= 5, str(birds.flock_count()))
	var ground: Dictionary = {}
	for f in birds._flocks:
		if f["state"] == "ground":
			ground = f
			break
	check("pigeons pecking in the street", not ground.is_empty())
	if ground.is_empty():
		return
	var c: Vector3 = ground["center"]
	await tp(Vector3(c.x + 1.5, c.y + 0.3, c.z + 1.5))
	await wait(10)
	check("they fly up when Harry walks at them", ground["state"] == "up", str(ground["state"]))


func _test_crowds() -> void:
	await wait_until(func() -> bool: return life.people_count() >= 30, 1200)
	check("the streets are crowded by day", life.people_count() >= 30, str(life.people_count()))
	await wait_until(func() -> bool: return not get_nodes_in_group_safe("dogs").is_empty(), 900)
	var dogs := get_nodes_in_group_safe("dogs")
	check("people walk their dogs", not dogs.is_empty(), str(dogs.size()))
	if not dogs.is_empty():
		var d := dogs[0] as StreetDog
		await wait(60)
		check("a dog keeps to its owner's heel", is_instance_valid(d) and is_instance_valid(d.owner_node) and d.global_position.distance_to(d.owner_node.global_position) < 4.0)
