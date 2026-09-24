class_name CaveHideout
extends Node3D
## Harry's home for seven years: a dry cave in a sandstone outcrop at the foot of the
## escarpment, its mouth facing south over a clearing. Streamed in by a StreamedScene when
## Harry comes near.
##
## Local coordinates: origin on the cave floor; the chamber runs north (-Z) from z = 4 to
## z = -20 and is 16 m wide; a 4 m passage leads south to the mouth at z = 16.
## Inside: a fire (it lights Harry up), his bedroll (sleep), the camp chest (stash loot)
## and his fletching bench (make arrows). The camp grows in Phase 9.

var fire_light: OmniLight3D
var bed: CampBed
var chest: CampChest
var bench: ArrowBench

var _body: StaticBody3D
var _mb: MeshBuilder
var _rock: Material
var _flicker := 0.0


func _ready() -> void:
	add_to_group("cave_hideout")
	_rock = MaterialLibrary.get_tinted("rock", Color(0.78, 0.66, 0.52)) # warm sandstone
	_body = StaticBody3D.new()
	_body.name = "Rock"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	add_child(_body)
	_mb = MeshBuilder.new()
	_build_rock()
	_build_camp()
	_mb.build_into(self, "RockMesh").gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var v := InteriorVolume.new()
	v.position = Vector3(-8.0, 0.0, -20.0)
	v.size = Vector3(16.0, 4.2, 36.0)
	v.daylight_factor = 0.12
	add_child(v)


func _solid(size: Vector3, center: Vector3, mat: Material = null) -> void:
	_mb.add_box(size, center, mat if mat else _rock)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	_body.add_child(cs)


func _build_rock() -> void:
	# The outcrop: solid rock all round the chamber and passage, rising towards the back.
	_solid(Vector3(6.0, 10.0, 38.0), Vector3(-11.0, 5.0, -7.0)) # west
	_solid(Vector3(6.0, 10.0, 38.0), Vector3(11.0, 5.0, -7.0)) # east
	_solid(Vector3(16.0, 13.0, 6.0), Vector3(0.0, 6.5, -23.0)) # back
	_solid(Vector3(6.0, 7.5, 12.0), Vector3(-5.0, 3.75, 10.0)) # either side of the passage
	_solid(Vector3(6.0, 7.5, 12.0), Vector3(5.0, 3.75, 10.0))
	_solid(Vector3(16.0, 3.4, 24.0), Vector3(0.0, 4.2 + 1.7, -8.0)) # chamber roof
	_solid(Vector3(4.0, 4.0, 12.0), Vector3(0.0, 3.2 + 2.0, 10.0)) # passage roof
	_solid(Vector3(28.0, 4.0, 30.0), Vector3(0.0, 9.5, -9.0)) # the crown of the outcrop
	# Weathered boulders softening the outline (visual only).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 26:
		var s := SphereMesh.new()
		var r := rng.randf_range(1.2, 3.2)
		s.radius = r
		s.height = r * 1.4
		s.radial_segments = 10
		s.rings = 6
		var side := rng.randi() % 3
		var p: Vector3
		match side:
			0:
				p = Vector3(rng.randf_range(-14.0, -12.0), rng.randf_range(1.0, 10.0), rng.randf_range(-24.0, 14.0))
			1:
				p = Vector3(rng.randf_range(12.0, 14.0), rng.randf_range(1.0, 10.0), rng.randf_range(-24.0, 14.0))
			_:
				p = Vector3(rng.randf_range(-13.0, 13.0), rng.randf_range(10.0, 12.0), rng.randf_range(-24.0, 5.0))
		_mb.add_mesh(s, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), _rock)
	# Bedded sandstone: weathered strata stepping in and out across the face and flanks.
	var y := 0.0
	while y < 7.2:
		var th := rng.randf_range(0.35, 0.8)
		for side: float in [-1.0, 1.0]:
			var x0 := 2.4
			while x0 < 8.4:
				var w := rng.randf_range(1.2, 3.2)
				var out := rng.randf_range(0.1, 0.9)
				_mb.add_box(Vector3(w, th, out + 0.3), Vector3(side * (x0 + w * 0.5), y + th * 0.5, 16.0 + out * 0.5), _rock)
				x0 += w
		for side: float in [-1.0, 1.0]:
			var z0 := -26.0
			while z0 < 12.0:
				var w := rng.randf_range(2.0, 5.0)
				var out := rng.randf_range(0.1, 1.0)
				_mb.add_box(Vector3(out + 0.3, th, w), Vector3(side * (14.0 + out * 0.5), y + th * 0.5, z0 + w * 0.5), _rock)
				z0 += w
		y += th
	# Rough boulders framing the mouth.
	for x: float in [-2.6, 2.6]:
		var s := SphereMesh.new()
		s.radius = 1.3
		s.height = 3.4
		_mb.add_mesh(s, Transform3D(Basis.IDENTITY, Vector3(x, 1.5, 16.2)), _rock)


func _build_camp() -> void:
	var dirt := MaterialLibrary.get_material("dirt")
	var wood := MaterialLibrary.get_tinted("wood_planks", Color(0.55, 0.42, 0.3))
	var fur := MaterialLibrary.get_tinted("fabric", Color(0.45, 0.35, 0.25))
	var iron := MaterialLibrary.get_material("iron")
	var stone := MaterialLibrary.get_tinted("rock", Color(0.6, 0.58, 0.55))
	_mb.add_box(Vector3(16.0, 0.04, 32.0), Vector3(0.0, 0.02, -4.0), dirt) # beaten earth floor
	# Fire pit: a ring of stones, logs, the glow, a wisp of smoke.
	var fire := Vector3(0.0, 0.0, -6.0)
	for k in 9:
		var a := TAU * k / 9.0
		var s := SphereMesh.new()
		s.radius = 0.18
		s.height = 0.26
		_mb.add_mesh(s, Transform3D(Basis.IDENTITY, fire + Vector3(cos(a) * 0.55, 0.1, sin(a) * 0.55)), stone)
	for k in 3:
		_mb.add_cylinder(0.06, 0.06, 0.8, fire + Vector3(0, 0.12, 0), wood, 6, Basis(Vector3.UP, k * 1.05) * Basis(Vector3.RIGHT, PI * 0.5))
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(0.2, 0.05, 0.0)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.45, 0.1)
	ember.emission_energy_multiplier = 4.0
	_mb.add_cylinder(0.32, 0.2, 0.12, fire + Vector3(0, 0.08, 0), ember, 10)
	fire_light = OmniLight3D.new()
	fire_light.name = "Campfire"
	fire_light.position = fire + Vector3(0, 0.6, 0)
	fire_light.light_color = Color(1.0, 0.58, 0.25)
	fire_light.light_energy = 1.8
	fire_light.omni_range = 9.0
	fire_light.shadow_enabled = true
	fire_light.add_to_group("stealth_lights")
	add_child(fire_light)
	var smoke := ChimneySmoke.new()
	smoke.position = fire + Vector3(0, 0.5, 0)
	smoke.amount = 12
	add_child(smoke)
	# Cooking tripod and pot.
	for k in 3:
		var a := TAU * k / 3.0
		_mb.add_cylinder(0.025, 0.025, 1.3, fire + Vector3(cos(a) * 0.35, 0.6, sin(a) * 0.35), wood, 5, Basis(Vector3(-sin(a), 0, cos(a)), 0.28))
	_mb.add_cylinder(0.18, 0.14, 0.22, fire + Vector3(0, 0.55, 0), iron, 10)
	# Bedroll: skins over bracken.
	_mb.add_box(Vector3(1.0, 0.18, 2.1), Vector3(-5.0, 0.09, -12.0), fur)
	_mb.add_box(Vector3(0.9, 0.12, 0.35), Vector3(-5.0, 0.24, -12.8), fur)
	bed = CampBed.new()
	bed.name = "Bed"
	bed.position = Vector3(-5.0, 0.3, -12.0)
	add_child(bed)
	# The camp chest.
	_solid(Vector3(1.1, 0.6, 0.6), Vector3(5.5, 0.3, -13.0), wood)
	_mb.add_box(Vector3(1.14, 0.06, 0.64), Vector3(5.5, 0.62, -13.0), iron)
	chest = CampChest.new()
	chest.name = "Chest"
	chest.position = Vector3(5.5, 0.6, -13.0)
	add_child(chest)
	# Fletching bench with a bow rack and bundles of shafts.
	_solid(Vector3(1.6, 0.8, 0.7), Vector3(5.8, 0.4, -4.0), wood)
	_mb.add_box(Vector3(0.05, 1.6, 1.2), Vector3(6.9, 1.0, -4.0), wood)
	for k in 6:
		_mb.add_cylinder(0.01, 0.01, 0.8, Vector3(5.4 + k * 0.08, 0.84, -4.0), wood, 4, Basis(Vector3.BACK, PI * 0.5))
	bench = ArrowBench.new()
	bench.name = "Bench"
	bench.position = Vector3(5.8, 0.8, -4.0)
	add_child(bench)
	# Firewood stack and a water butt by the mouth.
	for k in 6:
		_mb.add_cylinder(0.09, 0.09, 1.1, Vector3(-6.5, 0.1 + (k / 3) * 0.18, -2.0 + (k % 3) * 0.2), wood, 6, Basis(Vector3.BACK, PI * 0.5))
	_solid(Vector3(0.6, 0.9, 0.6), Vector3(-6.8, 0.45, 2.0), wood)


func _process(delta: float) -> void:
	_flicker += delta
	if fire_light:
		fire_light.light_energy = 1.7 + sin(_flicker * 13.0) * 0.12 + sin(_flicker * 7.3) * 0.1
