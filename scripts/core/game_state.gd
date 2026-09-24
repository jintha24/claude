class_name GameState
extends RefCounted
## What carries over when Harry travels between London and the hills (and, in Phase 9,
## what goes into a save file): his purse, loot, keys, lockpicks, arrows and health, the
## camp stash, and where he should appear in the next place.

## Harry's belongings and condition (empty until first captured).
static var player: Dictionary = {}
## Loot left in the camp chest in the cave.
static var stash: Array[Dictionary] = []
## Name of the spawn point (a node in group "spawn_points") to use in the next scene.
static var spawn_at: String = ""
## Whether Harry arrived on horseback (Cinder comes with him).
static var arrived_mounted: bool = false


static func capture(h: Harry) -> void:
	var items: Array = []
	for it in h.inventory.items:
		items.append(it.duplicate())
	player = {
		"money": h.inventory.money,
		"items": items,
		"lockpicks": h.inventory.lockpicks,
		"arrows": {"blunt": h.combat.blunt_arrows, "whistle": h.combat.whistle_arrows, "broadhead": h.combat.broadhead_arrows},
		"health": h.health,
	}


static func restore(h: Harry) -> void:
	if player.is_empty():
		return
	h.inventory.money = int(player.get("money", 0))
	h.inventory.items.clear()
	for it: Dictionary in player.get("items", []):
		h.inventory.items.append(it.duplicate())
	h.inventory.lockpicks = int(player.get("lockpicks", 6))
	var arrows: Dictionary = player.get("arrows", {})
	h.combat.blunt_arrows = int(arrows.get("blunt", h.combat.blunt_arrows))
	h.combat.whistle_arrows = int(arrows.get("whistle", h.combat.whistle_arrows))
	h.combat.broadhead_arrows = int(arrows.get("broadhead", h.combat.broadhead_arrows))
	h.health = clampf(float(player.get("health", h.max_health)), 1.0, h.max_health)
	h.inventory.money_changed.emit(h.inventory.money)


## Finds the spawn point named `spawn_at` in the current scene, or null.
static func find_spawn(tree: SceneTree) -> Node3D:
	if spawn_at == "":
		return null
	for n in tree.get_nodes_in_group("spawn_points"):
		if n.name == spawn_at:
			return n as Node3D
	return null
