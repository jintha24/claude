class_name CityLife
extends Node3D
## The people in the streets of Greater London, outside the old neighbourhood (whose own
## residents Population looks after).
##
## Round the player, on the fully built chunks (CityStreamer), it keeps up a flow of
## passers-by walking from one door to another - clerks and gentlemen in the City and the
## West End, working men and women in the East End and over the river - plus street sellers
## crying their wares on the corners and constables walking their beats. How many depends
## on the hour and the weather. People are let go once they are well out of sight.
## Every passer-by is a Civilian: they can be robbed, they gawk and shout "Thief!".

@export var streamer_path: NodePath = NodePath("../City")
@export var player_path: NodePath = NodePath("../Harry")
## Passers-by kept within SPAWN_MAX of the player at the busiest hour.
@export var max_people: int = 56
@export var max_constables: int = 3
## Street scenes going on round the player at once (each one to four people).
@export var max_scenes: int = 12

const SPAWN_MIN := 28.0
const SPAWN_MAX := 85.0
const LET_GO := 115.0

var _streamer: CityStreamer
var _player: Node3D
var _people: Array[Civilian] = []
var _constables: Array[Guard] = []
var _routes: Array[PatrolRoute] = []
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _counter := 0
var _scenes: Array[Dictionary] = []
var _used_doors := {}

## What goes on at each kind of door, and when: [what, door kind, hours, people, outfits,
## pose, second pose, lines]. People "1-3" come as a group round the doorstep.
const SCENES: Array = [
	["sweep", "house", Vector2(6.5, 10.5), 1, [NPCBody.Outfit.LADY, NPCBody.Outfit.RAGGED], NPCBody.Pose.BROWSE, NPCBody.Pose.NORMAL,
		["These steps won't scrub themselves.", "Soot, soot, soot. Every blessed day.", "Morning, love."]],
	["gossip", "house", Vector2(9.5, 18.5), 2, [NPCBody.Outfit.LADY], NPCBody.Pose.TALK, NPCBody.Pose.NORMAL,
		["...and she never even said thank you.", "Her at number nine's expecting again.", "I heard the Hill Fox gave a whole guinea to the widow Pratt.", "Price of coal! It's robbery."]],
	["pipe", "house", Vector2(18.0, 22.5), 1, [NPCBody.Outfit.WORKER, NPCBody.Outfit.GENTLEMAN], NPCBody.Pose.LOOK_AROUND, NPCBody.Pose.NORMAL,
		["Evenin'.", "Mild night for it.", "Don't let the missus see you out here."]],
	["keeper", "shop", Vector2(8.0, 19.0), 1, [NPCBody.Outfit.WORKER, NPCBody.Outfit.GENTLEMAN], NPCBody.Pose.NORMAL, NPCBody.Pose.WAVE,
		["Come in, come in! Best prices in the street.", "Fresh in today, madam!", "Mind the step, sir."]],
	["window", "shop", Vector2(9.0, 19.0), 2, [NPCBody.Outfit.LADY, NPCBody.Outfit.GENTLEMAN], NPCBody.Pose.BROWSE, NPCBody.Pose.TALK,
		["Oh, isn't that lovely.", "Far too dear.", "Perhaps for Christmas."]],
	["drinkers", "pub", Vector2(12.0, 0.5), 3, [NPCBody.Outfit.WORKER, NPCBody.Outfit.RAGGED], NPCBody.Pose.TALK, NPCBody.Pose.WAVE,
		["Your round, Charlie!", "Another pint of porter!", "And I says to him, I says...", "Here's to the Hill Fox!", "Ha! Pull the other one."]],
	["loading", "work", Vector2(6.5, 18.0), 2, [NPCBody.Outfit.WORKER], NPCBody.Pose.BROWSE, NPCBody.Pose.NORMAL,
		["Mind your back!", "Up she goes.", "Who packed this, a giant?", "Two more and we're done."]],
	["play", "house", Vector2(9.0, 18.0), 3, [NPCBody.Outfit.RAGGED], NPCBody.Pose.NORMAL, -1,
		["You're it!", "Can't catch me!", "No fair!"]],
	["beggar", "shop", Vector2(8.0, 21.0), 1, [NPCBody.Outfit.RAGGED], NPCBody.Pose.WAVE, NPCBody.Pose.NORMAL,
		["Spare a copper, sir?", "God bless you, miss.", "Just a ha'penny for a crust."]],
]


func _ready() -> void:
	add_to_group("city_life")
	_rng.seed = 1866


func people_count() -> int:
	return _people.size()


func constable_count() -> int:
	return _constables.size()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.4
	if _streamer == null:
		_streamer = get_node_or_null(streamer_path) as CityStreamer
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node3D
	if _streamer == null or _player == null or _streamer.plan == null:
		return
	var p := _player.global_position
	_let_go(p)
	var doors := _streamer.near_doors()
	if doors.is_empty():
		return
	var want := _wanted_people(p)
	var spawned := 0
	while _people.size() < want and spawned < 3:
		if not _spawn_person(p, doors):
			break
		spawned += 1
	if _constables.size() < _wanted_constables(p):
		_spawn_constable(p)
	_update_scenes(p, doors)


## Fewer people at night and in foul weather; none while the player is deep in the old
## streets (they have their own crowds).
func _wanted_people(p: Vector3) -> int:
	var inner := CityPlan.CORE.grow(-8.0)
	if inner.has_point(Vector2(p.x, p.z)):
		return 0
	var h := GameClock.hours()
	var busy := 1.0
	if h >= 1.0 and h < 5.0:
		busy = 0.15
	elif h < 1.0 or h >= 23.0:
		busy = 0.3 # pubs turning out, cabmen, night workers
	elif h < 7.0:
		busy = 0.4
	elif h >= 20.0:
		busy = 0.65 # theatres, music halls and gin palaces
	elif (h >= 8.0 and h < 10.0) or (h >= 17.0 and h < 19.0):
		busy = 1.0 # going to work and coming home
	else:
		busy = 0.8
	if Weather.rain > 0.5:
		busy *= 0.45
	elif Weather.rain > 0.2:
		busy *= 0.7
	if Weather.snow > 0.4:
		busy *= 0.6
	return int(round(max_people * busy))


func _wanted_constables(p: Vector3) -> int:
	if CityPlan.CORE.grow(-8.0).has_point(Vector2(p.x, p.z)):
		return 0
	return max_constables


var _night := false


func _let_go(p: Vector3) -> void:
	var h := GameClock.hours()
	var night := h >= 18.0 or h < 6.0
	if night != _night:
		# The shift changes: the day men go off and the night men come on with lanterns.
		_night = night
		for g: Variant in _constables:
			if is_instance_valid(g) and (g as Guard).state in [Guard.State.PATROL, Guard.State.WAIT, Guard.State.RETURN]:
				(g as Guard).queue_free()
	var alive: Array[Civilian] = []
	for c: Variant in _people:
		if is_instance_valid(c) and not (c as Civilian).is_queued_for_deletion():
			alive.append(c)
	_people = alive
	for c: Civilian in _people.duplicate():
		var far := c.global_position.distance_to(p) > LET_GO
		var calm := c.state in [Civilian.State.TRAVEL, Civilian.State.WANDER, Civilian.State.TEND_STALL]
		if far and calm or not _streamer.is_detailed_at(c.global_position) and far:
			_people.erase(c)
			c.queue_free()
	var on_duty: Array[Guard] = []
	for g: Variant in _constables:
		if is_instance_valid(g) and not (g as Guard).is_queued_for_deletion():
			on_duty.append(g)
	_constables = on_duty
	for g: Guard in _constables.duplicate():
		var busy := g.state in [Guard.State.CHASE, Guard.State.SEARCH, Guard.State.INVESTIGATE, Guard.State.UNCONSCIOUS, Guard.State.STUNNED]
		if g.global_position.distance_to(p) > LET_GO + 30.0 and not busy:
			_constables.erase(g)
			g.queue_free()
	for r: Variant in _routes.duplicate():
		if not is_instance_valid(r):
			_routes.erase(r)
			continue
		var used := false
		for g in _constables:
			if g.get_meta("route", null) == r:
				used = true
		if not used:
			_routes.erase(r)
			r.queue_free()


func _pick_door(doors: Array, p: Vector3, min_d: float, max_d: float) -> Array:
	for attempt in 12:
		var d: Array = doors[_rng.randi() % doors.size()]
		var pos: Vector3 = d[0]
		var dist := Vector2(pos.x - p.x, pos.z - p.z).length()
		if dist >= min_d and dist <= max_d:
			return d
	return []


## A passer-by: comes out of a door and walks to another, where they go in.
func _spawn_person(p: Vector3, doors: Array) -> bool:
	var from := _pick_door(doors, p, SPAWN_MIN, SPAWN_MAX)
	if from.is_empty():
		return false
	var start: Vector3 = from[0]
	var to := _pick_door(doors, start, 35.0, 150.0)
	if to.is_empty():
		return false
	var plan := _streamer.plan
	var district := plan.district(start.x, start.z)
	var c := Civilian.new()
	_counter += 1
	c.name = "CityFolk%d" % _counter
	c.display_name = "Passer-by"
	c.outfit = _outfit_for(district)
	c.look_seed = _rng.randi() % 100000
	var seller := _rng.randf() < 0.12 and GameClock.hours() > 7.0 and GameClock.hours() < 20.0
	start.y = plan.ground_y(start.x, start.z) + 0.05
	c.position = start
	c.walk_speed = _rng.randf_range(1.1, 1.5)
	if seller:
		# A costermonger with a tray, standing at the kerb crying his wares.
		c.display_name = "Street seller"
		c.is_merchant = true
		c.stall_point = start
		c.stall_look = start + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	add_child(c)
	if not seller:
		var dest: Vector3 = to[0]
		dest.y = plan.ground_y(dest.x, dest.z)
		c.go_to(dest, "vanish")
		if GameClock.hours() >= 22.0 or GameClock.hours() < 2.0:
			if _rng.randf() < 0.3 and district in ["east", "south", "city"]:
				c.set_drunk(true)
	_people.append(c)
	# Some take their dog out with them.
	if not seller and _rng.randf() < 0.18:
		var dog := StreetDog.new()
		dog.name = "Dog%d" % _counter
		dog.owner_node = c
		dog.ground_fn = plan.ground_y
		add_child(dog)
		dog.global_position = start
	return true


# ---------------------------------------------------------------------------
# Street scenes: people at their daily business round the doors near the player
# ---------------------------------------------------------------------------
func scene_count() -> int:
	return _scenes.size()


func scene_kinds() -> Array:
	return _scenes.map(func(sc: Dictionary) -> String: return sc["what"])


func _update_scenes(p: Vector3, doors: Array) -> void:
	# Over when everyone's gone in, or the player's left them behind.
	for sc: Dictionary in _scenes.duplicate():
		var people: Array = (sc["people"] as Array).filter(func(c: Variant) -> bool: return is_instance_valid(c) and not (c as Node).is_queued_for_deletion())
		sc["people"] = people
		var spot: Vector3 = sc["spot"]
		if people.is_empty() or spot.distance_to(p) > LET_GO:
			for c: Variant in people:
				(c as Node).queue_free()
			_used_doors.erase(sc["door"])
			_scenes.erase(sc)
	var inner := CityPlan.CORE.grow(-8.0)
	if inner.has_point(Vector2(p.x, p.z)) or _scenes.size() >= _wanted_scenes():
		return
	var h := GameClock.hours()
	# Try a few doors near the player for something that fits the door and the hour.
	for attempt in 6:
		var d := _pick_door(doors, p, 14.0, 70.0)
		if d.is_empty():
			return
		var at: Vector3 = d[0]
		var key := Vector2i(roundi(at.x), roundi(at.z))
		if _used_doors.has(key):
			continue
		var kinds := scene_kinds()
		var fits := SCENES.filter(func(row: Array) -> bool:
			var cap := 2 if row[0] in ["beggar", "keeper", "pipe"] else 3
			return row[1] == d[1] and Civilian.in_hours(h, row[2]) and kinds.count(row[0]) < cap)
		if fits.is_empty():
			continue
		_start_scene(fits[_rng.randi() % fits.size()], at, key)
		return


func _wanted_scenes() -> int:
	var h := GameClock.hours()
	var n := max_scenes
	if h < 6.0 or h >= 23.5:
		n = 3
	if Weather.rain > 0.5:
		n = 2
	return n


func _start_scene(row: Array, door: Vector3, key: Vector2i) -> void:
	var plan := _streamer.plan
	var what: String = row[0]
	var out := _street_dir(door)
	var spot := door + out * (1.2 if what in ["sweep", "keeper", "pipe"] else 2.2)
	if what == "window" or what == "beggar":
		spot = door + out * 1.3 + out.cross(Vector3.UP) * (2.0 if what == "window" else -1.6)
	if what == "play":
		spot = door + out * 2.6
	spot.y = plan.ground_y(spot.x, spot.z)
	var n: int = row[3]
	var people: Array = []
	for i in n:
		var c := Civilian.new()
		_counter += 1
		c.name = "Street%s%d" % [what.capitalize(), _counter]
		var outfits: Array = row[4]
		c.outfit = outfits[_rng.randi() % outfits.size()]
		c.display_name = {"sweep": "Housewife", "gossip": "Neighbour", "pipe": "Neighbour", "keeper": "Shopkeeper", "window": "Shopper",
			"drinkers": "Drinker", "loading": "Carter", "play": "Urchin", "beggar": "Beggar"}.get(what, "Passer-by")
		if what == "play":
			c.fixed_height = _rng.randf_range(1.2, 1.42)
		c.look_seed = _rng.randi() % 100000
		c.walk_speed = _rng.randf_range(1.1, 1.4)
		var from := door
		from.y = plan.ground_y(from.x, from.z) + 0.05
		c.position = from
		add_child(c)
		# Round the spot, facing into the group (or the door, the window, the street).
		var place := spot
		var look := spot + out
		if n > 1:
			var a := TAU * i / n + _rng.randf_range(-0.3, 0.3)
			place = spot + Vector3(cos(a), 0, sin(a)) * (0.55 if n == 2 else 0.8)
			look = spot
		match what:
			"sweep", "keeper":
				look = spot + out.cross(Vector3.UP) * 2.0
			"window":
				look = place - out * 2.0
			"loading":
				look = door
		var hours: Vector2 = row[2]
		# Not everyone keeps quite the same hours.
		hours += Vector2(0.0, _rng.randf_range(-0.6, 0.4))
		if what == "drinkers" and GameClock.hours() >= 22.0 and _rng.randf() < 0.4:
			c.set_drunk(true)
		c.start_activity(what, place, look, row[5], row[6], hours, row[7], from)
		if what == "play":
			c.set("_target", place)
		people.append(c)
	_used_doors[key] = true
	_scenes.append({"what": what, "people": people, "spot": spot, "door": key})


## The way out from a door into the street: from the nearest edge of the block it's in.
func _street_dir(p: Vector3) -> Vector3:
	var plan := _streamer.plan
	for bi in plan.blocks_overlapping(plan.coord_of(p)):
		var r: Rect2 = (plan.blocks[bi] as Dictionary)["rect"]
		if not r.grow(0.5).has_point(Vector2(p.x, p.z)):
			continue
		var dn := p.z - r.position.y
		var ds := r.end.y - p.z
		var dw := p.x - r.position.x
		var de := r.end.x - p.x
		var m := minf(minf(dn, ds), minf(dw, de))
		if m == dn:
			return Vector3(0, 0, -1)
		if m == ds:
			return Vector3(0, 0, 1)
		if m == dw:
			return Vector3(-1, 0, 0)
		return Vector3(1, 0, 0)
	return Vector3(0, 0, 1)


func _outfit_for(district: String) -> NPCBody.Outfit:
	var r := _rng.randf()
	match district:
		"west":
			return NPCBody.Outfit.GENTLEMAN if r < 0.45 else (NPCBody.Outfit.LADY if r < 0.85 else NPCBody.Outfit.WORKER)
		"city":
			return NPCBody.Outfit.GENTLEMAN if r < 0.45 else (NPCBody.Outfit.WORKER if r < 0.8 else NPCBody.Outfit.LADY)
		"east":
			return NPCBody.Outfit.WORKER if r < 0.62 else (NPCBody.Outfit.RAGGED if r < 0.8 else NPCBody.Outfit.LADY)
		"south":
			return NPCBody.Outfit.WORKER if r < 0.6 else (NPCBody.Outfit.LADY if r < 0.85 else NPCBody.Outfit.RAGGED)
	return NPCBody.Outfit.WORKER if r < 0.45 else (NPCBody.Outfit.GENTLEMAN if r < 0.7 else NPCBody.Outfit.LADY)


## A constable walking the pavements round a block near the player.
func _spawn_constable(p: Vector3) -> void:
	var plan := _streamer.plan
	var c := plan.coord_of(p)
	var candidates: Array[Dictionary] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cc := c + Vector2i(dx, dz)
			if _streamer.chunk_lod(cc) != 0:
				continue
			for i in plan.blocks_owned(cc):
				var b: Dictionary = plan.blocks[i]
				if b["kind"] in [CityPlan.Kind.TERRACE, CityPlan.Kind.SQUARE, CityPlan.Kind.CHURCH, CityPlan.Kind.WAREHOUSE] and not b.get("core", false):
					var r: Rect2 = b["rect"]
					var d := r.get_center().distance_to(Vector2(p.x, p.z))
					if d > 45.0 and d < 140.0:
						candidates.append(b)
	if candidates.is_empty():
		return
	var b: Dictionary = candidates[_rng.randi() % candidates.size()]
	var r: Rect2 = b["rect"]
	var pave: Array = b["pave"]
	var y := CityPlan.PAVE_TOP
	# Round the block along the middle of its pavements.
	var n: float = r.position.y + float(pave[CityPlan.Side.N]) * 0.5
	var s: float = r.end.y - float(pave[CityPlan.Side.S]) * 0.5
	var w: float = r.position.x + float(pave[CityPlan.Side.W]) * 0.5
	var e: float = r.end.x - float(pave[CityPlan.Side.E]) * 0.5
	var route := PatrolRoute.new()
	route.name = "CityBeat%d" % _counter
	route.loop = true
	for corner: Vector3 in [Vector3(w, y, n), Vector3(e, y, n), Vector3(e, y, s), Vector3(w, y, s)]:
		route.add_point(corner, _rng.randf_range(0.0, 4.0), NAN)
	add_child(route)
	_routes.append(route)
	var g := Guard.new()
	_counter += 1
	g.name = "CityConstable%d" % _counter
	g.display_name = "Constable"
	var h := GameClock.hours()
	g.has_lantern = h >= 18.0 or h < 6.0
	g.position = Vector3(w, y + 0.05, n)
	g.set_meta("route", route)
	g.add_to_group("city_constables")
	add_child(g)
	g.set_route(route)
	_constables.append(g)
