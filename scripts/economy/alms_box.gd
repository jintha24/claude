class_name AlmsBox
extends Interactable
## Father Bernard's poor box outside the St Giles Mission: money given here feeds and
## houses the rookery's poor. Giving is what raises the Hill Fox's Legend (Progress).


func _ready() -> void:
	interact_range = 1.8
	var mb := MeshBuilder.new()
	var wood := MaterialLibrary.get_tinted("wood_painted", Color(0.2, 0.25, 0.18))
	var iron := MaterialLibrary.get_material("iron")
	mb.add_box(Vector3(0.14, 1.0, 0.14), Vector3(0, 0.5, 0), wood)
	mb.add_box(Vector3(0.4, 0.34, 0.3), Vector3(0, 1.17, 0), wood)
	mb.add_box(Vector3(0.44, 0.04, 0.34), Vector3(0, 1.36, 0), iron)
	mb.add_box(Vector3(0.12, 0.01, 0.02), Vector3(0, 1.385, 0), MaterialLibrary.get_material("brass"))
	mb.build_into(self, "Box")
	var sign := Label3D.new()
	sign.text = "ST GILES MISSION\nFor the Poor\nFr. Bernard"
	sign.font = UIKit.font()
	sign.font_size = 28
	sign.pixel_size = 0.004
	sign.modulate = Color(0.95, 0.9, 0.75)
	sign.position = Vector3(0, 1.62, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(sign)
	var solid := StaticBody3D.new()
	solid.collision_layer = 1
	solid.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 1.4, 0.3)
	cs.shape = box
	cs.position = Vector3(0, 0.7, 0)
	solid.add_child(cs)
	add_child(solid)


func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func get_prompt(_harry: Harry) -> String:
	return "Give to Father Bernard's poor box"


## Puts `pence` (at most what he has) in the box.
static func give(harry: Harry, pence: int) -> int:
	var amount := mini(pence, harry.inventory.money)
	if amount <= 0:
		return 0
	harry.inventory.add_money(-amount)
	Progress.on_given(amount)
	Progress.bus().note.emit("You give %s. The poor of St Giles will eat tonight." % Money.format(amount))
	return amount


func interact(harry: Harry) -> void:
	var m := harry.inventory.money
	var text := "\"Take from those who won't miss it; give to those who can't live without it.\" - Tobias Finch\n\nYour purse: %s.  Given so far: %s.\nYour Legend: %s." % [Money.format(m), Money.format(Progress.given_total), Progress.rank()]
	var opts: Array[Dictionary] = []
	for amount: int in [240, 1200, 4800]:
		opts.append({"text": "Give %s" % Money.format(amount), "enabled": m >= amount, "action": func() -> void: AlmsBox.give(harry, amount)})
	opts.append({"text": "Give half your purse (%s)" % Money.format(m / 2), "enabled": m >= 2, "action": func() -> void: AlmsBox.give(harry, m / 2)})
	ChoiceMenu.open(get_tree(), "The Poor Box", text, opts)
