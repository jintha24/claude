extends "res://tests/test_base.gd"
## Phase 8: the hills. World streaming and detail levels, the terrain, the cave hideout
## (streamed in on a background thread) and its bed, chest and bench, wild deer and rabbits
## (senses, herds, hunting, the Outlaw's Code), Cinder (mounting, gaits, stamina, jumps,
## refusals, whistling), wading, and travelling to London and back with everything kept.

var streamer: WorldStreamer
var cinder: Horse
var noises: Array[Dictionary] = []


func make_scene() -> Node:
	return load("res://scenes/wilderness/hills.tscn").instantiate()


func tp(pos: Vector3, yaw: float = 0.0, settle: int = 20) -> void:
	var cam := main.get_node_or_null("ThirdPersonCamera") as ThirdPersonCamera
	if cam:
		cam.snap_behind(yaw)
	await super.tp(pos, yaw, settle)


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, streamer.height_at(x, z) + 0.05, z)


func run_tests() -> void:
	streamer = main.get_node("Streamer")
	cinder = main.get_node("Cinder")
	Weather.automatic = false
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Stealth.bus().noise_made.connect(func(p: Vector3, r: float, k: String, s: bool, src: Node) -> void:
		noises.append({"pos": p, "radius": r, "kind": k, "suspicious": s, "source": src}))
	(main.get_node("Animals") as AnimalSpawner).deer_herds = 0
	(main.get_node("Animals") as AnimalSpawner).rabbits = 0
	await _test_streaming()
	await _test_cave()
	await _test_animals()
	await _test_horse()
	await _test_travel()


# ---------------------------------------------------------------------------
func _test_streaming() -> void:
	await wait_until(func() -> bool: return harry.is_on_floor(), 60)
	check("Harry starts on solid ground in the clearing", harry.is_on_floor() and absf(harry.global_position.y - streamer.height_at(harry.global_position.x, harry.global_position.z)) < 0.3, describe())
	var c := streamer.coord_of(harry.global_position)
	check("the chunks round Harry are loaded in full detail with collision", streamer.is_ready_around(harry.global_position) and streamer.chunk_lod(c) == 0)
	await wait_until(func() -> bool: return streamer.loaded_count() >= (streamer.far_radius * 2 + 1) * (streamer.far_radius * 2 + 1) - 6, 900)
	var full := (streamer.far_radius * 2 + 1) * (streamer.far_radius * 2 + 1)
	check("the rest of the view streams in on background threads", streamer.loaded_count() >= full - 6, "%d of %d chunks" % [streamer.loaded_count(), full])
	check("near chunks detailed, middle without grass, far ones coarse", streamer.chunk_lod(c) == 0 and streamer.chunk_lod(c + Vector2i(2, 0)) == 1 and streamer.chunk_lod(c + Vector2i(5, 0)) == 2)
	var g2 := TerrainGenerator.new(streamer.world_seed)
	check("the terrain is the same whichever thread builds it", is_equal_approx(g2.height(123.4, -567.8), streamer.height_at(123.4, -567.8)))
	check("the lake holds water (1-1.5 m deep in the middle)", streamer.generator.water_depth(TerrainGenerator.LAKE.x, TerrainGenerator.LAKE.y) > 0.8 and streamer.generator.water_depth(TerrainGenerator.LAKE.x, TerrainGenerator.LAKE.y) < 1.6)
	var steep := 0.0
	for seg in range(1, TerrainGenerator.ROAD.size() - 2):
		var a: Vector2 = TerrainGenerator.ROAD[seg]
		var b: Vector2 = TerrainGenerator.ROAD[seg + 1]
		var n := int(a.distance_to(b) / 5.0)
		var prev := streamer.height_at(a.x, a.y)
		for i in range(1, n + 1):
			var p := a.lerp(b, float(i) / n)
			var h := streamer.height_at(p.x, p.y)
			steep = maxf(steep, absf(h - prev) / (a.distance_to(b) / n))
			prev = h
	check("the London road is graded gently (no steeper than 1 in 4)", steep < 0.25, "%.2f" % steep)
	# Ride off 450 m: the old chunks go, new ones come.
	var far := ground(480.0, 150.0)
	streamer.prime(far)
	await tp(far, 0.0, 30)
	await wait_until(func() -> bool: return streamer.chunk_lod(c) == -1, 600)
	check("chunks far behind are freed", streamer.chunk_lod(c) == -1)
	check("and he stands on the new ground", harry.is_on_floor() and not harry.is_dead(), describe())
	# Wading.
	var lake := ground(TerrainGenerator.LAKE.x, TerrainGenerator.LAKE.y + 20.0)
	streamer.prime(lake)
	await tp(lake, 0.0, 30)
	Input.action_press("move_forward")
	await wait(90)
	var wade := harry.get_horizontal_speed()
	Input.action_release("move_forward")
	check("wading through the lake slows him right down", wade < harry.run_speed * 0.7, "%.2f m/s" % wade)


func _test_cave() -> void:
	var cave := main.get_node("Cave") as StreamedScene
	var clearing := ground(-120.0, 96.0)
	streamer.prime(clearing)
	await tp(clearing, 0.0, 20)
	await wait_until(func() -> bool: return cave.is_loaded(), 600)
	check("the cave is loaded on a background thread when Harry comes near", cave.is_loaded())
	var hideout := cave.instance as CaveHideout
	var inside := hideout.to_global(Vector3(-3.0, 0.05, -14.0))
	await tp(inside, 0.0, 40)
	check("inside, he stands on the cave floor", harry.is_on_floor() and absf(harry.global_position.y - hideout.global_position.y) < 0.3, describe())
	var dark := harry.stealth.exposure
	await tp(hideout.to_global(Vector3(0.0, 0.05, -4.8)), 0.0, 30)
	var fire := harry.stealth.exposure
	check("the back of the cave is dark by day; the fire lights him up", dark < 0.25 and fire > dark + 0.15, "back %.2f by the fire %.2f" % [dark, fire])
	# Sleep until dusk; wake healed.
	harry.health = 40.0
	await tp(hideout.to_global(Vector3(-5.0, 0.05, -10.6)), 0.0, 20)
	await wait(12)
	check("the bedroll offers sleep", harry.interaction.prompt.begins_with("Sleep until"), harry.interaction.prompt)
	var day := GameClock.day
	Input.action_press("interact")
	await wait(80)
	Input.action_release("interact")
	await wait(5)
	check("sleeping passes the day away to dusk", absf(GameClock.hours() - 18.0) < 0.05 and GameClock.day == day, GameClock.clock_string())
	check("...and he wakes fully healed", harry.health == harry.max_health)
	GameClock.minutes = 12.0 * 60.0
	# Stash loot in the chest.
	harry.inventory.add_item({"name": "Gold watch", "value": 1200, "kind": "valuable"})
	harry.inventory.add_item({"name": "Door key", "value": 0, "kind": "key", "key_id": "x"})
	await tp(hideout.to_global(Vector3(5.5, 0.05, -11.8)), 0.0, 20)
	await wait(12)
	check("the chest offers to take his loot", harry.interaction.prompt.begins_with("Stash your loot"), harry.interaction.prompt)
	await press_for("interact", 2)
	await wait(5)
	check("loot goes in the chest; keys stay in his pocket", GameState.stash.size() == 1 and harry.inventory.items.size() == 1 and harry.inventory.has_key("x"))
	await wait(12)
	await press_for("interact", 2)
	await wait(5)
	check("...and can be taken out again", GameState.stash.is_empty() and harry.inventory.items.size() == 2)
	# Make arrows.
	harry.combat.blunt_arrows = 1
	harry.combat.broadhead_arrows = 0
	await tp(hideout.to_global(Vector3(4.6, 0.05, -4.0)), -PI * 0.5, 20)
	await wait(12)
	check("the bench offers to make arrows", harry.interaction.prompt == "Make arrows", harry.interaction.prompt)
	Input.action_press("interact")
	await wait(200)
	Input.action_release("interact")
	check("fletching fills his quiver", harry.combat.blunt_arrows == 12 and harry.combat.broadhead_arrows == 8)
	# Ride away and the cave is let go.
	var away := ground(200.0, 250.0)
	streamer.prime(away)
	await tp(away, 0.0, 20)
	await wait_until(func() -> bool: return not cave.is_loaded(), 300)
	check("far away, the cave is unloaded to save memory", not cave.is_loaded())


func _test_animals() -> void:
	var spawner := main.get_node("Animals") as AnimalSpawner
	Weather.wind = 0.1
	Weather.wind_direction = Vector3(0, 0, 1)
	var herd_at := ground(40.0, 120.0)
	var start := ground(40.0, 162.0) # 42 m south; the breeze blows from the deer towards him
	streamer.prime(herd_at)
	streamer.prime(start)
	await tp(start, 0.0, 10)
	harry.set_crouched(true)
	var herd := spawner.spawn_herd(herd_at, 4)
	await wait(180)
	check("a herd of red deer grazes, not noticing a still, crouched figure upwind", herd.size() == 4 and herd.all(func(d: WildAnimal) -> bool: return d.state != WildAnimal.State.FLEE), str(herd.map(func(d: WildAnimal) -> String: return WildAnimal.State.keys()[d.state])))
	var d0 := herd[1].global_position.distance_to(harry.global_position)
	harry.set_crouched(false)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_until(func() -> bool: return herd.any(func(d: WildAnimal) -> bool: return d.state == WildAnimal.State.FLEE), 400)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check("run at them and they bolt", herd.any(func(d: WildAnimal) -> bool: return d.state == WildAnimal.State.FLEE))
	check("...the whole herd together", herd.all(func(d: WildAnimal) -> bool: return d.state == WildAnimal.State.FLEE))
	await wait(120)
	check("and they run away from him fast", herd[1].global_position.distance_to(harry.global_position) > d0 + 8.0, "%.1f -> %.1f m" % [d0, herd[1].global_position.distance_to(harry.global_position)])
	# Scent: downwind, a deer notices him from far off even though he's hidden.
	var h2 := spawner.spawn_herd(ground(-40.0, 120.0), 3)
	var deer := h2[0]
	Weather.wind = 0.9
	Weather.wind_direction = Vector3(0, 0, -1) # blowing from Harry (south) to the deer
	await tp(ground(-40.0, 160.0), 0.0, 5)
	harry.set_crouched(true)
	await wait_until(func() -> bool: return deer.state != WildAnimal.State.GRAZE and deer.state != WildAnimal.State.WANDER, 300)
	check("downwind, deer scent him at 40 m however still he keeps", deer.state in [WildAnimal.State.ALERT, WildAnimal.State.FLEE], WildAnimal.State.keys()[deer.state])
	harry.set_crouched(false)
	Weather.wind = 0.2
	# Hunting: a broadhead brings a deer down after a few strides.
	var h3 := spawner.spawn_herd(ground(40.0, 120.0), 2)
	var target := h3[0]
	# Hold the pair still for the shot (grazing beasts that haven't noticed him).
	for d in h3:
		d.set("_sense_timer", 1000.0)
		d.set("_timer", 1000.0)
		d.state = WildAnimal.State.GRAZE
	# Take up a spot 8 m off with a clear line of sight (no tree trunk in the way).
	var tpos := target.global_position
	var shot_from := ground(tpos.x, tpos.z + 8.0)
	for k in 12:
		var a := TAU * k / 12.0
		var p := ground(tpos.x + sin(a) * 8.0, tpos.z + cos(a) * 8.0)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, tpos + Vector3.UP * 1.0, 1)
		if main.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			shot_from = p
			break
	var face := tpos - shot_from
	await tp(shot_from, atan2(-face.x, -face.z), 5)
	await wait(2)
	var arrow := Arrow.create("broadhead")
	main.add_child(arrow)
	var from := harry.global_position + Vector3.UP * 1.5
	var aim := target.global_position + Vector3.UP * 1.0
	arrow.launch(from, HarryCombat._ballistic_direction(from, aim, 50.0) * 50.0, harry) # allowing for the drop, as Harry does
	# (If the other hind steps into the arrow's path, she's the one it takes.)
	await wait_until(func() -> bool: return h3.any(func(d: WildAnimal) -> bool: return d.state == WildAnimal.State.DEAD), 400)
	for d in h3:
		if d.state == WildAnimal.State.DEAD:
			target = d
	check("a broadhead brings the deer down after a short run", target.state == WildAnimal.State.DEAD, "arrow hit %s at %s from %s aiming %s; herd %s at %s" % [arrow.hit_node, arrow.global_position, from, aim, str(h3.map(func(d: WildAnimal) -> String: return WildAnimal.State.keys()[d.state])), str(h3.map(func(d: WildAnimal) -> Vector3: return d.global_position))])
	var carcass: Carcass = null
	for ch in target.get_children():
		if ch is Carcass:
			carcass = ch
	check("it can be butchered", carcass != null)
	if carcass:
		var cp := target.global_position
		await tp(ground(cp.x, cp.z + 1.2), 0.0, 10)
		await wait(12)
		var n := harry.inventory.items.size()
		Input.action_press("interact")
		await wait(260)
		Input.action_release("interact")
		await wait(5)
		check("butchering gives venison and a hide", harry.inventory.items.size() == n + 2 and harry.inventory.count_kind("provision") >= 1, harry.interaction.prompt)
	# A blunt only frightens a deer; it kills a rabbit.
	var other := h3[1] if h3[0] == target else h3[0]
	other.state = WildAnimal.State.GRAZE
	other.on_arrow_hit("blunt", other.global_position, Vector3(1, 0, 0))
	check("a blunt arrow only frightens a deer", other.state == WildAnimal.State.FLEE)
	var rabbit := spawner.spawn_rabbit(ground(46.0, 128.0))
	rabbit.on_arrow_hit("blunt", rabbit.global_position, Vector3(1, 0, 0))
	await wait(40)
	check("...but kills a rabbit (blunts were for small game)", rabbit.state == WildAnimal.State.DEAD)
	# The Outlaw's Code: no broadhead at a man.
	var cam := main.get_node("ThirdPersonCamera") as ThirdPersonCamera
	await tp(ground(-120.0, 104.0), 0.0, 10)
	var man := Guard.new()
	main.add_child(man)
	var refused := [0]
	harry.combat.code_refused.connect(func() -> void: refused[0] += 1)
	harry.combat.arrow_kind = "broadhead"
	var had := harry.combat.broadhead_arrows
	cam.set("_pitch", -0.05)
	Input.action_press("aim")
	await wait(90) # let the camera settle over his shoulder
	# Put the man right under the crosshair (the over-the-shoulder camera's centre line).
	var c3 := main.get_viewport().get_camera_3d()
	var fwd := -c3.global_basis.z
	var spot := c3.global_position + fwd * 6.0
	for i in 60:
		var p := c3.global_position + fwd * (4.0 + i * 0.25)
		if p.y - streamer.height_at(p.x, p.z) < 1.2: # the crosshair line at chest height
			spot = p
			break
	man.global_position = ground(spot.x, spot.z)
	man.reset_physics_interpolation()
	await wait(5)
	Input.action_press("fire")
	await wait(70)
	Input.action_release("fire")
	await wait(5)
	Input.action_release("aim")
	check("Harry won't loose a broadhead at a man (the Outlaw's Code)", refused[0] == 1 and harry.combat.broadhead_arrows == had, "refused %d, crosshair on %s, man at %s, cam %s" % [refused[0], harry.combat.last_aim_target, man.global_position, c3.global_position])
	man.queue_free()
	harry.combat.arrow_kind = "blunt"


func _test_horse() -> void:
	var course := ground(-134.0, 98.0)
	streamer.prime(course)
	cinder.global_position = course + Vector3.UP * 0.1
	cinder.set("_yaw", -PI * 0.5)
	cinder.speed = 0.0
	cinder.reset_physics_interpolation()
	await tp(course + Vector3(0, 0, 1.6), -PI * 0.5, 30)
	await press_for("mount_horse", 2)
	await wait(5)
	check("F by the horse: Harry swings up into the saddle", harry.is_riding() and harry.state == Harry.State.RIDE)
	check("the rider's own collision is off while mounted", (harry.get_node("CollisionShape3D") as CollisionShape3D).disabled)
	# Walk / trot / canter.
	Input.action_press("move_forward")
	Input.action_press("walk")
	await wait(90)
	var walk := cinder.speed
	Input.action_release("walk")
	await wait(60)
	var trot := cinder.speed
	check("a gentle walk, then a trot", absf(walk - Horse.GAIT_SPEED[Horse.Gait.WALK]) < 0.3 and absf(trot - Horse.GAIT_SPEED[Horse.Gait.TROT]) < 0.4, "%.1f, %.1f m/s" % [walk, trot])
	# Canter at the jumps: log, rail fence, stone wall.
	var jumps := [0]
	var jl := func(_h: float) -> void: jumps[0] += 1
	cinder.jumped.connect(jl)
	await press_for("sprint", 2)
	await wait_until(func() -> bool: return cinder.global_position.x > -90.0, 900)
	Input.action_release("move_forward")
	cinder.jumped.disconnect(jl)
	check("at a canter he clears the log, the fence and the wall on his own", jumps[0] >= 3 and cinder.global_position.x > -90.0, "%d jumps, x=%.1f" % [jumps[0], cinder.global_position.x])
	await wait(90)
	# The sheepfold wall is too high: he refuses.
	var refusals := [""]
	cinder.refused.connect(func(r: String) -> void: refusals[0] = r)
	cinder.global_position = ground(-150.0, 104.0) + Vector3.UP * 0.1
	cinder.set("_yaw", -PI * 0.5)
	cinder.speed = 0.0
	cinder.reset_physics_interpolation()
	(main.get_node("ThirdPersonCamera") as ThirdPersonCamera).snap_behind(-PI * 0.5)
	await wait(5)
	Input.action_press("move_forward")
	await press_for("sprint", 2)
	await wait(240)
	Input.action_release("move_forward")
	check("a 2 m wall: he refuses and stops short", refusals[0] == "too high" and cinder.global_position.x < -136.5, "'%s' x=%.1f" % [refusals[0], cinder.global_position.x])
	# Gallop along the road; stamina.
	var a: Vector2 = TerrainGenerator.ROAD[1]
	var b: Vector2 = TerrainGenerator.ROAD[2]
	var dir := (b - a).normalized()
	var yaw := atan2(-dir.x, -dir.y)
	var st := ground(a.x, a.y)
	streamer.prime(st)
	cinder.global_position = st + Vector3.UP * 0.1
	cinder.set("_yaw", yaw)
	cinder.speed = 0.0
	cinder.stamina = 1.0
	cinder.reset_physics_interpolation()
	(main.get_node("ThirdPersonCamera") as ThirdPersonCamera).snap_behind(yaw)
	await wait(5)
	var since := noises.size()
	Input.action_press("move_forward")
	await press_for("sprint", 2)
	await wait(20)
	await press_for("sprint", 2)
	var top := [0.0]
	for i in 240:
		top[0] = maxf(top[0], cinder.speed)
		await wait(1)
	check("spurred twice he gallops at about 13 m/s", top[0] > 12.0, "%.1f m/s" % top[0])
	check("galloping tires him", cinder.stamina < 0.95, "%.2f" % cinder.stamina)
	var hooves := noises.slice(since).filter(func(n: Dictionary) -> bool: return n["kind"] == "hooves")
	check("hoofbeats carry a long way at the gallop", hooves.size() > 5 and hooves.any(func(n: Dictionary) -> bool: return float(n["radius"]) >= 20.0))
	cinder.stamina = 0.02
	await wait(120)
	check("spent, he drops back to a canter", cinder.speed < Horse.GAIT_SPEED[Horse.Gait.CANTER] + 0.5, "%.1f m/s" % cinder.speed)
	Input.action_release("move_forward")
	await wait_until(func() -> bool: return absf(cinder.speed) < 0.2, 300)
	await press_for("mount_horse", 2)
	await wait(30)
	check("F again: he gets down beside the horse", not harry.is_riding() and harry.state != Harry.State.RIDE and harry.global_position.distance_to(cinder.global_position) < 2.5, describe())
	check("...on foot again with his collision back", not (harry.get_node("CollisionShape3D") as CollisionShape3D).disabled)
	# Whistle from far away.
	var here := ground(60.0, 300.0)
	streamer.prime(here)
	await tp(here, 0.0, 20)
	cinder.global_position = ground(300.0, 500.0)
	await press_for("whistle_horse", 2)
	await wait(3)
	check("whistled for from far off, he appears nearby, out of sight", cinder.global_position.distance_to(harry.global_position) < 60.0)
	await wait_until(func() -> bool: return not cinder.called, 900)
	check("...and trots up to Harry", cinder.global_position.distance_to(harry.global_position) < 4.0, "%.1f m" % cinder.global_position.distance_to(harry.global_position))


func _test_travel() -> void:
	# Ride to the London signpost and set off; everything comes too.
	harry.inventory.add_money(777)
	var money := harry.inventory.money
	var items := harry.inventory.items.size()
	var post := main.get_node("ToLondon") as TravelPoint
	var p := ground(post.global_position.x - 2.0, post.global_position.z)
	streamer.prime(p)
	await tp(p, -PI * 0.5, 20)
	await wait(12)
	check("the signpost offers the road to London", harry.interaction.prompt == "Set off for London", harry.interaction.prompt)
	await press_for("interact", 2)
	await wait_until(func() -> bool: return current_scene != null and current_scene.name == "Main" and current_scene.has_node("Harry"), 1200)
	check("a loading card, and London loads (on a background thread)", current_scene.name == "Main")
	main = current_scene
	harry = main.get_node("Harry") as Harry
	await wait(30)
	var spawn := main.get_node("HillsRoad") as Node3D
	check("he arrives on the north road into the market", harry.global_position.distance_to(spawn.global_position) < 1.5, describe())
	check("with his purse and his bag", harry.inventory.money == money and harry.inventory.items.size() == items, "%d / %d" % [harry.inventory.money, harry.inventory.items.size()])
	await wait(90)
	var back := main.get_node("ToHills") as TravelPoint
	back.travel()
	await wait_until(func() -> bool: return current_scene != null and current_scene.name == "Hills" and current_scene.has_node("Harry"), 1200)
	main = current_scene
	harry = main.get_node("Harry") as Harry
	streamer = main.get_node("Streamer") as WorldStreamer
	await wait(30)
	check("and back to the hills, arriving by the London road", harry.global_position.distance_to((main.get_node("LondonRoad") as Node3D).global_position) < 1.5 and harry.is_on_floor(), describe())
	check("still with his money", harry.inventory.money == money)
