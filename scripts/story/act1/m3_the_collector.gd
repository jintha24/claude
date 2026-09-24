extends Mission
## Act 1, Mission 3: "The Collector" (the street). Mrs Hale's quarter's rent, two pounds
## five shillings, has been taken early by Mr Sloane, Lord Ashcombe's collector, who is
## walking it up the street, across the market and down Ashcombe Row to the house. Harry
## must lift the rent bag from his coat before he gets there, and bring it back to her:
## all of it, or keeping a little for himself. The first gift: the Legend begins.
## Teaches: pickpocketing a moving, wary mark; the Legend.

const HALE_AT := Vector3(-5.3, 0.15, 13.0)
const SLOANE_FROM := Vector3(1.2, 0.05, 32.0)
const ASHCOMBE_GATE := Vector3(39.0, 0.05, -71.0) # on Ashcombe Row, just short of the gates
const RENT := 540 # £2 5s

var hale: StoryNPC
var sloane: Civilian
var _wary_time := 0.0


func step_count() -> int:
	return 3


func setup(from_step: int) -> void:
	hale = npc("Mrs Hale", NPCBody.Outfit.LADY, 1.6, HALE_AT, Vector3(0.0, 0.0, 13.0))
	if from_step <= 1:
		sloane = Civilian.new()
		sloane.name = "MrSloane"
		sloane.display_name = "Mr Sloane"
		sloane.outfit = NPCBody.Outfit.GENTLEMAN
		sloane.walk_speed = 1.15
		sloane.state = Civilian.State.TRAVEL
		sloane.position = SLOANE_FROM
		spawn(sloane)
		sloane.pockets = [{"name": "Ashcombe's rent bag", "value": RENT, "kind": "story", "victim_class": "gentleman", "rent_bag": true}]
		sloane.visible = from_step == 1
		sloane.process_mode = Node.PROCESS_MODE_INHERIT if from_step == 1 else Node.PROCESS_MODE_DISABLED
		if from_step == 1:
			sloane.go_to(ASHCOMBE_GATE, "vanish")


func run_step(i: int) -> void:
	match i:
		0: await _hale_story()
		1: await _steal()
		2: await _return()


func _has_bag() -> bool:
	return count_items(func(it: Dictionary) -> bool: return it.get("rent_bag", false)) > 0


func _hale_story() -> void:
	hale.face(harry)
	hale.idle_pose = NPCBody.Pose.TALK
	await say([
		["Mrs Hale", "Oh, sir. He's took it, all of it. Two pound five shillings, the quarter's rent, and the quarter's not up till Michaelmas!"],
		["Harry", "Who took it?"],
		["Mrs Hale", "Mr Sloane. Lord Ashcombe's collector. He said if I made a fuss he'd have my children in the workhouse by Sunday."],
		["Mrs Hale", "He'll be walking it up to Ashcombe House now. Up the street, through the market, top hat and a cane. You can't miss him."],
	])
	hale.idle_pose = NPCBody.Pose.NORMAL
	sloane.visible = true
	sloane.process_mode = Node.PROCESS_MODE_INHERIT
	sloane.go_to(ASHCOMBE_GATE, "vanish")


func _steal() -> void:
	set_objective("Pick Mr Sloane's pocket before he reaches Ashcombe House", sloane)
	_wary_time = 0.0
	await until(func() -> bool:
		if _has_bag():
			return true
		if not is_instance_valid(sloane) or sloane.is_queued_for_deletion() or sloane.global_position.distance_to(ASHCOMBE_GATE) < 3.5:
			fail("Sloane got the rent to Ashcombe House.")
			return false
		# A failed grab puts him on his guard, but he calms down again in a while.
		if sloane.wary:
			_wary_time += get_physics_process_delta_time()
			if _wary_time > 20.0 and sloane.state == Civilian.State.TRAVEL:
				sloane.wary = false
				_wary_time = 0.0
		return false)


func _return() -> void:
	set_objective("Take the rent back to Mrs Hale", hale)
	if not await until(func() -> bool: return harry_near(hale.global_position, 2.6)):
		return
	hale.face(harry)
	var pick := await choose("Mrs Hale's rent", "The bag holds two pounds five shillings in silver: every penny she had.",
		["Give it all back (£2 5s)", "Give her £2 and keep five shillings for your trouble"])
	for it in harry.inventory.items.duplicate():
		if it.get("rent_bag", false):
			harry.inventory.remove_item(it)
	if pick == 0:
		Progress.on_given(RENT)
		Story.set_flag("hale_full")
		await say([
			["Mrs Hale", "All of it? Oh, God bless you, sir. God bless you!"],
			["Harry", "Pay the rent when it's due. Not before."],
			["Mrs Hale", "Who are you?"],
			["Harry", "Nobody. A fox from the hills."],
		])
	else:
		Progress.on_given(RENT - 60)
		harry.inventory.add_money(60)
		Story.set_flag("hale_kept_some")
		await say([
			["Mrs Hale", "Two pound! That's the rent, near enough. Thank you, sir, thank you."],
			["Harry", "Pay it when it's due. Not before."],
		])


func on_complete() -> void:
	Story.set_flag("legend_known")
	Progress.bus().note.emit("Word spreads through the rookery. Your Legend has begun (hold Tab).")
