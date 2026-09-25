class_name CampLife
extends Node3D
## Aldous's camp in the clearing before Harry's cave: a campfire, log seats, tents, a
## chopping block and a woodpile, and the people who live there going about their day.
## Aldous (once Harry has met him properly) rises at dawn, tends the fire, eats, splits
## wood, goes off into the woods, whittles by the tents, and sits at the fire in the evening
## with his old dog at his heel. The Lantern Men who have joined (Pip, Big Tom) come up from
## London in the evening, sit round the fire yarning, and sleep in the tents. Talk to any of
## them with E; they chat among themselves when Harry's near.

# (West of the paddock's jumps, clear of the cave mouth.)
const FIRE := Vector2(-143.0, 90.0)
## Log seats round the fire (the sitters sit on them).
const SEATS: Array[Vector2] = [Vector2(-143.0, 92.1), Vector2(-145.1, 89.4), Vector2(-141.0, 88.2), Vector2(-140.9, 91.3)]
const TENTS: Array[Vector2] = [Vector2(-148.0, 84.0), Vector2(-148.5, 95.0), Vector2(-143.0, 80.5)]
const BLOCK := Vector2(-139.0, 84.5)
const STUMP := Vector2(-146.5, 86.5)
## Where they come and go from (off into the woods, or the London road).
const WOODS := Vector2(-170.0, 96.0)
const ROAD := Vector2(-122.0, 118.0)
## Beyond this from the fire, the camp is left to itself: people are placed, not walked
## (the ground they'd walk on may not be loaded).
const NEAR := 110.0

## [start hour, activity, spot] - activity is sleep, tend, eat, chop, whittle, fire or away.
const ROUTINES := {
	"aldous": [[0.0, "sleep", 0], [5.5, "tend", -1], [6.5, "eat", 0], [7.5, "chop", -1], [10.0, "away", -1],
		[12.5, "eat", 0], [13.5, "whittle", -1], [16.0, "away", -1], [18.5, "fire", 0], [22.5, "sleep", 0]],
	"pip": [[0.0, "sleep", 1], [6.5, "eat", 1], [7.5, "away", -1], [19.5, "fire", 1], [23.5, "sleep", 1]],
	"tom": [[0.0, "sleep", 2], [5.5, "chop", -1], [6.5, "eat", 2], [7.0, "away", -1], [19.0, "fire", 2], [22.0, "sleep", 2]],
}
const PEOPLE := {
	"aldous": {"name": "Aldous", "outfit": NPCBody.Outfit.WORKER, "height": 1.72, "away_to": "woods"},
	"pip": {"name": "Pip", "outfit": NPCBody.Outfit.RAGGED, "height": 1.42, "away_to": "road"},
	"tom": {"name": "Big Tom", "outfit": NPCBody.Outfit.WORKER, "height": 1.98, "away_to": "road"},
}
## What they say when Harry talks to them, by what they're doing.
const TALK := {
	"aldous": {
		"tend": ["Fire's the first job of the day. Always was.", "Morning, lad. Kettle'll be a while."],
		"eat": ["Rabbit again. I'm not complaining.", "Sit, eat. You're all bones."],
		"chop": ["Split it along the grain and it does the work for you.", "Winter's long up here. Wood's never wasted."],
		"whittle": ["Straight shafts fly true. Crooked ones find the ground.", "Goose feathers, not hen. Hens don't know the air."],
		"fire": ["Keep the wind in your face and they'll never know you're there.", "Tench bite best when the light's going.", "London's no place for a hill man. Mind yourself down there.", "Your father sat just there. Same stubborn jaw."],
	},
	"pip": {
		"eat": ["Best breakfast I ever 'ad, this.", "Don't tell Tom, but I pinched the last egg."],
		"fire": ["Mornin', Fox. Pockets were fat today.", "Toffs keep their watches on the left. Always the left.", "Can you teach me the bow? Go on."],
	},
	"tom": {
		"chop": ["Beats heavin' coal barges, this.", "Stand back. I don't always aim so good."],
		"eat": ["Bernard'd call this a feast.", "Pass the bread, Fox."],
		"fire": ["Anyone gives you trouble in the rookery, you send 'em to me.", "Still sore from that bridge, you know. Worth it.", "Quiet up here. Too quiet. I miss the din."],
	},
}
## Round the fire of an evening: someone starts, someone answers.
const YARNS: Array = [
	["Tell 'em about the Duke's pheasants, Aldous.", "Forty brace, and his keeper carried half of 'em for me. Thought I was the new under-keeper."],
	["What's the Fox want with all that money, anyway?", "It's not for him, Pip. That's the point."],
	["Cold tonight.", "Colder in the Fleet. Pass the pot."],
	["Crowe's put another five pound on your head, Fox.", "Then he's paying better than any of us ever did."],
	["You hear that? Owl.", "Or a keeper doing an owl. Keep your voice down."],
]
const SOLO := {
	"tend": ["Come on, catch...", "Damp wood. Always damp wood."],
	"chop": ["Hup!", "There."],
	"whittle": ["Hm. Near enough.", "That'll fly."],
	"eat": ["Not bad.", "Could use salt."],
}

var _gen: TerrainGenerator
var _player: Node3D
var _furniture: StaticBody3D
var _fire_light: OmniLight3D
var _flames: Array[MeshInstance3D] = []
var _people: Dictionary = {} # id -> {npc, talk, activity, arrived, dog}
var _tick := 0.0
var _chat := 12.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("camp")
	_rng.randomize()
	var streamer := get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
	_gen = streamer.generator if streamer else TerrainGenerator.new()
	_build()
	Story.bus().mission_completed.connect(func(_id: String) -> void: _refresh())
	Story.bus().flag_changed.connect(func(key: String) -> void:
		if key.begins_with("band_"):
			_refresh())
	_refresh.call_deferred()


func ground(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, _gen.height(p.x, p.y) + lift, p.y)


## Who lives at the camp now.
func residents() -> Array[String]:
	var out: Array[String] = []
	if Story.is_done("cold_hearth"):
		out.append("aldous")
	for m in ["pip", "tom"]:
		if Story.has_band(m):
			out.append(m)
	return out


func person(id: String) -> StoryNPC:
	return _people[id]["npc"] if _people.has(id) else null


func activity(id: String) -> String:
	return _people[id]["activity"] if _people.has(id) else ""


## At it: arrived where their activity is done (or gone off, if it's "away").
func is_settled(id: String) -> bool:
	return _people.has(id) and _people[id]["arrived"]


## What `id` should be doing at hour `h`: [activity, spot index].
static func scheduled(id: String, h: float) -> Array:
	var cur: Array = ROUTINES[id][0]
	for row: Array in ROUTINES[id]:
		if h >= float(row[0]):
			cur = row
	return [cur[1], cur[2]]


# ---------------------------------------------------------------------------
# The camp itself
# ---------------------------------------------------------------------------
func _build() -> void:
	var mb := MeshBuilder.new()
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.5, 0.4, 0.3))
	var bark := MaterialLibrary.get_tinted("wood_planks", Color(0.35, 0.27, 0.2))
	var stone := MaterialLibrary.get_tinted("rock", Color(0.6, 0.58, 0.55))
	var canvas := MaterialLibrary.get_tinted("fabric", Color(0.72, 0.66, 0.52))
	var fur := MaterialLibrary.get_tinted("fabric", Color(0.42, 0.33, 0.24))
	var iron := MaterialLibrary.get_material("iron")
	var dirt := MaterialLibrary.get_material("dirt")
	_furniture = StaticBody3D.new()
	_furniture.name = "CampFurniture"
	_furniture.collision_layer = 1
	_furniture.collision_mask = 0
	add_child(_furniture)
	var f := ground(FIRE)
	# Beaten earth round the fire.
	mb.add_cylinder(3.4, 3.4, 0.04, f + Vector3(0, 0.0, 0), dirt, 20)
	# The fire: a ring of stones, logs, embers, a cooking tripod and pot.
	for k in 10:
		var a := TAU * k / 10.0
		var s := SphereMesh.new()
		s.radius = 0.2
		s.height = 0.28
		mb.add_mesh(s, Transform3D(Basis.IDENTITY, f + Vector3(cos(a) * 0.62, 0.1, sin(a) * 0.62)), stone)
	for k in 4:
		mb.add_cylinder(0.07, 0.07, 0.9, f + Vector3(0, 0.14, 0), bark, 6, Basis(Vector3.UP, k * 0.8) * Basis(Vector3.RIGHT, PI * 0.5))
	for k in 3:
		var a := TAU * k / 3.0 + 0.3
		mb.add_cylinder(0.025, 0.025, 1.4, f + Vector3(cos(a) * 0.4, 0.65, sin(a) * 0.4), wood, 5, Basis(Vector3(-sin(a), 0, cos(a)), 0.28))
	mb.add_cylinder(0.2, 0.16, 0.24, f + Vector3(0, 0.62, 0), iron, 10)
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(0.2, 0.05, 0.0)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.42, 0.1)
	ember.emission_energy_multiplier = 5.0
	mb.add_cylinder(0.38, 0.24, 0.12, f + Vector3(0, 0.08, 0), ember, 12)
	_col_box(Vector3(1.3, 0.3, 1.3), f + Vector3(0, 0.15, 0)) # nobody stands in the fire
	# Log seats (the sitters face the fire).
	for s: Vector2 in SEATS:
		var p := ground(s)
		var along := Vector3(s.x - FIRE.x, 0, s.y - FIRE.y).normalized().cross(Vector3.UP)
		var yaw_b := Basis(Vector3.UP, atan2(along.x, along.z))
		mb.add_cylinder(0.21, 0.21, 1.5, p + Vector3(0, 0.21, 0), bark, 10, yaw_b * Basis(Vector3.RIGHT, PI * 0.5))
		_col_box(Vector3(0.4, 0.42, 1.5), p + Vector3(0, 0.21, 0), yaw_b)
	# Tents: an A of canvas over a ridge pole, a bedroll inside.
	for i in TENTS.size():
		var t := ground(TENTS[i])
		var yaw := atan2(FIRE.x - TENTS[i].x, FIRE.y - TENTS[i].y) # the door faces the fire
		var b := Basis(Vector3.UP, yaw)
		for side: float in [-1.0, 1.0]:
			var panel := b * Basis(Vector3.FORWARD, -side * 0.72)
			mb.add_box(Vector3(0.03, 1.75, 2.6), t + b * Vector3(side * 0.55, 0.68, 0), canvas, panel)
		mb.add_cylinder(0.03, 0.03, 2.9, t + Vector3(0, 1.36, 0), wood, 5, b * Basis(Vector3.RIGHT, PI * 0.5))
		for z: float in [-1.35, 1.35]:
			mb.add_cylinder(0.03, 0.03, 1.4, t + b * Vector3(0, 0.68, z), wood, 5)
		mb.add_box(Vector3(0.8, 0.1, 1.9), t + Vector3(0, 0.05, 0), fur, b)
		_col_box(Vector3(1.9, 1.3, 2.7), t + Vector3(0, 0.65, 0), b)
	# Chopping block, axe, woodpile; the whittling stump.
	var blk := ground(BLOCK)
	mb.add_cylinder(0.3, 0.3, 0.5, blk + Vector3(0, 0.25, 0), bark, 10)
	_col_box(Vector3(0.6, 0.5, 0.6), blk + Vector3(0, 0.25, 0))
	var pile := ground(BLOCK + Vector2(-1.8, 1.2))
	for row in 3:
		for k in 5 - row:
			mb.add_cylinder(0.1, 0.1, 1.0, pile + Vector3(-0.42 + (k + row * 0.5) * 0.21, 0.1 + row * 0.18, 0), wood, 6, Basis(Vector3.RIGHT, PI * 0.5))
	_col_box(Vector3(1.2, 0.6, 1.0), pile + Vector3(0, 0.3, 0))
	mb.add_cylinder(0.26, 0.26, 0.42, ground(STUMP) + Vector3(0, 0.21, 0), bark, 10)
	mb.add_cylinder(0.024, 0.024, 0.8, blk + Vector3(0.12, 0.72, 0.1), wood, 5, Basis(Vector3.FORWARD, 0.35))
	mb.add_box(Vector3(0.05, 0.16, 0.2), blk + Vector3(0.0, 0.52, 0.1), iron)
	mb.build_into(self, "CampMesh")
	# Flames: two crossed emissive cards that flicker.
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame_mat.albedo_color = Color(1.0, 0.5, 0.15, 0.85)
	flame_mat.albedo_texture = _flame_texture()
	for k in 3:
		var q := QuadMesh.new()
		q.size = Vector2(0.7, 0.95)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = flame_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = f + Vector3(0, 0.5, 0)
		mi.rotation.y = k * PI / 3.0
		_flames.append(mi)
	_fire_light = OmniLight3D.new()
	_fire_light.name = "CampfireLight"
	_fire_light.light_color = Color(1.0, 0.56, 0.24)
	_fire_light.omni_range = 16.0
	_fire_light.omni_attenuation = 1.4
	_fire_light.shadow_enabled = true
	_fire_light.distance_fade_enabled = true
	_fire_light.distance_fade_begin = 90.0
	_fire_light.distance_fade_length = 30.0
	_fire_light.add_to_group("stealth_lights")
	add_child(_fire_light)
	_fire_light.global_position = f + Vector3(0, 0.9, 0)
	AudioDirector.attach_loop(_fire_light, "fire", -3.0, 22.0)
	var smoke := ChimneySmoke.new()
	smoke.amount = 14
	add_child(smoke)
	smoke.global_position = f + Vector3(0, 0.8, 0)


func _col_box(size: Vector3, at: Vector3, basis := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	_furniture.add_child(cs)
	cs.global_transform = Transform3D(basis, at)


static var _flame_tex: Texture2D
static func _flame_texture() -> Texture2D:
	if _flame_tex:
		return _flame_tex
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 32:
			var u := (x - 15.5) / 16.0
			var v := y / 47.0 # 0 at the top
			var width := lerpf(0.05, 0.95, pow(v, 0.7)) * (1.0 - smoothstep(0.85, 1.0, v) * 0.4)
			var a := clampf(1.0 - absf(u) / maxf(width, 0.01), 0.0, 1.0)
			a *= smoothstep(0.0, 0.35, v)
			var hot := clampf(v * 1.3 - absf(u), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.45 + hot * 0.5, 0.1 + hot * 0.4, a * a))
	_flame_tex = ImageTexture.create_from_image(img)
	return _flame_tex


# ---------------------------------------------------------------------------
# The people
# ---------------------------------------------------------------------------
func _refresh() -> void:
	var want := residents()
	for id: String in _people.keys():
		if not want.has(id):
			_remove(id)
	for id in want:
		if not _people.has(id):
			_add(id)
	_update(true)


func _add(id: String) -> void:
	var d: Dictionary = PEOPLE[id]
	var n := StoryNPC.new()
	n.name = "Camp" + String(d["name"]).replace(" ", "")
	n.display_name = d["name"]
	n.outfit = d["outfit"]
	n.body_height = d["height"]
	n.use_navmesh = false
	n.look_seed = hash(id) % 100000
	add_child(n)
	n.add_collision_exception_with(_furniture)
	var talk := StoryTalk.new()
	talk.name = "Talk_" + n.name
	talk.speaker = d["name"]
	talk.npc = n
	add_child(talk)
	var dog: StreetDog = null
	if id == "aldous":
		dog = StreetDog.new()
		dog.name = "CampDog"
		dog.owner_node = n
		dog.ground_fn = _gen.height
		add_child(dog)
	_people[id] = {"npc": n, "talk": talk, "activity": "", "spot": -1, "arrived": false, "dog": dog, "hidden": false}
	_place(id, scheduled(id, GameClock.hours()))


func _remove(id: String) -> void:
	var p: Dictionary = _people[id]
	for k in ["npc", "talk", "dog"]:
		if p[k] != null and is_instance_valid(p[k]):
			(p[k] as Node).queue_free()
	_people.erase(id)


## Where an activity is done, and which way they face.
func _spot(id: String, act: String, idx: int) -> Vector3:
	match act:
		"sleep":
			return ground(TENTS[idx % TENTS.size()], 0.1)
		"tend":
			return ground(FIRE + Vector2(0.9, 0.5), 0.05)
		"chop":
			return ground(BLOCK + Vector2(0.0, -0.95), 0.05)
		"whittle":
			return ground(STUMP, 0.05)
		"away":
			return ground(WOODS if PEOPLE[id]["away_to"] == "woods" else ROAD, 0.05)
	return ground(SEATS[idx % SEATS.size()], 0.05)


func _facing(act: String, at: Vector3) -> Vector3:
	match act:
		"chop":
			return ground(BLOCK)
		"whittle":
			return ground(FIRE)
		"sleep":
			return at + Vector3(0, 0, 1)
	return ground(FIRE)


func _pose(act: String) -> int:
	match act:
		"sleep":
			return NPCBody.Pose.UNCONSCIOUS
		"tend":
			return NPCBody.Pose.BROWSE
		"eat", "fire", "whittle":
			return NPCBody.Pose.SIT
	return NPCBody.Pose.NORMAL


## Straight into place for `sched` (when Harry's away, or on arrival).
func _place(id: String, sched: Array) -> void:
	var p: Dictionary = _people[id]
	var n: StoryNPC = p["npc"]
	var act: String = sched[0]
	p["activity"] = act
	p["spot"] = sched[1]
	p["arrived"] = true
	n.stop()
	var at := _spot(id, act, sched[1])
	n.global_position = at
	n.velocity = Vector3.ZERO
	_settle(id)
	if p["dog"]:
		(p["dog"] as Node3D).global_position = at + Vector3(0.8, -0.05, 0.6)


func _settle(id: String) -> void:
	var p: Dictionary = _people[id]
	var n: StoryNPC = p["npc"]
	var act: String = p["activity"]
	n.pose_override = _pose(act)
	n.face(_facing(act, n.global_position))
	var talk: StoryTalk = p["talk"]
	var lines: Array = TALK[id].get(act, TALK[id].get("fire", []))
	talk.lines = lines
	_set_hidden(id, act == "away")


func _set_hidden(id: String, hidden: bool) -> void:
	var p: Dictionary = _people[id]
	var n: StoryNPC = p["npc"]
	p["hidden"] = hidden
	n.visible = not hidden
	n.collision_layer = 0 if hidden else NPCCharacter.LAYER_NPC


func _update(force := false) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var near := _player != null and Vector2(_player.global_position.x, _player.global_position.z).distance_to(FIRE) < NEAR
	var mission := Story.is_active()
	var h := GameClock.hours()
	for id: String in _people:
		_update_one(id, near, mission, force, h)
		var p: Dictionary = _people[id]
		(p["talk"] as StoryTalk).enabled = not mission and not p["hidden"] and p["activity"] != "sleep"


func _update_one(id: String, near: bool, mission: bool, force: bool, h: float) -> void:
	var p: Dictionary = _people[id]
	var n: StoryNPC = p["npc"]
	var sched := scheduled(id, h)
	# Away during a mission (it has its own people), and resting when Harry's far off.
	n.process_mode = Node.PROCESS_MODE_INHERIT if near and not mission else Node.PROCESS_MODE_DISABLED
	if p["dog"]:
		var dog := p["dog"] as Node3D
		dog.visible = n.visible and not mission
		dog.process_mode = n.process_mode
	if mission:
		n.visible = false
		n.collision_layer = 0
		return
	_set_hidden(id, p["hidden"]) # (back from behind a mission)
	if force or not near:
		if force or sched[0] != p["activity"] or sched[1] != p["spot"]:
			_place(id, sched)
		return
	if sched[0] != p["activity"] or sched[1] != p["spot"]:
		# Off to the next thing: out from wherever they've been, on foot.
		var was_away: bool = p["hidden"]
		p["activity"] = sched[0]
		p["spot"] = sched[1]
		p["arrived"] = false
		n.pose_override = -1
		if was_away:
			n.global_position = _spot(id, "away", 0)
			_set_hidden(id, false)
		var to := _spot(id, sched[0], sched[1])
		p["deadline"] = _t + n.global_position.distance_to(to) / 1.3 * 1.8 + 8.0
		n.go_to(to, 1.3)
	elif not p["arrived"] and n.has_arrived():
		p["arrived"] = true
		_settle(id)
	elif not p["arrived"] and _t > float(p.get("deadline", INF)):
		_place(id, sched) # caught on a tree or a rock: on with the day


func _process(delta: float) -> void:
	_t += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_update()
	_animate_fire(delta)
	if Story.is_active():
		return
	for id: String in _people:
		var p: Dictionary = _people[id]
		if p["activity"] == "chop" and p["arrived"] and not p["hidden"]:
			# Up with the axe, and down.
			var n: StoryNPC = p["npc"]
			var phase := fmod(_t + float(hash(id) % 7) * 0.1, 1.4)
			var want := NPCBody.Pose.WINDUP if phase < 0.9 else NPCBody.Pose.PUNCH
			if n.pose_override != want:
				n.pose_override = want
				if want == NPCBody.Pose.PUNCH and _player and _player.global_position.distance_to(n.global_position) < 35.0:
					AudioDirector.play("punch", ground(BLOCK, 0.5), -10.0, 0.55, 35.0)
	_chatter(delta)


func _animate_fire(_delta: float) -> void:
	# Brighter against the dark; a glow even by day.
	var dark := 1.0 - clampf(Stealth.ambient_light, 0.0, 1.0)
	var flick := sin(_t * 13.0) * 0.12 + sin(_t * 7.3) * 0.1 + sin(_t * 23.0) * 0.05
	_fire_light.light_energy = (0.8 + dark * 2.6) * (1.0 + flick)
	for i in _flames.size():
		var s := 1.0 + sin(_t * (9.0 + i * 2.3) + i) * 0.12
		_flames[i].scale = Vector3(1.0 + flick * 0.5, s, 1.0)


## A word now and then while Harry's about: a yarn round the fire, or a grumble at work.
func _chatter(delta: float) -> void:
	_chat -= delta
	if _chat > 0.0 or _player == null:
		return
	_chat = _rng.randf_range(18.0, 34.0)
	if Vector2(_player.global_position.x, _player.global_position.z).distance_to(FIRE) > 22.0:
		return
	var at_fire: Array[StoryNPC] = []
	var busy: Array = []
	for id: String in _people:
		var p: Dictionary = _people[id]
		if p["hidden"] or not p["arrived"]:
			continue
		if p["activity"] in ["fire", "eat"]:
			at_fire.append(p["npc"])
		elif SOLO.has(p["activity"]):
			busy.append([p["npc"], p["activity"]])
	if at_fire.size() >= 2:
		var yarn: Array = YARNS[_rng.randi() % YARNS.size()]
		var a := at_fire[_rng.randi() % at_fire.size()]
		var b := at_fire[(at_fire.find(a) + 1) % at_fire.size()]
		a.say(yarn[0])
		get_tree().create_timer(3.5).timeout.connect(func() -> void:
			if is_instance_valid(b) and b.visible:
				b.say(yarn[1]))
	elif not busy.is_empty():
		var pick: Array = busy[_rng.randi() % busy.size()]
		var lines: Array = SOLO[pick[1]]
		(pick[0] as StoryNPC).say(lines[_rng.randi() % lines.size()])
