extends Mission
## Act 1, Mission 1: "Cold Hearth" (the hills). Old Aldous finds Harry's larder bare with
## winter coming, gives him broadhead arrows and sends him out: bring down a deer and
## butcher it, catch a fish from the jetty, and bring supper back to the clearing. At the
## end Aldous turns Harry's eyes towards London.
## Teaches: stalking with the wind, the longbow's broadheads, butchering, fishing.

const ALDOUS_AT := Vector3(-114.5, 0.0, 99.5)
const CLEARING := Vector3(-120.0, 0.0, 96.0)

var aldous: StoryNPC
var _fish_before := 0
var _venison_before := 0


func step_count() -> int:
	return 4


func setup(_from_step: int) -> void:
	aldous = npc("Aldous", NPCBody.Outfit.WORKER, 1.72, ALDOUS_AT, ground(CLEARING), NPCBody.Pose.TALK)


func run_step(i: int) -> void:
	match i:
		0: await _intro()
		1: await _hunt()
		2: await _fish()
		3: await _supper()


func _intro() -> void:
	set_objective("Talk to Aldous", aldous)
	var a := aldous.global_position
	var eye := a + Vector3.UP * 1.6
	await cutscene([
		{"from": a + Vector3(6.0, 2.6, 5.0), "to": a + Vector3(4.2, 2.1, 3.6), "look": eye, "lines": [
			["Aldous", "There you are, lad. I looked in your larder. There's nothing in it but mice, and they're leaving."],
			["Harry", "I'll manage."],
			["Aldous", "You'll manage to starve. Seven years in that cave and you still hunt like a townie."]]},
		{"from": a + Vector3(-1.6, 1.8, 2.4), "look": eye, "lines": [
			["Aldous", "There's red deer grazing down the valley. Take my broadheads. Keep the wind in your face and your feet quiet."],
			["Aldous", "Then show me you still remember how to land a fish. Supper's on you tonight."]]},
	])
	harry.combat.add_ammo("broadhead", maxi(6 - harry.combat.get_ammo("broadhead"), 0))
	bark("Aldous", "Broadheads, lad. R changes your arrows.")


func _nearest_deer() -> WildAnimal:
	var best: WildAnimal = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("wild_animals"):
		var w := n as WildAnimal
		if w and w.species == WildAnimal.Species.DEER and not w.is_dead():
			var d := w.global_position.distance_to(harry.global_position)
			if d < best_d:
				best_d = d
				best = w
	return best


func _dead_deer() -> Node3D:
	for n in get_tree().get_nodes_in_group("wild_animals"):
		var w := n as WildAnimal
		if w and w.species == WildAnimal.Species.DEER and w.is_dead():
			return w
	return null


func _venison() -> int:
	return count_items(func(it: Dictionary) -> bool: return String(it.get("name", "")) == "Venison")


func _hunt() -> void:
	_venison_before = _venison()
	# Make sure there's a herd within reach.
	var deer := _nearest_deer()
	if deer == null or deer.global_position.distance_to(harry.global_position) > 260.0:
		var spawner := get_tree().current_scene.get_node_or_null("Animals") as AnimalSpawner
		if spawner:
			spawner.spawn_herd(ground(harry.global_position + Vector3(90.0, 0.0, 40.0)), 4)
	set_objective("Bring down a deer with a broadhead arrow", _nearest_deer())
	var done := await until(func() -> bool:
		if _venison() > _venison_before:
			return true
		var dead := _dead_deer()
		if dead:
			if objective != "Butcher the deer (hold E)":
				set_objective("Butcher the deer (hold E)", dead)
		else:
			var d := _nearest_deer()
			if d and objective_target != d:
				objective_target = d
		return false)
	if done:
		bark("Harry", "That'll feed us a week.")


func _fish() -> void:
	var jetty := get_tree().current_scene.get_node_or_null("Jetty") as Node3D
	_fish_before = count_items(func(it: Dictionary) -> bool: return it.has("fish"))
	set_objective("Catch a fish from the jetty on the lake", jetty)
	await until(func() -> bool: return count_items(func(it: Dictionary) -> bool: return it.has("fish")) > _fish_before)


func _supper() -> void:
	set_objective("Bring supper back to Aldous", aldous)
	aldous.idle_pose = NPCBody.Pose.SIT
	if not await until(func() -> bool: return harry_near(aldous.global_position, 3.0)):
		return
	aldous.idle_pose = NPCBody.Pose.TALK
	aldous.face(harry)
	await say([
		["Aldous", "Venison, and a fish fit for a parson. You haven't forgotten everything I taught you."],
		["Harry", "It'll be a hard winter up here."],
		["Aldous", "Harder in London, where there's no deer to hunt. You were a rookery lad once. You've seen them queue for bread."],
		["Aldous", "Go down to the market, Harry. Keep your eyes open, and your hand on your purse."],
	])


func on_complete() -> void:
	# Supper for two: the venison goes in the pot.
	for it in harry.inventory.items.duplicate():
		if String(it.get("name", "")) == "Venison":
			harry.inventory.remove_item(it)
			break
	Story.set_flag("aldous_taught")
