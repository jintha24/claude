class_name Upgrades
extends RefCounted
## Things Harry can buy with stolen money (from T. Wren, Ironmonger, and for the camp).
## Prices are in pence (£1 = 240d). Effects are applied to Harry (and Cinder) whenever
## they're bought or a game is loaded: see apply().

const CATALOG := {
	"picks": {"name": "Set of Chubb-pattern picks", "price": 360, "desc": "Lock gates 30% wider.", "kind": "gear"},
	"boots": {"name": "Soft-soled boots", "price": 480, "desc": "Footsteps 25% quieter.", "kind": "gear"},
	"coat": {"name": "Dark worsted greatcoat", "price": 600, "desc": "15% harder to see in the shadows.", "kind": "gear"},
	"gloves": {"name": "Pickpocket's kid gloves", "price": 300, "desc": "A 25% wider sweet spot for picking pockets.", "kind": "gear"},
	"bow": {"name": "Yew war-bow", "price": 960, "desc": "Draws in 0.7 s and shoots farther.", "kind": "gear"},
	"quiver": {"name": "Large quiver", "price": 240, "desc": "Carry 30 of each kind of arrow.", "kind": "gear"},
	"camp_paddock": {"name": "A paddock for Cinder", "price": 600, "desc": "Cinder gets his wind back twice as fast.", "kind": "camp"},
	"camp_smokehouse": {"name": "A smokehouse", "price": 720, "desc": "Smoked venison and fish fetch twice the price.", "kind": "camp"},
	"camp_bunks": {"name": "Bunks and a stove", "price": 1200, "desc": "Room for the Lantern Men. Sleep heals and restores your picks.", "kind": "camp"},
}

## Supplies for sale by the piece: [name, price each (d), max you can carry].
const SUPPLIES := {
	"lockpick": ["Lockpick", 6],
	"blunt": ["Blunt arrow", 2],
	"whistle": ["Whistle arrow", 3],
	"broadhead": ["Broadhead arrow", 4],
}


static func price(id: String) -> int:
	return int(CATALOG[id]["price"])


## Buys an upgrade with Harry's purse. Returns false if owned already or he can't afford it.
static func buy(harry: Harry, id: String) -> bool:
	if not CATALOG.has(id) or Progress.has_upgrade(id) or harry.inventory.money < price(id):
		return false
	harry.inventory.add_money(-price(id))
	Progress.upgrades[id] = true
	apply(harry)
	Progress.bus().upgrade_bought.emit(id)
	return true


## Buys `count` of a supply (lockpicks or arrows). Returns how many were bought.
static func buy_supply(harry: Harry, id: String, count: int) -> int:
	var each: int = SUPPLIES[id][1]
	var room := 0
	if id == "lockpick":
		room = harry.inventory.max_lockpicks - harry.inventory.lockpicks
	else:
		room = harry.combat.max_arrows_per_kind - harry.combat.get_ammo(id)
	var n := mini(mini(count, room), harry.inventory.money / each)
	if n <= 0:
		return 0
	harry.inventory.add_money(-n * each)
	if id == "lockpick":
		harry.inventory.add_lockpicks(n)
	else:
		harry.combat.add_ammo(id, n)
	return n


## Sets every upgrade's effect on Harry (and his horse). Safe to call any number of times.
static func apply(harry: Harry) -> void:
	var u := Progress.upgrades
	harry.interaction.lock_skill = 1.3 if u.has("picks") else 1.0
	harry.stealth.footstep_multiplier = 0.75 if u.has("boots") else 1.0
	harry.stealth.shadow_multiplier = 0.85 if u.has("coat") else 1.0
	harry.thievery.skill = 1.25 if u.has("gloves") else 1.0
	harry.combat.draw_time = 0.7 if u.has("bow") else 0.9
	harry.combat.max_arrow_speed = 62.0 if u.has("bow") else 55.0
	harry.combat.max_arrows_per_kind = 30 if u.has("quiver") else 20
	for n in harry.get_tree().get_nodes_in_group("player_horse"):
		(n as Horse).recover_seconds = 12.5 if u.has("camp_paddock") else 25.0


## What a fence pays for an item (pence). Stolen goods fetch a fraction of their worth,
## less for "hot" goods from a famous burglary; provisions sell near their value.
static func fence_price(item: Dictionary) -> int:
	var v := int(item.get("value", 0))
	match String(item.get("kind", "")):
		"provision":
			return int(v * (1.6 if Progress.has_upgrade("camp_smokehouse") else 0.8))
		"valuable":
			var cut := 0.35
			if item.get("victim_class", "") == "aristocrat":
				cut = 0.25 # everyone knows where it came from
			elif item.get("victim_class", "") == "game":
				cut = 0.7
			return int(v * cut)
	return 0
