class_name RestrictedZone
extends Area3D
## Private property (yards, gardens, palace grounds). Anyone who sees Harry inside treats
## him as a trespasser, however calmly he walks. Give it a CollisionShape3D child
## (or call set_box()) covering the area.

@export var zone_name: String = "Private property"


func _ready() -> void:
	add_to_group("restricted_zones")
	collision_layer = 1 << 5
	collision_mask = 1 << 1
	monitoring = true
	monitorable = false
	body_entered.connect(func(b: Node) -> void:
		if b is Harry:
			(b as Harry).stealth.enter_restricted(self))
	body_exited.connect(func(b: Node) -> void:
		if b is Harry:
			(b as Harry).stealth.exit_restricted(self))


func set_box(size: Vector3, center: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	add_child(cs)
