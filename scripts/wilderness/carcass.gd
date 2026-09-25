class_name Carcass
extends Interactable
## A deer or rabbit brought down with the bow. Butchering it (held E) gives venison and a
## hide (or a rabbit and its pelt): food for the camp and things to sell (Phase 9).

var species: WildAnimal.Species = WildAnimal.Species.DEER
var is_stag := false
var animal: Node3D
var _done := false


func _ready() -> void:
	interact_range = 2.4


func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.4


func get_prompt(_harry: Harry) -> String:
	if _done:
		return ""
	match species:
		WildAnimal.Species.DEER:
			return "Butcher the deer"
		WildAnimal.Species.FOX:
			return "Skin the fox"
	return "Take the rabbit"


func interact(harry: Harry) -> void:
	if _done:
		return
	var secs := 4.0 if species == WildAnimal.Species.DEER else (2.5 if species == WildAnimal.Species.FOX else 0.6)
	var label := "Butchering" if species == WildAnimal.Species.DEER else ("Skinning" if species == WildAnimal.Species.FOX else "Picking up")
	harry.interaction.begin_hold(self, label, secs, func() -> void: _butcher(harry))


func items() -> Array[Dictionary]:
	if species == WildAnimal.Species.DEER:
		return [
			{"name": "Venison", "value": 60 if not is_stag else 84, "kind": "provision", "victim_class": "game"},
			{"name": "Stag's hide" if is_stag else "Deer hide", "value": 96 if is_stag else 72, "kind": "valuable", "victim_class": "game"},
		]
	if species == WildAnimal.Species.FOX:
		# A good winter fox pelt fetched a furrier several shillings.
		return [{"name": "Fox pelt", "value": 42, "kind": "valuable", "victim_class": "game"}]
	return [
		{"name": "Rabbit", "value": 4, "kind": "provision", "victim_class": "game"},
		{"name": "Rabbit pelt", "value": 3, "kind": "valuable", "victim_class": "game"},
	]


func _butcher(harry: Harry) -> void:
	_done = true
	for it in items():
		harry.inventory.add_item(it)
	if animal:
		animal.queue_free()
