class_name LootSpot
extends Interactable
## Something worth stealing that sits in the world: silver on a sideboard, a painting on
## the wall, a jewel case, a key on its hook, papers on a desk.
##
## E (held for `take_seconds`) takes it. Children of this node are the visible object and
## are hidden once it's gone. If `missed_when_gone`, a guard who later sees the empty spot
## raises the alarm ("The silver's gone!").

signal taken(item: Dictionary)

@export var item_name: String = "Silver candlestick"
## Worth in pence (a fence pays only part of it).
@export var value: int = 240
## "valuable", "key", "document" or "coins".
@export var kind: String = "valuable"
@export var key_id: String = ""
@export var verb: String = "Take"
@export var take_seconds: float = 0.6
## Radius of the small suspicious sound made each second while working (0 = silent).
@export var work_noise: float = 0.0
@export var missed_when_gone: bool = true
@export var missed_line: String = "Something's been taken! Thieves in the house!"
## Who it belongs to, for the Legend system (Phase 9).
@export var owner_class: String = "aristocrat"

var is_taken: bool = false

var _witness_timer := 0.0
var _noticed := false


func _ready() -> void:
	add_to_group("loot_spots")
	# Already stolen in this game (a saved game remembers)?
	if (GameState.world.get("taken_loot", []) as Array).has(String(get_path())):
		is_taken = true
		_noticed = true
		_hide_visuals.call_deferred()


func get_prompt(_harry: Harry) -> String:
	if is_taken:
		return ""
	return "%s: %s" % [verb, item_name]


func interact(harry: Harry) -> void:
	if is_taken:
		return
	if take_seconds <= 0.3:
		_take(harry)
	else:
		harry.interaction.begin_hold(self, "%s: %s" % [verb, item_name], take_seconds, func() -> void: _take(harry), work_noise)


func to_item() -> Dictionary:
	var item := {"name": item_name, "value": value, "kind": kind, "victim_class": owner_class}
	if key_id != "":
		item["key_id"] = key_id
	return item


func _take(harry: Harry) -> void:
	if is_taken:
		return
	is_taken = true
	var item := to_item()
	var loot: Array[Dictionary] = [item]
	harry.inventory.receive_loot(loot)
	if kind != "key":
		harry.stealth.commit_crime(2.0)
	_hide_visuals()
	var gone: Array = GameState.world.get("taken_loot", [])
	if not gone.has(String(get_path())):
		gone.append(String(get_path()))
	GameState.world["taken_loot"] = gone
	taken.emit(item)


func _hide_visuals() -> void:
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = false


func _physics_process(delta: float) -> void:
	if not is_taken or not missed_when_gone or _noticed:
		return
	_witness_timer -= delta
	if _witness_timer > 0.0:
		return
	_witness_timer = 0.7
	var g := Guard.find_witness(get_interact_point(), 7.0)
	if g:
		_noticed = true
		g.notice_disturbance(global_position, missed_line, true)
