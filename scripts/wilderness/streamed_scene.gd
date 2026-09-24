class_name StreamedScene
extends Node3D
## A place that is only in memory while the player is near: when he comes within
## `load_radius` it is loaded on a background thread (ResourceLoader.load_threaded_request)
## and added as a child; beyond `unload_radius` it is freed again. Used for the cave
## hideout and, later, other points of interest.

signal loaded(instance: Node)
signal unloaded

@export_file("*.tscn") var scene_path: String
@export var load_radius: float = 220.0
@export var unload_radius: float = 320.0

var instance: Node = null
var _requested := false
var _check := 0.0


func is_loaded() -> bool:
	return instance != null


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 and not _requested:
		return
	_check = 0.25
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or scene_path == "":
		return
	var d := player.global_position.distance_to(global_position)
	if instance == null and not _requested and d < load_radius:
		ResourceLoader.load_threaded_request(scene_path, "PackedScene", false)
		_requested = true
	if _requested:
		var status := ResourceLoader.load_threaded_get_status(scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_requested = false
			var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
			instance = packed.instantiate()
			add_child(instance)
			loaded.emit(instance)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_requested = false
			push_error("StreamedScene: could not load %s" % scene_path)
	elif instance and d > unload_radius:
		instance.queue_free()
		instance = null
		unloaded.emit()
