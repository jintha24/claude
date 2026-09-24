class_name CampBed
extends Interactable
## Harry's bedroll by the fire. Sleeping passes the time to the next dawn (or dusk, if it's
## night-time sleep you're after: sleep in daylight to wake at dusk) and heals him fully.

signal slept(hours: float)


func _ready() -> void:
	interact_range = 1.8


func get_prompt(_harry: Harry) -> String:
	var h := GameClock.hours()
	return "Sleep until dusk" if h >= 6.0 and h < 17.0 else "Sleep until dawn"


func interact(harry: Harry) -> void:
	harry.interaction.begin_hold(self, "Settling down to sleep", 1.0, func() -> void: sleep(harry))


func sleep(harry: Harry) -> void:
	var before := GameClock.day * 24.0 + GameClock.hours()
	var h := GameClock.hours()
	GameClock.set_time(18.0 if h >= 6.0 and h < 17.0 else 6.0, true)
	harry.health = harry.max_health
	harry.health_changed.emit(harry.health, harry.max_health)
	slept.emit(GameClock.day * 24.0 + GameClock.hours() - before)
