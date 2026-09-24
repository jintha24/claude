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
	var spawn := GameState.find_spawn(get_tree())
	if spawn == null:
		spawn = $CaveClearing
	streamer.prime(spawn.global_position)
	harry.set_spawn(spawn.global_transform)
	# After a fall or a mauling he wakes at the spawn: make sure its ground is there.
	harry.respawned.connect(func() -> void: streamer.prime(harry.global_position))
	GameState.restore(harry)
	GameState.spawn_at = ""
	cinder.global_position = spawn.global_position + spawn.global_basis.x * 3.0 + Vector3.UP * 0.2
	cinder.global_position.y = gen.height(cinder.global_position.x, cinder.global_position.z) + 0.1
	if GameState.arrived_mounted:
		GameState.arrived_mounted = false
		cinder.global_position = spawn.global_position + Vector3.UP * 0.1
		harry.try_mount()


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
