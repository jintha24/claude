class_name AshcombeStaff
extends Node3D
## The people (and dogs) who guard Ashcombe House, and the household's daily routine.
##
##  * Six of Lord Ashcombe's men in his dark livery: the gatekeeper at his post by the
##    lodge, one on the forecourt and lawns, one in the garden, one in the service yard,
##    and two inside (ground floor and first floor). Outdoor men carry lanterns after dark.
##  * Two mastiffs: chained by their kennels by day, loosed in the grounds at night.
##  * The routine: gates open at 7 am and are locked at 10 pm; the outer doors are locked
##    at night; gasoliers are lit from 5 pm to half past 11, after which only a night-lamp
##    burns on the landing.

const GATE_OPEN_HOUR := 7.0
const GATE_LOCK_HOUR := 22.0
const DOGS_LOOSE_HOUR := 21.0
const DOGS_CHAINED_HOUR := 6.0
const LAMPS_ON := 17.0
const LAMPS_OFF := 23.5

@export var house_path: NodePath = ^"../AshcombeHouse"

var house: AshcombeHouse
var guards: Array[Guard] = []
var dogs: Array[GuardDog] = []

var _routes := {}
var _last_state := ""


func _ready() -> void:
	house = get_node_or_null(house_path) as AshcombeHouse
	var gf := AshcombeHouse.GF
	var ff := AshcombeHouse.FF
	_routes["forecourt"] = _route("ForecourtBeat", [
		[Vector3(52.0, 0, -86.0), 4.0, NAN], [Vector3(58.0, 0, -78.0), 0.0, NAN],
		[Vector3(58.0, 0, -61.0), 0.0, NAN], [Vector3(56.0, 0, -50.0), 3.0, NAN],
		[Vector3(72.0, 0, -44.0), 0.0, NAN], [Vector3(86.0, 0, -50.0), 4.0, NAN],
		[Vector3(70.0, 0, -50.0), 0.0, NAN],
	], true)
	_routes["garden"] = _route("GardenBeat", [
		[Vector3(84.0, 0, -80.0), 3.0, NAN], [Vector3(98.0, 0, -90.0), 0.0, NAN],
		[Vector3(102.0, 0, -71.0), 4.0, -PI * 0.5], [Vector3(96.0, 0, -60.0), 0.0, NAN],
		[Vector3(86.0, 0, -62.0), 3.0, NAN], [Vector3(84.0, 0, -71.0), 0.0, NAN],
	], true)
	_routes["yard"] = _route("YardBeat", [
		[Vector3(52.0, 0, -96.0), 3.0, NAN], [Vector3(58.0, 0, -106.0), 0.0, NAN],
		[Vector3(72.0, 0, -106.0), 3.0, NAN], [Vector3(82.0, 0, -100.0), 0.0, NAN],
		[Vector3(60.0, 0, -92.0), 4.0, NAN],
	], true)
	_routes["ground_floor"] = _route("GroundFloorRound", [
		[Vector3(66.0, gf, -71.0), 4.0, NAN], [Vector3(68.0, gf, -63.5), 3.0, NAN],
		[Vector3(76.0, gf, -63.5), 0.0, NAN], [Vector3(76.0, gf, -70.0), 3.0, NAN],
		[Vector3(66.0, gf, -72.0), 0.0, NAN], [Vector3(66.0, gf, -82.0), 4.0, NAN],
		[Vector3(75.0, gf, -82.0), 3.0, NAN], [Vector3(66.0, gf, -79.0), 0.0, NAN],
	], true)
	_routes["first_floor"] = _route("FirstFloorRound", [
		[Vector3(64.0, ff, -70.0), 4.0, NAN], [Vector3(66.0, ff, -61.0), 3.0, NAN],
		[Vector3(66.0, ff, -70.0), 0.0, NAN], [Vector3(76.0, ff, -70.0), 3.0, NAN],
		[Vector3(76.0, ff, -61.0), 3.0, NAN], [Vector3(76.0, ff, -70.0), 0.0, NAN],
		[Vector3(66.0, ff, -71.0), 0.0, NAN], [Vector3(66.0, ff, -81.0), 3.0, NAN],
	], false)
	_routes["dog_grounds"] = _route("DogRun", [
		[Vector3(88.0, 0, -96.0), 0.0, NAN], [Vector3(100.0, 0, -80.0), 0.0, NAN],
		[Vector3(100.0, 0, -50.0), 0.0, NAN], [Vector3(80.0, 0, -40.0), 0.0, NAN],
		[Vector3(90.0, 0, -66.0), 0.0, NAN],
	], true)
	_routes["dog_front"] = _route("DogRunFront", [
		[Vector3(55.0, 0, -100.0), 0.0, NAN], [Vector3(56.0, 0, -80.0), 0.0, NAN],
		[Vector3(54.0, 0, -52.0), 0.0, NAN], [Vector3(66.0, 0, -40.0), 0.0, NAN],
		[Vector3(58.0, 0, -66.0), 0.0, NAN],
	], true)
	for spec: Array in [
		["Gatekeeper", "Gatekeeper Sparrow", "", AshcombeHouse.GATE_POST, PI * 0.5, true],
		["ForecourtMan", "Ashcombe's man", "forecourt", Vector3(58.0, 0, -78.0), 0.0, true],
		["GardenMan", "Ashcombe's man", "garden", Vector3(84.0, 0, -80.0), 0.0, true],
		["YardMan", "Ashcombe's man", "yard", Vector3(52.0, 0, -96.0), 0.0, true],
		["Footman", "Footman", "ground_floor", Vector3(66.0, gf + 0.05, -71.0), 0.0, false],
		["Valet", "Lord Ashcombe's valet", "first_floor", Vector3(64.0, ff + 0.05, -70.0), 0.0, false],
	]:
		var g := Guard.new()
		g.name = spec[0]
		g.display_name = spec[1]
		g.outfit = NPCBody.Outfit.HOUSE_GUARD
		g.has_lantern = spec[5]
		g.position = spec[3]
		g.rotation.y = spec[4]
		g.add_to_group("ashcombe_guards")
		if not spec[5]:
			g.vision_range = 18.0 # indoors: rooms, not streets
		add_child(g)
		if spec[2] != "":
			g.set_route(_routes[spec[2]])
		guards.append(g)
	for spec: Array in [["Brutus", AshcombeHouse.KENNEL_GARDEN, "dog_grounds"], ["Nell", AshcombeHouse.KENNEL_YARD, "dog_front"]]:
		var d := GuardDog.new()
		d.name = spec[0]
		d.display_name = spec[0]
		d.position = spec[1]
		add_child(d)
		d.set_route(_routes[spec[2]])
		dogs.append(d)
	GameClock.bus().hour_passed.connect(func(_h: int) -> void: apply_schedule())
	GameClock.bus().time_jumped.connect(func(_h: float) -> void: apply_schedule())
	apply_schedule.call_deferred()


func _process(_delta: float) -> void:
	# Half-hour changes (lamps out at 11:30) need a finer check than hour_passed.
	var key := _schedule_key()
	if key != _last_state:
		apply_schedule()


static func is_night_hours(h: float, from: float, to: float) -> bool:
	return h >= from or h < to


func _schedule_key() -> String:
	var h := GameClock.hours()
	return "%s%s%s%s" % [
		int(is_night_hours(h, GATE_LOCK_HOUR, GATE_OPEN_HOUR)),
		int(is_night_hours(h, DOGS_LOOSE_HOUR, DOGS_CHAINED_HOUR)),
		int(h >= LAMPS_ON and h < LAMPS_OFF),
		int(Stealth.ambient_light < 0.3),
	]


## Puts gates, doors, dogs, lanterns and lamps in the right state for the time of day.
func apply_schedule() -> void:
	_last_state = _schedule_key()
	var h := GameClock.hours()
	var locked_up := is_night_hours(h, GATE_LOCK_HOUR, GATE_OPEN_HOUR)
	var dogs_loose := is_night_hours(h, DOGS_LOOSE_HOUR, DOGS_CHAINED_HOUR)
	var evening := h >= LAMPS_ON and h < LAMPS_OFF
	var dark := Stealth.ambient_light < 0.3 or h >= 19.0 or h < 6.0
	if house:
		for n: String in ["GateNorth", "GateSouth"]:
			var gate := house.get_node_or_null(n) as MansionDoor
			if gate == null:
				continue
			if locked_up:
				gate.set_locked(true)
			else:
				gate.set_locked(false)
				if not gate.is_open:
					gate.open_from(gate.global_transform * Vector3(0, 0, 3.0 if n == "GateNorth" else -3.0))
		for n: String in ["FrontDoor", "GardenDoor", "ServantsEntrance"]:
			var door := house.get_node_or_null("Doors/" + n) as MansionDoor
			if door:
				# The front door is always kept locked (the footman answers it); the garden
				# door and servants' entrance only at night.
				door.set_locked(locked_up or n == "FrontDoor")
		var lights := house.get_node_or_null("Lights")
		if lights:
			for l in lights.get_children():
				var light := l as Light3D
				match String(light.get_meta("schedule", "always")):
					"evening":
						light.visible = evening
					"night":
						light.visible = not evening and dark
					_:
						light.visible = true
	for g in guards:
		if is_instance_valid(g):
			g.set_lantern_lit(dark)
	for d in dogs:
		if is_instance_valid(d):
			var kennel := AshcombeHouse.KENNEL_GARDEN if d.name == "Brutus" else AshcombeHouse.KENNEL_YARD
			if d.chained == dogs_loose:
				d.set_chained(not dogs_loose, kennel)


func _route(route_name: String, pts: Array, loop: bool) -> PatrolRoute:
	var r := PatrolRoute.new()
	r.name = route_name
	r.loop = loop
	for p in pts:
		r.add_point(p[0], p[1], p[2])
	add_child(r)
	return r
