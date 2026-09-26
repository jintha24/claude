extends "res://tests/test_base.gd"
## The London crowd (Throng): hundreds of walkers on every pavement beyond the real
## townsfolk, walked on the GPU, thinning out at night and in the rain.

var throng: Throng


func run_tests() -> void:
	throng = main.get_node("Throng")
	Weather.automatic = false
	Weather.set_weather(Weather.Kind.CLEAR, true)
	GameClock.minutes = 9.0 * 60.0
	await wait(60)
	check("the old streets have their crowd (along clear runs of the navigation mesh)", throng.walker_count() >= 600, str(throng.walker_count()))
	await tp(Vector3(320.0, 0.4, -60.0))
	await wait(60)
	check("the pavements round a city street are thronged", throng.walker_count() >= 2000, str(throng.walker_count()))
	check("the crowd is kept in one group per block (plus the old streets)", throng.get_child_count() == throng.group_count())
	var morning := throng.busy
	GameClock.minutes = 3.0 * 60.0
	await wait(40)
	check("a handful out at three in the morning", throng.busy < 0.15 and morning >= 0.9, "%.2f vs %.2f" % [throng.busy, morning])
	GameClock.minutes = 12.0 * 60.0
	Weather.set_weather(Weather.Kind.STORM, true)
	await wait(40)
	var wet := throng.busy
	Weather.set_weather(Weather.Kind.CLEAR, true)
	await wait(40)
	check("rain keeps people indoors", wet < throng.busy * 0.8, "%.2f vs %.2f" % [wet, throng.busy])
	# Far blocks are dropped as Harry moves on.
	var before := throng.group_count()
	await tp(Vector3(-900.0, 0.4, 320.0))
	await wait(60)
	check("the crowd follows Harry across the city", throng.group_count() > 0 and throng.walker_count() > 500, "%d groups (was %d)" % [throng.group_count(), before])
	check("and doesn't pile up behind him", throng.group_count() <= 26, str(throng.group_count()))
