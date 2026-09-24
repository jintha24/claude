class_name Fence
extends Interactable
## Mags Doyle, the market fence: buys stolen valuables, game and fish, no questions
## asked, for a fraction of their worth (see Upgrades.fence_price). She stands at her own
## stall; keys and papers are no use to her.


func _ready() -> void:
	interact_range = 2.2
	var body := NPCBody.new()
	body.name = "Mags"
	body.outfit = NPCBody.Outfit.LADY
	add_child(body)
	var mb := MeshBuilder.new()
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.5, 0.4, 0.3))
	mb.add_box(Vector3(1.4, 0.8, 0.6), Vector3(0, 0.4, -0.7), wood)
	mb.add_box(Vector3(1.5, 0.04, 0.7), Vector3(0, 0.82, -0.7), MaterialLibrary.get_tinted("fabric", Color(0.25, 0.2, 0.35)))
	mb.build_into(self, "Table")
	var solid := StaticBody3D.new()
	solid.collision_layer = 1
	solid.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.85, 0.6)
	cs.shape = box
	cs.position = Vector3(0, 0.42, -0.7)
	solid.add_child(cs)
	add_child(solid)


func _process(delta: float) -> void:
	var b := get_node_or_null("Mags") as NPCBody
	if b:
		b.update_body(0.0, NPCBody.Pose.NORMAL, delta)


func get_interact_point() -> Vector3:
	return global_transform * Vector3(0, 1.1, -0.7)


func get_prompt(_harry: Harry) -> String:
	return "Talk to Mags Doyle (fence)"


static func sellable(harry: Harry) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in harry.inventory.items:
		if Upgrades.fence_price(it) > 0:
			out.append(it)
	return out


## Sells everything she'll take. Returns the pence received.
static func sell_all(harry: Harry) -> int:
	var total := 0
	for it in sellable(harry):
		total += Upgrades.fence_price(it)
		harry.inventory.remove_item(it)
	harry.inventory.add_money(total)
	return total


func interact(harry: Harry) -> void:
	var items := sellable(harry)
	var total := 0
	for it in items:
		total += Upgrades.fence_price(it)
	var text := "\"Let's see what you've got, love.\"\n\n"
	if items.is_empty():
		text += "You've nothing she'll buy. (She won't touch keys or papers.)"
	else:
		for it in items:
			text += "%s - %s\n" % [it["name"], Money.format(Upgrades.fence_price(it))]
	var opts: Array[Dictionary] = [
		{"text": "Sell it all for %s" % Money.format(total), "enabled": not items.is_empty(), "action": func() -> void: Fence.sell_all(harry)},
	]
	ChoiceMenu.open(get_tree(), "Mags Doyle, Fence", text, opts)
