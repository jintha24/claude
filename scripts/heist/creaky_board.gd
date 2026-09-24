class_name CreakyBoard
extends Area3D
## A loose floorboard. Stepping on it makes it creak: loud when walking or running, barely
## a whisper when creeping slowly (crouched). The old boards are near doorways, on the
## landing and in the passages; a patient thief learns where they are.

@export var size: Vector3 = Vector3(1.0, 0.3, 1.0)
@export var walk_radius: float = 7.0
@export var run_radius: float = 12.0
@export var creep_radius: float = 1.8

var _cooldown := 0.0
var _harry: Harry


func _ready() -> void:
	add_to_group("creaky_boards")
	collision_layer = 1 << 5
	collision_mask = 1 << 1
	monitoring = true
	monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)
	body_entered.connect(func(b: Node) -> void:
		if b is Harry:
			_harry = b as Harry
			_cooldown = 0.0)
	body_exited.connect(func(b: Node) -> void:
		if b == _harry:
			_harry = null)


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _harry == null or _cooldown > 0.0 or not _harry.is_on_floor():
		return
	var speed := _harry.get_horizontal_speed()
	if speed < 0.25:
		return
	_cooldown = 1.1
	var r := walk_radius
	if _harry.is_crouching and speed < 1.2:
		r = creep_radius
	elif speed > (_harry.walk_speed + _harry.run_speed) * 0.5:
		r = run_radius
	Stealth.make_noise(_harry.global_position, r, "creak", true, _harry)
