class_name GameClock
extends Node
## The in-game clock and calendar (self-creating singleton, like Stealth).
##
## Default pace: one in-game day lasts 48 real minutes (30x real time). Change
## `real_minutes_per_game_day` (e.g. in Settings, Phase 9) to speed it up or slow it down.
## The story begins on Thursday 20 September 1866 at 4 pm.

signal hour_passed(hour: int)
signal day_passed(day: int)
## The time jumped (sleeping, waiting, loading a save): schedules must catch up at once.
signal time_jumped(hours: float)

const MONTHS: Array[String] = ["January", "February", "March", "April", "May", "June", "July",
	"August", "September", "October", "November", "December"]
const WEEKDAYS: Array[String] = ["Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
const DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

## Minute of the day, 0 .. 1440.
static var minutes: float = 16.0 * 60.0
## Days since the start date.
static var day: int = 0
static var start_year: int = 1866
static var start_month: int = 9
static var start_day: int = 20
static var real_minutes_per_game_day: float = 48.0
static var paused: bool = false

static var _bus: GameClock
static var _last_hour: int = -1


static func bus() -> GameClock:
	if _bus == null or not is_instance_valid(_bus):
		var tree := Engine.get_main_loop() as SceneTree
		_bus = tree.root.get_node_or_null("GameClock") as GameClock
		if _bus == null:
			_bus = GameClock.new()
			_bus.name = "GameClock"
			_bus.process_mode = Node.PROCESS_MODE_PAUSABLE
			tree.root.add_child.call_deferred(_bus)
	return _bus


## Hours as a decimal, 0 .. 24 (e.g. 16.5 = half past four).
static func hours() -> float:
	return minutes / 60.0


## Jump to a time of day (today, or tomorrow if `next_day_if_earlier` and it's earlier).
static func set_time(h: float, next_day_if_earlier: bool = false) -> void:
	var target := fposmod(h, 24.0) * 60.0
	var delta := target - minutes
	if delta < 0.0 and next_day_if_earlier:
		delta += 1440.0
	advance(delta)


## Moves time forward (or back) by `delta_minutes` at once.
static func advance(delta_minutes: float) -> void:
	var total := minutes + delta_minutes
	while total >= 1440.0:
		total -= 1440.0
		day += 1
		bus().day_passed.emit(day)
	while total < 0.0:
		total += 1440.0
		day = maxi(day - 1, 0)
	minutes = total
	_last_hour = int(hours())
	bus().time_jumped.emit(hours())


## Day of the year (1 .. 365) for the sun's path and seasons.
static func day_of_year() -> int:
	var d := start_day + day
	for m in start_month - 1:
		d += DAYS_IN_MONTH[m]
	return ((d - 1) % 365) + 1


## Current calendar date as [year, month (1-12), day].
static func date() -> Array[int]:
	var y := start_year
	var m := start_month
	var d := start_day + day
	while d > DAYS_IN_MONTH[m - 1]:
		d -= DAYS_IN_MONTH[m - 1]
		m += 1
		if m > 12:
			m = 1
			y += 1
	return [y, m, d]


## 1 = winter (Dec-Feb) ... used for snow in Phase 6.
static func is_winter() -> bool:
	var m := date()[1]
	return m == 12 or m <= 2


## "Thursday 20 September 1866"
static func date_string() -> String:
	var dt := date()
	var y := dt[0]
	var m := dt[1]
	var d := dt[2]
	# Zeller's congruence for the weekday.
	var mm := m
	var yy := y
	if mm < 3:
		mm += 12
		yy -= 1
	var k := yy % 100
	var j := yy / 100
	var h := (d + (13 * (mm + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7
	return "%s %d %s %d" % [WEEKDAYS[h], d, MONTHS[m - 1], y]


## "4:15 pm"
static func clock_string() -> String:
	var total := int(minutes)
	var h := total / 60
	var mins := total % 60
	var suffix := "am" if h < 12 else "pm"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, mins, suffix]


func _ready() -> void:
	_last_hour = int(GameClock.hours())


func _process(delta: float) -> void:
	if paused:
		return
	var game_minutes_per_second := 1440.0 / (real_minutes_per_game_day * 60.0)
	minutes += delta * game_minutes_per_second
	if minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
		day_passed.emit(day)
	var h := int(GameClock.hours())
	if h != _last_hour:
		_last_hour = h
		hour_passed.emit(h)
