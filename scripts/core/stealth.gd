class_name Stealth
extends Node
## Stealth: the global stealth rules shared by Harry and every guard.
##
## A self-creating singleton: the first call adds one "Stealth" node under the scene root,
## so it works the same in the game, the editor and the automated tests. Use the static
## functions (Stealth.make_noise(...)) and Stealth.bus() to connect to its signals.
##
##  * Noise bus: anything that makes a sound calls Stealth.make_noise(); every guard
##    listening within range reacts (footsteps, landings, arrows, crates, police rattles).
##  * Light: light_exposure_at() works out how lit a point is from the sun/sky and every
##    lit gas lamp (with real line-of-sight checks), 0 = pitch dark, 1 = full daylight.
##  * World modifiers that later phases drive: ambient_light (day/night, Phase 5),
##    visibility_multiplier and hearing_multiplier (fog and rain, Phase 6).

signal noise_made(position: Vector3, radius: float, kind: String, suspicious: bool, source: Node)
signal alarm_raised(position: Vector3, raised_by: Node)
## Something an NPC says out loud (shown as a subtitle near Harry).
signal npc_spoke(speaker: Node3D, line: String)

## Brightness of open sky light, 0 (moonless night) .. 1 (noon). Phase 5 drives this.
static var ambient_light: float = 0.8
## How much of the ambient light remains in shade (sky light only, no direct sun).
static var shade_factor: float = 0.5
## Fog, rain and snow reduce how far anyone can see (Phase 6).
static var visibility_multiplier: float = 1.0
## Rain drowns out footsteps (Phase 6).
static var hearing_multiplier: float = 1.0

static var _bus: Stealth


## The single Stealth node (created on first use). Connect to its signals through this.
static func bus() -> Stealth:
	if _bus == null or not is_instance_valid(_bus):
		var tree := Engine.get_main_loop() as SceneTree
		_bus = tree.root.get_node_or_null("Stealth") as Stealth
		if _bus == null:
			_bus = Stealth.new()
			_bus.name = "Stealth"
			tree.root.add_child.call_deferred(_bus)
	return _bus

const MASK_OCCLUDERS := 1 | (1 << 3) | (1 << 7) # world, props, closed doors


## Broadcast a sound. `radius` is how far (m) a guard can hear it in the open.
## `suspicious` sounds make guards investigate; ordinary ones (a man walking down a public
## street) are ignored unless they come from somewhere a man shouldn't be.
static func make_noise(pos: Vector3, radius: float, kind: String = "", suspicious: bool = true, source: Node = null) -> void:
	if radius <= 0.0:
		return
	bus().noise_made.emit(pos, radius * hearing_multiplier, kind, suspicious, source)


static func bark(speaker: Node3D, line: String) -> void:
	bus().npc_spoke.emit(speaker, line)


static func raise_alarm(pos: Vector3, raised_by: Node) -> void:
	bus().alarm_raised.emit(pos, raised_by)
	# A police rattle carries a long way over the rooftops.
	make_noise(pos, 45.0, "rattle", true, raised_by)


## How brightly lit `point` is (0..1).
static func light_exposure_at(point: Vector3, world: World3D, exclude: Array[RID] = []) -> float:
	var space := world.direct_space_state
	var tree := Engine.get_main_loop() as SceneTree
	var total := 0.0

	# Sun and sky (only a little daylight reaches indoors).
	var daylight := InteriorVolume.daylight_at(point)
	var sun := tree.get_first_node_in_group("sun") as DirectionalLight3D
	if daylight < 1.0:
		total += ambient_light * shade_factor * daylight
	elif sun and sun.visible:
		var to_sun := sun.global_transform.basis.z.normalized()
		var sun_up := clampf(to_sun.y * 4.0, 0.0, 1.0)
		var q := PhysicsRayQueryParameters3D.create(point, point + to_sun * 150.0, MASK_OCCLUDERS, exclude)
		var in_sun := space.intersect_ray(q).is_empty() and sun_up > 0.0
		total += ambient_light * (1.0 if in_sun else shade_factor)
	else:
		total += ambient_light * shade_factor

	# Gas lamps and any other light added to the "stealth_lights" group.
	for node in tree.get_nodes_in_group("stealth_lights"):
		var light := node as Light3D
		if light == null or not light.is_visible_in_tree() or light.light_energy <= 0.0:
			continue
		var d := light.global_position.distance_to(point)
		var light_range := 0.0
		if light is OmniLight3D:
			light_range = (light as OmniLight3D).omni_range
		elif light is SpotLight3D:
			# A lantern beam only lights what's inside its cone.
			var spot := light as SpotLight3D
			light_range = spot.spot_range
			var fwd := -spot.global_basis.z
			if rad_to_deg(fwd.angle_to(point - spot.global_position)) > spot.spot_angle:
				continue
		if d >= light_range:
			continue
		# Start just outside the lantern so the lamp's own post doesn't shadow everything.
		var from := light.global_position + (point - light.global_position).normalized() * 0.3
		var q2 := PhysicsRayQueryParameters3D.create(from, point, MASK_OCCLUDERS, exclude)
		if not space.intersect_ray(q2).is_empty():
			continue
		# Inverse-square-like falloff that reaches zero at the light's range.
		var falloff := pow(1.0 - d / light_range, 2.0)
		total += light.light_energy / 2.2 * falloff * 1.1
	return clampf(total, 0.0, 1.0)
