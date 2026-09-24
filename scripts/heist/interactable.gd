class_name Interactable
extends Node3D
## Base class for anything Harry can use with E (interact): doors, windows, valuables,
## safes, drain covers. HarryInteraction finds the nearest one he's facing and shows its
## prompt; pressing E calls interact().
##
## Subclasses override get_prompt() (return "" when there's nothing to do right now) and
## interact(). Long actions (lifting a painting from its frame, picking a lock) are run by
## HarryInteraction through begin_hold() / begin_lockpick() / begin_traverse().

## How close (m, from Harry's chest to get_interact_point()) Harry must be.
@export var interact_range: float = 1.5


func _enter_tree() -> void:
	add_to_group("interactables")


## Text after "[E] ", or "" if Harry can't use this right now.
func get_prompt(_harry: Harry) -> String:
	return ""


## Where Harry's hands go (and what range is measured to).
func get_interact_point() -> Vector3:
	return global_position


func interact(_harry: Harry) -> void:
	pass
