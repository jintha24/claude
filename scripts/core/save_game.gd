class_name SaveGame
extends RefCounted
## Saving and loading games: JSON files in user://saves/ (slot 0 is the autosave, 1-5 are
## the player's). A save holds where Harry is (scene, position, on horseback or not), his
## belongings, the camp stash, the Legend and notoriety, upgrades, the date and time, the
## weather, and what's already been stolen from Ashcombe House.
##
## Autosaves happen when Harry travels between London and the hills and when he sleeps.

const DIR := "user://saves"
const VERSION := 1
const SLOTS := 5

## Seconds played (counted by the GameHUD while unpaused).
static var playtime: float = 0.0


static func path(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


## Writes the current game to `slot`. Returns true on success.
static func save(tree: SceneTree, slot: int) -> bool:
	if Story.is_active():
		return false # missions restart from their beginning, so there's nothing to save mid-way
	var scene := tree.current_scene
	var harry := tree.get_first_node_in_group("player") as Harry
	if scene == null or harry == null:
		return false
	GameState.capture(harry)
	var p := harry.global_position
	var data := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"playtime": playtime,
		"scene": scene.scene_file_path,
		"place": "the hills" if scene.scene_file_path.contains("wilderness") else "London",
		"position": [p.x, p.y, p.z],
		"yaw": harry.facing_yaw,
		"riding": harry.is_riding(),
		"player": GameState.player,
		"stash": GameState.stash,
		"world": GameState.world,
		"progress": Progress.to_dict(),
		"story": Story.to_dict(),
		"clock": {"day": GameClock.day, "minutes": GameClock.minutes},
		"weather": int(Weather.kind),
	}
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


static func read(slot: int) -> Dictionary:
	if not exists(slot):
		return {}
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## One line for the load menu: "Thu 20 Sep 1866, 4:30 pm - London - £12 3s 4d".
static func describe(slot: int) -> String:
	var d := read(slot)
	if d.is_empty():
		return "(empty)"
	var money := int((d.get("player", {}) as Dictionary).get("money", 0))
	var mins := int(float(d.get("playtime", 0.0)) / 60.0)
	return "%s  -  %s  -  %s  -  played %dh %02dm" % [String(d.get("saved_at", "")).replace("T", " "), d.get("place", ""), Money.format(money), mins / 60, mins % 60]


## The most recently written save (for "Continue"), or -1.
static func latest() -> int:
	var best := -1
	var best_time := ""
	for slot in range(0, SLOTS + 1):
		var d := read(slot)
		if d.is_empty():
			continue
		var t := String(d.get("saved_at", ""))
		if t > best_time:
			best_time = t
			best = slot
	return best


## Restores everything from `slot` and loads the saved place (behind the loading card).
static func load_game(tree: SceneTree, slot: int) -> bool:
	var d := read(slot)
	if d.is_empty() or int(d.get("version", 0)) > VERSION:
		return false
	GameState.player = d.get("player", {})
	GameState.stash.clear()
	for it in d.get("stash", []):
		GameState.stash.append(it)
	GameState.world = d.get("world", {})
	Progress.from_dict(d.get("progress", {}))
	Story.from_dict(d.get("story", {}))
	var clock: Dictionary = d.get("clock", {})
	GameClock.day = int(clock.get("day", 0))
	GameClock.minutes = float(clock.get("minutes", 16.0 * 60.0))
	Weather.set_weather(int(d.get("weather", 0)) as Weather.Kind, true)
	playtime = float(d.get("playtime", 0.0))
	var pos: Array = d.get("position", [0, 0, 0])
	GameState.spawn_position = Vector3(pos[0], pos[1], pos[2])
	GameState.spawn_yaw = float(d.get("yaw", 0.0))
	GameState.arrived_mounted = bool(d.get("riding", false))
	GameState.spawn_at = ""
	tree.paused = false
	var ls := LoadingScreen.new()
	ls.scene_path = String(d.get("scene", "res://scenes/main/main.tscn"))
	ls.title = "Loading..."
	tree.root.add_child(ls)
	return true


static func delete(slot: int) -> void:
	if exists(slot):
		DirAccess.remove_absolute(path(slot))


## A fresh game: forget everything carried over.
static func new_game() -> void:
	GameState.player = {}
	GameState.stash.clear()
	GameState.world = {}
	GameState.spawn_at = ""
	GameState.spawn_position = Vector3.INF
	GameState.arrived_mounted = false
	Progress.reset()
	Story.reset()
	GameClock.day = 0
	GameClock.minutes = 16.0 * 60.0
	playtime = 0.0
