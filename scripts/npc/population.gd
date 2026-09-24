class_name Population
extends Node3D
## Brings the town to life around the clock (node "Population" in main.tscn).
##
## Everybody comes out of, and goes back into, a real door (house, shop or pub):
##   * Traders: arrive and set up their stalls from 6:30, trade until 6:30 pm, pack up.
##   * Shoppers: fill the market by the hour, thickest late morning to mid afternoon.
##   * Passers-by: people going to and from work along the street, fewest at night.
##   * Pub-goers: head for the Crown & Anchor, the Ten Bells and the White Hart in the
##     evening; at closing time (half past midnight) drunks weave home, singing.
## Sleeping, waiting or loading a save rebuilds the town instantly for the new hour.

## How many shoppers fill the market at each hour (interpolated).
const SHOPPER_CURVE: Array[Vector2] = [
	Vector2(0, 0), Vector2(5, 0), Vector2(6.5, 3), Vector2(8, 10), Vector2(10, 24), Vector2(12, 30),
	Vector2(15, 30), Vector2(17, 22), Vector2(18.5, 12), Vector2(20, 4), Vector2(22, 1), Vector2(24, 0),
]
## How many passers-by are on the street at each hour.
const PASSER_CURVE: Array[Vector2] = [
	Vector2(0, 1), Vector2(5, 1), Vector2(7, 8), Vector2(9, 10), Vector2(18, 10), Vector2(20, 6),
	Vector2(23, 3), Vector2(24, 1),
]
const TRADE_OPEN := 6.5
const TRADE_CLOSE := 18.5
const MARKET_Z := -46.0

@export var market_path: NodePath = ^"../MarketSquare"
## Scales every crowd (Settings, Phase 9: lower on slower PCs).
@export var density: float = 1.0

var traders := {} # stall index -> Civilian

var _market: MarketSquare
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _ready_done := false
## Absolute game minute of the next pub-goer / drunk (so it works at any clock speed).
var _next_pub_minute := -1.0
var _serial := 0


func _ready() -> void:
	_rng.seed = 1866
	_market = get_node_or_null(market_path) as MarketSquare
	GameClock.bus().time_jumped.connect(func(_h: float) -> void: _rebuild())
	_start.call_deferred()


func _start() -> void:
	# Wait until the navigation mesh has been baked and synced.
	while NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) == 0:
		await get_tree().physics_frame
	await get_tree().physics_frame
	_ready_done = true
	_rebuild()


func _process(delta: float) -> void:
	if not _ready_done:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_update(false)


## Counts each kind of person currently out. People sent home early (dismissed because
## the crowd is thinning) don't count; people simply on their way somewhere do.
func count(kind: String) -> int:
	var n := 0
	for c in get_children():
		if c is Civilian and not c.is_queued_for_deletion() and not c.get_meta("dismissed", false) and c.get_meta("kind", "") == kind:
			n += 1
	return n


static func curve_value(curve: Array[Vector2], h: float) -> float:
	for i in curve.size() - 1:
		var a := curve[i]
		var b := curve[i + 1]
		if h >= a.x and h <= b.x:
			return lerpf(a.y, b.y, (h - a.x) / maxf(b.x - a.x, 0.001))
	return curve[-1].y


func _rebuild() -> void:
	if not _ready_done:
		return
	for c in get_children():
		if c is Civilian:
			c.queue_free()
	traders.clear()
	_next_pub_minute = -1.0
	_update(true)


func _update(immediate: bool) -> void:
	var h := GameClock.hours()
	_update_traders(h, immediate)
	_update_crowd("shopper", roundi(curve_value(SHOPPER_CURVE, h) * density), immediate)
	_update_crowd("passer", roundi(curve_value(PASSER_CURVE, h) * density), immediate)
	_update_pubs(h, immediate)


func _update_traders(h: float, immediate: bool) -> void:
	if _market == null:
		return
	var open := h >= TRADE_OPEN and h < TRADE_CLOSE
	for i in _market.stalls.size():
		var t: Civilian = traders.get(i)
		if t != null and not is_instance_valid(t):
			traders.erase(i)
			t = null
		if open and t == null:
			# Stagger arrivals over the first half hour.
			if not immediate and h < TRADE_OPEN + 0.5 and _rng.randf() > 0.25:
				continue
			var spot := _market.get_trader_spot(i)
			var c := _make_person("trader", NPCBody.Outfit.WORKER if i % 3 != 0 else NPCBody.Outfit.LADY, "Costermonger")
			c.stall_look = spot[1]
			if immediate:
				c.is_merchant = true
				c.state = Civilian.State.TEND_STALL
				c.stall_point = spot[0]
				c.position = spot[0]
				add_child(c)
			else:
				c.position = _door_near(spot[0]).global_position
				c.go_to(spot[0], "stall")
				c.stall_point = spot[0]
				add_child(c)
			traders[i] = c
		elif not open and t != null and not t.leaving:
			if immediate:
				t.queue_free()
			else:
				t.is_merchant = false
				t.go_to(_door_near(t.global_position).global_position, "vanish")
			traders.erase(i)


func _update_crowd(kind: String, target: int, immediate: bool) -> void:
	var current := count(kind)
	if current < target:
		var add := target - current if immediate else mini(target - current, 2)
		for i in add:
			_spawn_crowd_member(kind, immediate)
	elif current > target:
		var extra := current - target if immediate else mini(current - target, 2)
		for c in get_children():
			if extra <= 0:
				break
			if c is Civilian and c.get_meta("kind", "") == kind and not c.get_meta("dismissed", false):
				if immediate:
					c.queue_free()
				else:
					var civ := c as Civilian
					civ.set_meta("dismissed", true)
					civ.go_to(_door_near(civ.global_position).global_position, "vanish")
				extra -= 1


func _spawn_crowd_member(kind: String, immediate: bool) -> void:
	var roll := _rng.randf()
	var outfit := NPCBody.Outfit.GENTLEMAN if roll < 0.25 else (NPCBody.Outfit.LADY if roll < 0.55 else NPCBody.Outfit.WORKER)
	var c := _make_person(kind, outfit, _random_name(outfit))
	if kind == "shopper" and _market:
		c.wander_center = _market.get_wander_center()
		c.wander_extent = _market.get_wander_extent()
		if immediate:
			c.position = _random_market_point()
		else:
			c.position = _random_door("market").global_position
			c.go_to(_random_market_point(), "wander")
		add_child(c)
	else:
		# Passers-by walk from one street door to another and go in.
		var from := _random_door("street")
		var to := _random_door("street")
		c.position = from.global_position
		if immediate:
			c.position = Vector3(_rng.randf_range(-5.0, 5.0), 0.1, _rng.randf_range(-40.0, 40.0))
		add_child(c)
		c.go_to(to.global_position, "vanish")


func _update_pubs(h: float, _immediate: bool) -> void:
	var now := GameClock.day * 1440.0 + GameClock.minutes
	if _next_pub_minute < 0.0:
		_next_pub_minute = now
	if now < _next_pub_minute:
		return
	var pubs := _doors("pub")
	if pubs.is_empty():
		return
	if h >= 19.0 and h < 23.0:
		# Evening: someone heads for the pub every few minutes.
		_next_pub_minute = now + _rng.randf_range(4.0, 10.0)
		var c := _make_person("pubgoer", NPCBody.Outfit.WORKER if _rng.randf() < 0.7 else NPCBody.Outfit.GENTLEMAN, "")
		c.display_name = _random_name(c.outfit)
		c.position = _random_door("any").global_position
		add_child(c)
		c.go_to(pubs[_rng.randi() % pubs.size()].global_position, "vanish")
	elif h >= 0.5 and h < 1.5:
		# Closing time: out they stagger.
		_next_pub_minute = now + _rng.randf_range(3.0, 7.0)
		var c := _make_person("drunk", NPCBody.Outfit.WORKER, "")
		c.display_name = _random_name(c.outfit)
		c.drunk = true
		c.position = pubs[_rng.randi() % pubs.size()].global_position
		add_child(c)
		c.go_to(_random_door("house").global_position, "vanish")


# ---------------------------------------------------------------------------
func _make_person(kind: String, outfit: NPCBody.Outfit, display: String) -> Civilian:
	var c := Civilian.new()
	_serial += 1
	c.name = "%s_%d" % [kind.capitalize(), _serial]
	c.outfit = outfit
	c.display_name = display if display != "" else _random_name(outfit)
	c.set_meta("kind", kind)
	c.state = Civilian.State.TRAVEL if kind != "shopper" else Civilian.State.WANDER
	return c


func _doors(kind: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for n in get_tree().get_nodes_in_group("npc_doors"):
		var m := n as Marker3D
		var in_market := m.global_position.z < MARKET_Z
		var k: String = m.get_meta("kind", "house")
		match kind:
			"market":
				if in_market:
					out.append(m)
			"street":
				if not in_market:
					out.append(m)
			"any":
				out.append(m)
			_:
				if k == kind:
					out.append(m)
	return out


func _random_door(kind: String) -> Marker3D:
	var list := _doors(kind)
	if list.is_empty():
		list = _doors("any")
	return list[_rng.randi() % list.size()]


func _door_near(p: Vector3) -> Marker3D:
	var best: Marker3D = null
	var best_d := INF
	for m in _doors("any"):
		var d := m.global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = m
	return best


func _random_market_point() -> Vector3:
	var c := _market.get_wander_center()
	var e := _market.get_wander_extent()
	for attempt in 10:
		var p := c + Vector3(_rng.randf_range(-e.x, e.x), 0.05, _rng.randf_range(-e.y, e.y))
		var clear := true
		for s in _market.stalls:
			if Vector2(p.x - s.global_position.x, p.z - s.global_position.z).length() < 2.4:
				clear = false
				break
		if clear:
			return p
	return c


func _random_name(outfit: NPCBody.Outfit) -> String:
	var surnames := ["Clarke", "Hughes", "Price", "Evans", "Shaw", "Moss", "Riley", "Dawes", "Pratt", "Leach", "Bell", "Stone", "Hale", "Gates", "Webb", "Tanner", "Hobbs", "Kemp"]
	var title := "Mr"
	if outfit == NPCBody.Outfit.LADY:
		title = "Mrs" if _rng.randf() < 0.6 else "Miss"
	return "%s %s" % [title, surnames[_rng.randi() % surnames.size()]]
