class_name IronSafe
extends Interactable
## A free-standing Chubb "fire-resisting" iron safe (as in every counting-house and
## gentleman's study of the 1860s), with a Chubb detector lock. The door faces local +Z.
##
## Picking it is possible but unforgiving: one lever lifted too far trips the detector and
## the lock jams until the true key is turned. The key is kept somewhere in the house.
## Once open, E (held) empties it into Harry's bag.

signal opened
signal emptied(items: Array)

@export var safe_name: String = "safe"
@export var levers: int = 5
@export_range(0.05, 0.5) var gate: float = 0.16
@export var key_id: String = ""
## Each entry is an item dictionary {name, value, kind, [key_id]}.
var contents: Array[Dictionary] = []

var lock: LeverLock
var is_open: bool = false
var is_empty: bool = false

var _door_pivot: Node3D
var _door_angle := 0.0


func _ready() -> void:
	interact_range = 1.5
	add_to_group("safes")
	lock = LeverLock.make(levers, gate, key_id, safe_name, true)
	_build()
	if GameState.world.get("safe_" + String(get_path()), false):
		is_open = true
		is_empty = true
		lock.locked = false


func _build() -> void:
	var iron := MaterialLibrary.get_tinted("stone_trim", Color(0.13, 0.16, 0.13))
	var brass := MaterialLibrary.get_material("brass")
	var dark := MaterialLibrary.get_tinted("stone_trim", Color(0.05, 0.05, 0.05))
	var gold := MaterialLibrary.get_material("gilt_letters")
	var body := StaticBody3D.new()
	body.name = "SafeBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.15, 0.7)
	cs.shape = box
	cs.position = Vector3(0, 0.575, -0.35)
	body.add_child(cs)
	var mb := MeshBuilder.new()
	# Body open at the front (+Z), on a plinth, with dark interior and two shelves.
	mb.add_box(Vector3(0.8, 0.08, 0.7), Vector3(0, 0.04, -0.35), iron)
	mb.add_box(Vector3(0.8, 0.07, 0.7), Vector3(0, 1.115, -0.35), iron)
	mb.add_box(Vector3(0.07, 1.15, 0.7), Vector3(-0.365, 0.575, -0.35), iron)
	mb.add_box(Vector3(0.07, 1.15, 0.7), Vector3(0.365, 0.575, -0.35), iron)
	mb.add_box(Vector3(0.8, 1.15, 0.05), Vector3(0, 0.575, -0.675), dark)
	mb.add_box(Vector3(0.66, 0.02, 0.6), Vector3(0, 0.45, -0.35), dark)
	mb.add_box(Vector3(0.66, 0.02, 0.6), Vector3(0, 0.8, -0.35), dark)
	mb.build_into(self, "Body")
	_door_pivot = Node3D.new()
	_door_pivot.name = "DoorPivot"
	_door_pivot.position = Vector3(-0.4, 0.0, 0.0)
	add_child(_door_pivot)
	var db := MeshBuilder.new()
	db.add_box(Vector3(0.8, 1.15, 0.1), Vector3(0.4, 0.575, 0.05), iron)
	db.add_box(Vector3(0.62, 0.95, 0.02), Vector3(0.4, 0.575, 0.105), iron) # raised panel
	db.add_box(Vector3(0.07, 0.11, 0.02), Vector3(0.62, 0.64, 0.12), brass) # keyhole escutcheon
	db.add_cylinder(0.04, 0.04, 0.06, Vector3(0.62, 0.48, 0.14), brass, 10, Basis(Vector3.RIGHT, PI * 0.5))
	db.add_box(Vector3(0.4, 0.05, 0.01), Vector3(0.4, 0.98, 0.12), gold) # "CHUBB & SON"
	db.build_into(_door_pivot, "Door")


func get_interact_point() -> Vector3:
	return global_transform * Vector3(0.2, 0.62, 0.15)


func get_prompt(harry: Harry) -> String:
	if is_open:
		return "" if is_empty else "Empty the %s" % safe_name
	if harry.inventory.has_key(lock.key_id):
		return "Unlock the %s (key)" % safe_name
	if lock.jammed:
		return "Detector tripped - only the key will open it now"
	if harry.inventory.lockpicks <= 0:
		return "Locked - no lockpicks"
	return "Pick the %s lock (%s)" % [safe_name, lock.describe()]


func interact(harry: Harry) -> void:
	if is_open:
		if not is_empty:
			harry.interaction.begin_hold(self, "Emptying the %s" % safe_name, 2.0, func() -> void: _empty(harry))
		return
	if harry.inventory.has_key(lock.key_id):
		lock.locked = false
		lock.jammed = false # the true key resets Chubb's detector
		_open()
		return
	if lock.jammed or harry.inventory.lockpicks <= 0:
		return
	harry.interaction.begin_lockpick(self, lock, _open)


func _open() -> void:
	is_open = true
	Stealth.make_noise(get_interact_point(), 3.0, "safe", true, self)
	opened.emit()


func _empty(harry: Harry) -> void:
	is_empty = true
	GameState.world["safe_" + String(get_path())] = true
	harry.inventory.receive_loot(contents)
	harry.stealth.commit_crime(2.0)
	emptied.emit(contents)


func _process(delta: float) -> void:
	var want := -1.9 if is_open else 0.0
	if not is_equal_approx(_door_angle, want):
		_door_angle = move_toward(_door_angle, want, delta * 1.6)
		_door_pivot.rotation.y = _door_angle
