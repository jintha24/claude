class_name AnimalBody
extends Node3D
## An animal's visible body: the sculpted model (AnimalLook) walked by QuadrupedRig, with
## tack where it's needed (a riding horse's saddle and bridle, a cab horse's collar). The
## owner (Horse, WildAnimal, the dogs, livestock...) moves the animal and calls
## `update_body` every frame with its speed; poses ease in and out by `want`.
##
## Faces -Z like everything else. Far away it is stepped less often (it can't be seen to).

@export var species := "horse"
@export var variation_seed := 0
## Coat index (AnimalLook.COATS), -1 = picked by the seed.
@export var coat := -1
## Size relative to the model (a pony 0.85, a big cart horse 1.1).
@export var size := 1.0
## Tack: "" none, "saddle" (riding), "harness" (between the shafts).
@export var tack := ""

## Gait speeds (m/s) per species: [walk->trot, trot->canter, canter->gallop, bounding].
const GAIT_SPEEDS := {
	"horse": [2.0, 4.8, 8.5, false], "deer": [1.8, 3.6, 6.0, false], "stag": [1.8, 3.6, 6.0, false],
	"fox": [0.9, 2.6, 4.5, false], "rabbit": [0.3, 1.0, 2.0, true], "dog": [1.3, 3.0, 5.0, false],
	"mastiff": [1.3, 3.0, 5.0, false], "sheep": [1.0, 2.6, 4.0, false], "cow": [1.4, 3.2, 5.5, false],
}

var rig: QuadrupedRig
var look: Node3D
var _want := {}
var _rate := {}
var _accum := 0.0
var _frame := 0
var _prev_yaw := INF


func _ready() -> void:
	look = AnimalLook.instantiate(species, variation_seed, coat)
	if look == null:
		return
	look.scale = Vector3.ONE * size
	add_child(look)
	var sk := look.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	rig = QuadrupedRig.new()
	if not rig.setup(sk[0] as Skeleton3D, variation_seed):
		rig = null
		return
	var g: Array = GAIT_SPEEDS.get(species, [2.0, 4.8, 8.5, false])
	rig.trot_at = g[0] * size
	rig.canter_at = g[1] * size
	rig.gallop_at = g[2] * size
	rig.bounding = g[3]
	if species in ["sheep", "cow"]:
		rig.run_gait = "canter"
	if tack != "":
		_add_tack(sk[0] as Skeleton3D)
	rig.update(0.0)


## True when there is a real body (the model exists).
func is_ok() -> bool:
	return rig != null


## Eases a pose towards `value` (0..1) at `rate` per second: "graze", "alert", "lie",
## "dead", "jump", "rear", "sit".
func want(pose: String, value: float, rate: float = 2.0) -> void:
	_want[pose] = value
	_rate[pose] = rate


## Where the head looks: yaw (radians, + left) and pitch (+ down), relative to the body.
func look_at_angle(yaw: float, pitch: float = 0.0) -> void:
	if rig:
		rig.look_yaw = yaw
		rig.look_pitch = pitch


## Moves the legs for `speed` (m/s, forward +) turning at `turn` (rad/s, + left), and
## steps the poses. `yaw` (optional) lets the turn rate be worked out here instead.
func update_body(delta: float, speed: float, turn: float = 0.0, yaw: float = INF) -> void:
	if rig == null:
		return
	if yaw != INF:
		if _prev_yaw != INF and delta > 0.0:
			turn = wrapf(yaw - _prev_yaw, -PI, PI) / delta
		_prev_yaw = yaw
	# Far off, a few times a second is plenty.
	_frame += 1
	_accum += delta
	var every := 1
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		var d := cam.global_position.distance_to(global_position)
		every = 1 if d < 35.0 else (2 if d < 70.0 else 4)
	if not is_visible_in_tree():
		every = 8
	if _frame % every != 0:
		return
	var dt := _accum
	_accum = 0.0
	rig.speed = speed / maxf(size, 0.1)
	rig.turn = turn
	for p: String in _want:
		rig.set(p, move_toward(float(rig.get(p)), _want[p], dt * _rate[p]))
	rig.update(dt)


func _add_tack(sk: Skeleton3D) -> void:
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.2, 0.11, 0.05)
	leather.roughness = 0.45
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.25, 0.07, 0.06)
	cloth.roughness = 0.9
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.56, 0.3)
	brass.metallic = 1.0
	brass.roughness = 0.35
	var back := sk.find_bone("spine")
	var chest := sk.find_bone("chest")
	var head := sk.find_bone("head")
	var neck := sk.find_bone("neck1")
	var top := _top_of_back(sk)
	if tack == "saddle" and back >= 0:
		var mb := MeshBuilder.new()
		# Saddle cloth, the seat with its pommel and cantle, girth and stirrups.
		mb.add_box(Vector3(0.72, 0.03, 0.7), Vector3(0, top - 0.02, -0.12), cloth)
		mb.add_box(Vector3(0.44, 0.09, 0.56), Vector3(0, top + 0.03, -0.12), leather)
		mb.add_box(Vector3(0.14, 0.12, 0.1), Vector3(0, top + 0.1, -0.38), leather)
		mb.add_box(Vector3(0.36, 0.1, 0.06), Vector3(0, top + 0.09, 0.14), leather)
		mb.add_box(Vector3(0.7, 0.07, 0.09), Vector3(0, top - 0.34, -0.3), leather, Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 1.0)))
		for side: float in [-1.0, 1.0]:
			mb.add_box(Vector3(0.02, 0.42, 0.035), Vector3(side * 0.3, top - 0.2, -0.12), leather)
			mb.add_box(Vector3(0.09, 0.02, 0.05), Vector3(side * 0.31, top - 0.42, -0.12), brass)
		_attach(sk, back, mb.build())
	if tack == "harness" and neck >= 0:
		# A heavy collar round the base of the neck, and the saddle pad the shafts hang from.
		var mb := MeshBuilder.new()
		var collar := TorusMesh.new()
		collar.inner_radius = 0.2
		collar.outer_radius = 0.3
		var n1: Vector3 = sk.get_bone_global_rest(neck).origin
		mb.add_mesh(collar, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-55.0)).scaled(Vector3(0.9, 1.0, 1.25)), n1 + Vector3(0, 0.05, 0.0)), leather)
		mb.add_box(Vector3(0.08, 0.28, 0.05), n1 + Vector3(-0.29, -0.05, 0.02), brass)
		mb.add_box(Vector3(0.08, 0.28, 0.05), n1 + Vector3(0.29, -0.05, 0.02), brass)
		_attach(sk, neck, mb.build())
		if back >= 0:
			var pb := MeshBuilder.new()
			pb.add_box(Vector3(0.5, 0.08, 0.3), Vector3(0, top + 0.01, -0.2), leather)
			pb.add_box(Vector3(0.72, 0.07, 0.08), Vector3(0, top - 0.33, -0.2), leather)
			_attach(sk, back, pb.build())
	if head >= 0 and tack != "":
		# Bridle: headpiece, browband, noseband and the reins back to the withers.
		var hb := MeshBuilder.new()
		var hp: Vector3 = sk.get_bone_global_rest(head).origin
		hb.add_box(Vector3(0.23, 0.025, 0.03), hp + Vector3(0, -0.03, -0.04), leather)
		hb.add_box(Vector3(0.2, 0.025, 0.02), hp + Vector3(0, -0.07, -0.18), leather)
		hb.add_box(Vector3(0.16, 0.03, 0.14), hp + Vector3(0, -0.33, -0.34), leather, Basis(Vector3.RIGHT, 0.7))
		for side: float in [-1.0, 1.0]:
			hb.add_box(Vector3(0.015, 0.36, 0.02), hp + Vector3(side * 0.1, -0.2, -0.2), leather, Basis(Vector3.RIGHT, 0.65))
			hb.add_box(Vector3(0.035, 0.035, 0.035), hp + Vector3(side * 0.07, -0.37, -0.42), brass)
		_attach(sk, head, hb.build())
		if chest >= 0 and tack == "saddle":
			var rb := MeshBuilder.new()
			var from := hp + Vector3(0, -0.37, -0.42)
			var to := Vector3(0, top + 0.12, -0.45)
			var mid := (from + to) * 0.5 + Vector3(0, -0.12, 0)
			for side: float in [-1.0, 1.0]:
				for seg: Array in [[from, mid], [mid, to]]:
					var a: Vector3 = seg[0] + Vector3(side * 0.07, 0, 0)
					var b: Vector3 = seg[1] + Vector3(side * 0.1, 0, 0)
					var len := a.distance_to(b)
					var basis := Basis.looking_at((b - a).normalized(), Vector3.UP)
					rb.add_box(Vector3(0.012, 0.012, len), (a + b) * 0.5, leather, basis)
			_attach(sk, chest, rb.build())


## The height of the back where a saddle sits.
func _top_of_back(sk: Skeleton3D) -> float:
	var s := sk.find_bone("spine")
	var c := sk.find_bone("chest")
	var y := 0.0
	if s >= 0:
		y = sk.get_bone_global_rest(s).origin.y
	if c >= 0:
		y = maxf(y, sk.get_bone_global_rest(c).origin.y)
	# The bones run along the spine; the back is a little above.
	return y + 0.17 * (y / 1.45)


func _attach(sk: Skeleton3D, bone: int, mesh: Mesh) -> void:
	var ba := BoneAttachment3D.new()
	ba.bone_idx = bone
	sk.add_child(ba)
	var mi := MeshInstance3D.new()
	mi.name = "Tack"
	mi.mesh = mesh
	mi.visibility_range_end = 160.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	ba.add_child(mi)
	# The skeleton's bones rest axis-aligned: only their position to take off.
	mi.position = -sk.get_bone_global_rest(bone).origin
