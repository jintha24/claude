extends Mission
## Act 1, Mission 6: "Wanted: The Hill Fox" (the market). The Illustrated Police News
## gives the unknown thief of Spitalfields a name, and Captain Crowe puts twenty pounds on
## his head. Crowe himself turns up with three constables who know Harry by sight; Harry
## has to get away: out of sight and out of mind, or into the sanctuary of St Giles.
## The end of Act One.
## Teaches: notoriety, a full police chase, losing pursuers, sanctuary.

const CROWE_FROM := Vector3(0.0, 0.05, -34.0)
const CALM_SECONDS := 6.0

var boy: StoryNPC
var crowe: Guard
var men: Array[Guard] = []
var _calm := 0.0
var _chasing := false
var _in_church := 0.0


func step_count() -> int:
	return 4


func setup(from_step: int) -> void:
	boy = npc("Newsboy", NPCBody.Outfit.RAGGED, 1.45, Vector3(4.7, 0.15, -48.6), Vector3(0.0, 0.0, -48.6), NPCBody.Pose.WAVE)
	if from_step >= 2:
		_spawn_crowe(harry.global_position)


func run_step(i: int) -> void:
	match i:
		0: await _paper()
		1: await _crowe()
		2: await _escape()
		3: await _after()


func _paper() -> void:
	harry.inventory.add_money(-mini(1, harry.inventory.money))
	await cutscene([
		{"card": "THE ILLUSTRATED POLICE NEWS\nWHO IS THE HILL FOX?\nDaring Thefts in Spitalfields. A Widow's Rent Restored by an Unknown Hand.\nThe Poor of St Giles Fed with Stolen Silver.\nCAPTAIN CROWE OFFERS A REWARD OF TWENTY POUNDS.", "time": 7.0},
	])
	Progress.add_notoriety(maxf(55.0 - Progress.notoriety, 0.0), "named in the papers")
	Progress.add_legend(3.0, "named in the papers")


func _spawn_crowe(near: Vector3) -> void:
	var from := CROWE_FROM
	if near.distance_to(from) < 14.0:
		from = near + Vector3(0.0, 0.0, 22.0)
	crowe = _constable("CaptainCrowe", "Captain Crowe", from)
	crowe.run_speed = 5.5
	for k in 3:
		men.append(_constable("CrowesMan%d" % (k + 1), "Constable (Crowe's man)", from + Vector3(-1.5 + k * 1.5, 0.0, 1.5)))


func _constable(node_name: String, display: String, at: Vector3) -> Guard:
	var g := Guard.new()
	g.name = node_name
	g.display_name = display
	g.position = at
	spawn(g)
	g.set_home(Transform3D(Basis.IDENTITY, at))
	return g


func _crowe() -> void:
	_spawn_crowe(harry.global_position)
	await wait(0.3)
	var c := crowe.global_position
	await cutscene([
		{"from": c + Vector3(2.6, 1.8, -3.2), "look": c + Vector3.UP * 1.7, "lines": [
			["Captain Crowe", "There! The tall one in the long coat. That's our fox."],
			["Captain Crowe", "Twenty pounds to the man who brings me the Hill Fox. Alive, lads. I want him to hang."]]},
	])
	_start_chasing()


func _start_chasing() -> void:
	_chasing = true
	for g in [crowe] + men:
		(g as Guard).start_chase(harry.global_position)


func _escape() -> void:
	set_objective("Escape Crowe's men: break their line of sight and hide, or reach the sanctuary of St Giles's church", null)
	if crowe == null:
		_spawn_crowe(harry.global_position)
	if not _chasing:
		_start_chasing()
	_calm = 0.0
	_in_church = 0.0
	await until(func() -> bool:
		var dt := get_physics_process_delta_time()
		var hunting := false
		for g in [crowe] + men:
			var guard := g as Guard
			if is_instance_valid(guard) and not guard.is_down() and (guard.state == Guard.State.CHASE or guard.awareness > 0.6):
				hunting = true
		_calm = 0.0 if hunting else _calm + dt
		_in_church = _in_church + dt if StGiles.is_sanctuary(harry.global_position) else 0.0
		return _calm >= CALM_SECONDS or _in_church >= 3.0)
	for g in [crowe] + men:
		if is_instance_valid(g):
			(g as Guard).stand_down()


func _after() -> void:
	await say([
		["Harry", "A name in the papers, and a price on my head."],
		["Harry", "Well, Tobias. It's a start."],
	])


func on_complete() -> void:
	Story.set_flag("act1_complete")
	Progress.add_legend(2.0, "escaped Crowe")
