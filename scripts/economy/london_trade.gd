class_name LondonTrade
extends Node3D
## Puts the places Harry deals with in London: Mags Doyle's stall in the market, Father
## Bernard's poor box at the north end of the street, the counter of T. Wren, Ironmonger
## (at its shop door), and Captain Crowe's wanted posters.

var fence: Fence
var alms: AlmsBox
var shop: ShopCounter


func _ready() -> void:
	add_to_group("navigation_source") # townsfolk and constables walk round the stall and box
	fence = Fence.new()
	fence.name = "MagsDoyle"
	fence.position = Vector3(21.3, 0.0, -63.0)
	fence.rotation.y = PI * 0.5 # facing west, into the square
	add_child(fence)
	alms = AlmsBox.new()
	alms.name = "PoorBox"
	alms.position = Vector3(-5.7, 0.15, -43.5)
	add_child(alms)
	shop = ShopCounter.new()
	shop.name = "WrenIronmonger"
	add_child(shop)
	_place_shop.call_deferred()
	var posters := WantedPosters.new()
	posters.name = "WantedPosters"
	add_child(posters)


func _place_shop() -> void:
	for n in get_tree().get_nodes_in_group("npc_doors"):
		var b := n.get_parent() as BuildingFacade
		if b and b.shop_name.contains("WREN"):
			shop.global_position = (n as Node3D).global_position
			return
	shop.global_position = Vector3(5.5, 0.15, 0.0)
