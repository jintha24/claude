class_name StoryDirector
extends Node3D
## Puts the story into a place: the StoryUI, the mission givers for missions played here,
## and the characters Harry has met, going about their lives once their missions are done
## (Pip in the market, Big Tom and Father Bernard at the soup
## kitchen...). Talk to them with E.

## Where each mission is offered. "pos" is on the ground (hills: x, z; the height is
## looked up); "npc" is the character offering it; "auto" starts it on arrival.
const GIVERS := {
	"cold_hearth": {"place": "hills", "pos": Vector3(-114.5, 0.0, 99.5), "face": Vector3(-120.0, 0.0, 96.0),
		"npc": {"name": "Aldous", "outfit": NPCBody.Outfit.WORKER, "height": 1.72, "pose": NPCBody.Pose.TALK}, "prompt": "Talk to Aldous"},
	"crowded_pockets": {"place": "london", "pos": Vector3(0.0, 0.05, -70.0), "auto": 14.0, "hours": Vector2(7, 19)},
	"the_collector": {"place": "london", "pos": Vector3(-5.3, 0.15, 13.0), "face": Vector3(0.0, 0.0, 13.0), "hours": Vector2(7, 21),
		"npc": {"name": "Mrs Hale", "outfit": NPCBody.Outfit.LADY, "height": 1.6, "pose": NPCBody.Pose.NORMAL}, "prompt": "Talk to Mrs Hale"},
	"the_bridge": {"place": "london", "pos": Vector3(-31.8, 0.05, -4.3), "auto": 2.6},
	"bernards_kitchen": {"place": "london", "pos": Vector3(-45.6, 0.0, -8.2), "face": Vector3(-40.0, 0.0, -4.3), "hours": Vector2(8, 20),
		"npc": {"name": "Father Bernard", "outfit": NPCBody.Outfit.PRIEST, "height": 1.74, "pose": NPCBody.Pose.TALK}, "prompt": "Talk to Father Bernard"},
	"wanted": {"place": "london", "pos": Vector3(4.7, 0.15, -48.6), "face": Vector3(0.0, 0.0, -48.6), "hours": Vector2(6, 22),
		"npc": {"name": "Newsboy", "outfit": NPCBody.Outfit.RAGGED, "height": 1.45, "pose": NPCBody.Pose.WAVE}, "prompt": "Buy a newspaper (1d)"},
}

## The people Harry has met, after their missions (Aldous lives at the camp: CampLife): [after mission, place, name, outfit,
## height, position, face, pose, hours, lines].
const RESIDENTS: Array = [
	["crowded_pockets", "london", "Pip", NPCBody.Outfit.RAGGED, 1.42, Vector3(-19.5, 0.05, -60.5), Vector3(0.0, 0.0, -70.0), NPCBody.Pose.TALK, Vector2(7, 19),
		["Mornin', Fox. Pockets are fat today.", "Watch the big peeler by the fountain. He's quicker than he looks.", "Toffs keep their watches on the left. Always the left."]],
	["the_collector", "london", "Mrs Hale", NPCBody.Outfit.LADY, 1.6, Vector3(-5.3, 0.15, 13.0), Vector3(0.0, 0.0, 13.0), NPCBody.Pose.NORMAL, Vector2(8, 20),
		["God bless you, sir. The children have eaten every day this week.", "That rent man's not been back. They say he's afraid of foxes."]],
	["the_bridge", "london", "Big Tom", NPCBody.Outfit.WORKER, 1.98, Vector3(-43.2, 0.0, -12.2), Vector3(-49.0, 0.0, -12.0), NPCBody.Pose.NORMAL, Vector2(8, 20),
		["Still sore from that bridge, you know. Worth it.", "Anyone gives you trouble in the rookery, you send 'em to me.", "Bernard's soup's thin, but it's hot."]],
	["bernards_kitchen", "london", "Father Bernard", NPCBody.Outfit.PRIEST, 1.74, Vector3(-45.6, 0.0, -8.2), Vector3(-40.0, 0.0, -4.3), NPCBody.Pose.TALK, Vector2(8, 20),
		["The crypt's yours whenever you need it, my son.", "Every shilling you give feeds a family for a week.", "The Lord moves in mysterious ways. So, I notice, do you."]],
	["bernards_kitchen", "london", "Father Bernard", NPCBody.Outfit.PRIEST, 1.74, Vector3(-47.2, 0.15, 14.0), Vector3(-56.0, 0.0, 14.0), NPCBody.Pose.NORMAL, Vector2(20, 8),
		["Late for honest men, Harry. Rest below.", "Pray with me, or just sit a while. Either will do."]],
]

var place := "london"
var givers: Dictionary = {}
var _residents: Array[Dictionary] = []
var _check := 0.0
var _news_timer := 3.0


func _ready() -> void:
	# Where we are, from our own scene (the tree's current scene may not be set yet).
	var scene_root: Node = owner if owner else get_parent()
	place = "hills" if scene_root and scene_root.scene_file_path.contains("wilderness") else Story.place_of(get_tree())
	StoryUI.find(get_tree())
	_place_givers.call_deferred()
	Story.bus().mission_completed.connect(func(_id: String) -> void: _refresh_residents())


func _ground(p: Vector3) -> Vector3:
	var s := get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	if s:
		return Vector3(p.x, s.height_at(p.x, p.z) + 0.05, p.z)
	return p


func _place_givers() -> void:
	for id: String in GIVERS:
		var g: Dictionary = GIVERS[id]
		if g["place"] != place:
			continue
		var giver := MissionGiver.new()
		giver.name = "Giver_" + id
		giver.mission_id = id
		giver.prompt_text = g.get("prompt", "Begin")
		giver.auto_radius = float(g.get("auto", 0.0))
		giver.hours = g.get("hours", Vector2(-1, -1))
		add_child(giver)
		giver.global_position = _ground(g["pos"])
		if g.has("npc"):
			giver.npc = _make_npc(g["npc"], giver.global_position, g.get("face", Vector3.INF))
		givers[id] = giver
	_refresh_residents()


func _make_npc(d: Dictionary, pos: Vector3, face_to: Vector3) -> StoryNPC:
	var n := StoryNPC.new()
	n.name = String(d["name"]).replace(" ", "")
	n.display_name = d["name"]
	n.outfit = d.get("outfit", NPCBody.Outfit.WORKER)
	n.body_height = float(d.get("height", 1.76))
	n.idle_pose = d.get("pose", NPCBody.Pose.NORMAL)
	if face_to != Vector3.INF:
		n.rotation.y = atan2(-(face_to.x - pos.x), -(face_to.z - pos.z))
	add_child(n)
	n.global_position = pos
	if face_to != Vector3.INF:
		n.face(_ground(face_to))
	return n


func _refresh_residents() -> void:
	for r in _residents:
		if is_instance_valid(r["npc"]):
			r["npc"].queue_free()
		if is_instance_valid(r["talk"]):
			r["talk"].queue_free()
	_residents.clear()
	for row: Array in RESIDENTS:
		if row[1] != place or not Story.is_done(row[0]):
			continue
		var pos := _ground(row[5])
		var npc := _make_npc({"name": row[2], "outfit": row[3], "height": row[4], "pose": row[7]}, pos, row[6])
		var talk := StoryTalk.new()
		talk.name = "Talk_" + npc.name
		talk.speaker = row[2]
		talk.lines = row[9]
		talk.npc = npc
		add_child(talk)
		_residents.append({"npc": npc, "talk": talk, "hours": row[8]})
	_update_residents()


func _update_residents() -> void:
	var h := GameClock.hours()
	for r in _residents:
		var hours: Vector2 = r["hours"]
		var on := hours.x < 0.0 or ((h >= hours.x and h < hours.y) if hours.x <= hours.y else (h >= hours.x or h < hours.y))
		# Out of the way while a mission is on: the mission has its own people.
		on = on and not Story.is_active()
		var npc: StoryNPC = r["npc"]
		if is_instance_valid(npc):
			npc.visible = on
			npc.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
			npc.collision_layer = NPCCharacter.LAYER_NPC if on else 0
			(r["talk"] as StoryTalk).enabled = on


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		_update_residents()
	# The newsboy cries the news while he has it to sell.
	var boy: MissionGiver = givers.get("wanted")
	if boy and boy.is_available() and boy.npc:
		_news_timer -= delta
		if _news_timer <= 0.0:
			_news_timer = 9.0
			boy.npc.say(["Hill Fox strikes again! Read all about it!", "Police News! Who is the Hill Fox? Only a penny!", "Crowe offers twenty pound for the Fox! Read all about it!"][randi() % 3])
