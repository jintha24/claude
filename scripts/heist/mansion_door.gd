class_name MansionDoor
extends Interactable
## A hinged, panelled interior or exterior door.
##
## Placement: the node sits at the middle of the doorway threshold. Local X runs across
## the opening, local +Z is the "outside" (or corridor) side. The leaf is hinged at -X and
## always swings away from whoever opens it.
##
##  * Harry opens and closes doors with E. A locked door needs its key, or the lock picked
##    (LeverLock). From the inside (-Z) a locked outer door just needs the key turned or the
##    bolt drawn, if `opens_freely_from_inside`.
##  * Guards and servants carry keys: they open any door in their way and it swings shut
##    behind them (locked doors stay locked).
##  * A door Harry leaves open that should be shut makes a passing guard suspicious.
##  * Closed doors block sight and light (physics layer 8, "doors"), open ones don't.

const LAYER_DOORS := 1 << 7
const OPEN_ANGLE := deg_to_rad(100.0)

@export var door_name: String = "door"
@export var width: float = 1.1
@export var height: float = 2.5
@export var thickness: float = 0.06
@export var start_open: bool = false
## 0 = no lock. Otherwise the number of levers to pick (3 is an ordinary house lock).
@export var lock_levers: int = 0
@export_range(0.05, 0.5) var lock_gate: float = 0.22
@export var key_id: String = ""
## Outer doors: from the inside there's a key in the lock or a bolt to draw.
@export var opens_freely_from_inside: bool = true
## Guards notice this door standing open if Harry left it so.
@export var should_stay_closed: bool = true
@export var leaf_color: Color = Color(0.22, 0.12, 0.07)
## A wrought-iron gate leaf: bars you can see (and shoot) through.
@export var iron_gate: bool = false
## Which way a door that starts open is swung (+1 = towards local -Z).
@export var start_swing: float = 1.0
## False for a gate leaf that's bolted to the ground from inside (only its partner opens).
@export var harry_can_use: bool = true

var lock: LeverLock = null
var is_open: bool = false
## -1..1: current swing (fraction of OPEN_ANGLE, sign = direction).
var swing: float = 0.0

var _target_swing := 0.0
var _hinge: Node3D
var _leaf: AnimatableBody3D
var _npc_opened := false
var _harry_opened := false
var _npc_timer := 0.0
var _close_timer := 0.0
var _witness_timer := 0.0
var _noticed := false


func _ready() -> void:
	interact_range = 1.6
	add_to_group("mansion_doors")
	if lock_levers > 0:
		lock = LeverLock.make(lock_levers, lock_gate, key_id, door_name)
	_build()
	if start_open:
		_target_swing = signf(start_swing)
		swing = _target_swing
		is_open = true
		_apply_swing()


func _build() -> void:
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.position = Vector3(-width * 0.5, 0.0, 0.0)
	add_child(_hinge)
	_leaf = AnimatableBody3D.new()
	_leaf.name = "Leaf"
	_leaf.collision_layer = MansionWindow.LAYER_GLASS if iron_gate else LAYER_DOORS
	_leaf.collision_mask = 0
	_leaf.sync_to_physics = false
	_leaf.set_meta("surface", "wood")
	_hinge.add_child(_leaf)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width - 0.02, height - 0.02, thickness)
	cs.shape = box
	cs.position = Vector3(width * 0.5, height * 0.5, 0.0)
	_leaf.add_child(cs)

	if iron_gate:
		_build_gate_mesh()
		return
	var mb := MeshBuilder.new()
	var wood := MaterialLibrary.get_tinted("wood_painted", leaf_color)
	var brass := MaterialLibrary.get_material("brass")
	mb.add_box(Vector3(width - 0.02, height - 0.02, thickness), Vector3(width * 0.5, height * 0.5, 0.0), wood)
	# Six raised fielded panels, both faces.
	var pw := (width - 0.3) * 0.5
	for side: float in [-1.0, 1.0]:
		for col in 2:
			for row in 3:
				var ph := [0.45, 0.8, 0.8][row] as float
				var py := [0.25, 0.85, 1.8][row] as float
				py = py * height / 2.5
				ph = ph * height / 2.5
				var px := 0.1 + pw * 0.5 + col * (pw + 0.1)
				mb.add_box(Vector3(pw, ph, 0.012), Vector3(px, py + ph * 0.5, side * (thickness * 0.5 + 0.006)), wood)
		# Brass knob and escutcheon.
		mb.add_cylinder(0.03, 0.03, 0.06, Vector3(width - 0.1, 1.0, side * (thickness * 0.5 + 0.04)), brass, 10, Basis(Vector3.RIGHT, PI * 0.5))
		if lock_levers > 0:
			mb.add_box(Vector3(0.03, 0.06, 0.01), Vector3(width - 0.1, 0.88, side * (thickness * 0.5 + 0.006)), brass)
	mb.build_into(_leaf, "LeafMesh")


func _build_gate_mesh() -> void:
	var mb := MeshBuilder.new()
	var iron := MaterialLibrary.get_material("iron")
	var gilt := MaterialLibrary.get_material("gilt")
	for y: float in [0.12, 1.1, height - 0.1]:
		mb.add_box(Vector3(width - 0.04, 0.05, 0.04), Vector3(width * 0.5, y, 0.0), iron)
	mb.add_box(Vector3(0.07, height, 0.06), Vector3(0.035, height * 0.5, 0.0), iron) # hanging stile
	mb.add_box(Vector3(0.05, height, 0.05), Vector3(width - 0.03, height * 0.5, 0.0), iron)
	var n := int(width / 0.13)
	for i in n:
		var x := 0.1 + i * (width - 0.14) / maxf(n - 1, 1)
		mb.add_cylinder(0.013, 0.013, height + 0.2, Vector3(x, (height + 0.2) * 0.5, 0.0), iron, 6)
		mb.add_cylinder(0.0, 0.03, 0.12, Vector3(x, height + 0.26, 0.0), gilt, 6) # spear heads
	mb.build_into(_leaf, "GateMesh")


# ---------------------------------------------------------------------------
# Interactable
# ---------------------------------------------------------------------------
func get_interact_point() -> Vector3:
	return global_transform * Vector3(0.0, 1.1, 0.0)


func get_prompt(harry: Harry) -> String:
	if not harry_can_use:
		return ""
	if is_open or absf(swing) > 0.05:
		return "Close the %s" % door_name
	if lock and lock.locked:
		if harry.inventory.has_key(lock.key_id):
			return "Unlock the %s (key)" % door_name
		if opens_freely_from_inside and _side_of(harry.global_position) < 0.0:
			return "Unbolt the %s" % door_name
		if lock.jammed:
			return "The lock is jammed"
		if harry.inventory.lockpicks <= 0:
			return "Locked - no lockpicks"
		return "Pick the lock (%s)" % lock.describe()
	return "Open the %s" % door_name


func interact(harry: Harry) -> void:
	if not harry_can_use:
		return
	if is_open or absf(swing) > 0.05:
		close()
		return
	if lock and lock.locked:
		if harry.inventory.has_key(lock.key_id) or (opens_freely_from_inside and _side_of(harry.global_position) < 0.0):
			lock.locked = false
			lock.jammed = false
			open_from(harry.global_position, true)
			return
		if lock.jammed or harry.inventory.lockpicks <= 0:
			return
		harry.interaction.begin_lockpick(self, lock, func() -> void:
			Stealth.make_noise(get_interact_point(), 2.0, "lock", true, harry))
		return
	open_from(harry.global_position, true)


# ---------------------------------------------------------------------------
# Opening and closing
# ---------------------------------------------------------------------------
func is_locked() -> bool:
	return lock != null and lock.locked


## Shut and lock (night-time rounds), or unlock (morning).
func set_locked(on: bool) -> void:
	if on and (is_open or absf(swing) > 0.05):
		close()
	if lock:
		lock.locked = on
		if not on:
			lock.jammed = false


## Swing the door open away from `from_pos`. `auto_close`: it swings shut again once
## nobody is near (doors guards open on their way through).
func open_from(from_pos: Vector3, by_harry: bool = false, auto_close: bool = false) -> void:
	var side := _side_of(from_pos)
	_target_swing = 1.0 if side >= 0.0 else -1.0
	is_open = true
	_harry_opened = by_harry
	_npc_opened = auto_close
	_noticed = false
	Stealth.make_noise(get_interact_point(), 3.0 if by_harry else 2.0, "door", by_harry, self)


func close() -> void:
	_target_swing = 0.0
	is_open = false
	_harry_opened = false
	_npc_opened = false
	Stealth.make_noise(get_interact_point(), 3.5, "door", false, self)


## Which side of the doorway `p` is on: + = outside (+Z), - = inside.
func _side_of(p: Vector3) -> float:
	var local := global_transform.affine_inverse() * p
	return 1.0 if local.z >= 0.0 else -1.0


func _physics_process(delta: float) -> void:
	if not is_equal_approx(swing, _target_swing):
		swing = move_toward(swing, _target_swing, delta * 1.3)
		_apply_swing()
	_npc_timer -= delta
	if _npc_timer <= 0.0:
		_npc_timer = 0.15
		_update_npcs()
	if _harry_opened and should_stay_closed and not _noticed:
		_witness_timer -= delta
		if _witness_timer <= 0.0:
			_witness_timer = 0.5
			var g := Guard.find_witness(get_interact_point(), 12.0, [_leaf.get_rid()])
			if g:
				_noticed = true
				g.notice_disturbance(global_position, "Who left this door open?", false)
				# He'll shut it behind him when he's been through.
				_harry_opened = false
				_npc_opened = true
				_close_timer = 8.0


func _apply_swing() -> void:
	# Positive swing turns the leaf towards -Z (away from someone on the + side).
	_hinge.rotation.y = swing * OPEN_ANGLE


## Guards and servants open doors in their path and let them swing shut behind them.
func _update_npcs() -> void:
	var here := global_position
	var nearest: Node3D = null
	var nearest_d := INF
	for group: String in ["guards", "servants"]:
		for node in get_tree().get_nodes_in_group(group):
			var n := node as Node3D
			if n == null:
				continue
			if n is Guard and (n as Guard).is_down():
				continue
			var dy := absf(n.global_position.y - here.y)
			if dy > 1.5:
				continue
			var d := Vector2(n.global_position.x - here.x, n.global_position.z - here.z).length()
			if d < nearest_d:
				nearest_d = d
				nearest = n
	if nearest and nearest_d < 1.7:
		if not is_open:
			open_from(nearest.global_position, false, true)
		_close_timer = 2.0
	elif _npc_opened and is_open:
		_close_timer -= 0.15
		if _close_timer <= 0.0 and nearest_d > 1.9 and not _harry_near(1.3):
			close()


func _harry_near(r: float) -> bool:
	var h := get_tree().get_first_node_in_group("player") as Node3D
	return h != null and h.global_position.distance_to(global_position) < r
