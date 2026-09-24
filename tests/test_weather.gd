extends "res://tests/test_base.gd"
## Phase 6: weather kinds and smooth blending, wet streets and puddles, the senses,
## slippery roofs, townsfolk in the rain, lightning, wind, snow only in winter.

var fx: WeatherEffects


func _init() -> void:
	keep_guards = true


func run_tests() -> void:
	fx = main.get_node("WeatherFX")
	Weather.automatic = false
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Weather.wetness = 0.0
	Weather.puddles = 0.0
	await wait(30)
	var population := main.get_node("Population") as Population
	var clear_crowd := population.count("shopper")
	var dry_rough := MaterialLibrary.get_material("cobblestone").roughness
	var sun := main.get_node("Sun") as DirectionalLight3D
	var clear_sun := sun.light_energy

	# --- Smooth transitions -------------------------------------------------------
	GameClock.paused = false
	GameClock.real_minutes_per_game_day = 12.0 # 2 game minutes per real second
	Weather.set_weather(Weather.Kind.STORM)
	await wait(60)
	check("weather blends gradually, never switches abruptly", Weather.rain > 0.05 and Weather.rain < 0.5, "rain %.2f after 1 s" % Weather.rain)
	await wait_until(func() -> bool: return Weather.rain > 0.97, 900)
	check("the storm arrives in full", Weather.rain > 0.97 and Weather.cloud > 0.97)

	# --- Its effects --------------------------------------------------------------
	check("rain drowns out footsteps", Stealth.hearing_multiplier < 0.6, "%.2f" % Stealth.hearing_multiplier)
	check("rain shortens sight", Stealth.visibility_multiplier < 0.8)
	await wait_until(func() -> bool: return Weather.wetness > 0.95, 900)
	check("the streets get soaked", Weather.wetness > 0.95)
	await wait(10)
	var wet_rough := MaterialLibrary.get_material("cobblestone").roughness
	check("wet cobbles turn glossy", wet_rough < dry_rough * 0.5, "%.2f -> %.2f" % [dry_rough, wet_rough])
	check("rain is falling (particles)", (fx.get_node("Rain") as GPUParticles3D).emitting and (fx.get_node("Rain") as GPUParticles3D).amount_ratio > 0.9)
	check("the sun is dimmed under the storm clouds", sun.light_energy < clear_sun * 0.3, "%.2f vs %.2f" % [sun.light_energy, clear_sun])
	var smoke := get_nodes_in_group_safe("chimney_smoke")
	check("chimney smoke leans with the wind", not smoke.is_empty() and (smoke[0] as ChimneySmoke).wind.length() > 0.8)
	check("washing lines are strung across the yard", main.get_node_or_null("LondonStreet/Laundry") != null)

	# Lightning in a storm (made frequent for the test).
	var flashes := [0]
	Weather.bus().lightning.connect(func(_s: float) -> void: flashes[0] += 1)
	Weather.lightning_rate = 5.0
	await wait(60)
	Weather.lightning_rate = 0.08
	check("lightning flashes in a storm", flashes[0] > 0)
	await wait(300)
	check("thunder: puddles have formed", Weather.puddles > 0.3, "%.2f" % Weather.puddles)

	# Fewer people out; those who are shelter or carry umbrellas.
	await wait(400)
	var wet_crowd := population.count("shopper")
	check("far fewer shoppers in a storm", wet_crowd < clear_crowd * 0.6, "%d vs %d" % [wet_crowd, clear_crowd])
	var sheltering := 0
	var umbrellas := 0
	for c in get_nodes_in_group_safe("civilians"):
		var civ := c as Civilian
		if civ.state == Civilian.State.SHELTER:
			sheltering += 1
		if civ.get_node("Body").has_umbrella_open():
			umbrellas += 1
	check("people shelter under awnings or put up umbrellas", sheltering + umbrellas > 0, "%d sheltering, %d umbrellas" % [sheltering, umbrellas])

	# --- Slippery roofs -----------------------------------------------------------------
	GameClock.paused = true
	var b: BuildingFacade = main.get_node("LondonStreet/East_00")
	var roof_point := Vector3(6.3 + 2.5, 20.0, b.global_position.z + b.width * 0.5)
	await tp(roof_point, 0.0, 90)
	var start := harry.global_position
	await wait(120)
	var wet_drift := harry.global_position.distance_to(start)
	check("standing on a wet slate roof, Harry slides", wet_drift > 0.4, "%.2f m in 2 s" % wet_drift)
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Weather.wetness = 0.0
	Weather.snow_cover = 0.0
	await tp(roof_point, 0.0, 90)
	start = harry.global_position
	await wait(120)
	check("on a dry roof he stays put", harry.global_position.distance_to(start) < 0.05)

	# Drying out: puddles last longer than the wet sheen.
	Weather.set_weather(Weather.Kind.LIGHT_RAIN, true)
	Weather.wetness = 1.0
	Weather.puddles = 0.8
	Weather.set_weather(Weather.Kind.CLEAR, false)
	GameClock.paused = false
	GameClock.real_minutes_per_game_day = 2.0 # 12 game minutes per real second
	await wait(240)
	check("after the rain the streets dry out", Weather.wetness < 0.7 and Weather.puddles > Weather.wetness * 0.5, "wet %.2f puddles %.2f" % [Weather.wetness, Weather.puddles])

	# --- Fog --------------------------------------------------------------------
	GameClock.paused = true
	Weather.set_weather(Weather.Kind.CLEAR, true)
	var g := Guard.new()
	g.name = "FogTest"
	g.position = Vector3(0, 0, 20)
	main.add_child(g)
	await tp(Vector3(0, 0.05, 6.0), 0.0)
	await wait(30)
	var clear_score := g.vision_score()
	Weather.set_weather(Weather.Kind.FOG, true)
	await wait(30)
	var fog_score := g.vision_score()
	check("thick fog: a constable 14 m away can barely see you", fog_score < clear_score * 0.5, "%.2f vs %.2f" % [fog_score, clear_score])
	g.free()

	# --- Snow only in winter -------------------------------------------------------
	Weather.set_weather(Weather.Kind.SNOW, true)
	check("no snow in September: it falls as rain", Weather.kind == Weather.Kind.LIGHT_RAIN)
	var old_month := GameClock.start_month
	GameClock.start_month = 1
	Weather.set_weather(Weather.Kind.SNOW, true)
	check("snow in January", Weather.kind == Weather.Kind.SNOW and Weather.snow > 0.5)
	GameClock.start_month = old_month

	# --- Automatic changes ---------------------------------------------------------------
	Weather.set_weather(Weather.Kind.CLEAR, true)
	Weather.automatic = true
	var kinds := {}
	Weather.bus().kind_changed.connect(func(k: Weather.Kind) -> void: kinds[k] = true)
	GameClock.real_minutes_per_game_day = 0.5 # 48 game minutes per real second
	GameClock.paused = false
	await wait(900)
	GameClock.paused = true
	GameClock.real_minutes_per_game_day = 48.0
	check("the weather changes on its own over the hours", kinds.size() >= 2, "%d kinds seen" % kinds.size())
