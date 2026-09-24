class_name HarryStealth
extends Node
## How visible and how audible Harry is. Child node "StealthProfile" of Harry.
##
##  * exposure: how brightly lit he is (Stealth.light_exposure_at), updated 10x a second.
##  * visibility: exposure x posture (crouched is smaller) x movement x hiding place.
##  * conspicuousness: how suspicious what he's doing looks to a constable. Walking down a
##    public street in daylight is 0 (it's not a crime), rooftops and drainpipes, sneaking,
##    trespassing, aiming a bow or knocking someone out are high.
##  * footsteps: emits a noise every stride, louder for faster gaits and hard or hollow
##    surfaces (cobbles < timber < slate roofs), quieter when crouching.

signal footstep(surface: String, loudness: float)

## Hearing radius (m) of one footstep on stone for each gait.
const STEP_RADIUS := {"crouch": 1.5, "walk": 4.0, "run": 9.0, "sprint": 15.0}
const STRIDE := {"crouch": 0.5, "walk": 0.75, "run": 1.2, "sprint": 1.8}
const SURFACE_LOUDNESS := {"stone": 1.0, "wood": 1.25, "slate": 1.3, "metal": 1.4, "grass": 0.45, "mud": 0.6, "gravel": 1.5, "carpet": 0.35}

var exposure: float = 1.0
var visibility: float = 1.0
var conspicuousness: float = 0.0
var hiding_spot: Node = null
var surface: String = "stone"
## Upgrades: soft-soled boots make footsteps quieter; a dark coat hides him better.
var footstep_multiplier: float = 1.0
var shadow_multiplier: float = 1.0
## Seconds left during which a witnessed crime makes Harry maximally suspicious.
var crime_timer: float = 0.0

var _harry: Harry
var _restricted_zones: Array[Node] = []
var _light_timer := 0.0
var _stride_acc := 0.0
## Number of townsfolk close around Harry: a crowd hides him.
var crowd_cover: int = 0


func setup(harry: Harry) -> void:
	_harry = harry
	harry.landed.connect(_on_landed)


func is_hidden() -> bool:
	return hiding_spot != null and _harry.is_crouching


func is_in_restricted_zone() -> bool:
	return not _restricted_zones.is_empty()


func enter_restricted(zone: Node) -> void:
	if not _restricted_zones.has(zone):
		_restricted_zones.append(zone)


func exit_restricted(zone: Node) -> void:
	_restricted_zones.erase(zone)


## Called when Harry does something a witness would call a crime.
func commit_crime(duration: float = 6.0) -> void:
	crime_timer = maxf(crime_timer, duration)


## Points guards test for line of sight: head, chest and hips.
func get_sample_points() -> Array[Vector3]:
	var p := _harry.global_position
	var h := 1.1 if _harry.is_crouching else 1.7
	return [p + Vector3.UP * h, p + Vector3.UP * h * 0.72, p + Vector3.UP * h * 0.45]


func _physics_process(delta: float) -> void:
	if _harry == null:
		return
	crime_timer = maxf(crime_timer - delta, 0.0)
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.1
		var exclude: Array[RID] = [_harry.get_rid()]
		exposure = Stealth.light_exposure_at(_harry.global_position + Vector3.UP * 1.2, _harry.get_world_3d(), exclude)
		_update_surface()
		_update_crowd()
	_update_visibility()
	_update_conspicuousness()
	_update_footsteps(delta)


func _update_visibility() -> void:
	var v := exposure
	if exposure < 0.5:
		v *= shadow_multiplier # a dark coat melts into the shadows (not into lamplight)
	if _harry.is_crouching:
		v *= 0.6
	if _harry.get_horizontal_speed() < 0.2 and not _harry.is_climbing():
		v *= 0.75 # a still figure is harder to pick out
	if crowd_cover >= 2:
		v *= 0.55 # lost among the crowd
	if is_hidden():
		v = 0.0
	visibility = clampf(v, 0.0, 1.0)


func _update_conspicuousness() -> void:
	var c := 0.0
	if _harry.is_sprinting():
		c = maxf(c, 0.3)
	if _harry.is_crouching and _harry.get_horizontal_speed() > 0.2:
		c = maxf(c, 0.5)
	if _harry.thievery and _harry.thievery.is_busy():
		c = maxf(c, 0.6) # hand in a stranger's pocket
	if _harry.interaction and _harry.interaction.mode in [HarryInteraction.Mode.HOLD, HarryInteraction.Mode.LOCKPICK]:
		c = maxf(c, 0.8) # fiddling with a lock, prising at a frame
	if _harry.is_climbing() or surface == "slate":
		c = maxf(c, 0.9)
	if is_in_restricted_zone():
		c = 1.0
	if _harry.combat and (_harry.combat.is_aiming() or _harry.combat.is_busy()):
		c = 1.0
	if crime_timer > 0.0:
		c = 1.0
	conspicuousness = c


func _update_crowd() -> void:
	crowd_cover = 0
	for node in _harry.get_tree().get_nodes_in_group("civilians"):
		if (node as Node3D).global_position.distance_to(_harry.global_position) < 2.2:
			crowd_cover += 1


func _update_surface() -> void:
	surface = "stone"
	var exclude: Array[RID] = [_harry.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(_harry.global_position + Vector3.UP * 0.2, _harry.global_position + Vector3.DOWN * 0.4, 1 | (1 << 3), exclude)
	var hit := _harry.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var body := hit["collider"] as CollisionObject3D
	if body == null:
		return
	if body is RigidBody3D:
		surface = "wood"
		return
	var owner_id := body.shape_find_owner(int(hit["shape"]))
	var shape_node := body.shape_owner_get_owner(owner_id) as Node
	if shape_node and shape_node.has_meta("surface"):
		surface = shape_node.get_meta("surface")
	elif body.has_meta("surface"):
		surface = body.get_meta("surface")


func _update_footsteps(delta: float) -> void:
	if not _harry.is_on_floor() or _harry.is_climbing():
		_stride_acc = 0.0
		return
	var speed := _harry.get_horizontal_speed()
	if speed < 0.2:
		return
	var gait := "walk"
	if _harry.is_crouching:
		gait = "crouch"
	elif _harry.is_sprinting():
		gait = "sprint"
	elif speed > (_harry.walk_speed + _harry.run_speed) * 0.5:
		gait = "run"
	_stride_acc += speed * delta
	if _stride_acc < STRIDE[gait]:
		return
	_stride_acc = 0.0
	var radius: float = STEP_RADIUS[gait] * SURFACE_LOUDNESS.get(surface, 1.0) * footstep_multiplier
	footstep.emit(surface, radius)
	Stealth.make_noise(_harry.global_position, radius, "footstep", conspicuousness >= 0.45, _harry)


func _on_landed(fall_height: float) -> void:
	if fall_height < 0.4:
		return
	var radius: float = clampf(4.0 + fall_height * 4.0, 4.0, 30.0) * float(SURFACE_LOUDNESS.get(surface, 1.0))
	if _harry.state == Harry.State.ROLL:
		radius *= 0.6
	Stealth.make_noise(_harry.global_position, radius, "landing", fall_height > 1.5 or conspicuousness >= 0.45, _harry)
