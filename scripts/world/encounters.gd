class_name Encounters
extends Node3D
## Things that happen in the world as Harry goes about it - the small stories of the
## street and the road, every couple of minutes somewhere near him:
##   London: a purse snatched ("Stop, thief!") - catch the thief, give the lady her purse
##           back (or keep it); two drunks brawling with a crowd round them - break it up;
##           a street preacher and his listeners; a hungry child asking for a penny.
##   Hills:  a highwayman holding up a traveller ("Stand and deliver!") - run him off;
##           a carter whose wheel is stuck in the rut - help him push.
## Helping the poor raises Harry's Legend; keeping what isn't his costs a little of it.

signal started(kind: String)
signal resolved(kind: String, outcome: String)

@export var player_path: NodePath = NodePath("../Harry")
## "london" or "hills".
@export var place: String = "london"
## Real seconds between encounters (randomised a little).
@export var interval: float = 90.0
## Off: none happen by chance, only through start().
@export var random_encounters := true

const SERMONS: Array[String] = [
	"Repent! The gin shop is the gate of Hell!", "The meek shall inherit the earth, brothers!",
	"Turn from drink and the Lord will fill your cup!", "Is your soul as black as the Thames, friend?",
]
const INSULTS: Array[String] = ["You'll take that back!", "Come on then!", "I'll 'ave you!", "That's my pint you spilt!"]

var active := ""
var _player: Harry
var _timer := 25.0
var _age := 0.0
var _rng := RandomNumberGenerator.new()
var _nodes: Array[Node] = []
var _state := {}
var _anchor := Vector3.ZERO
var _serial := 0


func _ready() -> void:
	add_to_group("encounters")
	_rng.randomize()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Harry
		if _player == null:
			return
	if active != "":
		_age += delta
		_update(delta)
		# Walked away from it, or it ran its course.
		if _age > 240.0 or _player.global_position.distance_to(_anchor) > 170.0:
			_end("faded")
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval * _rng.randf_range(0.7, 1.3)
	if Story.is_active() or not random_encounters:
		return
	start_random()


## Starts a random encounter that suits the place and hour (tests call start()).
func start_random() -> bool:
	var h := GameClock.hours()
	var kinds: Array[String] = []
	if place == "london":
		kinds = ["purse_snatch", "beggar_child"]
		if h > 8.0 and h < 20.0:
			kinds.append("preacher")
		if h > 17.0 or h < 1.0:
			kinds.append("brawl")
	else:
		kinds = ["stuck_cart"]
		if h > 6.0 and h < 21.0:
			kinds.append("highwayman")
	return start(kinds[_rng.randi() % kinds.size()])


func start(kind: String) -> bool:
	if active != "" or _player == null:
		return false
	var spot := _find_spot()
	if spot == Vector3.INF:
		return false
	_anchor = spot
	_serial += 1
	_age = 0.0
	_state = {}
	active = kind
	match kind:
		"purse_snatch":
			_purse_snatch(spot)
		"brawl":
			_brawl(spot)
		"preacher":
			_preacher(spot)
		"beggar_child":
			_beggar(spot)
		"highwayman":
			_highwayman(spot)
		"stuck_cart":
			_stuck_cart(spot)
	started.emit(kind)
	return true


## Ends this encounter after a while - unless it has already ended and another begun.
func _end_later(seconds: float, outcome: String) -> void:
	var serial := _serial
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if serial == _serial and active != "":
			_end(outcome))


func _end(outcome: String) -> void:
	_serial += 1
	var kind := active
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	active = ""
	resolved.emit(kind, outcome)


# ---------------------------------------------------------------------------
# Where
# ---------------------------------------------------------------------------
func _find_spot() -> Vector3:
	var p := _player.global_position
	if place == "london":
		var city := get_tree().get_first_node_in_group("city_streamer") as CityStreamer
		var doors: Array = city.near_doors() if city else []
		for attempt in 16:
			if doors.is_empty():
				break
			var d: Array = doors[_rng.randi() % doors.size()]
			var q: Vector3 = d[0]
			var dist := Vector2(q.x - p.x, q.z - p.z).length()
			if dist > 22.0 and dist < 60.0:
				q.y = city.plan.ground_y(q.x, q.z) + 0.05
				return q
		# In the old streets: a spot on the navigation mesh near Harry.
		var map := (get_parent() as Node3D).get_world_3d().navigation_map
		for attempt in 8:
			var a := _rng.randf() * TAU
			var q := NavigationServer3D.map_get_closest_point(map, p + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(20.0, 45.0))
			if q.distance_to(p) > 15.0:
				return q + Vector3(0, 0.05, 0)
		return Vector3.INF
	# Hills: on the road near Harry.
	var gen := (get_tree().get_first_node_in_group("world_streamer") as WorldStreamer).generator
	# Every point along the road and lanes 30-90 m away, then one of them at random.
	var found: Array[Vector2] = []
	var pp := Vector2(p.x, p.z)
	for path: Array in [TerrainGenerator.ROAD] + TerrainGenerator.LANES:
		for k in path.size() - 1:
			var a: Vector2 = path[k]
			var b: Vector2 = path[k + 1]
			var n := maxi(1, int(a.distance_to(b) / 5.0))
			for m in n:
				var q := a.lerp(b, float(m) / n)
				var d := q.distance_to(pp)
				if d > 30.0 and d < 90.0:
					found.append(q)
	if found.is_empty():
		return Vector3.INF
	var q2 := found[_rng.randi() % found.size()]
	return Vector3(q2.x, gen.height(q2.x, q2.y) + 0.1, q2.y)


func _person(name_: String, outfit: NPCBody.Outfit, at: Vector3, height := 1.74, pose := NPCBody.Pose.NORMAL) -> StoryNPC:
	var n := StoryNPC.new()
	n.name = name_.replace(" ", "") + str(_rng.randi() % 1000)
	n.display_name = name_
	n.outfit = outfit
	n.body_height = height
	n.idle_pose = pose
	n.use_navmesh = place == "london"
	n.look_seed = _rng.randi() % 100000
	add_child(n)
	if place == "london" and at.y < 1.0:
		# Onto the walkable pavement (not inside a doorway or a railing).
		var map := (get_parent() as Node3D).get_world_3d().navigation_map
		var q := NavigationServer3D.map_get_closest_point(map, at)
		if q.distance_to(at) < 4.0:
			at = Vector3(q.x, at.y, q.z)
	n.global_position = at
	_nodes.append(n)
	return n


func _prompt(on: Node3D, text: Callable, action: Callable, reach := 2.2) -> EncounterAction:
	var a := EncounterAction.new()
	a.text = text
	a.action = action
	a.interact_range = reach
	on.add_child(a)
	a.position = Vector3(0, 1.3, 0)
	return a


func _say(n: StoryNPC, line: String) -> void:
	if is_instance_valid(n) and _player.global_position.distance_to(n.global_position) < 40.0:
		n.say(line)


func _dialogue(speaker: String, line: String) -> void:
	StoryUI.find(get_tree()).dialogue.play([[speaker, line]])


# ---------------------------------------------------------------------------
# London
# ---------------------------------------------------------------------------
func _purse_snatch(spot: Vector3) -> void:
	# He runs for it, away from Harry (starting from the lady's far side).
	var away := (spot - _player.global_position)
	away.y = 0.0
	var lady := _person("Lady", NPCBody.Outfit.LADY, spot, 1.64, NPCBody.Pose.SHOUT)
	var thief := _person("Cutpurse", NPCBody.Outfit.RAGGED, spot + away.normalized() * 1.6, 1.66)
	lady.face(thief)
	thief.add_collision_exception_with(lady) # he barges past her
	thief.collision_mask &= ~NPCCharacter.LAYER_NPC # and dodges through the crowd
	_state = {"lady": lady, "thief": thief, "phase": "run", "purse": false}
	var run_to := spot + away.normalized() * 70.0 + Vector3(_rng.randf_range(-20, 20), 0, _rng.randf_range(-20, 20))
	if place == "london":
		run_to = _escape_route(thief.global_position, away.normalized())
	# (A moment for his pathfinding to wake up, then he's off.)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if is_instance_valid(thief) and _state.get("phase") == "run":
			thief.go_to(run_to, 4.3))
	_say(lady, "Stop, thief! He's got my purse!")
	_prompt(thief, func() -> String: return "Grab the thief" if _state.get("phase") == "run" else "", func() -> void:
		_state["phase"] = "caught"
		_state["purse"] = true
		thief.set_puppet(true)
		thief.pose_override = NPCBody.Pose.STUNNED
		_say(thief, "All right, all right! Take it, guv!")
		Stealth.bark(_player, "Harry takes back the purse.")
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if is_instance_valid(thief):
				thief.set_puppet(false)
				thief.pose_override = -1
				thief.go_to(run_to, 4.0)), 1.9)
	_prompt(lady, func() -> String: return "Give the lady her purse back" if _state.get("purse", false) else "", func() -> void:
		_state["purse"] = false
		Progress.add_legend(3.0, "returned a stolen purse")
		_player.inventory.add_money(6)
		_dialogue("Lady", "Oh, bless you, sir! Here - take this sixpence for your trouble.")
		lady.pose_override = NPCBody.Pose.TALK
		_end_later(6.0, "returned"))


## Somewhere 40-80 m off, mostly away from Harry, that the navigation mesh can really
## reach from `from` (not an island behind railings or over the river).
func _escape_route(from: Vector3, away: Vector3) -> Vector3:
	var map := (get_parent() as Node3D).get_world_3d().navigation_map
	var best := from
	var best_len := 0.0
	for attempt in 12:
		var ang := _rng.randf_range(-1.2, 1.2) if attempt < 8 else _rng.randf() * TAU
		var dir := away.rotated(Vector3.UP, ang)
		var target := NavigationServer3D.map_get_closest_point(map, from + dir * _rng.randf_range(40.0, 80.0))
		var path := NavigationServer3D.map_get_path(map, from, target, true)
		if path.is_empty() or path[path.size() - 1].distance_to(target) > 2.0:
			continue
		var length := 0.0
		for k in path.size() - 1:
			length += path[k].distance_to(path[k + 1])
		if length > 25.0:
			return target
		if length > best_len:
			best_len = length
			best = target
	return best


func _brawl(spot: Vector3) -> void:
	var a := _person("Drunk", NPCBody.Outfit.WORKER, spot, 1.76, NPCBody.Pose.GUARD)
	var b := _person("Drunk", NPCBody.Outfit.WORKER, spot + Vector3(1.3, 0, 0), 1.8, NPCBody.Pose.GUARD)
	a.face(b)
	b.face(a)
	_state = {"a": a, "b": b, "t": 0.0}
	for k in 4:
		var ang := TAU * k / 4.0 + 0.4
		var g := _person("Onlooker", [NPCBody.Outfit.WORKER, NPCBody.Outfit.LADY, NPCBody.Outfit.RAGGED][k % 3], spot + Vector3(cos(ang) * 4.0, 0, sin(ang) * 4.0), 1.7, NPCBody.Pose.SHOUT if k % 2 == 0 else NPCBody.Pose.NORMAL)
		g.face(spot)
	_prompt(a, func() -> String: return "Break up the fight", func() -> void:
		Progress.add_legend(1.0, "broke up a brawl")
		_say(a, "Alright, alright... he started it.")
		for n in [a, b]:
			(n as StoryNPC).pose_override = NPCBody.Pose.NORMAL
		_end_later(4.0, "broken_up"), 2.4)


func _preacher(spot: Vector3) -> void:
	var box := StreetProps.make_crate(0.6)
	box.freeze = true
	add_child(box)
	box.global_position = spot + Vector3(0, 0.3, 0)
	_nodes.append(box)
	var preacher := _person("Street preacher", NPCBody.Outfit.PRIEST, spot + Vector3(0, 0.62, 0), 1.72, NPCBody.Pose.SHOUT)
	preacher.set_puppet(true)
	_state = {"preacher": preacher, "t": 0.0}
	for k in 5:
		var ang := PI * 0.3 + k * 0.45
		var l := _person("Listener", [NPCBody.Outfit.WORKER, NPCBody.Outfit.LADY, NPCBody.Outfit.GENTLEMAN, NPCBody.Outfit.RAGGED][k % 4], spot + Vector3(cos(ang) * 3.5, 0, sin(ang) * 3.5), 1.7)
		l.face(preacher)
	_prompt(preacher, func() -> String: return "Listen to the sermon", func() -> void:
		_dialogue("Street preacher", SERMONS[_rng.randi() % SERMONS.size()] + " Go in peace, friend."), 3.0)


func _beggar(spot: Vector3) -> void:
	var child := _person("Ragged child", NPCBody.Outfit.RAGGED, spot, 1.3, NPCBody.Pose.WAVE)
	child.face(_player)
	_state = {"child": child, "given": false}
	_say(child, "Spare a penny, mister? Ain't 'ad nothin' since yesterday.")
	_prompt(child, func() -> String: return "Give a penny (1d)" if not _state["given"] and _player.inventory.money >= 1 else "", func() -> void:
		_state["given"] = true
		_player.inventory.add_money(-1)
		Progress.add_legend(0.5, "gave to a hungry child")
		Progress.on_given(1)
		_dialogue("Ragged child", "Cor! Thank you, mister! God bless!")
		child.idle_pose = NPCBody.Pose.NORMAL
		_end_later(5.0, "given"))


# ---------------------------------------------------------------------------
# Hills
# ---------------------------------------------------------------------------
func _highwayman(spot: Vector3) -> void:
	var victim := _person("Traveller", NPCBody.Outfit.GENTLEMAN, spot, 1.76, NPCBody.Pose.ALERT)
	var robber := _person("Highwayman", NPCBody.Outfit.WORKER, spot + Vector3(2.2, 0, 0.6), 1.82, NPCBody.Pose.GUARD)
	victim.face(robber)
	robber.face(victim)
	_state = {"victim": victim, "robber": robber, "phase": "robbing", "t": 0.0}


func _stuck_cart(spot: Vector3) -> void:
	var carter := _person("Carter", NPCBody.Outfit.WORKER, spot, 1.74, NPCBody.Pose.WAVE)
	var gen := (get_tree().get_first_node_in_group("world_streamer") as WorldStreamer).generator
	var cart := HorseVehicle.new()
	cart.name = "StuckCart"
	cart.kind = HorseVehicle.Kind.CART
	cart.height_fn = gen.height
	add_child(cart)
	cart.place(spot + Vector3(3.0, 0, 0), Vector3(0, 0, -1))
	_nodes.append(cart)
	carter.face(cart)
	_state = {"carter": carter, "done": false}
	_say(carter, "You there! Lend a shoulder? My wheel's sunk in the rut.")
	var act := _prompt(carter, func() -> String: return "Help push the cart" if not _state["done"] else "", func() -> void:
		pass, 2.6)
	act.hold_seconds = 3.0
	act.on_done = func() -> void:
		_state["done"] = true
		_player.inventory.add_money(3)
		Progress.add_legend(1.0, "helped a carter on the road")
		_dialogue("Carter", "She's free! Thank 'ee kindly - here's thruppence, and God bless.")
		cart.cruise = 2.8
		var fwd := Vector3(0, 0, -1)
		for k in 8:
			cart.waypoints.append(cart.global_position + fwd * (12.0 * (k + 1)))
		carter.follow(cart, 3.0, 2.2)
		_end_later(12.0, "helped")


# ---------------------------------------------------------------------------
func _update(delta: float) -> void:
	match active:
		"brawl":
			_state["t"] = float(_state["t"]) + delta
			var a := _state.get("a") as StoryNPC
			var b := _state.get("b") as StoryNPC
			if is_instance_valid(a) and is_instance_valid(b) and a.pose_override != NPCBody.Pose.NORMAL:
				var beat := int(float(_state["t"]) / 0.7) % 4
				a.pose_override = NPCBody.Pose.PUNCH if beat == 0 else NPCBody.Pose.GUARD
				b.pose_override = NPCBody.Pose.PUNCH if beat == 2 else NPCBody.Pose.GUARD
				if beat == 1 and fmod(float(_state["t"]), 5.0) < delta:
					_say(a if _rng.randf() < 0.5 else b, INSULTS[_rng.randi() % INSULTS.size()])
		"preacher":
			_state["t"] = float(_state["t"]) + delta
			if fmod(float(_state["t"]), 9.0) < delta:
				_say(_state["preacher"], SERMONS[_rng.randi() % SERMONS.size()])
		"purse_snatch":
			var thief := _state.get("thief") as StoryNPC
			if _age > 3.0 and _state.get("phase") == "run" and is_instance_valid(thief) and thief.has_arrived():
				_end("escaped")
		"highwayman":
			_state["t"] = float(_state["t"]) + delta
			var robber := _state.get("robber") as StoryNPC
			var victim := _state.get("victim") as StoryNPC
			if _state["phase"] == "robbing":
				if fmod(float(_state["t"]), 7.0) < delta:
					_say(robber, ["Stand and deliver!", "Your purse, or your life!", "Quick now, and nobody gets hurt."][_rng.randi() % 3])
				if is_instance_valid(robber) and _player.global_position.distance_to(robber.global_position) < 14.0:
					_state["phase"] = "fled"
					_say(robber, "Hell's teeth - it's the Fox! I'm off!")
					var away := robber.global_position - _player.global_position
					away.y = 0.0
					robber.go_to(robber.global_position + away.normalized() * 120.0, 5.0)
					victim.idle_pose = NPCBody.Pose.NORMAL
					victim.face(_player)
					_prompt(victim, func() -> String: return "Talk to the traveller" if _state["phase"] == "fled" else "", func() -> void:
						_state["phase"] = "thanked"
						_player.inventory.add_money(24)
						Progress.add_legend(2.0, "saw off a highwayman")
						_dialogue("Traveller", "You saved my neck, friend. Two shillings - it's little enough.")
						_end_later(8.0, "rescued"))
