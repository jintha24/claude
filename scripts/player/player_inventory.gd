class_name PlayerInventory
extends Node
## Harry's purse and stolen goods. Child node "Inventory" of Harry.
## Coins go straight into `money` (pence). Valuables are kept as items until they're sold
## to a fence or given away through Father Bernard (Phase 9). Saved with the game (Phase 9).

signal money_changed(pence: int)
signal item_added(item: Dictionary)
signal item_removed(item: Dictionary)
## Fired for every theft so the Legend system (Phase 9) can judge who was robbed.
signal stolen(victim_class: String, value: int)
signal lockpicks_changed(count: int)

var money: int = 0
var items: Array[Dictionary] = []
## Bent-wire picks and a tension wrench. One can snap when a lever slips.
var lockpicks: int = 6
@export var max_lockpicks: int = 12


func add_money(pence: int) -> void:
	money = maxi(money + pence, 0)
	money_changed.emit(money)


func add_item(item: Dictionary) -> void:
	items.append(item)
	item_added.emit(item)


func remove_item(item: Dictionary) -> void:
	items.erase(item)
	item_removed.emit(item)


## Takes loot from a pocket: coins to the purse, valuables into the bag.
func receive_loot(loot: Array[Dictionary]) -> void:
	for item in loot:
		stolen.emit(item.get("victim_class", ""), int(item["value"]))
		if item["kind"] == "coins":
			add_money(int(item["value"]))
		else:
			add_item(item)


func add_lockpicks(n: int) -> void:
	lockpicks = clampi(lockpicks + n, 0, max_lockpicks)
	lockpicks_changed.emit(lockpicks)


## True if Harry carries the key with this id (keys are items of kind "key").
func has_key(key_id: String) -> bool:
	if key_id == "":
		return false
	for i in items:
		if i.get("kind", "") == "key" and i.get("key_id", "") == key_id:
			return true
	return false


func count_kind(kind: String) -> int:
	var n := 0
	for i in items:
		if i.get("kind", "") == kind:
			n += 1
	return n


## Total worth of the stolen goods (keys and papers are worth nothing to a fence).
func total_value() -> int:
	var v := 0
	for i in items:
		v += int(i["value"])
	return v
