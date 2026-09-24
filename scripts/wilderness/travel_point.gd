class_name TravelPoint
extends Interactable
## A signpost at the edge of a place: E to set off for somewhere else (London, the hills).
## Works on foot or on horseback. Builds its own finger-post.

@export var destination_name: String = "London"
@export_file("*.tscn") var destination_scene: String
## Spawn point name (group "spawn_points") in the destination.
@export var arrive_at: String = ""
@export var card_title: String = "The road to London"

var _travelling := false


func _ready() -> void:
	interact_range = 3.0
	var mb := MeshBuilder.new()
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.5, 0.4, 0.3))
	var paint := MaterialLibrary.get_tinted("wood_painted", Color(0.9, 0.88, 0.8))
	mb.add_box(Vector3(0.14, 2.6, 0.14), Vector3(0, 1.3, 0), wood)
	mb.add_box(Vector3(1.3, 0.25, 0.05), Vector3(0.55, 2.2, 0), paint)
	mb.add_box(Vector3(0.12, 0.12, 0.12), Vector3(0, 2.66, 0), wood)
	mb.build_into(self, "Post")
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.16, 2.6, 0.16)
	cs.shape = box
	cs.position = Vector3(0, 1.3, 0)
	body.add_child(cs)
	add_child(body)


func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.4


func get_prompt(_harry: Harry) -> String:
	if _travelling:
		return ""
	if Story.is_active():
		return "Finish \"%s\" before you leave" % Story.active.title
	return "Set off for %s" % destination_name


func interact(_harry: Harry) -> void:
	if not Story.is_active():
		travel()


func travel() -> void:
	if _travelling or destination_scene == "":
		return
	_travelling = true
	LoadingScreen.travel(get_tree(), destination_scene, arrive_at, card_title)
