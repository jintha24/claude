extends SceneTree
## Renders character models to PNG for checking the look (needs a GPU, or lavapipe):
##   godot --path . --rendering-driver vulkan --script res://tools/characters/preview.gd -- <out.png> <outfit> [<outfit>...]
## Outfits are CharacterLook names (e.g. gentleman lady constable worker harry); each is
## shown front and three-quarter, in daylight.

var _out := "user://preview.png"
var _outfits: Array[String] = []
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	for i in range(1, args.size()):
		_outfits.append(args[i])
	if _outfits.is_empty():
		_outfits = ["gentleman"]
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.35
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.4, 0.37)
	ground.material_override = gm
	world.add_child(ground)
	var x := -(_outfits.size() - 1) * 0.95 - 0.25
	for name in _outfits:
		for turn: float in [0.0, 0.6]:
			var body := NPCBody.new()
			body.look = name
			body.height = 1.78 if name != "child" else 1.42
			body.variation_seed = hash(name) + int(turn * 10.0)
			body.position = Vector3(x + turn * 0.9 - 0.2, 0, 0)
			body.rotation.y = PI + turn
			world.add_child(body)
			# PREVIEW_PLAIN=1: every blend shape at zero (the unvaried model).
			if OS.get_environment("PREVIEW_PLAIN") == "1" and body.get_look_model():
				for mi: MeshInstance3D in body.get_look_model().find_children("*", "MeshInstance3D", true, false):
					for k in mi.mesh.get_blend_shape_count():
						mi.set_blend_shape_value(k, 0.0)
		x += 1.9
	var cam := Camera3D.new()
	cam.fov = 32
	var span := _outfits.size() * 1.9
	world.add_child(cam)
	var from := Vector3(0.0, 1.25, 2.6 + span * 1.05)
	var at := Vector3(0.0, 1.0, 0.0)
	# PREVIEW_CAM="x,y,z,tx,ty,tz" for close-ups.
	var spec := OS.get_environment("PREVIEW_CAM").split_floats(",")
	if spec.size() == 6:
		from = Vector3(spec[0], spec[1], spec[2])
		at = Vector3(spec[3], spec[4], spec[5])
	cam.look_at_from_position(from, at)
	cam.make_current()


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 30:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		quit()
	return false
