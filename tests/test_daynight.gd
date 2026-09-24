extends "res://tests/test_base.gd"
## Phase 5: the clock, the sun and moon, lamps and windows, and everybody's daily routine.

var day_night: DayNightCycle
var population: Population
var patrols: StreetPatrols


func _init() -> void:
	keep_guards = true


func run_tests() -> void:
	day_night = main.get_node("DayNight")
	population = main.get_node("Population")
	patrols = main.get_node("Patrols")
	await wait(30)

	# --- Clock and calendar -------------------------------------------------
	check("the story starts on Thursday 20 September 1866", GameClock.date_string() == "Thursday 20 September 1866", GameClock.date_string())
	check("clock format", GameClock.clock_string() == "12:00 pm", GameClock.clock_string())
	GameClock.paused = false
	var m0 := GameClock.minutes
	await wait(60)
	var rate := GameClock.minutes - m0
	GameClock.paused = true
	check("one day lasts 48 real minutes (0.5 game min per real second)", absf(rate - 0.5) < 0.08, "%.3f min in 1 s" % rate)

	# --- Sun and moon ----------------------------------------------------------
	var doy := GameClock.day_of_year()
	var noon := DayNightCycle.solar_position(12.0, doy)
	var dawn := DayNightCycle.solar_position(6.0, doy)
	var midnight := DayNightCycle.solar_position(0.0, doy)
	check("London noon sun ~38-40 deg high near the equinox", noon.x > 37.0 and noon.x < 41.0, "%.1f" % noon.x)
	check("sunrise about 6 am", absf(dawn.x) < 3.0, "%.1f" % dawn.x)
	check("sun due south at noon", absf(noon.y - 180.0) < 1.0, "%.1f" % noon.y)
	check("midnight sun far below the horizon", midnight.x < -30.0)
	await set_hour(12.0)
	var sun := main.get_node("Sun") as DirectionalLight3D
	check("noon: bright sun, daylight for stealth", sun.visible and sun.light_energy > 2.0 and Stealth.ambient_light > 0.7)
	check("noon: sunlight comes from the south (+Z)", sun.global_basis.z.z > 0.3, "%.2f" % sun.global_basis.z.z)
	await set_hour(0.0)
	var moon := day_night.get_node("Moon") as DirectionalLight3D
	check("midnight: no sun, faint moonlight, dark for stealth", not sun.visible and moon.visible and Stealth.ambient_light < 0.1)

	# --- Lamps and windows --------------------------------------------------------
	await set_hour(12.0)
	check("noon: every gas lamp is out", lamps().all(func(l: GasLamp) -> bool: return not l.lit))
	check("noon: windows dark", not MaterialLibrary.get_material("glass_0").emission_enabled)
	await set_hour(22.0)
	check("10 pm: every gas lamp lit", lamps().all(func(l: GasLamp) -> bool: return l.lit))
	var shadowed := lamps().filter(func(l: GasLamp) -> bool: return l.casts_shadows).size()
	check("only the 6 lamps nearest the camera cast shadows", shadowed <= DayNightCycle.LAMP_SHADOW_BUDGET, "%d" % shadowed)
	check("10 pm: lamplight in the windows", MaterialLibrary.get_material("glass_1").emission_enabled)
	await set_hour(2.0)
	check("2 am: most houses have gone to bed", not MaterialLibrary.get_material("glass_1").emission_enabled and not MaterialLibrary.get_material("glass_shop").emission_enabled)
	# Dusk: the lamplighter is part-way round.
	var dusk := find_hour_with_elevation(16.0, 19.5, 1.3)
	await set_hour(dusk)
	var lit_count := lamps().filter(func(l: GasLamp) -> bool: return l.lit).size()
	check("at dusk the lamps are lit one by one", lit_count > 0 and lit_count < lamps().size(), "%d of %d lit" % [lit_count, lamps().size()])

	# --- Population by the hour -----------------------------------------------
	await set_hour(12.0)
	await wait(10)
	check("noon: the market is busy", population.count("shopper") >= 25 and population.traders.size() == 16, "%d shoppers, %d traders" % [population.count("shopper"), population.traders.size()])
	await set_hour(3.0)
	await wait(10)
	check("3 am: the market is empty", population.count("shopper") == 0 and population.traders.is_empty())
	check("3 am: the street is nearly deserted", population.count("passer") <= 1)
	check("3 am: the night shift is on duty with lanterns", on_duty().size() == 4 and on_duty().all(func(g: Guard) -> bool: return g.has_lantern and g.lantern != null))

	# Traders pack up and go home at 6:30 pm.
	await set_hour(18.4)
	await wait(10)
	check("6:24 pm: traders still at their stalls", population.traders.size() == 16)
	run_clock(4.0) # 4 real minutes per game day: fast
	await wait_until(func() -> bool: return GameClock.hours() >= 18.55, 900)
	GameClock.paused = true
	var leaving := 0
	for c in get_nodes_in_group_safe("civilians"):
		if c.get_meta("kind", "") == "trader" and (c as Civilian).leaving:
			leaving += 1
	check("6:33 pm: traders pack up and walk off home", population.traders.is_empty() and leaving > 0, "%d walking home" % leaving)

	# Police change shift at 6 pm: the day men walk off, the night men arrive.
	await set_hour(17.9)
	await wait(10)
	var day_men := on_duty().map(func(g: Guard) -> String: return g.name)
	check("before 6 pm the day shift is on", "ConstableBates" in day_men and on_duty().all(func(g: Guard) -> bool: return not g.has_lantern))
	run_clock(4.0)
	var went := await wait_until(func() -> bool:
		return get_nodes_in_group_safe("guards").any(func(g: Node) -> bool: return (g as Guard).state == Guard.State.OFF_DUTY), 900)
	check("at 6 pm the day shift goes off duty", went)
	var arrived := await wait_until(func() -> bool:
		return on_duty().any(func(g: Guard) -> bool: return g.name == "ConstableHale"), 1200)
	GameClock.paused = true
	check("the night shift arrives from the station", arrived)
	var hale: Guard = null
	for g in on_duty():
		if g.name == "ConstableHale":
			hale = g
	check("night constables carry bullseye lanterns", hale != null and hale.has_lantern and hale.lantern != null)

	# The lantern beam lights up whatever it points at.
	await set_hour(23.0)
	await wait(20)
	var g2 := Guard.new()
	g2.name = "LanternTest"
	g2.has_lantern = true
	g2.position = Vector3(0.0, 0.0, 5.0)
	main.add_child(g2)
	await wait(20)
	await tp(Vector3(0.0, 0.05, -1.0), 0.0) # 6 m in front of him, in the beam
	await wait(10)
	var in_beam := harry.stealth.exposure
	await tp(Vector3(0.0, 0.05, 11.0), 0.0) # behind him
	await wait(10)
	var behind := harry.stealth.exposure
	check("a bullseye lantern lights Harry up", in_beam > behind + 0.2, "%.2f vs %.2f" % [in_beam, behind])
	g2.free()

	# Evening: off to the pub. Closing time: drunks weave home.
	await set_hour(19.5)
	run_clock(4.0)
	var pubgoer := await wait_until(func() -> bool: return population.count("pubgoer") > 0, 900)
	GameClock.paused = true
	check("evening: people head for the pubs", pubgoer)
	await set_hour(0.6)
	run_clock(4.0)
	var drunk := await wait_until(func() -> bool:
		return get_nodes_in_group_safe("civilians").any(func(c: Node) -> bool: return (c as Civilian).drunk), 900)
	GameClock.paused = true
	check("closing time: drunks stagger home", drunk)
	GameClock.real_minutes_per_game_day = 48.0


func lamps() -> Array:
	return get_nodes_in_group_safe("gas_lamps")


## Police constables on duty (not Lord Ashcombe's private men, who never change shift).
func on_duty() -> Array:
	return get_nodes_in_group_safe("guards").filter(func(g: Node) -> bool:
		return is_instance_valid(g) and not g.is_queued_for_deletion() and not g.is_in_group("ashcombe_guards") and (g as Guard).state != Guard.State.OFF_DUTY)


func set_hour(h: float) -> void:
	GameClock.paused = true
	GameClock.advance(fposmod(h * 60.0 - GameClock.minutes, 1440.0))
	await wait(45)


func run_clock(real_minutes_per_day: float) -> void:
	GameClock.real_minutes_per_game_day = real_minutes_per_day
	GameClock.paused = false


func find_hour_with_elevation(a: float, b: float, target: float) -> float:
	var doy := GameClock.day_of_year()
	for i in 40:
		var mid := (a + b) * 0.5
		if DayNightCycle.solar_position(mid, doy).x > target:
			a = mid
		else:
			b = mid
	return (a + b) * 0.5
