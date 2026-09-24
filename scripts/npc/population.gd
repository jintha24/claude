class_name Population
extends Node3D
## Brings the town to life around the clock (node "Population" in main.tscn).
##
## The town has a roster of residents (DailyRoutine), each with a home, a trade and a
## daily routine, and every one of them is where their routine puts them:
##   * Costermongers leave home at half past six, keep their stall till half past six in
##     the evening and walk home again.
##   * Clerks and shopmen walk to work, come out to the market in their dinner hour,
##     go back, and walk home in the evening (Saturday: a half day).
##   * Housewives do the family's shopping, a different hour each day, and call at a shop
##     on the way home. Pensioners take their morning turn about the market.
##   * Gentlemen call at a shop, browse the market and spend the afternoon at the club.
##   * Labourers are off to the docks before six and home at six (Saturday: one o'clock).
##   * Rookery folk of St Giles work in their yards, queue at the soup kitchen at midday
##     and go back to their lodgings at night.
##   * Sunday morning: church. Evenings: some go to the pub, a few go home early and the
##     rest are turned out at half past midnight to stagger home, singing.
## People come out of their own front door and go in through a real one. In foul weather,
## or with the crowd density turned down, some stay at home rather than go shopping.
## Sleeping, waiting or loading a save puts everyone where they'd be at the new hour.

const TRADE_OPEN := 6.5
const TRADE_CLOSE := 18.5
const MARKET_Z := -46.0
## How many of each trade live in town (St Giles folk are added when the district exists).
const ROSTER := {"clerk": 24, "housewife": 22, "gentleman": 10, "labourer": 22, "pensioner": 9}
const ROOKERY_FOLK := 9
const ROOKERY_NAMES: Array[String] = ["Old Meg", "Dan Tully", "Widow Carey", "Nell Doyle", "Paddy Burke", "Sal Finn", "Jem Tighe", "Biddy Walsh", "Ned Quill"]

@export var market_path: NodePath = ^"../MarketSquare"
## Scales every crowd (Settings, Phase 9: lower on slower PCs).
@export var density: float = 1.0

## Stall index -> the Civilian keeping (or setting up) that stall.
var traders := {}
var residents: Array[DailyRoutine] = []

var _market: MarketSquare
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _ready_done := false
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
	_build_roster()
	_ready_done = true
	_rebuild()


func _process(delta: float) -> void:
	if not _ready_done:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_update(false)


## Counts the people of one kind out of doors: "trader", "shopper", "passer" (walking
## somewhere), "pubgoer" (on the way to the pub), "drunk", "rookery", "churchgoer".
## People on their way home early (sent in by rain) don't count.
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


## Today's weekday, 0 = Saturday .. 6 = Friday (GameClock.WEEKDAYS).
static func weekday() -> int:
	return GameClock.WEEKDAYS.find(GameClock.date_string().get_slice(" ", 0))


## The resident a Civilian is, or null.
func resident_of(c: Civilian) -> DailyRoutine:
	var i: int = c.get_meta("resident", -1)
	return residents[i] if i >= 0 and i < residents.size() else null


# ---------------------------------------------------------------------------
# The roster
# ---------------------------------------------------------------------------
func _build_roster() -> void:
	residents.clear()
	var homes := _doors("house").filter(func(d: Node3D) -> bool: return not _in_rookery(d.global_position))
	var rookery_homes := _doors("house").filter(func(d: Node3D) -> bool: return _in_rookery(d.global_position))
	var shops := _doors("shop")
	var pubs := _doors("pub")
	var churches := _doors("church")
	if homes.is_empty():
		homes = _doors("any")
	if homes.is_empty():
		return
	var plan: Array = []
	if _market:
		for i in _market.stalls.size():
			plan.append(["costermonger", i])
	for job: String in ROSTER:
		for i in ROSTER[job]:
			plan.append([job, -1])
	if not rookery_homes.is_empty() and get_tree().get_first_node_in_group("st_giles") != null:
		for i in ROOKERY_FOLK:
			plan.append(["rookery", i])
	for entry: Array in plan:
		var r := DailyRoutine.create(residents.size(), entry[0], _rng)
		if r.job == "costermonger":
			r.stall = entry[1]
		if r.job == "rookery":
			r.display_name = ROOKERY_NAMES[int(entry[1]) % ROOKERY_NAMES.size()]
			r.home = rookery_homes[_rng.randi() % rookery_homes.size()]
			var yards: Array = StGiles.YARDS
			var y: Array = yards[int(entry[1]) % yards.size()]
			r.yard_center = y[0]
			r.yard_extent = y[1]
		else:
			r.display_name = _random_name(r.outfit)
			r.home = homes[_rng.randi() % homes.size()]
		# Where they work, drink, pray and shop.
		match r.job:
			"clerk", "gentleman":
				r.work = shops[_rng.randi() % shops.size()] if not shops.is_empty() else null
			"labourer":
				r.work = _far_door(r.home, homes)
		r.pub = _nearest(r.home.global_position, pubs) if _rng.randf() < 0.6 or pubs.size() < 2 else (pubs[_rng.randi() % pubs.size()] if not pubs.is_empty() else null)
		r.church = churches[0] if not churches.is_empty() else null
		for k in 3:
			if not shops.is_empty():
				r.errands.append(shops[_rng.randi() % shops.size()])
		r.place = r.home
		residents.append(r)


func _in_rookery(p: Vector3) -> bool:
	return p.x < StGiles.TERRACE_BACK_X


func _far_door(from: Node3D, doors: Array) -> Node3D:
	var best: Node3D = from
	var best_d := -1.0
	for i in 6:
		var d: Node3D = doors[_rng.randi() % doors.size()]
		var dist := d.global_position.distance_to(from.global_position)
		if dist > best_d:
			best_d = dist
			best = d
	return best


func _nearest(p: Vector3, doors: Array) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for d: Node3D in doors:
		var dist := d.global_position.distance_to(p)
		if dist < best_d:
			best_d = dist
			best = d
	return best


# ---------------------------------------------------------------------------
# Following the routines
# ---------------------------------------------------------------------------
func _rebuild() -> void:
	if not _ready_done:
		return
	for c in get_children():
		if c is Civilian:
			c.queue_free()
	traders.clear()
	for r in residents:
		r.civ = null
		r.activity = ""
		r.place = r.home
	_update(true)


func _update(immediate: bool) -> void:
	var h := GameClock.hours()
	var wd := weekday()
	# Fewer people go out shopping in the rain, fog or snow, or on a slow PC.
	var keen := Weather.population_factor() * density
	for r in residents:
		var act := r.activity_at(h, wd)
		if act in DailyRoutine.OPTIONAL and r.rank > keen:
			act = DailyRoutine.HOME
		_follow(r, act, h, immediate)
	# Tidy the traders' register.
	for i in traders.keys():
		var t: Civilian = traders[i]
		if not is_instance_valid(t) or t.leaving:
			traders.erase(i)


func _follow(r: DailyRoutine, act: String, h: float, immediate: bool) -> void:
	if r.civ != null and not is_instance_valid(r.civ):
		# They went in somewhere (their destination, or out of the rain): they're behind that door.
		r.civ = null
	if act == r.activity and (r.civ != null or not r.is_outdoor(act)):
		return
	# Out of the rain: whoever went in to shelter stays in until it eases (traders excepted).
	if r.is_outdoor(act) and r.civ == null and not immediate and act != DailyRoutine.STALL and Weather.rain >= 0.15:
		r.activity = act
		return
	var previous := r.activity
	r.activity = act
	if r.is_outdoor(act):
		_go_out(r, act, immediate)
		return
	# Indoors somewhere: walk there and go in.
	var door := r.door_for(act)
	if immediate:
		if r.civ:
			r.civ.queue_free()
			r.civ = null
		r.place = door
		return
	if r.civ == null:
		if door == r.place:
			return
		r.civ = _spawn(r, r.place.global_position)
	var c := r.civ
	if r.stall >= 0 and traders.get(r.stall) == c:
		traders.erase(r.stall)
	c.is_merchant = false
	c.set_meta("dismissed", false)
	# A costermonger packing up is still a trader on the way home.
	c.set_meta("kind", "trader" if previous == DailyRoutine.STALL else _walking_kind(act))
	# Turned out of the pub after midnight: three sheets to the wind.
	if previous == DailyRoutine.PUB and (h >= 23.5 or h < 4.0):
		c.set_drunk(true)
		c.set_meta("kind", "drunk")
	c.go_to(door.global_position, "vanish")
	r.place = door


func _go_out(r: DailyRoutine, act: String, immediate: bool) -> void:
	var target := _outdoor_point(r, act)
	var c := r.civ
	if c == null:
		c = _spawn(r, target if immediate else r.place.global_position)
		r.civ = c
	c.set_meta("dismissed", false)
	c.is_merchant = false
	match act:
		DailyRoutine.STALL:
			c.set_meta("kind", "trader")
			var spot := _market.get_trader_spot(r.stall)
			c.stall_point = spot[0]
			c.stall_look = spot[1]
			if immediate:
				c.global_position = spot[0]
				c.position = spot[0]
				c.is_merchant = true
				c.state = Civilian.State.TEND_STALL
			else:
				c.go_to(spot[0], "stall")
			traders[r.stall] = c
		DailyRoutine.MARKET:
			c.set_meta("kind", "shopper")
			c.wander_center = _market.get_wander_center() if _market else r.home.global_position
			c.wander_extent = _market.get_wander_extent() if _market else Vector2(6, 6)
			if immediate:
				c.start_wandering()
			else:
				c.go_to(target, "wander")
		DailyRoutine.YARD, DailyRoutine.SOUP:
			c.set_meta("kind", "rookery")
			c.wander_center = r.yard_center if act == DailyRoutine.YARD else StGiles.SOUP_POINT + Vector3(4.0, 0.0, 1.0)
			c.wander_extent = r.yard_extent if act == DailyRoutine.YARD else Vector2(3.0, 3.0)
			if immediate:
				c.start_wandering()
			else:
				c.go_to(target, "wander")
	r.place = r.home


func _outdoor_point(r: DailyRoutine, act: String) -> Vector3:
	match act:
		DailyRoutine.STALL:
			return _market.get_trader_spot(r.stall)[0] if _market else r.home.global_position
		DailyRoutine.MARKET:
			return _random_market_point() if _market else r.home.global_position
		DailyRoutine.YARD:
			return r.yard_center + Vector3(_rng.randf_range(-r.yard_extent.x, r.yard_extent.x), 0.05, _rng.randf_range(-r.yard_extent.y, r.yard_extent.y))
		DailyRoutine.SOUP:
			return StGiles.SOUP_POINT + Vector3(_rng.randf_range(2.0, 6.0), 0.05, _rng.randf_range(-2.0, 4.0))
	return r.home.global_position


static func _walking_kind(act: String) -> String:
	match act:
		DailyRoutine.PUB:
			return "pubgoer"
		DailyRoutine.CHURCH:
			return "churchgoer"
	return "passer"


func _spawn(r: DailyRoutine, at: Vector3) -> Civilian:
	var c := Civilian.new()
	_serial += 1
	c.name = "%s_%d" % [r.job.capitalize(), _serial]
	c.outfit = r.outfit
	c.display_name = r.display_name
	c.look_seed = r.look_seed
	c.fixed_height = r.height
	c.set_meta("resident", r.id)
	c.set_meta("job", r.job)
	c.state = Civilian.State.TRAVEL
	c.position = at
	add_child(c)
	return c


# ---------------------------------------------------------------------------
func _doors(kind: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("npc_doors"):
		var m := n as Node3D
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
	var surnames := ["Clarke", "Hughes", "Price", "Evans", "Shaw", "Moss", "Riley", "Dawes", "Pratt", "Leach", "Bell", "Stone", "Hale", "Gates", "Webb", "Tanner", "Hobbs", "Kemp",
		"Pike", "Norris", "Dunn", "Rudd", "Cole", "Mercer", "Tate", "Ashby", "Crane", "Voss", "Blake", "Hurst"]
	var title := "Mr"
	if outfit == NPCBody.Outfit.LADY:
		title = "Mrs" if _rng.randf() < 0.6 else "Miss"
	return "%s %s" % [title, surnames[_rng.randi() % surnames.size()]]
