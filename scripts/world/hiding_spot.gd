class_name HidingSpot
extends Area3D
## Somewhere Harry can hide while crouched: a haystack, a heap of sacks, under a
## tarpaulin. While he's crouched inside, guards can't see him, but a guard searching
## the area may poke it and find him.

var occupant: Harry = null


func _ready() -> void:
	add_to_group("hiding_spots")
	collision_layer = 1 << 5 # interactable
	collision_mask = 1 << 1 # player
	monitoring = true
	monitorable = false
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(body: Node) -> void:
	if body is Harry:
		occupant = body
		(body as Harry).stealth.hiding_spot = self


func _on_exit(body: Node) -> void:
	if body is Harry:
		if (body as Harry).stealth.hiding_spot == self:
			(body as Harry).stealth.hiding_spot = null
		occupant = null


## True if Harry is actually concealed in here right now.
func is_occupied() -> bool:
	return occupant != null and occupant.stealth.is_hidden() and occupant.stealth.hiding_spot == self
