extends "res://tests/test_base.gd"
## Phase 9 (London): the Legend and notoriety, arrest, escalation (wanted posters, extra
## constables, sharper guards), the fence, the poor box, the ironmonger and upgrades,
## saving and loading, settings and re-binding, and the menus.


func _init() -> void:
	keep_guards = true


func run_tests() -> void:
	Progress.reset()
	GameSettings.load_settings()
	await wait(10)
	await _test_legend_and_notoriety()
	await _test_trade()
	await _test_upgrades()
	await _test_settings()
	await _test_menus()
	await _test_save_load()


func _test_legend_and_notoriety() -> void:
	check("a new outlaw is a Nobody, unknown to the police", Progress.rank() == "Nobody" and Progress.escalation() == 0 and Progress.bounty() == 0)
	# Robbing a gentleman raises notoriety; robbing a working man costs Legend.
	var legend0 := Progress.legend
	harry.inventory.receive_loot([{"name": "Gold watch", "value": 2400, "kind": "valuable", "victim_class": "gentleman"}] as Array[Dictionary])
	check("robbing the rich makes Crowe take notice", Progress.notoriety > 4.0, "%.1f" % Progress.notoriety)
	harry.inventory.receive_loot([{"name": "Coins", "value": 12, "kind": "coins", "victim_class": "worker"}] as Array[Dictionary])
	check("robbing a working man costs Legend", Progress.legend < legend0, "%.1f -> %.1f" % [legend0, Progress.legend])
	# Giving raises it.
	var before := Progress.legend
	Progress.on_given(2400)
	check("giving £10 to the poor raises the Legend a good deal", Progress.legend >= before + 10.0 and Progress.given_total == 2400)
	Progress.legend = 45.0
	check("with enough giving he becomes the Hill Fox", Progress.rank() == "The Hill Fox")
	check("and witnesses start to look the other way", Progress.witness_silence() > 0.1)
	# Notoriety cools day by day.
	Progress.notoriety = 30.0
	await wait(2)
	GameClock.advance(1440.0)
	await wait(2)
	check("lying low: notoriety cools each day", Progress.notoriety < 30.0 and Progress.notoriety >= 20.0, "%.1f" % Progress.notoriety)
	# Escalation.
	var posters := main.get_node("Trade/WantedPosters") as WantedPosters
	Progress.notoriety = 10.0
	Progress.add_notoriety(0.1, "test")
	check("no posters while he's barely known", not posters.is_showing())
	Progress.add_notoriety(20.0, "test")
	check("notoriety 25+: wanted posters go up with Crowe's reward", posters.is_showing() and Progress.bounty() > 0, Money.format(Progress.bounty()))
	var patrols := main.get_node("Patrols") as StreetPatrols
	var before_extra := patrols.extra.size()
	Progress.add_notoriety(30.0, "test")
	await wait(5)
	check("notoriety 50+: an extra constable walks the beat", before_extra == 0 and patrols.extra.size() == 1, "%d" % patrols.extra.size())
	var g := patrols.extra[0]
	g.alertness = 0.0
	await wait(60)
	check("and every guard stays on edge while the Fox is wanted", g.alertness > 0.0)
	Progress.notoriety = 0.0
	Progress.add_notoriety(0.1, "test")
	await wait(5)
	check("when things cool off the extra man goes home and the posters come down", not posters.is_showing() and patrols.extra.is_empty())
	# Arrest: fined, stolen goods seized.
	harry.inventory.money = 2000
	harry.inventory.items.clear()
	harry.inventory.add_item({"name": "Silver locket", "value": 600, "kind": "valuable"})
	harry.inventory.add_item({"name": "A key", "value": 0, "kind": "key", "key_id": "k"})
	var guard := get_nodes_in_group_safe("guards")[0] as Guard
	harry.arrest(guard)
	await wait(5)
	check("arrested: fined a quarter of his purse", harry.inventory.money == 1500, Money.format(harry.inventory.money))
	check("...and the stolen goods he carried are seized (keys aren't)", harry.inventory.items.size() == 1 and harry.inventory.has_key("k"))
	await wait(260)
	Progress.notoriety = 0.0
	Progress.add_notoriety(0.1, "test")


func _test_trade() -> void:
	var fence := main.get_node("Trade/MagsDoyle") as Fence
	harry.inventory.items.clear()
	harry.inventory.money = 0
	harry.inventory.add_item({"name": "Gold watch", "value": 2400, "kind": "valuable", "victim_class": "gentleman"})
	harry.inventory.add_item({"name": "Canteen of silver", "value": 3600, "kind": "valuable", "victim_class": "aristocrat"})
	harry.inventory.add_item({"name": "Venison", "value": 60, "kind": "provision", "victim_class": "game"})
	harry.inventory.add_item({"name": "Letter from Captain Crowe", "value": 0, "kind": "document"})
	var fp := fence.get_interact_point()
	await tp(Vector3(fp.x - 1.4, 0.05, fp.z), -PI * 0.5, 20)
	await wait(12)
	check("Mags Doyle, the fence, keeps a stall in the market", harry.interaction.target == fence, harry.interaction.prompt)
	await press_for("interact", 2)
	await wait(3)
	var menus := get_nodes_in_group_safe("choice_menus")
	check("talking to her opens her offer (and pauses the game)", menus.size() == 1 and paused)
	var expected := int(2400 * 0.35) + int(3600 * 0.25) + int(60 * 0.8)
	(menus[0] as ChoiceMenu).choose(0)
	await wait(3)
	check("she pays a fraction of their worth; less for hot Ashcombe goods", harry.inventory.money == expected, "%s (expected %s)" % [Money.format(harry.inventory.money), Money.format(expected)])
	check("...but won't touch papers", harry.inventory.items.size() == 1 and harry.inventory.count_kind("document") == 1)
	check("the game carries on after", not paused)
	# The poor box.
	var alms := main.get_node("Trade/PoorBox") as AlmsBox
	harry.inventory.money = 5000
	var given := Progress.given_total
	var legend := Progress.legend
	await tp(alms.global_position + Vector3(0.9, -0.1, 0.0), PI * 0.5, 20)
	await wait(12)
	check("Father Bernard's poor box at the end of the street", harry.interaction.target == alms, harry.interaction.prompt)
	await press_for("interact", 2)
	await wait(3)
	menus = get_nodes_in_group_safe("choice_menus")
	(menus[0] as ChoiceMenu).choose(1) # £5
	await wait(3)
	check("giving £5 takes it from his purse, raises his Legend", harry.inventory.money == 5000 - 1200 and Progress.given_total == given + 1200 and Progress.legend > legend)


func _test_upgrades() -> void:
	var shop := main.get_node("Trade/WrenIronmonger") as ShopCounter
	check("T. Wren, Ironmonger's shop counter is at its door", shop.global_position.distance_to(Vector3.ZERO) > 1.0 and absf(absf(shop.global_position.x) - 6.3) < 1.5, str(shop.global_position))
	harry.inventory.money = 3000
	harry.inventory.lockpicks = 2
	var n := Upgrades.buy_supply(harry, "lockpick", 6)
	check("buying lockpicks", n == 6 and harry.inventory.lockpicks == 8 and harry.inventory.money == 3000 - 36)
	var ok := Upgrades.buy(harry, "boots")
	check("buying soft-soled boots", ok and Progress.has_upgrade("boots") and harry.inventory.money == 3000 - 36 - 480)
	check("...makes footsteps quieter", is_equal_approx(harry.stealth.footstep_multiplier, 0.75))
	check("can't buy the same thing twice", not Upgrades.buy(harry, "boots"))
	harry.inventory.money = 100
	check("or what he can't afford", not Upgrades.buy(harry, "bow"))
	harry.inventory.money = 5000
	Upgrades.buy(harry, "picks")
	Upgrades.buy(harry, "bow")
	Upgrades.buy(harry, "quiver")
	check("better picks widen the lock gates", is_equal_approx(harry.interaction.lock_skill, 1.3))
	check("the yew bow draws faster", harry.combat.draw_time < 0.8)
	check("the large quiver carries more", harry.combat.max_arrows_per_kind == 30)
	# The shop menu itself.
	await tp(shop.global_position + (Vector3(0, 0.1, 0)), 0.0, 10)
	shop.interact(harry)
	await wait(3)
	var menus := get_nodes_in_group_safe("choice_menus")
	check("the shop menu lists supplies and kit", menus.size() == 1 and (menus[0] as ChoiceMenu).options.size() >= 8)
	(menus[0] as ChoiceMenu).close()
	await wait(3)


func _test_settings() -> void:
	GameSettings.apply_preset("Low")
	GameSettings.apply(self)
	var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	check("the Low preset turns off the costly effects", not env.sdfgi_enabled and not env.ssr_enabled and not env.volumetric_fog_enabled)
	check("...and renders at a lower scale with FSR 2", main.get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and main.get_viewport().scaling_3d_scale < 0.8)
	GameSettings.apply_preset("Ultra")
	GameSettings.apply(self)
	check("Ultra turns them all on", env.sdfgi_enabled and env.ssr_enabled and env.volumetric_fog_enabled and env.ssil_enabled)
	GameSettings.set_value("graphics/ssr", false)
	check("changing one option makes the preset 'Custom'", GameSettings.get_value("graphics/preset") == "Custom")
	GameSettings.apply_preset("High")
	GameSettings.set_value("audio/Music", 0.5)
	GameSettings.apply(self)
	check("volume sliders drive the audio buses", AudioServer.get_bus_index("Music") > 0 and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.5)) < 0.1)
	GameSettings.set_value("gameplay/invert_y", true)
	GameSettings.set_value("gameplay/mouse_sensitivity", 1.5)
	GameSettings.apply(self)
	var cam := main.get_node("ThirdPersonCamera") as ThirdPersonCamera
	check("mouse sensitivity and invert-Y reach the camera", cam.invert_y and absf(cam.mouse_sensitivity - 0.0033) < 0.0001)
	GameSettings.set_value("gameplay/invert_y", false)
	GameSettings.set_value("gameplay/mouse_sensitivity", 1.0)
	# Re-binding: jump to J, saved and restored.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	GameSettings.rebind("jump", key, false)
	check("jump re-bound to J", GameSettings.binding_text("jump", false) == "J")
	GameSettings.save_settings()
	GameSettings.reset_controls()
	check("reset puts Space back", GameSettings.binding_text("jump", false) == "Space")
	GameSettings.load_settings()
	check("saved bindings come back when settings are loaded", GameSettings.binding_text("jump", false) == "J")
	GameSettings.reset_controls()
	GameSettings.set_value("audio/Music", 0.8)
	GameSettings.save_settings()
	GameSettings.apply(self)


func _test_menus() -> void:
	PauseMenu.open(self)
	await wait(3)
	check("Esc opens the pause menu and pauses the game", paused and get_nodes_in_group_safe("pause_menu").size() == 1)
	var pm := get_nodes_in_group_safe("pause_menu")[0] as PauseMenu
	var settings := SettingsMenu.open(self)
	await wait(3)
	check("the settings screen has its five tabs", settings.find_children("*", "TabContainer", true, false).size() == 1 and (settings.find_children("*", "TabContainer", true, false)[0] as TabContainer).get_tab_count() == 5)
	settings.close()
	await wait(2)
	pm.resume()
	await wait(3)
	check("Resume carries on", not paused)
	var title := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(title)
	await wait(3)
	var labels := title.find_children("*", "Button", true, false).map(func(b: Node) -> String: return (b as Button).text)
	check("the title screen offers Continue, New Game, Load Game, Settings, Quit", labels == ["Continue", "New Game", "Load Game", "Settings", "Quit"], str(labels))
	title.queue_free()
	await wait(2)


func _test_save_load() -> void:
	# Set up a distinctive state, save to slot 5, change it all, load it back.
	var spot := Vector3(3.0, 0.05, 12.0)
	await tp(spot, 0.3, 30)
	harry.inventory.items.clear()
	harry.inventory.money = 4321
	harry.inventory.add_item({"name": "Pearl necklace", "value": 4800, "kind": "valuable"})
	GameState.stash = [{"name": "Silver candelabra", "value": 1440, "kind": "valuable"}] as Array[Dictionary]
	Progress.legend = 55.0
	Progress.notoriety = 12.0
	Progress.upgrades = {"boots": true}
	GameClock.day = 3
	GameClock.minutes = 21.5 * 60.0
	var loot := main.get_node("AshcombeHouse/Loot/Candelabra") as LootSpot
	loot._take(harry)
	harry.inventory.remove_item(harry.inventory.items[harry.inventory.items.size() - 1])
	Progress.notoriety = 12.0 # (the theft just now raised it)
	check("saving to a slot", SaveGame.save(self, 5) and SaveGame.exists(5))
	check("the load menu describes the save", SaveGame.describe(5).contains("London") and SaveGame.describe(5).contains(Money.format(4321)), SaveGame.describe(5))
	harry.inventory.money = 1
	harry.inventory.items.clear()
	GameState.stash.clear()
	Progress.legend = 1.0
	Progress.upgrades = {}
	GameClock.day = 9
	GameClock.minutes = 8.0 * 60.0
	GameState.world = {}
	check("loading", SaveGame.load_game(self, 5))
	await wait_until(func() -> bool: return current_scene != main and current_scene != null and current_scene.has_node("Harry"), 900)
	main = current_scene
	harry = main.get_node("Harry") as Harry
	await wait(30)
	check("Harry is back where he saved", harry.global_position.distance_to(spot) < 0.5, describe())
	check("with his purse and bag", harry.inventory.money == 4321 and harry.inventory.items.size() == 1 and harry.inventory.items[0]["name"] == "Pearl necklace")
	check("the camp stash, the Legend, notoriety and upgrades are restored", GameState.stash.size() == 1 and is_equal_approx(Progress.legend, 55.0) and is_equal_approx(Progress.notoriety, 12.0) and Progress.has_upgrade("boots"), "stash %d legend %.1f notoriety %.1f upgrades %s" % [GameState.stash.size(), Progress.legend, Progress.notoriety, str(Progress.upgrades)])
	check("upgrades take effect again", is_equal_approx(harry.stealth.footstep_multiplier, 0.75))
	check("and the date and time", GameClock.day == 3 and absf(GameClock.hours() - 21.5) < 0.05)
	var loot2 := main.get_node("AshcombeHouse/Loot/Candelabra") as LootSpot
	check("what was stolen from Ashcombe House stays stolen", loot2.is_taken)
	SaveGame.delete(5)
	check("a slot can be deleted", not SaveGame.exists(5))
