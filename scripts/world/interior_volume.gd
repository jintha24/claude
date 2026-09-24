class_name InteriorVolume
extends Node3D
## Marks an indoor space (an axis-aligned box from this node's position, `size` metres).
## Indoors only a little daylight gets in through the windows, so Stealth counts just
## `daylight_factor` of the sky light there. Lamps inside still light Harry up fully.

@export var size: Vector3 = Vector3(10, 4, 10)
## Fraction of outdoor sky light that reaches inside (0 = a cellar or sewer).
@export_range(0.0, 1.0) var daylight_factor: float = 0.3


func _ready() -> void:
	add_to_group("interior_volumes")


func contains(p: Vector3) -> bool:
	var o := global_position
	return p.x >= o.x and p.x <= o.x + size.x and p.y >= o.y and p.y <= o.y + size.y and p.z >= o.z and p.z <= o.z + size.z


## The daylight factor at `p` (1.0 = outdoors).
static func daylight_at(p: Vector3) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	for node in tree.get_nodes_in_group("interior_volumes"):
		var v := node as InteriorVolume
		if v and v.contains(p):
			return v.daylight_factor
	return 1.0
