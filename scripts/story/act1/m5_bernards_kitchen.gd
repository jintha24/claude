extends Mission
## Act 1, Mission 5: "Father Bernard's Kitchen" (St Giles). Tom brings Harry to the slum
## priest who feeds the rookery from a soup kitchen outside St Giles-in-the-Fields.
## Bernard asks no questions about money, only that there be some: Harry gives at least
## a pound in the church's poor box. Then Bernard shows him the crypt, Harry's safehouse
## in town from now on (a cot to sleep and save on, a strongbox, and a sanctuary: chasing
## constables lose him once he's inside the church).
## Teaches: giving (and raising money by fencing loot), safehouses.

const GIFT := 240 # £1

var bernard: StoryNPC
var tom: StoryNPC
var _given_before := 0
var _hinted := false
var _waited := 0.0


func step_count() -> int:
	return 3


func setup(from_step: int) -> void:
	var at := Vector3(-45.6, 0.0, -8.2) if from_step < 2 else StGiles.ALTAR_POINT
	bernard = npc("Father Bernard", NPCBody.Outfit.PRIEST, 1.74, at, Vector3(-40.0, 0.0, -4.3), NPCBody.Pose.TALK)
	tom = npc("Big Tom", NPCBody.Outfit.WORKER, 1.98, Vector3(-43.2, 0.0, -12.2), StGiles.SOUP_POINT)


func run_step(i: int) -> void:
	match i:
		0: await _meet()
		1: await _give()
		2: await _crypt()


func _meet() -> void:
	bernard.face(harry)
	var b := bernard.global_position
	await cutscene([
		{"from": b + Vector3(3.2, 1.7, 2.6), "to": b + Vector3(2.6, 1.6, 2.0), "look": b + Vector3.UP * 1.6, "lines": [
			["Big Tom", "Father, this is the one I told you of."],
			["Father Bernard", "The Hill Fox. Tom says you have a talent for finding money that other people have mislaid."],
			["Harry", "Some of it finds its way back where it belongs."]]},
		{"from": b + Vector3(-2.2, 1.8, -3.4), "look": StGiles.SOUP_POINT + Vector3(0.0, 1.0, 0.0), "lines": [
			["Father Bernard", "Half the rookery eats here, and most days the pot's thinner than a curate's sermon."],
			["Father Bernard", "I don't ask where money comes from. I only ask that it comes. There's a poor box at the church door."]]},
	])


func _give() -> void:
	_given_before = Progress.given_total
	var box := get_tree().current_scene.get_node_or_null("StGiles/StGilesPoorBox") as Node3D
	var where: Variant = box.global_position + Vector3.UP * 1.6 if box else StGiles.POOR_BOX + Vector3.UP * 1.6
	set_objective("Give at least £1 in the poor box at the church door", where)
	_hinted = false
	await until(func() -> bool:
		if not _hinted and harry.inventory.money < GIFT and harry.inventory.items.size() > 0:
			_hinted = true
			set_objective("Give at least £1 in the poor box (sell your loot to Mags Doyle in the market to raise it)", where)
		return Progress.given_total - _given_before >= GIFT)
	bark("Father Bernard", "Bless you, Harry. That's bread for forty families.")


func _crypt() -> void:
	bernard.go_to(StGiles.ALTAR_POINT, 1.5)
	set_objective("Follow Father Bernard into the church", bernard)
	_waited = 0.0
	if not await until(func() -> bool:
		if StGiles.in_church(harry.global_position) and not StGiles.in_church(bernard.global_position):
			# Harry's got there first: Bernard comes in by the vestry and waits at the altar.
			_waited += get_physics_process_delta_time()
			if _waited > 3.0:
				bernard.stop()
				bernard.global_position = StGiles.ALTAR_POINT
				bernard.reset_physics_interpolation()
		return StGiles.in_church(harry.global_position) and harry_near(bernard.global_position, 5.0)):
		return
	bernard.face(harry)
	var bed := StGiles.CRYPT_BED
	await cutscene([
		{"from": bernard.global_position + Vector3(-3.0, 1.8, -2.4), "look": bernard.global_position + Vector3.UP * 1.6, "lines": [
			["Father Bernard", "Come. Mind the steps: they were old when Wren was a boy."]]},
		{"from": bed + Vector3(5.2, 2.2, 3.4), "to": bed + Vector3(4.2, 2.0, 2.2), "look": bed + Vector3(0.0, 0.6, 0.0), "lines": [
			["Father Bernard", "Nobody searches a church crypt, Harry. Not even Captain Crowe. Sleep here when you must; leave what you must in the box."],
			["Father Bernard", "And when the constables are on your heels, come in through my door. God's house was a sanctuary long before the Metropolitan Police was a nuisance."]]},
	])


func on_complete() -> void:
	Story.set_flag("st_giles_safehouse")
	Progress.add_legend(2.0, "Father Bernard's blessing")
	Progress.bus().note.emit("St Giles's crypt is your safehouse: sleep, save and stash there. The church is a sanctuary.")
