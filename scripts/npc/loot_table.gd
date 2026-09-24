class_name LootTable
extends RefCounted
## What people carry in their pockets, by class (London, 1866). Values are what the item
## is worth; a fence (Phase 9) pays only a fraction of it.
##
## Each entry: [item name, min value (d), max value (d), chance 0..1, kind]
## kind: "coins" (goes straight into Harry's purse) or "valuable" (must be fenced).

const TABLES := {
	"gentleman": [
		["coins", 60, 480, 1.0, "coins"],
		["Gold pocket watch", 1920, 3600, 0.45, "valuable"],
		["Silver cigar case", 480, 960, 0.25, "valuable"],
		["Pocket-book with banknotes", 720, 2400, 0.3, "valuable"],
		["Silk handkerchief", 18, 36, 0.4, "valuable"],
	],
	"lady": [
		["coins", 24, 240, 1.0, "coins"],
		["Gold brooch", 480, 1440, 0.3, "valuable"],
		["Silver locket", 240, 720, 0.3, "valuable"],
		["Lace handkerchief", 12, 30, 0.4, "valuable"],
	],
	"merchant": [
		["coins", 60, 300, 1.0, "coins"],
		["Brass snuff box", 36, 96, 0.25, "valuable"],
	],
	"worker": [
		["coins", 1, 30, 1.0, "coins"],
		["Clay pipe and tobacco", 2, 6, 0.4, "valuable"],
		["Pocket knife", 6, 18, 0.2, "valuable"],
	],
	"constable": [
		["coins", 6, 60, 1.0, "coins"],
	],
}


static func class_for_outfit(o: NPCBody.Outfit) -> String:
	match o:
		NPCBody.Outfit.GENTLEMAN:
			return "gentleman"
		NPCBody.Outfit.LADY:
			return "lady"
		NPCBody.Outfit.CONSTABLE, NPCBody.Outfit.HOUSE_GUARD:
			return "constable"
	return "worker"


## Rolls the contents of one person's pockets. Returns an Array of item dictionaries:
## {name, value, kind, victim_class}.
static func roll(victim_class: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in TABLES.get(victim_class, TABLES["worker"]):
		if rng.randf() <= float(e[3]):
			out.append({
				"name": "Coins" if e[0] == "coins" else e[0],
				"value": rng.randi_range(int(e[1]), int(e[2])),
				"kind": e[4],
				"victim_class": victim_class,
			})
	return out
