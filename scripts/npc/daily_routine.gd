class_name DailyRoutine
extends RefCounted
## One resident of the town and their day, hour by hour. Population keeps a roster of
## these and puts every person where their routine says they are: asleep at home, at
## work, keeping a stall, shopping in the market, on an errand, in church on Sunday, at the
## pub of an evening and staggering home at closing time. Nobody appears from nowhere:
## people leave through their own front door and go in through a real one.
##
## A routine is the same every week (people are creatures of habit), with the small
## differences of each weekday: which day she does her shopping, when he takes his lunch,
## who goes to church on Sunday and who drinks on a Saturday night.

## Indoors at home: asleep, meals, chores.
const HOME := "home"
## Indoors at their workplace: a shop, counting-house, workshop or the docks.
const WORK := "work"
## Keeping their market stall.
const STALL := "stall"
## Out shopping and browsing in the market.
const MARKET := "market"
## Along the street to a shop, and in.
const ERRAND := "errand"
const PUB := "pub"
const CHURCH := "church"
## Rookery folk: sorting rags, mending and gossiping in their yard.
const YARD := "yard"
## Rookery folk: waiting about by the soup kitchen at dinner time.
const SOUP := "soup"

## Activities spent out of doors (the person is out in the world while they last).
const OUTDOOR: Array[String] = [STALL, MARKET, YARD, SOUP]
## Activities someone may skip when the weather is foul or the town is thinned for a slow PC.
const OPTIONAL: Array[String] = [MARKET, ERRAND]

const JOBS: Array[String] = ["costermonger", "clerk", "housewife", "gentleman", "labourer", "pensioner", "rookery"]

var id := 0
var display_name := ""
var job := ""
var outfit: NPCBody.Outfit = NPCBody.Outfit.WORKER
var height := 1.74
## Fixes the face, build and clothes of this person (NPCBody.variation_seed).
var look_seed := 0
## 0..1: who stays in first when it rains or the crowd is thinned.
var rank := 0.5
## How keen on the pub (0 = teetotal).
var drinker := 0.0
## Market stall index (costermongers), else -1.
var stall := -1
## Doors (Marker3D in group npc_doors).
var home: Node3D
var work: Node3D
var pub: Node3D
var church: Node3D
var errands: Array[Node3D] = []
## Rookery yard: centre and half-size.
var yard_center := Vector3.ZERO
var yard_extent := Vector2(4, 4)

## Weekday (0 = Saturday .. 6 = Friday, as GameClock.WEEKDAYS) -> [[start hour, activity], ...]
var _week := {}

## Runtime state, kept by Population.
var civ: Civilian = null
var activity := ""
## The door they are behind (or heading for) when not out.
var place: Node3D = null


## A resident of `job`, their week drawn from `rng`.
static func create(p_id: int, p_job: String, rng: RandomNumberGenerator) -> DailyRoutine:
	var r := DailyRoutine.new()
	r.id = p_id
	r.job = p_job
	r.look_seed = 7919 * p_id + 17
	r.rank = rng.randf()
	match p_job:
		"costermonger":
			r.outfit = NPCBody.Outfit.LADY if rng.randf() < 0.33 else NPCBody.Outfit.WORKER
			r.drinker = rng.randf_range(0.0, 0.9)
		"clerk":
			r.outfit = NPCBody.Outfit.GENTLEMAN if rng.randf() < 0.45 else NPCBody.Outfit.WORKER
			r.drinker = rng.randf_range(0.0, 0.7)
		"housewife":
			r.outfit = NPCBody.Outfit.LADY
			r.drinker = rng.randf_range(0.0, 0.25)
		"gentleman":
			r.outfit = NPCBody.Outfit.GENTLEMAN
			r.drinker = rng.randf_range(0.2, 0.8)
		"labourer":
			r.outfit = NPCBody.Outfit.WORKER
			r.drinker = rng.randf_range(0.3, 1.0)
		"pensioner":
			r.outfit = [NPCBody.Outfit.LADY, NPCBody.Outfit.GENTLEMAN, NPCBody.Outfit.WORKER][rng.randi() % 3]
			r.drinker = rng.randf_range(0.0, 0.4)
		"rookery":
			r.outfit = NPCBody.Outfit.RAGGED if rng.randf() < 0.75 else NPCBody.Outfit.WORKER
			r.drinker = rng.randf_range(0.2, 1.0)
	r.height = 1.64 + rng.randf() * 0.1 if r.outfit == NPCBody.Outfit.LADY else 1.68 + rng.randf() * 0.14
	for wd in 7:
		r._week[wd] = r._plan_day(wd, rng)
	return r


## What they are doing at `hour` on `weekday` (0 = Saturday).
func activity_at(hour: float, weekday: int) -> String:
	var day: Array = _week.get(weekday, [])
	var out := HOME
	for entry: Array in day:
		if hour >= float(entry[0]):
			out = entry[1]
		else:
			break
	return out


## The day as readable text, e.g. "6:30 stall, 18:30 home, 20:10 pub".
func describe(weekday: int) -> String:
	var parts: Array[String] = []
	for entry: Array in _week.get(weekday, []):
		var h := float(entry[0])
		parts.append("%d:%02d %s" % [int(h), int(fmod(h, 1.0) * 60.0), entry[1]])
	return ", ".join(parts)


func is_outdoor(act: String) -> bool:
	return act in OUTDOOR


## The door an indoor activity happens behind.
func door_for(act: String) -> Node3D:
	var d: Node3D = null
	match act:
		WORK: d = work
		PUB: d = pub
		CHURCH: d = church
		ERRAND: d = errands[0] if not errands.is_empty() else null
	return d if d != null else home


# ---------------------------------------------------------------------------
# Planning a day. Each plan is a list of [start hour, activity], sorted, starting at 0.
# ---------------------------------------------------------------------------
func _plan_day(weekday: int, rng: RandomNumberGenerator) -> Array:
	var sunday := weekday == 1
	var saturday := weekday == 0
	var plan: Array = []
	# Late the night before: still in the pub until closing (half past midnight).
	var yesterday := (weekday + 6) % 7
	var out_late := _drinks_tonight(yesterday) and not _leaves_early(yesterday)
	if out_late:
		plan.append([0.0, PUB])
		plan.append([0.5 + rng.randf() * 0.7, HOME])
	else:
		plan.append([0.0, HOME])
	var j := func(a: float, b: float) -> float: return rng.randf_range(a, b)
	match job:
		"costermonger":
			# The market trades every day from half past six until half past six.
			plan.append([Population.TRADE_OPEN + j.call(0.0, 0.25), STALL])
			plan.append([Population.TRADE_CLOSE, HOME])
		"clerk":
			if sunday:
				_church_or_home(plan, rng)
				plan.append([14.0 + j.call(0.0, 1.0), MARKET])
				plan.append([16.0 + j.call(0.0, 0.5), HOME])
			else:
				plan.append([7.3 + j.call(0.0, 0.9), WORK])
				# Dinner hour: most walk to the market for a pie and a look round.
				plan.append([11.8 + j.call(0.0, 0.3), MARKET if rng.randf() < 0.8 else ERRAND])
				plan.append([13.0 + j.call(0.0, 0.3), WORK])
				plan.append([(13.5 if saturday else 18.0) + j.call(0.0, 0.6), HOME])
		"housewife":
			if sunday:
				_church_or_home(plan, rng)
			else:
				# Her market day's shopping, at a different hour each day.
				var start := j.call(8.5, 14.0) as float
				plan.append([start, MARKET])
				plan.append([start + j.call(1.6, 3.0), ERRAND])
				plan.append([start + j.call(3.1, 3.6), HOME])
		"gentleman":
			if sunday:
				_church_or_home(plan, rng)
				plan.append([15.0 + j.call(0.0, 1.0), ERRAND])
				plan.append([16.5 + j.call(0.0, 0.5), HOME])
			else:
				plan.append([9.5 + j.call(0.0, 0.8), ERRAND])
				plan.append([10.8 + j.call(0.0, 0.8), MARKET])
				plan.append([13.8 + j.call(0.0, 0.6), WORK]) # his club, or the counting-house
				plan.append([18.0 + j.call(0.0, 0.8), HOME])
		"labourer":
			if sunday:
				plan.append([11.0 + j.call(0.0, 1.0), MARKET])
				plan.append([13.0 + j.call(0.0, 0.5), HOME])
			else:
				plan.append([5.6 + j.call(0.0, 0.6), WORK]) # the docks and the warehouses
				plan.append([(13.0 if saturday else 18.0) + j.call(0.0, 0.5), HOME])
		"pensioner":
			if sunday:
				_church_or_home(plan, rng)
			else:
				var start := j.call(9.5, 11.5) as float
				plan.append([start, MARKET])
				plan.append([start + j.call(1.8, 3.0), HOME])
				if rng.randf() < 0.6:
					plan.append([15.0 + j.call(0.0, 1.0), ERRAND])
					plan.append([16.5 + j.call(0.0, 0.5), HOME])
		"rookery":
			plan.append([6.3 + j.call(0.0, 0.8), YARD])
			plan.append([11.3 + j.call(0.0, 0.4), SOUP]) # the soup kitchen serves at noon
			plan.append([13.2 + j.call(0.0, 0.6), YARD])
			plan.append([20.0 + j.call(0.0, 1.0), HOME])
	# An evening in the pub, for those who drink tonight.
	if _drinks_tonight(weekday):
		var last := float(plan[-1][0])
		var go := minf(maxf(19.0 + j.call(0.0, 3.2), last + 0.5), 23.0)
		plan.append([go, PUB])
		# Early leavers go home before closing; the rest are thrown out after midnight.
		if _leaves_early(weekday):
			plan.append([minf(go + j.call(1.0, 2.5), 23.9), HOME])
	return plan


func _church_or_home(plan: Array, rng: RandomNumberGenerator) -> void:
	# Morning service at St Giles-in-the-Fields (for the church-going two thirds).
	if rng.randf() < 0.67:
		plan.append([9.6 + rng.randf() * 0.4, CHURCH])
		plan.append([12.0 + rng.randf() * 0.4, HOME])


## Whether they spend this evening in the pub: a steady habit, more of them on a Saturday.
func _drinks_tonight(weekday: int) -> bool:
	if drinker <= 0.0:
		return false
	var roll := fposmod(sin(float(id * 12.9898 + weekday * 78.233)) * 43758.5453, 1.0)
	var keen := drinker * (1.5 if weekday == 0 else (0.4 if weekday == 1 else 1.0))
	return roll < keen * 0.75


func _leaves_early(weekday: int) -> bool:
	return fposmod(sin(float(id * 4.1414 + weekday * 19.19)) * 24634.6345, 1.0) < 0.35
