extends Mission
## Act 1, Mission 2: "Crowded Pockets" (Spitalfields market, by day). A ragged boy
## bumps into Harry and is off with his purse. Harry chases him through the market and
## down the street into St Giles, gets it back, and the boy, Pip, dares him to prove he's
## the Hill Fox by lifting a gentleman's purse. Pip joins the Lantern Men: from now on he
## marks the constables near Harry on the HUD.
## Teaches: sprinting through crowds, pickpocketing.

const PIP_WAITS := Vector3(-19.5, 0.05, -60.5)
## Pip's escape: round the square, down the street and into Church Lane.
const ROUTE: Array[Vector3] = [
	Vector3(-21.5, 0.05, -58.0), Vector3(-21.5, 0.05, -84.0), Vector3(-6.0, 0.05, -87.0), Vector3(12.0, 0.05, -86.0),
	Vector3(21.5, 0.05, -80.0), Vector3(21.0, 0.05, -56.0), Vector3(2.0, 0.05, -49.0), Vector3(1.5, 0.05, -25.0),
	Vector3(-2.5, 0.05, -8.0), Vector3(-10.0, 0.05, -4.3), Vector3(-22.0, 0.05, -4.3), Vector3(-25.2, 0.05, 1.0),
	Vector3(-25.0, 0.05, 12.0),
]
const RUN_SPEED := 4.7

var pip: StoryNPC
var purse := 0
var _rich_before := 0
var _far := 0.0
var _next_bark := 3.0


func step_count() -> int:
	return 5


func setup(from_step: int) -> void:
	var at := harry.global_position + harry.get_facing_dir() * 9.0 if from_step == 0 else PIP_WAITS
	if from_step == 1:
		at = ROUTE[0]
	pip = npc("Pip", NPCBody.Outfit.RAGGED, 1.42, at, harry.global_position)
	if from_step >= 1:
		purse = int(Story.checkpoint.get("purse", 0))


func take_checkpoint() -> void:
	super.take_checkpoint()
	Story.checkpoint["purse"] = purse


func run_step(i: int) -> void:
	match i:
		0: await _bump()
		1: await _chase()
		2: await _caught()
		3: await _lift()
		4: await _join()


func _bump() -> void:
	set_objective("", null)
	pip.go_to(harry.global_position, 3.4)
	bark("Pip", "'Scuse me, mister! Sorry, mister!")
	if not await until(func() -> bool:
		if pip.has_arrived():
			pip.go_to(harry.global_position, 3.4)
		return pip.global_position.distance_to(harry.global_position) < 1.2, 20.0):
		pip.global_position = harry.global_position + harry.get_facing_dir() * 1.0
	purse = harry.inventory.money
	harry.inventory.add_money(-purse)
	AudioDirector.play("coin", harry.global_position, -6.0)
	pip.run_path(ROUTE, RUN_SPEED)
	await wait(0.8)
	bark("Harry", "My purse! You little...")


func _chase() -> void:
	if pip.mode != StoryNPC.Mode.PATH:
		pip.run_path(ROUTE, RUN_SPEED)
	set_objective("Catch the boy!", pip)
	_far = 0.0
	var lines := ["Can't catch me, lanky!", "Mind the cabbages!", "Too slow, mister!", "Coo-ee! Over 'ere!"]
	_next_bark = 3.0
	var caught := await until(func() -> bool:
		var d := pip.global_position.distance_to(harry.global_position)
		# A burst of speed when you're right on his heels.
		pip.move_speed = RUN_SPEED * (1.25 if d < 3.0 else 1.0)
		var dt := get_physics_process_delta_time()
		_far = _far + dt if d > 45.0 else 0.0
		if _far > 5.0:
			fail("The boy got away with your purse.")
			return false
		_next_bark -= dt
		if _next_bark <= 0.0 and d < 25.0:
			_next_bark = 5.0
			bark("Pip", lines[randi() % lines.size()])
		return d < 1.5)
	if caught:
		pip.stop()


func _caught() -> void:
	pip.face(harry)
	pip.idle_pose = NPCBody.Pose.STUNNED
	await say([
		["Pip", "Alright! Alright! Don't hand me to the peelers, mister!"],
		["Harry", "My purse."],
		["Pip", "Here, here, every penny, I swear it."],
	])
	harry.inventory.add_money(purse)
	purse = 0
	pip.idle_pose = NPCBody.Pose.TALK
	await say([
		["Pip", "You ain't no mark, though. Nobody runs like that. You're him, ain't you? The one from the hills."],
		["Harry", "Nobody's from the hills."],
		["Pip", "Prove it, then. Lift a toff's purse in the market, right under the peelers' noses. Then I'll believe it."],
	])
	pip.go_to(PIP_WAITS, 3.0)


func _lift() -> void:
	_rich_before = Progress.stolen_from_rich
	set_objective("Pick the pocket of a gentleman or a lady in the market", null)
	await until(func() -> bool: return Progress.stolen_from_rich > _rich_before)


func _join() -> void:
	pip.go_to(PIP_WAITS, 3.0)
	set_objective("Meet Pip on the west side of the market", pip)
	if not await until(func() -> bool: return harry_near(pip.global_position, 3.0)):
		return
	pip.face(harry)
	await say([
		["Pip", "Cor! Clean as a whistle, and he never felt a thing!"],
		["Pip", "I'm Pip. I know every alley and every peeler in Spitalfields, and which ones drink."],
		["Pip", "You need eyes in this town, Fox. I'll be yours."],
	])


func on_complete() -> void:
	Story.join_band("pip")
	Progress.bus().note.emit("Pip joins the Lantern Men: constables near you are marked on your screen.")
