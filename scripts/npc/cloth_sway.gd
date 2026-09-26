class_name ClothSway
extends Node3D
## Hanging cloth that swings: a lady's skirt (RealPeople), hung from the hips.
## It trails behind as its wearer goes, swings out on a turn and settles back with a
## little bounce when they stop: a damped spring driven by how the waist moves. Cheap
## enough for a whole street (no cloth simulation); stepped by the owner (`step`).

## How far it trails per m/s (radians), and at most.
@export var drag := 0.07
@export var max_angle := 0.45
## Spring stiffness (rad/s) and damping ratio.
@export var stiffness := 9.0
@export var damping := 0.35

var _prev := Vector3.INF
var _angle := Vector2.ZERO
var _spin := Vector2.ZERO


func step(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree():
		return
	var p := global_position
	if _prev == Vector3.INF or p.distance_to(_prev) > 2.0:
		# First step, or teleported: hang straight.
		_prev = p
		_angle = Vector2.ZERO
		_spin = Vector2.ZERO
		rotation = Vector3.ZERO
		return
	var v := (p - _prev) / delta
	_prev = p
	v = v.limit_length(10.0)
	# The move in the cloth's own frame (it faces -Z like its wearer; no tilt from the
	# swing itself).
	var local := (get_parent() as Node3D).global_basis.orthonormalized().inverse() * v if get_parent() is Node3D else v
	# Going forward (-Z) the hem trails back (+Z): a negative turn about X. Sideways,
	# about Z.
	var target := Vector2(clampf(local.z * drag, -max_angle, max_angle), clampf(-local.x * drag, -max_angle, max_angle))
	var accel := (target - _angle) * stiffness * stiffness - _spin * 2.0 * damping * stiffness
	_spin += accel * delta
	_angle += _spin * delta
	_angle = _angle.clampf(-max_angle * 1.3, max_angle * 1.3)
	rotation = Vector3(_angle.x, 0.0, _angle.y)
