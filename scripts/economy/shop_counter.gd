class_name ShopCounter
extends Interactable
## T. Wren, Ironmonger: lockpicks, arrows and the better kit (Upgrades.CATALOG, "gear").
## At the camp bench the same menu offers the camp improvements ("camp").

@export var shop_title: String = "T. Wren, Ironmonger"
## "gear" (in town) or "camp" (at the hideout).
@export var kind: String = "gear"


func _ready() -> void:
	interact_range = 2.0


func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func get_prompt(_harry: Harry) -> String:
	return "Go into %s" % shop_title if kind == "gear" else "Improve the camp"


func options(harry: Harry) -> Array[Dictionary]:
	var opts: Array[Dictionary] = []
	if kind == "gear":
		for id: String in ["lockpick", "blunt", "broadhead", "whistle"]:
			var s: Array = Upgrades.SUPPLIES[id]
			opts.append({"text": "%s x6 - %s" % [s[0], Money.format(int(s[1]) * 6)], "enabled": harry.inventory.money >= int(s[1]), "keep_open": true, "action": func() -> void: Upgrades.buy_supply(harry, id, 6)})
	for id: String in Upgrades.CATALOG:
		var u: Dictionary = Upgrades.CATALOG[id]
		if u["kind"] != kind:
			continue
		var owned := Progress.has_upgrade(id)
		var text := "%s - %s" % [u["name"], "owned" if owned else Money.format(int(u["price"]))]
		opts.append({"text": text, "enabled": not owned and harry.inventory.money >= int(u["price"]), "keep_open": true, "action": func() -> void: Upgrades.buy(harry, id)})
	return opts


func interact(harry: Harry) -> void:
	var text := "Your purse: %s." % Money.format(harry.inventory.money)
	for id: String in Upgrades.CATALOG:
		if Upgrades.CATALOG[id]["kind"] == kind:
			text += "\n%s: %s" % [Upgrades.CATALOG[id]["name"], Upgrades.CATALOG[id]["desc"]]
	var m := ChoiceMenu.open(get_tree(), shop_title if kind == "gear" else "The Camp", text, options(harry))
	m.set_meta("rebuild", func() -> Array[Dictionary]: return options(harry))
