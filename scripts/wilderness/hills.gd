extends Node3D
## Root of the hills north of London (Phase 8): places Harry at his spawn point once the
## ground under him has streamed in, positions the streamed cave, builds Aldous's old jump
## course in the clearing, and brings Cinder along if Harry rode here.

const CAVE_ORIGIN_Z := 70.0

@onready var streamer: WorldStreamer = $Streamer
@onready var harry: Harry = $Harry
@onready var cinder: Horse = $Cinder


func _ready() -> void:
	var gen := streamer.generator
	var ch := gen.clearing_height()
	($Cave as Node3D).position = Vector3(-120.0, ch, CAVE_ORIGIN_Z)
	for m: Node3D in [$CaveClearing, $LondonRoad, $ToLondon]:
		m.position.y = gen.height(m.position.x, m.position.z) + 0.05
	_build_jump_course(gen)
	_build_fishing(gen)
	for i in TerrainGenerator.VILLAGES.size():
		var village := Village.new()
		village.setup(gen, i)
		add_child(village)
	var farm := FarmAnimals.new()
	farm.name = "FarmAnimals"
	add_child(farm)
	var traffic := RoadTraffic.new()
	traffic.name = "RoadTraffic"
	add_child(traffic)
	var birds := BirdLife.new()
	birds.name = "Birds"
	birds.place = "hills"
	birds.flying_flocks = 3
	birds.ground_flocks = 3
	birds.set_height_fn(gen.height)
	add_child(birds)
	var audio := get_node_or_null("Audio") as AudioDirector
	if audio:
		audio.add_zone("water_lap", Vector3(TerrainGenerator.LAKE.x, TerrainGenerator.WATER_Y, TerrainGenerator.LAKE.y), TerrainGenerator.LAKE_RADIUS - 15.0, 45.0, 0.7)
	GameSettings.apply(get_tree())
	var spawn_v: Variant = GameState.take_spawn(get_tree())
	var spawn_t: Transform3D = spawn_v if spawn_v != null else ($CaveClearing as Node3D).global_transform
	var spawn := Marker3D.new()
	spawn.name = "ArrivalPoint"
	add_child(spawn)
	spawn.global_transform = spawn_t
	streamer.prime(spawn.global_position)
	harry.set_spawn(spawn.global_transform)
	# After a fall or a mauling he wakes at the spawn: make sure its ground is there.
	harry.respawned.connect(func() -> void: streamer.prime(harry.global_position))
	GameState.restore(harry)
	cinder.global_position = spawn.global_position + spawn.global_basis.x * 3.0 + Vector3.UP * 0.2
	cinder.global_position.y = gen.height(cinder.global_position.x, cinder.global_position.z) + 0.1
	if GameState.arrived_mounted:
		GameState.arrived_mounted = false
		cinder.global_position = spawn.global_position + Vector3.UP * 0.1
		harry.try_mount()
	if GameState.autosave_on_arrival:
		GameState.autosave_on_arrival = false
		SaveGame.save.call_deferred(get_tree(), 0)


## An anglers' jetty on the lake's north shore, and two quiet spots on the bank.
func _build_fishing(gen: TerrainGenerator) -> void:
	var lake := Vector3(TerrainGenerator.LAKE.x, 0.0, TerrainGenerator.LAKE.y)
	var dirs: Array[Vector3] = [Vector3(-0.6, 0, -0.8).normalized(), Vector3(0.9, 0, -0.3).normalized(), Vector3(-0.2, 0, 1.0).normalized()]
	for i in dirs.size():
		# Walk out from the middle of the lake until the ground rises out of the water.
		var shore := lake
		for k in 400:
			var p := lake + dirs[i] * (k * 0.5)
			if gen.height(p.x, p.z) > TerrainGenerator.WATER_Y + 0.15:
				shore = p
				break
		var spot := FishingSpot.new()
		spot.cast_dir = -dirs[i]
		if i == 0:
			# The jetty: planks on posts running 8 m out over the water.
			spot.name = "Jetty"
			spot.spot_name = "Fish from the jetty"
			var deck_y := TerrainGenerator.WATER_Y + 0.55
			var body := StaticBody3D.new()
			body.name = "JettyDeck"
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("surface", "wood")
			add_child(body)
			var start := shore + dirs[i] * 2.0
			var end := shore - dirs[i] * 8.0
			var mid := (start + end) * 0.5
			var length := start.distance_to(end)
			var basis := Basis(Vector3.UP, atan2(dirs[i].x, dirs[i].z))
			var mb := MeshBuilder.new()
			var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.55, 0.46, 0.36))
			mb.add_box(Vector3(1.6, 0.12, length), Vector3(mid.x, deck_y - 0.06, mid.z), wood, basis)
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.6, 0.3, length)
			cs.shape = box
			cs.transform = Transform3D(basis, Vector3(mid.x, deck_y - 0.15, mid.z))
			body.add_child(cs)
			for k in 5:
				var pp := start.lerp(end, k / 4.0)
				for side: float in [-0.7, 0.7]:
					var q := pp + basis.x * side
					mb.add_cylinder(0.08, 0.08, 2.4, Vector3(q.x, deck_y - 1.2, q.z), wood, 6)
			mb.build_into(self, "JettyMesh")
			spot.position = Vector3(end.x, deck_y, end.z) + dirs[i] * 0.8
		else:
			spot.name = "Bank%d" % i
			spot.spot_name = "Fish from the bank"
			var land := shore + dirs[i] * 1.5
			spot.position = Vector3(land.x, gen.height(land.x, land.z), land.z)
		add_child(spot)


## Aldous's old paddock at the edge of the clearing: a log, a rail fence, a dry-stone wall
## (all jumpable at a canter) and the sheepfold wall (too high: a horse refuses it).
func _build_jump_course(gen: TerrainGenerator) -> void:
	var course := StaticBody3D.new()
	course.name = "JumpCourse"
	course.collision_layer = 1
	course.collision_mask = 0
	add_child(course)
	var mb := MeshBuilder.new()
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.55, 0.45, 0.35))
	var stone := MaterialLibrary.get_tinted("rock", Color(0.7, 0.68, 0.62))
	var specs := [
		["Log", Vector3(-112.0, 0, 98.0), Vector3(0.55, 0.55, 4.0), wood],
		["RailFence", Vector3(-104.0, 0, 98.0), Vector3(0.12, 1.1, 4.0), wood],
		["StoneWall", Vector3(-96.0, 0, 98.0), Vector3(0.6, 1.25, 4.0), stone],
		["SheepfoldWall", Vector3(-136.0, 0, 104.0), Vector3(0.7, 2.0, 5.0), stone],
	]
	for s: Array in specs:
		var p: Vector3 = s[1]
		var size: Vector3 = s[2]
		p.y = gen.height(p.x, p.z) + size.y * 0.5
		if s[0] == "Log":
			mb.add_cylinder(size.x * 0.5, size.x * 0.5, size.z, p, wood, 10, Basis(Vector3.RIGHT, PI * 0.5))
		elif s[0] == "RailFence":
			for y: float in [-0.45, -0.05, 0.4]:
				mb.add_box(Vector3(0.08, 0.1, size.z), p + Vector3(0, y, 0), wood)
			for z: float in [-1.9, 0.0, 1.9]:
				mb.add_box(Vector3(0.14, size.y + 0.1, 0.14), p + Vector3(0, 0.05, z), wood)
		else:
			mb.add_box(size, p, s[3])
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = p
		cs.name = s[0]
		course.add_child(cs)
	mb.build_into(self, "JumpCourseMesh")
