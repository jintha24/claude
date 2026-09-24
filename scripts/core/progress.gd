class_name Progress
extends Node
## The story-driven systems (self-creating singleton, like Stealth and GameClock).
##
##  * The Legend (0-100): what London's poor think of the Hill Fox. It rises when he gives
##    to Father Bernard's poor box and robs only those who won't miss it; it falls when he
##    robs working folk. Ranks: Nobody, a Rumour, The Hill Fox, a Folk Hero, the Legend of
##    London. A high Legend makes witnesses look the other way.
##  * Notoriety (0-100): Lord Ashcombe's and Captain Crowe's attention. Thefts from the
##    rich, alarms and witnessed crimes raise it; it cools by itself a few points a day.
##    It sets the bounty and the escalation level (more constables on the beat, sharper
##    guards, wanted posters on the walls).
##  * Upgrades and the camp, bought with stolen money (see Upgrades).

signal legend_changed(value: float, delta: float, reason: String)
signal notoriety_changed(value: float, delta: float, reason: String)
signal upgrade_bought(id: String)
## A line for the HUD ("The poor of St Giles bless the Hill Fox").
signal note(text: String)

const RANKS: Array[String] = ["Nobody", "A Rumour", "The Hill Fox", "A Folk Hero", "The Legend of London"]
const NOTORIETY_DECAY_PER_DAY := 8.0

static var legend: float = 8.0
static var notoriety: float = 0.0
static var given_total: int = 0
static var stolen_from_rich: int = 0
static var stolen_from_poor: int = 0
static var upgrades: Dictionary = {}
## How much Father Bernard's parish has been helped (0-100): the rookery improves.
static var wellbeing: float = 0.0
static var _last_day: int = 0
static var _bus: Progress


static func bus() -> Progress:
	if _bus == null or not is_instance_valid(_bus):
		var tree := Engine.get_main_loop() as SceneTree
		_bus = tree.root.get_node_or_null("Progress") as Progress
		if _bus == null:
			_bus = Progress.new()
			_bus.name = "Progress"
			tree.root.add_child.call_deferred(_bus)
	return _bus


static func reset() -> void:
	legend = 8.0
	notoriety = 0.0
	given_total = 0
	stolen_from_rich = 0
	stolen_from_poor = 0
	upgrades = {}
	wellbeing = 0.0
	_last_day = GameClock.day


static func add_legend(amount: float, reason: String) -> void:
	var before := legend
	legend = clampf(legend + amount, 0.0, 100.0)
	if not is_equal_approx(before, legend):
		var old_rank := rank_index(before)
		bus().legend_changed.emit(legend, legend - before, reason)
		if rank_index(legend) != old_rank:
			bus().note.emit("Your Legend: %s" % rank())


static func add_notoriety(amount: float, reason: String) -> void:
	var before := notoriety
	var old_level := escalation()
	notoriety = clampf(notoriety + amount, 0.0, 100.0)
	if not is_equal_approx(before, notoriety):
		bus().notoriety_changed.emit(notoriety, notoriety - before, reason)
		if escalation() > old_level:
			bus().note.emit(["", "Wanted posters go up: Crowe offers a reward for the Hill Fox.", "More constables walk the beat.", "Ashcombe's men are everywhere. Lie low."][escalation()])


static func rank_index(v: float = legend) -> int:
	return clampi(int(v / 20.0), 0, RANKS.size() - 1)


static func rank() -> String:
	return RANKS[rank_index()]


## 0 = unknown, 1 = posters, 2 = extra constables, 3 = a hunted man.
static func escalation() -> int:
	return 0 if notoriety < 25.0 else (1 if notoriety < 50.0 else (2 if notoriety < 75.0 else 3))


## Captain Crowe's reward, in pence (up to £50).
static func bounty() -> int:
	if notoriety < 10.0:
		return 0
	return int(pow(notoriety / 100.0, 1.3) * 12000.0) / 240 * 240 # whole pounds


## Chance a witness keeps quiet about a theft from the rich (the poor love their Fox).
static func witness_silence() -> float:
	return clampf((legend - 30.0) / 100.0, 0.0, 0.6)


## Every theft goes through here (PlayerInventory.stolen).
static func on_stolen(victim_class: String, value: int) -> void:
	match victim_class:
		"aristocrat", "gentleman", "lady":
			stolen_from_rich += value
			add_notoriety(clampf(value / 480.0, 0.3, 6.0), "theft")
		"merchant":
			add_notoriety(clampf(value / 480.0, 0.2, 3.0), "theft")
			add_legend(-0.5, "robbed a trader")
		"worker":
			stolen_from_poor += value
			add_legend(-2.5, "robbed a working man")
			bus().note.emit("Robbing the poor: your Legend suffers.")
		"constable":
			add_notoriety(1.0, "robbed a constable")


## Caught: the constables fine him a quarter of his purse and take the stolen goods he's
## carrying (loot stashed at the camp is safe). Crowe's reputation grows with every arrest.
static func on_arrested(h: Harry) -> void:
	var fine := h.inventory.money / 4
	h.inventory.add_money(-fine)
	var taken := 0
	for it in h.inventory.items.duplicate():
		if String(it.get("kind", "")) in ["valuable", "provision"]:
			h.inventory.remove_item(it)
			taken += 1
	add_notoriety(5.0, "arrested")
	bus().note.emit("Taken in: fined %s and %d stolen things seized. (Stash loot at the camp.)" % [Money.format(fine), taken])


## Money given to Father Bernard's poor box.
static func on_given(pence: int) -> void:
	if pence <= 0:
		return
	given_total += pence
	wellbeing = clampf(wellbeing + pence / 240.0, 0.0, 100.0)
	add_legend(clampf(pence / 120.0, 0.5, 12.0), "gave to the poor")


static func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


static func to_dict() -> Dictionary:
	return {
		"legend": legend, "notoriety": notoriety, "given_total": given_total,
		"stolen_from_rich": stolen_from_rich, "stolen_from_poor": stolen_from_poor,
		"upgrades": upgrades.keys(), "wellbeing": wellbeing, "last_day": _last_day,
	}


static func from_dict(d: Dictionary) -> void:
	legend = float(d.get("legend", 8.0))
	notoriety = float(d.get("notoriety", 0.0))
	given_total = int(d.get("given_total", 0))
	stolen_from_rich = int(d.get("stolen_from_rich", 0))
	stolen_from_poor = int(d.get("stolen_from_poor", 0))
	upgrades = {}
	for id in d.get("upgrades", []):
		upgrades[String(id)] = true
	wellbeing = float(d.get("wellbeing", 0.0))
	_last_day = int(d.get("last_day", GameClock.day))


func _ready() -> void:
	_last_day = GameClock.day
	GameClock.bus().day_passed.connect(func(day: int) -> void:
		# Laying low: the hue and cry dies down day by day.
		var days := maxi(day - Progress._last_day, 1)
		Progress._last_day = day
		Progress.add_notoriety(-Progress.NOTORIETY_DECAY_PER_DAY * days, "time"))
	Stealth.bus().alarm_raised.connect(func(_p: Vector3, _by: Node) -> void:
		Progress.add_notoriety(2.0, "alarm"))
