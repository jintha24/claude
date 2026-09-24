class_name MansionWindow
extends Interactable
## A Georgian sash window. The lower sash slides up; Harry climbs through the gap.
##
## Placement: the node sits at the middle of the window sill. Local X runs across the
## opening, local +Z points OUTSIDE. `width` x `height` is the glazed opening.
##
##  * From outside a latched window needs its brass catch slipped with a knife blade
##    (a few seconds' quiet work); from inside you just turn it.
##  * An open window can be climbed through when there's floor (or a roof) to land on
##    within reach on the other side.
##  * Glass blocks bodies and arrows but not sight or light (physics layer 7, "glass").
##  * Guards passing at night notice a window Harry left open.

const LAYER_GLASS := 1 << 6

@export var width: float = 1.1
@export var height: float = 2.2
@export var latched: bool = true
@export var should_stay_closed: bool = true

var is_open: bool = false

var _lower_sash: Node3D
var _glass_shape: CollisionShape3D
var _open_amount := 0.0
var _harry_opened := false
var _noticed := false
var _witness_timer := 0.0


func _ready() -> void:
	interact_range = 1.9
	add_to_group("mansion_windows")
	_build()


func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Glass"
	body.collision_layer = LAYER_GLASS
	body.collision_mask = 0
	add_child(body)
	_glass_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.06)
	_glass_shape.shape = box
	_glass_shape.position = Vector3(0, height * 0.5, 0)
	body.add_child(_glass_shape)

	var paint := MaterialLibrary.get_tinted("wood_painted", Color(0.92, 0.9, 0.84))
	var glass := MaterialLibrary.get_material("glass")
	var brass := MaterialLibrary.get_material("brass")
	var half := height * 0.5
	# Upper sash (fixed) and lower sash (slides), each with glazing bars (3 x 2 panes).
	for i in 2:
		var mb := MeshBuilder.new()
		var z := -0.03 if i == 0 else 0.03
		mb.add_box(Vector3(width, 0.05, 0.05), Vector3(0, 0.025, z), paint)
		mb.add_box(Vector3(width, 0.05, 0.05), Vector3(0, half - 0.025, z), paint)
		mb.add_box(Vector3(0.05, half, 0.05), Vector3(-width * 0.5 + 0.025, half * 0.5, z), paint)
		mb.add_box(Vector3(0.05, half, 0.05), Vector3(width * 0.5 - 0.025, half * 0.5, z), paint)
		for k in 2:
			mb.add_box(Vector3(0.025, half, 0.03), Vector3(-width * 0.5 + width * (k + 1) / 3.0, half * 0.5, z), paint)
		mb.add_box(Vector3(width, 0.025, 0.03), Vector3(0, half * 0.5, z), paint)
		mb.add_box(Vector3(width - 0.06, half - 0.06, 0.008), Vector3(0, half * 0.5, z), glass)
		if i == 1:
			mb.add_box(Vector3(0.08, 0.02, 0.05), Vector3(0, half - 0.01, z + 0.03), brass) # the catch
		var node := Node3D.new()
		node.name = "UpperSash" if i == 0 else "LowerSash"
		node.position = Vector3(0, half if i == 0 else 0.0, 0)
		add_child(node)
		var mi := mb.build_into(node, "Mesh")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i == 1:
			_lower_sash = node


func get_interact_point() -> Vector3:
	return global_transform * Vector3(0.0, 0.5, 0.0)


func get_prompt(harry: Harry) -> String:
	var outside := _side_of(harry.global_position) > 0.0
	if not is_open:
		if latched:
			return "Slip the sash catch" if outside else "Unfasten the catch"
		return "Raise the sash"
	if is_nan(_landing(harry).y):
		return ""
	return "Climb in through the window" if outside else "Climb out through the window"


func interact(harry: Harry) -> void:
	var outside := _side_of(harry.global_position) > 0.0
	if not is_open:
		if latched:
			if outside:
				harry.interaction.begin_hold(self, "Slipping the catch", 3.0, func() -> void:
					latched = false
					_raise(true), 1.5)
			else:
				harry.interaction.begin_hold(self, "Unfastening the catch", 0.6, func() -> void:
					latched = false
					_raise(true))
		else:
			harry.interaction.begin_hold(self, "Raising the sash", 0.8, func() -> void: _raise(true))
		return
	var dest := _landing(harry)
	if is_nan(dest.y):
		return
	harry.interaction.begin_traverse(self, dest, 1.1, Callable(), true)


## Opens the lower sash (by Harry, or by a mission script).
func _raise(by_harry: bool) -> void:
	is_open = true
	_harry_opened = by_harry
	_noticed = false
	_glass_shape.set_deferred("disabled", true)
	Stealth.make_noise(get_interact_point(), 2.5, "window", by_harry, self)


func close_window() -> void:
	is_open = false
	_harry_opened = false
	_glass_shape.set_deferred("disabled", false)


func _side_of(p: Vector3) -> float:
	var local := global_transform.affine_inverse() * p
	return 1.0 if local.z >= 0.0 else -1.0


## Where Harry lands on the other side: floor found below a point 0.7 m beyond the sill,
## no more than 1.7 m below it or 0.3 m above. NAN y = nowhere to stand.
func _landing(harry: Harry) -> Vector3:
	var side := _side_of(harry.global_position)
	var across := global_transform.basis.z.normalized() * -side
	var probe := global_position + across * 0.7 + Vector3.UP * 0.4
	var q := PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * 2.2, 1 | (1 << 3), [harry.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3(0, NAN, 0)
	var p: Vector3 = hit["position"]
	if p.y < global_position.y - 1.7 or p.y > global_position.y + 0.5:
		return Vector3(0, NAN, 0)
	return p + Vector3.UP * 0.05


func _physics_process(delta: float) -> void:
	var want := 1.0 if is_open else 0.0
	if not is_equal_approx(_open_amount, want):
		_open_amount = move_toward(_open_amount, want, delta * 1.5)
		_lower_sash.position.y = _open_amount * height * 0.45
	var h := GameClock.hours()
	var night := h >= 19.0 or h < 7.0 # by day an open window is nothing unusual
	if _harry_opened and should_stay_closed and not _noticed and night:
		_witness_timer -= delta
		if _witness_timer <= 0.0:
			_witness_timer = 0.6
			var g := Guard.find_witness(get_interact_point(), 10.0)
			if g:
				_noticed = true
				g.notice_disturbance(global_position, "That window was shut an hour ago...", false)
