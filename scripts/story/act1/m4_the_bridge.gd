extends Mission
## Act 1, Mission 4: "The Bridge" (St Giles). The only footbridge over the Fleet ditch
## has a toll-keeper: Big Tom Harlow, a giant of a dockworker. "Toll's a shilling."
## Harry hasn't got one, so they settle it the old way: a fist fight on seven metres of
## planks, loser into the Fleet. Beaten fair, Tom laughs, climbs out and joins the band.
## Teaches: the fist fight (BrawlFight).

## The fight is over the water: whoever loses his footing falls in the ditch.
const EAST_END := Vector3(StGiles.DITCH_X1 - 0.35, StGiles.BRIDGE_TOP + 0.02, StGiles.BRIDGE_Z)
const WEST_END := Vector3(StGiles.DITCH_X0 + 0.35, StGiles.BRIDGE_TOP + 0.02, StGiles.BRIDGE_Z)
const TOM_CLIMBS_OUT := Vector3(StGiles.DITCH_X0 - 1.6, 0.05, StGiles.BRIDGE_Z - 2.2)

var tom: StoryNPC
var fight: BrawlFight
var _won := false


func step_count() -> int:
	return 3


func setup(from_step: int) -> void:
	var at := StGiles.BRIDGE_MID + Vector3(-1.2, 0.0, 0.0)
	if from_step >= 2:
		at = TOM_CLIMBS_OUT
	tom = npc("Big Tom", NPCBody.Outfit.WORKER, 1.98, at, EAST_END, NPCBody.Pose.NORMAL)
	tom.use_navmesh = false


func run_step(i: int) -> void:
	match i:
		0: await _toll()
		1: await _fight()
		2: await _friends()


func _toll() -> void:
	tom.set_puppet(true)
	tom.global_position = StGiles.BRIDGE_MID + Vector3(-1.2, 0.0, 0.0)
	tom.set_yaw(atan2(-(EAST_END.x - tom.global_position.x), -(EAST_END.z - tom.global_position.z)))
	var mid := StGiles.BRIDGE_MID
	await cutscene([
		{"from": mid + Vector3(3.8, 1.9, 3.4), "to": mid + Vector3(3.0, 1.7, 2.6), "look": mid + Vector3(-1.2, 1.8, 0.0), "lines": [
			["Big Tom", "Hold up there, stranger. This here's my bridge."],
			["Big Tom", "Toll's a shilling."],
			["Harry", "Since when does anyone charge to cross the Fleet?"],
			["Big Tom", "Since I started standing on it."]]},
		{"from": mid + Vector3(-4.5, 1.6, -2.4), "look": mid + Vector3(1.4, 1.6, 0.0), "lines": [
			["Harry", "I've no shilling for you."],
			["Big Tom", "Then we'll settle it the old way. Fists, and the loser takes a bath."],
			["Harry", "Fair."]]},
	])


func _fight() -> void:
	tom.set_puppet(true)
	harry.global_position = EAST_END
	fight = BrawlFight.new()
	fight.name = "BridgeFight"
	fight.foe_name = "Big Tom"
	fight.water_y = StGiles.WATER_TOP
	spawn(fight)
	fight.start(harry, tom, EAST_END, WEST_END)
	set_objective("Knock Big Tom into the Fleet", null)
	fight.ended.connect(func(won: bool) -> void: _won = won)
	await until(func() -> bool: return fight == null or not is_instance_valid(fight) or fight.over)
	if finished:
		return
	if not _won:
		fail("Tom sent you into the Fleet.")


func _friends() -> void:
	# Tom wades out and climbs the bank, laughing.
	if tom.global_position.y < -0.5:
		await wait(1.2)
	tom.set_puppet(false)
	tom.global_position = TOM_CLIMBS_OUT
	tom.reset_physics_interpolation()
	tom.idle_pose = NPCBody.Pose.TALK
	tom.face(harry)
	set_objective("Talk to Big Tom", tom)
	if not await until(func() -> bool: return harry_near(tom.global_position, 3.2)):
		return
	await say([
		["Big Tom", "Ha! Nobody's put me in the Fleet since I was twelve years old!"],
		["Big Tom", "Tom Harlow. I heave cargo at the docks when there's cargo, and knock heads when there isn't."],
		["Harry", "Harry."],
		["Big Tom", "I know who you are. Pip's been telling half the rookery about the Hill Fox and the widow's rent."],
		["Big Tom", "You'll want a friend who can lift more than purses. Come and meet Father Bernard. He feeds this whole rookery on nothing."],
	])


func on_complete() -> void:
	Story.join_band("tom")
	Progress.add_legend(2.0, "beat Big Tom fair")
	Progress.bus().note.emit("Big Tom joins the Lantern Men.")
