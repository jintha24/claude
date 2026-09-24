class_name CampChest
extends Interactable
## The iron-bound chest at the back of the cave: loot left here is safe (GameState.stash)
## until it's fenced or given away (Phase 9). Keys stay in Harry's pocket.


func _ready() -> void:
	interact_range = 1.8


func _carried(harry: Harry) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in harry.inventory.items:
		if it.get("kind", "") != "key":
			out.append(it)
	return out


func get_prompt(harry: Harry) -> String:
	var n := _carried(harry).size()
	if n > 0:
		return "Stash your loot in the chest (%d)" % n
	if not GameState.stash.is_empty():
		return "Take your loot from the chest (%d)" % GameState.stash.size()
	return ""


func interact(harry: Harry) -> void:
	var carried := _carried(harry)
	if not carried.is_empty():
		for it in carried:
			harry.inventory.remove_item(it)
			GameState.stash.append(it)
		return
	for it in GameState.stash:
		harry.inventory.add_item(it)
	GameState.stash.clear()
