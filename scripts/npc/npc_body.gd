class_name NPCBody
extends Node3D
## Visible body for any NPC (guards now; crowds, merchants and gentry in later phases).
##
## If `model_path` points to a rigged .glb with Mixamo-style clips (idle, walk, run and
## optionally look_around, alert, stunned, unconscious), it is scaled to `height` and
## animated with an AnimationTree. Otherwise a procedural mannequin is built in the
## silhouette of the chosen period outfit and posed in code.

enum Pose { NORMAL, LOOK_AROUND, ALERT, RATTLE, STUNNED, UNCONSCIOUS, SHOUT, BROWSE }

## Victorian outfits for the stand-in mannequin.
enum Outfit { CONSTABLE, GENTLEMAN, WORKER, LADY, HOUSE_GUARD }

@export_file("*.glb", "*.gltf", "*.tscn") var model_path: String = ""
@export var outfit: Outfit = Outfit.CONSTABLE
@export var height: float = 1.78
@export var model_yaw_offset_degrees: float = 180.0

var pose: Pose = Pose.NORMAL
var head_yaw: float = 0.0

var _has_model := false
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _current := ""
var _clips := {}

# Mannequin parts
var _root_pivot: Node3D
var _hips: Node3D
var _spine: Node3D
var _head: Node3D
var _thigh: Array[Node3D] = []
var _knee: Array[Node3D] = []
var _shoulder: Array[Node3D] = []
var _elbow: Array[Node3D] = []
var _phase := 0.0
var _speed := 0.0
var _down := 0.0
var _t := 0.0
## Mannequin parts waiting to be merged: one mesh per joint, coloured by vertex colour,
## so a whole crowd shares a single material (few draw calls per person).
var _pending := {}
static var _shared_material: StandardMaterial3D


func _ready() -> void:
	if model_path != "" and ResourceLoader.exists(model_path):
		var scene := load(model_path) as PackedScene
		if scene:
			_setup_model(scene.instantiate() as Node3D)
	if not _has_model:
		_build_mannequin()


func is_model() -> bool:
	return _has_model


## Called by the owning NPC every physics frame.
func update_body(speed: float, new_pose: Pose, delta: float) -> void:
	pose = new_pose
	_t += delta
	_speed = lerpf(_speed, speed, 1.0 - exp(-8.0 * delta))
	if _has_model:
		_drive_model()
	else:
		_pose_mannequin(delta)


# ---------------------------------------------------------------------------
# Mannequin
# ---------------------------------------------------------------------------
func _build_mannequin() -> void:
	var s := height / 1.78
	var skin := _mat(Color(0.72, 0.56, 0.46), 0.6)
	var coat: StandardMaterial3D
	var legs: StandardMaterial3D
	var boots := _mat(Color(0.025, 0.022, 0.02), 0.4)
	var accent: StandardMaterial3D
	match outfit:
		Outfit.CONSTABLE:
			coat = _mat(Color(0.05, 0.06, 0.1), 0.85)
			legs = coat
			accent = _mat(Color(0.75, 0.72, 0.65), 0.35) # silver buttons and helmet plate
		Outfit.HOUSE_GUARD:
			coat = _mat(Color(0.2, 0.08, 0.07), 0.85)
			legs = _mat(Color(0.08, 0.08, 0.08), 0.9)
			accent = _mat(Color(0.8, 0.65, 0.3), 0.3)
		Outfit.GENTLEMAN:
			coat = _mat(Color(0.03, 0.03, 0.035), 0.7)
			legs = _mat(Color(0.18, 0.17, 0.16), 0.85)
			accent = _mat(Color(0.85, 0.83, 0.78), 0.6)
		Outfit.WORKER:
			coat = _mat(Color(0.3, 0.22, 0.15), 0.95)
			legs = _mat(Color(0.2, 0.19, 0.17), 0.95)
			accent = _mat(Color(0.5, 0.45, 0.38), 0.9)
		Outfit.LADY:
			coat = _mat(Color(0.2, 0.12, 0.2), 0.8)
			legs = coat
			accent = _mat(Color(0.85, 0.82, 0.76), 0.8)

	_root_pivot = _pivot(self, Vector3.ZERO)
	_root_pivot.scale = Vector3.ONE * s
	_hips = _pivot(_root_pivot, Vector3(0, 0.92, 0))
	_spine = _pivot(_hips, Vector3(0, 0.08, 0))
	_capsule(_spine, 0.19, 0.56, Vector3(0, 0.26, 0), coat)
	if outfit == Outfit.CONSTABLE or outfit == Outfit.HOUSE_GUARD:
		_box(_spine, Vector3(0.42, 0.06, 0.3), Vector3(0, 0.06, 0), _mat(Color(0.02, 0.02, 0.02), 0.5)) # belt
		for i in 5:
			_box(_spine, Vector3(0.025, 0.025, 0.02), Vector3(0, 0.12 + i * 0.09, -0.19), accent) # buttons
	if outfit == Outfit.LADY:
		_cylinder(_hips, 0.2, 0.42, 0.9, Vector3(0, -0.45, 0), coat) # crinoline skirt
	else:
		_box(_hips, Vector3(0.4, 0.45 if outfit != Outfit.WORKER else 0.25, 0.28), Vector3(0, -0.2, 0.01), coat) # coat skirt
	var neck := _pivot(_spine, Vector3(0, 0.54, 0))
	_head = _pivot(neck, Vector3(0, 0.08, 0))
	_capsule(_head, 0.1, 0.25, Vector3(0, 0.06, -0.01), skin)
	match outfit:
		Outfit.CONSTABLE:
			_capsule(_head, 0.12, 0.38, Vector3(0, 0.22, 0.0), coat) # custodian helmet (introduced 1863)
			_box(_head, Vector3(0.07, 0.08, 0.01), Vector3(0, 0.2, -0.12), accent) # helmet plate
		Outfit.GENTLEMAN:
			_cylinder(_head, 0.1, 0.1, 0.2, Vector3(0, 0.25, 0), coat) # top hat
			_cylinder(_head, 0.17, 0.17, 0.015, Vector3(0, 0.16, 0), coat)
		Outfit.WORKER:
			_capsule(_head, 0.115, 0.24, Vector3(0, 0.12, 0), accent, Vector3(90, 0, 0)) # flat cap
		Outfit.HOUSE_GUARD:
			_cylinder(_head, 0.11, 0.11, 0.12, Vector3(0, 0.2, 0), coat) # kepi-style cap
		Outfit.LADY:
			_capsule(_head, 0.13, 0.3, Vector3(0, 0.1, 0.03), accent) # bonnet

	for side in [-1.0, 1.0]:
		var thigh := _pivot(_hips, Vector3(side * 0.1, 0, 0))
		_capsule(thigh, 0.07, 0.48, Vector3(0, -0.22, 0), legs)
		var knee := _pivot(thigh, Vector3(0, -0.44, 0))
		_capsule(knee, 0.06, 0.46, Vector3(0, -0.21, 0), legs)
		_box(knee, Vector3(0.1, 0.08, 0.26), Vector3(0, -0.44, -0.05), boots)
		_thigh.append(thigh)
		_knee.append(knee)
		var shoulder := _pivot(_spine, Vector3(side * 0.22, 0.49, 0))
		_capsule(shoulder, 0.058, 0.36, Vector3(0, -0.16, 0), coat)
		var elbow := _pivot(shoulder, Vector3(0, -0.31, 0))
		_capsule(elbow, 0.05, 0.32, Vector3(0, -0.14, 0), coat)
		_capsule(elbow, 0.042, 0.13, Vector3(0, -0.32, 0), skin)
		_shoulder.append(shoulder)
		_elbow.append(elbow)
	if outfit == Outfit.CONSTABLE:
		# Truncheon at the right hip.
		_cylinder(_hips, 0.018, 0.018, 0.38, Vector3(0.22, -0.1, 0.02), _mat(Color(0.12, 0.07, 0.04), 0.6))
	_flush_parts()


func _pose_mannequin(delta: float) -> void:
	var move := clampf(_speed / 1.4, 0.0, 1.0)
	var run_t := clampf((_speed - 2.0) / 2.5, 0.0, 1.0)
	var stride := lerpf(0.72, 1.6, run_t)
	_phase = fmod(_phase + delta * _speed / (2.0 * stride) * TAU, TAU)
	var leg_amp := deg_to_rad(lerpf(24.0, 45.0, run_t)) * move
	var knee_amp := deg_to_rad(lerpf(35.0, 95.0, run_t)) * move
	var arm_amp := deg_to_rad(lerpf(15.0, 50.0, run_t)) * move
	var target_down := 1.0 if pose == Pose.UNCONSCIOUS else 0.0
	_down = move_toward(_down, target_down, delta * 1.8)
	for i in 2:
		var p := _phase + (PI if i == 1 else 0.0)
		_thigh[i].rotation.x = sin(p) * leg_amp
		_knee[i].rotation.x = -(maxf(0.0, -cos(p)) * knee_amp + deg_to_rad(4.0))
		_shoulder[i].rotation.x = -sin(p) * arm_amp
		_shoulder[i].rotation.z = (1.0 if i == 1 else -1.0) * deg_to_rad(5.0)
		_elbow[i].rotation.x = deg_to_rad(lerpf(10.0, 80.0, run_t))
	_hips.position.y = 0.92 + absf(sin(_phase)) * 0.04 * move
	_spine.rotation.x = -deg_to_rad(lerpf(1.0, 9.0, run_t))
	_head.rotation.y = head_yaw
	_head.rotation.x = 0.0
	match pose:
		Pose.LOOK_AROUND:
			_head.rotation.y = head_yaw + sin(_t * 1.3) * deg_to_rad(55.0)
			_shoulder[1].rotation.x = deg_to_rad(15.0)
		Pose.ALERT:
			# Truncheon drawn, arm raised.
			_shoulder[1].rotation.x = deg_to_rad(95.0)
			_elbow[1].rotation.x = deg_to_rad(60.0)
		Pose.RATTLE:
			# Swinging the police rattle above his head.
			_shoulder[1].rotation.x = deg_to_rad(160.0)
			_shoulder[1].rotation.z = deg_to_rad(20.0) + sin(_t * 18.0) * deg_to_rad(12.0)
		Pose.SHOUT:
			# Pointing and shouting after being robbed.
			_shoulder[1].rotation.x = deg_to_rad(95.0)
			_shoulder[0].rotation.x = deg_to_rad(40.0) + sin(_t * 8.0) * deg_to_rad(10.0)
			_head.rotation.x = -deg_to_rad(8.0)
		Pose.BROWSE:
			# Looking over the goods on a stall.
			_head.rotation.x = deg_to_rad(20.0)
			_spine.rotation.x = -deg_to_rad(8.0)
			_shoulder[1].rotation.x = deg_to_rad(25.0) + sin(_t * 0.7) * deg_to_rad(8.0)
			_elbow[1].rotation.x = deg_to_rad(50.0)
		Pose.STUNNED:
			for i in 2:
				_shoulder[i].rotation.x = deg_to_rad(150.0)
				_elbow[i].rotation.x = deg_to_rad(120.0)
			_spine.rotation.x = deg_to_rad(10.0) + sin(_t * 3.0) * deg_to_rad(6.0)
	# Unconscious: collapse onto his back.
	_root_pivot.rotation.x = _down * deg_to_rad(88.0)
	_root_pivot.position = Vector3(0, _down * 0.12, _down * 0.35)
	if _down > 0.0:
		for i in 2:
			_shoulder[i].rotation.x = lerpf(_shoulder[i].rotation.x, deg_to_rad(20.0), _down)
			_shoulder[i].rotation.z = lerpf(_shoulder[i].rotation.z, (1.0 if i == 1 else -1.0) * deg_to_rad(-40.0), _down)
			_thigh[i].rotation.x = lerpf(_thigh[i].rotation.x, deg_to_rad(8.0 + i * 12.0), _down)
		_head.rotation.y = lerpf(_head.rotation.y, deg_to_rad(35.0), _down)


# ---------------------------------------------------------------------------
# Imported model
# ---------------------------------------------------------------------------
func _setup_model(model: Node3D) -> void:
	if model == null:
		return
	var holder := Node3D.new()
	holder.name = "ModelRoot"
	add_child(holder)
	holder.add_child(model)
	model.rotation_degrees.y = model_yaw_offset_degrees
	var aabb := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != model:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var box := xf * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	if aabb.size.y > 0.01:
		holder.scale = Vector3.ONE * (height / aabb.size.y)
		holder.position.y = -aabb.position.y * holder.scale.y
	_has_model = true
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	var names := player.get_animation_list()
	var wanted := {
		"idle": ["idle"], "walk": ["walk"], "run": ["run"],
		"look_around": ["look_around", "looking around", "look"], "alert": ["alert", "angry", "threat"],
		"stunned": ["stunned", "hit reaction", "dizzy"], "unconscious": ["unconscious", "dying", "death"],
	}
	for key: String in wanted:
		_clips[key] = ""
		for alias: String in wanted[key]:
			for n in names:
				if n.to_lower().contains(alias):
					_clips[key] = n
					break
			if _clips[key] != "":
				break
	for key in ["walk", "run", "look_around", "alert", "stunned", "unconscious"]:
		if _clips[key] == "":
			_clips[key] = _clips["idle"]
	for key in ["idle", "walk", "run", "look_around"]:
		if _clips[key] != "":
			player.get_animation(_clips[key]).loop_mode = Animation.LOOP_LINEAR
	if _clips["unconscious"] != "" and _clips["unconscious"] != _clips["idle"]:
		player.get_animation(_clips["unconscious"]).loop_mode = Animation.LOOP_NONE

	var sm := AnimationNodeStateMachine.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.max_space = 5.0
	loco.add_blend_point(_anim_node("idle"), 0.0, -1, "idle")
	loco.add_blend_point(_anim_node("walk"), 1.4, -1, "walk")
	loco.add_blend_point(_anim_node("run"), 5.0, -1, "run")
	sm.add_node("loco", loco)
	for key in ["look_around", "alert", "stunned", "unconscious"]:
		sm.add_node(key, _anim_node(key))
	var states := ["loco", "look_around", "alert", "stunned", "unconscious"]
	for a: String in states:
		for b: String in states:
			if a != b:
				var t := AnimationNodeStateMachineTransition.new()
				t.xfade_time = 0.25
				sm.add_transition(a, b, t)
	_tree = AnimationTree.new()
	_tree.tree_root = sm
	player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.root_node = _tree.get_path_to(player.get_node(player.root_node))
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_tree.active = true
	_playback = _tree.get("parameters/playback")
	_playback.start("loco")
	_current = "loco"


func _anim_node(key: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = _clips.get(key, "")
	return n


func _drive_model() -> void:
	if _tree == null:
		return
	var target := "loco"
	match pose:
		Pose.LOOK_AROUND:
			target = "look_around"
		Pose.ALERT, Pose.RATTLE:
			target = "alert" if _speed < 0.5 else "loco"
		Pose.STUNNED:
			target = "stunned"
		Pose.UNCONSCIOUS:
			target = "unconscious"
	_tree.set("parameters/loco/blend_position", _speed)
	if target != _current:
		_playback.travel(target)
		_current = target


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _capsule(parent: Node3D, radius: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(h, radius * 2.0)
	mesh.radial_segments = 10
	mesh.rings = 2
	var basis := Basis.from_euler(rot_deg * (PI / 180.0))
	_add_part(parent, mesh, Transform3D(basis, pos), mat)


func _cylinder(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = h
	mesh.radial_segments = 12
	mesh.rings = 1
	_add_part(parent, mesh, Transform3D(Basis.IDENTITY, pos), mat)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_part(parent, mesh, Transform3D(Basis.IDENTITY, pos), mat)


func _add_part(parent: Node3D, mesh: PrimitiveMesh, xform: Transform3D, mat: Material) -> void:
	var color := (mat as StandardMaterial3D).albedo_color if mat is StandardMaterial3D else Color.WHITE
	var arrays := mesh.get_mesh_arrays()
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(color)
	arrays[Mesh.ARRAY_COLOR] = colors
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st: SurfaceTool = _pending.get(parent)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_pending[parent] = st
	st.append_from(tmp, 0, xform)


func _flush_parts() -> void:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.vertex_color_is_srgb = true
		_shared_material.roughness = 0.82
	for parent: Node3D in _pending:
		var st: SurfaceTool = _pending[parent]
		st.set_material(_shared_material)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.visibility_range_end = 150.0
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mi)
	_pending.clear()


static var _mat_cache := {}


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var key := "%s_%.2f" % [c.to_html(), rough]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mat_cache[key] = m
	return m
