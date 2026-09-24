class_name StreetPatrols
extends Node3D
## The Metropolitan Police on the test street and market (1866), on two shifts.
##
## Day shift (6 am - 6 pm): Bates walks the pavements, Wren guards the bank door, Pike walks
## the carriageway and looks into the private yard, Dunn walks the market square.
## Night shift (6 pm - 6 am): Hale, Moss, Tully and Rook take the same beats, each with a
## bullseye lantern.
## At a change of shift the outgoing men walk back to the station (the south end of the
## street) and go home; their relief arrives a few minutes later. That gap is a window.

const PAVE := 0.15
const STATION := Vector3(0.0, 0.0, 44.3)
const SHIFT_START_DAY := 6
const SHIFT_START_NIGHT := 18
## Game minutes between the old shift leaving and the new one arriving.
const RELIEF_DELAY_MINUTES := 6.0

var on_night_shift := false
var _routes := {}
var _relief_pending := false
var _relief_timer := 0.0


func _ready() -> void:
	_routes["pavements"] = _route("PavementBeat", [
		[Vector3(-4.6, PAVE, 40.0), 4.0, -PI * 0.5], [Vector3(-4.6, PAVE, 0.0), 0.0, NAN],
		[Vector3(-4.6, PAVE, -40.0), 4.0, -PI * 0.5], [Vector3(4.6, PAVE, -40.0), 4.0, PI * 0.5],
		[Vector3(4.6, PAVE, 0.0), 0.0, NAN], [Vector3(4.6, PAVE, 40.0), 4.0, PI * 0.5],
	], true)
	_routes["carriageway"] = _route("CarriagewayBeat", [
		[Vector3(0.0, 0.0, 30.0), 3.0, 0.0], [Vector3(1.0, 0.0, 6.0), 0.0, NAN],
		[Vector3(7.4, PAVE, 5.2), 5.0, -PI * 0.5], [Vector3(0.0, 0.0, -30.0), 3.0, PI],
	], false)
	_routes["market"] = _route("MarketBeat", [
		[Vector3(-20.0, 0.0, -55.5), 3.0, NAN], [Vector3(-20.0, 0.0, -86.0), 3.0, NAN],
		[Vector3(20.0, 0.0, -86.0), 3.0, NAN], [Vector3(20.0, 0.0, -55.5), 3.0, NAN],
		[Vector3(0.0, 0.0, -70.5), 5.0, NAN],
	], true)
	var h := GameClock.hours()
	on_night_shift = h >= SHIFT_START_NIGHT or h < SHIFT_START_DAY
	_spawn_shift(on_night_shift, true)
	GameClock.bus().hour_passed.connect(_on_hour)
	GameClock.bus().time_jumped.connect(_on_time_jumped)


func _process(delta: float) -> void:
	if not _relief_pending:
		return
	_relief_timer -= delta * 1440.0 / (GameClock.real_minutes_per_game_day * 60.0)
	if _relief_timer <= 0.0:
		_relief_pending = false
		_spawn_shift(on_night_shift, false)


func _on_hour(hour: int) -> void:
	if hour == SHIFT_START_DAY or hour == SHIFT_START_NIGHT:
		on_night_shift = hour == SHIFT_START_NIGHT
		for g in _on_duty():
			g.go_off_duty(STATION)
		_relief_pending = true
		_relief_timer = RELIEF_DELAY_MINUTES


## Sleeping or loading: put the right shift on duty at once.
func _on_time_jumped(_h: float) -> void:
	var h := GameClock.hours()
	var night := h >= SHIFT_START_NIGHT or h < SHIFT_START_DAY
	if night == on_night_shift and not _on_duty().is_empty():
		return
	on_night_shift = night
	_relief_pending = false
	for g in _on_duty():
		g.queue_free()
	_spawn_shift(night, true)


func _on_duty() -> Array[Guard]:
	var out: Array[Guard] = []
	for c in get_children():
		if c is Guard and not c.is_queued_for_deletion() and c.state != Guard.State.OFF_DUTY:
			out.append(c)
	return out


## Puts a shift on duty: straight at their posts (at_posts) or walking out from the station.
func _spawn_shift(night: bool, at_posts: bool) -> void:
	var roster := [
		["Hale" if night else "Bates", "pavements", Vector3(-4.6, PAVE, 30.0), 0.0],
		["Moss" if night else "Wren", "", Vector3(1.8, PAVE, 43.4), 0.0],
		["Tully" if night else "Pike", "carriageway", Vector3(0.0, 0.0, -25.0), PI],
		["Rook" if night else "Dunn", "market", Vector3(0.0, 0.0, -70.5), 0.0],
	]
	for r in roster:
		var g := Guard.new()
		g.name = "Constable" + r[0]
		g.display_name = "Constable " + r[0]
		g.has_lantern = night
		var post: Vector3 = r[2]
		g.position = post if at_posts else STATION + Vector3(randf_range(-1.0, 1.0), 0.0, 0.0)
		g.rotation.y = r[3]
		add_child(g)
		if not at_posts:
			g.set_home(Transform3D(Basis(Vector3.UP, r[3]), post))
		if r[1] != "":
			g.set_route(_routes[r[1]])


func _route(route_name: String, pts: Array, loop: bool) -> PatrolRoute:
	var r := PatrolRoute.new()
	r.name = route_name
	r.loop = loop
	for p in pts:
		r.add_point(p[0], p[1], p[2])
	add_child(r)
	return r
