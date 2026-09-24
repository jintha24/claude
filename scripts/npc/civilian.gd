class_name Civilian
extends NPCCharacter
## Townsfolk: shoppers, passers-by and market traders.
##
## Behaviour: wander between points in their area, stop at stalls to browse, gather and
## gawk at commotions (a shout of "Thief!", breaking glass, a man going down), and react
## to pickpockets. Merchants stay at their stall and cry their wares.
## Every person has real pocket contents rolled from LootTable for their class.

enum State { WANDER, BROWSE, GAWK, SHOUT, TEND_STALL, FLEE }

const CRIES: Array[String] = [
	"Fresh herrings! Three a penny!", "Hot baked potatoes, all hot!", "Sweet oranges, ha'penny each!",
	"Fine cabbages! Fine cabbages!", "Flowers! Pretty flowers for your sweetheart!",
	"Crockery, cheap today!", "New bread, fresh from the oven!", "Ribbons and laces!",
]

@export var is_merchant: bool = false
@export var walk_speed: float = 1.3
## Wandering area: centre and half-size (x, z) in world space.
@export var wander_center: Vector3 = Vector3.ZERO
@export var wander_extent: Vector2 = Vector2(10, 10)

var state: State = State.WANDER
var victim_class: String = "worker"
var pockets: Array[Dictionary] = []
var robbed := false
## Once someone has caught a thief (or found their pocket picked) they stay on guard.
var wary := false
## Rises while Harry's hand is in their pocket (0..1). Driven by HarryThievery.
var suspicion: float = 0.0
var stall_point: Vector3 = Vector3.ZERO
var stall_look: Vector3 = Vector3.ZERO

var _target: Vector3
var _timer := 0.0
var _gawk_point: Vector3
var _discover_timer := -1.0
var _cry_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _flee_from := Vector3.ZERO
var _browse_on_arrival := false


func _ready() -> void:
	add_to_group("civilians")
	_rng.seed = hash(name) ^ hash(global_position)
	walk_speed *= _rng.randf_range(0.85, 1.15)
	_setup_npc(walk_speed * 3.0, 1.72 if outfit == NPCBody.Outfit.LADY else _rng.randf_range(1.66, 1.8))
	victim_class = "merchant" if is_merchant else LootTable.class_for_outfit(outfit)
	pockets = LootTable.roll(victim_class, _rng)
	Stealth.bus().noise_made.connect(_on_noise)
	_cry_timer = _rng.randf_range(4.0, 15.0)
	if is_merchant:
		state = State.TEND_STALL
	else:
		_pick_wander_target()


func _physics_process(delta: float) -> void:
	_begin_frame(delta)
	if not _nav_ready():
		_apply_movement(delta)
		return
	_pose = NPCBody.Pose.NORMAL
	_timer -= delta
	suspicion = move_toward(suspicion, 0.0, delta * 0.15)
	if _discover_timer > 0.0:
		_discover_timer -= delta
		if _discover_timer <= 0.0:
			_discover_theft()
	match state:
		State.WANDER:
			if _move_to(_target, walk_speed):
				if _browse_on_arrival:
					_browse_on_arrival = false
					state = State.BROWSE
					_timer = _rng.randf_range(4.0, 12.0)
				elif _rng.randf() > 0.55 or not _start_browsing():
					_pick_wander_target()
		State.BROWSE:
			_pose = NPCBody.Pose.BROWSE
			_face_point(stall_look)
			if _timer <= 0.0:
				state = State.WANDER
				_pick_wander_target()
		State.TEND_STALL:
			if _move_to(stall_point, walk_speed):
				_face_point(stall_look)
				_pose = NPCBody.Pose.BROWSE if fmod(float(_frame) / 60.0, 20.0) > 14.0 else NPCBody.Pose.NORMAL
				_cry_timer -= delta
				if _cry_timer <= 0.0:
					_cry_timer = _rng.randf_range(10.0, 22.0)
					_cry()
		State.GAWK:
			_face_point(_gawk_point)
			if _timer <= 0.0:
				_resume()
		State.SHOUT:
			_pose = NPCBody.Pose.SHOUT
			_face_point(_gawk_point)
			if _timer <= 0.0:
				_resume()
		State.FLEE:
			var away := (global_position - _flee_from)
			away.y = 0.0
			if _move_to(global_position + away.normalized() * 4.0, walk_speed * 2.6) or _timer <= 0.0:
				_resume()
	_apply_movement(delta)


# ---------------------------------------------------------------------------
# Pickpocketing interface (used by HarryThievery)
# ---------------------------------------------------------------------------

## True if Harry, standing at `pos`, is behind or beside this person and close enough.
func can_be_pickpocketed_from(pos: Vector3) -> bool:
	if robbed or wary or pockets.is_empty() or state in [State.SHOUT, State.FLEE, State.GAWK]:
		return false
	var to_harry := pos - global_position
	to_harry.y = 0.0
	if to_harry.length() > 1.3 or absf(pos.y - global_position.y) > 0.5:
		return false
	return get_facing_dir().dot(to_harry.normalized()) < 0.35


func is_walking() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.3


## Empties their pockets. Some rich victims notice the loss a little later.
func take_loot() -> Array[Dictionary]:
	robbed = true
	var loot := pockets.duplicate()
	pockets.clear()
	if victim_class in ["gentleman", "lady"] and _rng.randf() < 0.3:
		_discover_timer = _rng.randf_range(20.0, 40.0)
	return loot


## A failed attempt: they spin round and shout. Returns true if they grab hold of Harry.
func catch_thief(harry: Harry) -> bool:
	wary = true
	suspicion = 0.0
	state = State.SHOUT
	_timer = 4.0
	_gawk_point = harry.global_position
	Stealth.bark(self, "%s: \"%s\"" % [display_name, ["Thief! Stop, thief!", "Get your hands off me! Thief!", "Police! Thief!"][_rng.randi() % 3]])
	Stealth.make_noise(global_position, 28.0, "thief_shout", true, self)
	harry.stealth.commit_crime(8.0)
	return victim_class in ["worker", "merchant"] and _rng.randf() < 0.5


# ---------------------------------------------------------------------------
# Reactions
# ---------------------------------------------------------------------------
func _on_noise(pos: Vector3, radius: float, kind: String, _suspicious: bool, source: Node) -> void:
	if source == self or state in [State.SHOUT, State.FLEE]:
		return
	if not kind in ["thief_shout", "glass", "body_fall", "rattle", "scuffle"]:
		return
	var d := global_position.distance_to(pos)
	if d > minf(radius, 18.0):
		return
	if d < 4.0 and kind in ["scuffle", "body_fall"] and _rng.randf() < 0.5:
		state = State.FLEE
		_flee_from = pos
		_timer = 4.0
		return
	state = State.GAWK
	_gawk_point = pos
	_timer = _rng.randf_range(5.0, 10.0)
	if _rng.randf() < 0.25:
		Stealth.bark(self, "%s: \"%s\"" % [display_name, ["What's going on?", "Did you see that?", "Good heavens!"][_rng.randi() % 3]])


func _discover_theft() -> void:
	wary = true
	state = State.SHOUT
	_timer = 5.0
	var harry := get_tree().get_first_node_in_group("player") as Harry
	_gawk_point = harry.global_position if harry else global_position
	var what := "watch" if victim_class == "gentleman" else "purse"
	Stealth.bark(self, "%s: \"My %s! I've been robbed!\"" % [display_name, what])
	Stealth.make_noise(global_position, 24.0, "thief_shout", true, self)
	# If Harry is close by and in view, he's the obvious suspect.
	if harry and harry.global_position.distance_to(global_position) < 10.0:
		var to_h := harry.global_position - global_position
		if get_facing_dir().dot(Vector3(to_h.x, 0, to_h.z).normalized()) > 0.0:
			harry.stealth.commit_crime(6.0)


func _cry() -> void:
	var harry := get_tree().get_first_node_in_group("player") as Node3D
	if harry and harry.global_position.distance_to(global_position) < 14.0:
		Stealth.bark(self, "%s: \"%s\"" % [display_name, CRIES[_rng.randi() % CRIES.size()]])


func _resume() -> void:
	if is_merchant:
		state = State.TEND_STALL
	else:
		state = State.WANDER
		_pick_wander_target()


func _pick_wander_target() -> void:
	var p := wander_center + Vector3(_rng.randf_range(-wander_extent.x, wander_extent.x), 0.0, _rng.randf_range(-wander_extent.y, wander_extent.y))
	_target = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p) if _nav_ready() else p
	state = State.WANDER


func _start_browsing() -> bool:
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("browse_points"):
		var m := node as Node3D
		var d := m.global_position.distance_to(global_position) + _rng.randf() * 6.0
		if d < best_d and d < 16.0:
			best_d = d
			best = m
	if best == null:
		return false
	_target = best.global_position
	stall_look = best.get_meta("look_at", best.global_position)
	_browse_on_arrival = true
	state = State.WANDER
	return true
