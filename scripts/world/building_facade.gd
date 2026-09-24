@tool
class_name BuildingFacade
extends Node3D
## One modular Victorian terraced building (house or shop), generated from parameters.
##
## Local space: the street facade is the plane z = 0 and faces +Z. The building spans
## x = 0 .. width and goes back to z = -depth. y = 0 is the pavement surface.
## Change any exported value in the Inspector and the building rebuilds instantly.

enum GroundFloor { HOUSE, SHOP }

const PAINT_COLORS: Array[Color] = [
	Color(0.08, 0.17, 0.12), # Brunswick green
	Color(0.28, 0.07, 0.06), # oxblood
	Color(0.04, 0.04, 0.045), # black
	Color(0.07, 0.10, 0.18), # navy
	Color(0.55, 0.50, 0.38), # stone
]
const WINDOW_WHITE := Color(0.86, 0.85, 0.8)
const STEP_RISE := 0.17
const STEP_RUN := 0.3

@export_range(3.0, 16.0, 0.1) var width: float = 6.0:
	set(v):
		width = v
		_queue_rebuild()
@export_range(4.0, 20.0, 0.1) var depth: float = 10.0:
	set(v):
		depth = v
		_queue_rebuild()
@export_range(1, 5) var upper_floors: int = 2:
	set(v):
		upper_floors = v
		_queue_rebuild()
@export var ground_floor_height: float = 3.4:
	set(v):
		ground_floor_height = v
		_queue_rebuild()
@export var floor_height: float = 3.0:
	set(v):
		floor_height = v
		_queue_rebuild()
@export_enum("brick_yellow", "brick_red", "stucco") var wall_material: String = "brick_yellow":
	set(v):
		wall_material = v
		_queue_rebuild()
@export var ground_floor: GroundFloor = GroundFloor.HOUSE:
	set(v):
		ground_floor = v
		_queue_rebuild()
@export var shop_name: String = "":
	set(v):
		shop_name = v
		_queue_rebuild()
@export var door_on_left: bool = true:
	set(v):
		door_on_left = v
		_queue_rebuild()
@export var chimney_smoke: bool = true:
	set(v):
		chimney_smoke = v
		_queue_rebuild()
@export var has_awning: bool = false:
	set(v):
		has_awning = v
		_queue_rebuild()
@export var variation_seed: int = 0:
	set(v):
		variation_seed = v
		_queue_rebuild()

var _rebuild_pending := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_pending:
		return
	_rebuild_pending = true
	(func() -> void:
		_rebuild_pending = false
		rebuild()).call_deferred()


## Total height of the facade (to the top of the cornice).
func get_facade_height() -> float:
	return ground_floor_height + upper_floors * floor_height


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_rng.seed = hash(variation_seed)

	var wall := MaterialLibrary.get_material(wall_material)
	var stone := MaterialLibrary.get_material("stone_trim")
	var paint := MaterialLibrary.get_tinted("wood_painted", PAINT_COLORS[_rng.randi() % PAINT_COLORS.size()])
	var white := MaterialLibrary.get_tinted("wood_painted", WINDOW_WHITE)
	var glass := MaterialLibrary.get_material("glass")
	var iron := MaterialLibrary.get_material("iron")

	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var h := get_facade_height()

	# --- Main mass and facade bands -------------------------------------------
	mb.add_box(Vector3(width, h + 0.3, depth), Vector3(width * 0.5, (h - 0.3) * 0.5, -depth * 0.5), wall)
	_add_box_collider(body, Vector3(width, h + 0.3, depth), Vector3(width * 0.5, (h - 0.3) * 0.5, -depth * 0.5))
	# Projecting bands are real ledges Harry can hang from, so they get collision too.
	_add_ledge(mb, body, Vector3(width, 0.22, 0.14), Vector3(width * 0.5, ground_floor_height, 0.07), stone) # string course
	mb.add_box(Vector3(width, 0.12, 0.18), Vector3(width * 0.5, h - 0.36, 0.09), stone) # dentil band
	_add_ledge(mb, body, Vector3(width, 0.34, 0.34), Vector3(width * 0.5, h - 0.12, 0.17), stone) # cornice

	# --- Upper floor windows ---------------------------------------------------
	var count := maxi(1, int((width - 0.6) / 1.8))
	var spacing := width / count
	for f in upper_floors:
		var top_floor := f == upper_floors - 1
		var y_floor := ground_floor_height + f * floor_height
		var wh := 1.45 if top_floor else 1.8
		var ww := 0.85 if top_floor else 0.95
		for i in count:
			_add_window(mb, body, spacing * (i + 0.5), y_floor + 0.75, ww, wh, stone, white, glass, not top_floor)

	# --- Ground floor ------------------------------------------------------------
	if ground_floor == GroundFloor.SHOP:
		_build_shopfront(mb, body, paint, white, glass, stone)
	else:
		_build_house_front(mb, body, paint, white, glass, stone, iron, count, spacing)

	# --- Roof, chimneys, rainwater pipe --------------------------------------
	_build_roof(mb, body, wall, stone)
	_build_downpipe(mb, iron, h)

	var mi := mb.build_into(self, "Mesh")
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC


func _add_window(mb: MeshBuilder, body: StaticBody3D, cx: float, y: float, ww: float, wh: float, stone: Material, frame: Material, glass: Material, keystone: bool) -> void:
	var yc := y + wh * 0.5
	# Glass sits just proud of the wall; the stone surround projects in front of it,
	# which reads as a window set back into the brickwork.
	mb.add_box(Vector3(ww, wh, 0.02), Vector3(cx, yc, 0.0), glass)
	# Sash frame, meeting rail and glazing bars (2-over-2 Victorian sash).
	mb.add_box(Vector3(0.06, wh, 0.05), Vector3(cx - ww * 0.5 + 0.03, yc, 0.025), frame)
	mb.add_box(Vector3(0.06, wh, 0.05), Vector3(cx + ww * 0.5 - 0.03, yc, 0.025), frame)
	mb.add_box(Vector3(ww, 0.06, 0.05), Vector3(cx, y + wh - 0.03, 0.025), frame)
	mb.add_box(Vector3(ww, 0.08, 0.05), Vector3(cx, y + 0.04, 0.025), frame)
	mb.add_box(Vector3(ww, 0.05, 0.06), Vector3(cx, yc, 0.03), frame)
	mb.add_box(Vector3(0.03, wh, 0.04), Vector3(cx, yc, 0.02), frame)
	# Stone surround: jambs, lintel, sill.
	mb.add_box(Vector3(0.14, wh + 0.1, 0.09), Vector3(cx - ww * 0.5 - 0.07, yc, 0.045), stone)
	mb.add_box(Vector3(0.14, wh + 0.1, 0.09), Vector3(cx + ww * 0.5 + 0.07, yc, 0.045), stone)
	_add_ledge(mb, body, Vector3(ww + 0.44, 0.24, 0.12), Vector3(cx, y + wh + 0.12, 0.06), stone) # lintel
	_add_ledge(mb, body, Vector3(ww + 0.3, 0.07, 0.17), Vector3(cx, y - 0.035, 0.085), stone) # sill
	if keystone:
		mb.add_box(Vector3(0.18, 0.32, 0.15), Vector3(cx, y + wh + 0.13, 0.075), stone)


func _build_house_front(mb: MeshBuilder, body: StaticBody3D, paint: Material, white: Material, glass: Material, stone: Material, iron: Material, count: int, spacing: float) -> void:
	var steps := 3
	var floor_y := steps * STEP_RISE # raised ground floor above the pavement
	var door_w := 1.05
	var door_h := 2.3
	var door_x := 0.95 if door_on_left else width - 0.95

	# Stone plinth along the base.
	mb.add_box(Vector3(width, 0.55, 0.06), Vector3(width * 0.5, 0.275, 0.03), stone)

	# Front door with panels, fanlight and pilastered doorcase.
	mb.add_box(Vector3(door_w, door_h, 0.06), Vector3(door_x, floor_y + door_h * 0.5, 0.0), paint)
	for px in [-0.22, 0.22]:
		for py in [0.55, 1.55]:
			mb.add_box(Vector3(0.34, 0.75, 0.025), Vector3(door_x + px, floor_y + py, 0.04), paint)
	mb.add_box(Vector3(0.05, 0.05, 0.06), Vector3(door_x + (0.38 if door_on_left else -0.38), floor_y + 1.05, 0.06), MaterialLibrary.get_material("brass"))
	mb.add_box(Vector3(door_w - 0.1, 0.42, 0.02), Vector3(door_x, floor_y + door_h + 0.26, 0.0), glass)
	mb.add_box(Vector3(door_w, 0.05, 0.05), Vector3(door_x, floor_y + door_h + 0.025, 0.025), white)
	for side in [-1.0, 1.0]:
		mb.add_box(Vector3(0.22, door_h + 0.55, 0.16), Vector3(door_x + side * (door_w * 0.5 + 0.11), floor_y + (door_h + 0.55) * 0.5, 0.08), stone)
	_add_ledge(mb, body, Vector3(door_w + 0.7, 0.32, 0.24), Vector3(door_x, floor_y + door_h + 0.66, 0.12), stone) # door hood

	# Ground-floor windows (skip the bay where the door is).
	for i in count:
		var cx := spacing * (i + 0.5)
		if absf(cx - door_x) < 1.3:
			continue
		_add_window(mb, body, cx, floor_y + 0.75, 1.0, 1.95, stone, white, glass, true)

	# Granite front steps (a "stoop"), each step a solid block you can walk up.
	var granite := MaterialLibrary.get_material("curb_granite")
	for k in steps:
		var step_h := (k + 1) * STEP_RISE
		var step_d := (steps - k) * STEP_RUN
		var size := Vector3(1.6, step_h, step_d)
		var center := Vector3(door_x, step_h * 0.5, step_d * 0.5)
		mb.add_box(size, center, granite)
		_add_box_collider(body, size, center)

	# Cast-iron railings in front of the house (with a gap at the steps).
	var rail_z := 0.95
	var gaps: Array[Vector2] = [Vector2(0.1, door_x - 0.85), Vector2(door_x + 0.85, width - 0.1)]
	for g in gaps:
		if g.y - g.x < 0.4:
			continue
		_add_railing(mb, body, g.x, g.y, rail_z, iron)


func _add_railing(mb: MeshBuilder, body: StaticBody3D, x0: float, x1: float, z: float, iron: Material) -> void:
	var height := 1.05
	var length := x1 - x0
	var bars := int(length / 0.13)
	for b in bars + 1:
		var x := x0 + length * float(b) / float(maxi(bars, 1))
		mb.add_cylinder(0.011, 0.011, height, Vector3(x, height * 0.5, z), iron, 6)
		mb.add_cylinder(0.022, 0.0, 0.09, Vector3(x, height + 0.045, z), iron, 4) # spear head
	mb.add_box(Vector3(length, 0.035, 0.03), Vector3((x0 + x1) * 0.5, height - 0.08, z), iron)
	mb.add_box(Vector3(length, 0.035, 0.03), Vector3((x0 + x1) * 0.5, 0.12, z), iron)
	_add_box_collider(body, Vector3(length, height, 0.06), Vector3((x0 + x1) * 0.5, height * 0.5, z))


func _build_shopfront(mb: MeshBuilder, body: StaticBody3D, paint: Material, white: Material, glass: Material, stone: Material) -> void:
	var gh := ground_floor_height
	var door_w := 1.0
	var door_x := 0.3 + door_w * 0.5 + 0.05 if door_on_left else width - 0.3 - door_w * 0.5 - 0.05

	# Pilasters, fascia (the sign board), cornice and stallriser.
	for x in [0.15, width - 0.15]:
		mb.add_box(Vector3(0.3, gh - 0.1, 0.18), Vector3(x, (gh - 0.1) * 0.5, 0.09), paint)
	mb.add_box(Vector3(width - 0.3, 0.55, 0.12), Vector3(width * 0.5, gh - 0.475, 0.2), paint)
	_add_ledge(mb, body, Vector3(width, 0.12, 0.34), Vector3(width * 0.5, gh - 0.14, 0.17), paint) # shop cornice

	# Display window: stallriser, glass, mullions, transom. The door is recessed.
	var disp_x0 := 0.3 if not door_on_left else door_x + door_w * 0.5 + 0.05
	var disp_x1 := width - 0.3 if door_on_left else door_x - door_w * 0.5 - 0.05
	var disp_w := disp_x1 - disp_x0
	var disp_c := (disp_x0 + disp_x1) * 0.5
	mb.add_box(Vector3(disp_w, 0.6, 0.14), Vector3(disp_c, 0.3, 0.07), paint)
	mb.add_box(Vector3(disp_w, 2.0, 0.02), Vector3(disp_c, 1.6, 0.06), glass)
	mb.add_box(Vector3(disp_w, 0.07, 0.08), Vector3(disp_c, 2.25, 0.08), white)
	mb.add_box(Vector3(disp_w, 0.08, 0.1), Vector3(disp_c, 2.62, 0.08), paint)
	var mullions := maxi(1, int(disp_w / 1.1))
	for m in mullions + 1:
		var mx := disp_x0 + disp_w * float(m) / float(mullions)
		mb.add_box(Vector3(0.06, 2.0, 0.08), Vector3(mx, 1.6, 0.08), white)

	# Half-glazed shop door, set back from the window line.
	mb.add_box(Vector3(door_w, 2.45, 0.05), Vector3(door_x, 1.225, -0.02), paint)
	mb.add_box(Vector3(door_w - 0.25, 1.1, 0.02), Vector3(door_x, 1.65, 0.01), glass)
	mb.add_box(Vector3(door_w, 0.3, 0.02), Vector3(door_x, 2.6, 0.0), glass)
	mb.add_box(Vector3(0.05, 0.05, 0.05), Vector3(door_x + 0.38 * (1.0 if door_on_left else -1.0), 1.05, 0.02), MaterialLibrary.get_material("brass"))

	# Canvas awning over the pavement.
	if has_awning:
		var out := 1.5
		var drop := 0.55
		var slope := sqrt(out * out + drop * drop)
		var tilt := atan2(drop, out)
		var canvas := MaterialLibrary.get_tinted("wood_painted", Color(0.36, 0.33, 0.25))
		var basis := Basis(Vector3.RIGHT, tilt)
		mb.add_box(Vector3(width - 0.4, 0.02, slope), Vector3(width * 0.5, gh - 0.85 - drop * 0.5, out * 0.5), canvas, basis)
		mb.add_box(Vector3(width - 0.4, 0.25, 0.02), Vector3(width * 0.5, gh - 0.85 - drop - 0.12, out), canvas)

	# Gilt sign lettering.
	if shop_name != "":
		var label := Label3D.new()
		label.name = "ShopSign"
		label.text = shop_name
		label.font_size = 72
		label.outline_size = 6
		label.outline_modulate = Color(0.1, 0.07, 0.03)
		label.modulate = Color(0.93, 0.76, 0.42)
		label.shaded = true
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		var est_width := shop_name.length() * 72.0 * 0.62
		label.pixel_size = minf(0.0045, (width - 0.8) / est_width)
		label.position = Vector3(width * 0.5, gh - 0.475, 0.262)
		add_child(label)


func _build_roof(mb: MeshBuilder, body: StaticBody3D, wall: Material, stone: Material) -> void:
	var h := get_facade_height()
	var pitch := deg_to_rad(32.0)
	var rise := depth * 0.5 * tan(pitch)
	var run := depth * 0.5

	# Gable fill (brick) so the roof volume is solid from every side.
	var prism := PrismMesh.new()
	prism.size = Vector3(depth, rise, width)
	mb.add_mesh(prism, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(width * 0.5, h + rise * 0.5, -run)), wall)

	# Two slate slopes with a small overhang.
	var slope_len := sqrt(run * run + rise * rise) + 0.35
	var n_front := Vector3(0.0, run, rise).normalized()
	var down_front := Vector3(0.0, -rise, run).normalized()
	var n_back := Vector3(0.0, run, -rise).normalized()
	var down_back := Vector3(0.0, -rise, -run).normalized()
	var slate := MaterialLibrary.get_for_uv_plane("slate_roof", Vector2(width + 0.1, slope_len))
	var mid_front := Vector3(width * 0.5, h + rise * 0.5, -run * 0.5) + n_front * 0.04 + down_front * 0.175
	var mid_back := Vector3(width * 0.5, h + rise * 0.5, -run * 1.5) + n_back * 0.04 + down_back * 0.175
	mb.add_plane(Vector2(width + 0.1, slope_len), mid_front, slate, Basis(Vector3.RIGHT, n_front, down_front))
	mb.add_plane(Vector2(width + 0.1, slope_len), mid_back, slate, Basis(Vector3.LEFT, n_back, down_back))
	mb.add_box(Vector3(width + 0.1, 0.14, 0.26), Vector3(width * 0.5, h + rise + 0.05, -run), MaterialLibrary.get_tinted("stone_trim", Color(0.35, 0.33, 0.32)))

	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(0.0, h, 0.0), Vector3(0.0, h, -depth), Vector3(0.0, h + rise, -run),
		Vector3(width, h, 0.0), Vector3(width, h, -depth), Vector3(width, h + rise, -run),
	])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.set_meta("surface", "slate") # clattering slates: loud to walk on
	body.add_child(cs)

	# Chimney stacks on the party walls, with clay pots and coal smoke.
	var stacks: Array[float] = [0.45]
	if width > 5.0 and _rng.randf() > 0.35:
		stacks.append(width - 0.45)
	var brick := MaterialLibrary.get_material("brick_red" if wall_material == "brick_yellow" and _rng.randf() > 0.6 else ("brick_yellow" if wall_material == "stucco" else wall_material))
	var pot := MaterialLibrary.get_material("terracotta")
	for sx in stacks:
		var base_y := h + rise - 0.6
		var stack_h := 2.1
		var size := Vector3(0.75, stack_h, 1.5)
		var center := Vector3(sx, base_y + stack_h * 0.5, -run)
		mb.add_box(size, center, brick)
		_add_box_collider(body, size, center)
		mb.add_box(Vector3(0.87, 0.1, 1.62), Vector3(sx, base_y + stack_h + 0.05, -run), stone)
		var pots := 2 + _rng.randi() % 3
		for p in pots:
			var pz := -run - 0.55 + 1.1 * float(p) / float(maxi(pots - 1, 1))
			var pot_h := 0.45 + _rng.randf() * 0.25
			mb.add_cylinder(0.13, 0.1, pot_h, Vector3(sx, base_y + stack_h + 0.1 + pot_h * 0.5, pz), pot, 10)
			if chimney_smoke and p == 0 and _rng.randf() > 0.3:
				var smoke := ChimneySmoke.new()
				smoke.position = Vector3(sx, base_y + stack_h + 0.15 + pot_h, pz)
				add_child(smoke)


func _build_downpipe(mb: MeshBuilder, iron: Material, h: float) -> void:
	var x := width - 0.12 if door_on_left else 0.12
	mb.add_cylinder(0.045, 0.045, h, Vector3(x, h * 0.5, 0.09), iron, 8)
	mb.add_box(Vector3(0.2, 0.22, 0.16), Vector3(x, h - 0.45, 0.1), iron) # hopper head
	mb.add_box(Vector3(width, 0.1, 0.12), Vector3(width * 0.5, h + 0.02, 0.37), iron) # gutter
	# Climbable (layer 5 only): Harry will detect this in Phase 2; it does not block movement.
	var pipe_body := StaticBody3D.new()
	pipe_body.name = "Drainpipe"
	pipe_body.collision_layer = 1 << 4
	pipe_body.collision_mask = 0
	pipe_body.add_to_group("climbable_pipe")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.06
	cyl.height = h
	cs.shape = cyl
	cs.position = Vector3(x, h * 0.5, 0.09)
	pipe_body.add_child(cs)
	add_child(pipe_body)


## A visible projecting ledge that also has collision (for climbing and the camera).
func _add_ledge(mb: MeshBuilder, body: StaticBody3D, size: Vector3, center: Vector3, mat: Material) -> void:
	mb.add_box(size, center, mat)
	_add_box_collider(body, size, center)


func _add_box_collider(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	body.add_child(cs)
