extends Node3D
## Root of the Phase 1 test scene. Places Harry at the street's spawn point.
## Later phases replace this with the world streaming manager (Phase 8).


func _ready() -> void:
	var street := $LondonStreet as LondonStreet
	var harry := $Harry as Harry
	harry.set_spawn(street.get_spawn_transform())
