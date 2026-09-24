class_name WaterVolume
extends Node3D
## A body of standing water in a built place (the Fleet ditch, a flooded cellar): an
## axis-aligned box from this node's position, `size` metres, whose surface is at the
## top. Harry wades through it slowly and noisily, as he does in the hills' lake.

@export var size: Vector3 = Vector3(6, 1.2, 40)


func _ready() -> void:
	add_to_group("water_volumes")


func surface_y() -> float:
	return global_position.y + size.y


func contains_xz(p: Vector3) -> bool:
	var o := global_position
	return p.x >= o.x and p.x <= o.x + size.x and p.z >= o.z and p.z <= o.z + size.z


## How deep the water is over `p` (0 outside, or above the surface).
static func depth_at(tree: SceneTree, p: Vector3) -> float:
	for node in tree.get_nodes_in_group("water_volumes"):
		var w := node as WaterVolume
		if w and w.contains_xz(p) and p.y < w.surface_y() + 0.1 and p.y > w.global_position.y - 0.5:
			return maxf(w.surface_y() - p.y, 0.0)
	return 0.0
