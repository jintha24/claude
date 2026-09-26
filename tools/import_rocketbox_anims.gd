extends SceneTree
## Turns Rocketbox motion-capture clips (FBX, copied into res://tmp_rb/) into the two
## animation libraries the real people move with (RealPeople, NPCBody):
##   assets/characters/rocketbox/anims/male.res and female.res
##   godot --headless --path . --script res://tools/import_rocketbox_anims.gd
##
## Every Rocketbox person has the same 3ds Max biped skeleton, so a clip is just each
## bone's rotation over time. The biped's root ("Bip01") carries where the actor walked;
## that is taken out (the game moves people itself) and what is left of it - the rise and
## fall of the hips, the sway, sitting down - goes onto the pelvis, in the avatars' frame.

const SRC := "res://tmp_rb/"
const OUT := "res://assets/characters/rocketbox/anims/"
## An avatar whose skeleton names the bones the clips may drive.
const REFERENCE := "res://assets/characters/rocketbox/Business_Male_01/Business_Male_01.glb"
## Clip name in the game -> source clip (without the m_/f_ prefix), and whether it loops.
const CLIPS := {
	"idle_1": ["idle_neutral_01", true], "idle_2": ["idle_neutral_02", true], "idle_3": ["idle_breathe_01", true],
	"idle_4": ["idle_waiting_01", true], "look_around": ["idle_look_around_01", true],
	"walk": ["walk_neutral_01", true], "stroll": ["walk_stroll_01", true], "run": ["run_neutral", true],
	"sprint": ["run_fast_01", true],
	"talk": ["gestic_talk_neutral_01", true], "listen": ["gestic_listen_neutral_01", true],
	"sit": ["sit_chair_idle_neutral_01", true], "wave": ["wave_01", true], "umbrella": ["umbrella_idle_01", true],
	"drunk": ["idle_drunk_01", true], "drunk_walk": ["walk_drunk", true], "crouch": ["crouch_idle", true],
}
## Clips whose actor walks along (root motion to strip).
const MOVING := ["walk", "stroll", "run", "sprint", "drunk_walk"]


func _init() -> void:
	var ref := (load(REFERENCE) as PackedScene).instantiate()
	var skel := ref.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bones := {}
	for b in skel.get_bone_count():
		bones[skel.get_bone_name(b)] = true
	# The pelvis's parent frame in the avatar (the "Bip01" node the skeleton sits under).
	var chain := Transform3D.IDENTITY
	var n: Node = skel
	while n != ref:
		chain = (n as Node3D).transform * chain
		n = n.get_parent()
	var frame := Quaternion(chain.basis.orthonormalized())
	ref.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for g: String in ["m", "f"]:
		var lib := AnimationLibrary.new()
		var standing := 0.0
		for key: String in CLIPS:
			var src := "%s%s_%s.max.fbx" % [SRC, g, CLIPS[key][0]]
			var ps := load(src) as PackedScene
			if ps == null:
				push_error("can't load " + src)
				continue
			var root := ps.instantiate()
			get_root().add_child(root)
			var player := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			var a := player.get_animation(player.get_animation_list()[0])
			if key == "idle_1":
				standing = _bip_pos(a, 0.0).y
			var clip_skel := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var out := _convert(a, clip_skel, bones, frame, standing, key in MOVING)
			out.loop_mode = Animation.LOOP_LINEAR if CLIPS[key][1] else Animation.LOOP_NONE
			if key in MOVING:
				# How far one cycle carries them, and when the left foot is furthest forward
				# (so walking and running can be blended in step).
				out.set_meta("travel", (_bip_pos(a, a.length) - _bip_pos(a, 0.0)).length())
				out.set_meta("phase0", _left_foot_forward(a, clip_skel))
			lib.add_animation(key, out)
			print("%s %-12s %5.2f s  %3d tracks  %s" % [g, key, out.length, out.get_track_count(), [out.get_meta("travel", 0.0), out.get_meta("phase0", 0.0)]])
			root.free()
		lib.set_meta("standing", standing)
		var path := OUT + ("male" if g == "m" else "female") + ".res"
		var err := ResourceSaver.save(lib, path, ResourceSaver.FLAG_COMPRESS)
		print(path, " ", "ok" if err == OK else "error %d" % err)
	quit()


func _track(a: Animation, path: String, type: int) -> int:
	for t in a.get_track_count():
		if String(a.track_get_path(t)) == path and a.track_get_type(t) == type:
			return t
	return -1


func _bip_pos(a: Animation, t: float) -> Vector3:
	var i := _track(a, "Skeleton3D:Bip01", Animation.TYPE_POSITION_3D)
	return a.position_track_interpolate(i, t) if i >= 0 else Vector3.ZERO


func _bip_rot(a: Animation, t: float) -> Quaternion:
	var i := _track(a, "Skeleton3D:Bip01", Animation.TYPE_ROTATION_3D)
	return a.rotation_track_interpolate(i, t) if i >= 0 else Quaternion.IDENTITY


func _convert(a: Animation, clip_skel: Skeleton3D, bones: Dictionary, frame: Quaternion, standing: float, moving: bool) -> Animation:
	var out := Animation.new()
	out.length = a.length
	var fps := 30.0
	var frames := maxi(1, roundi(a.length * fps))
	# Turn the actor to face the avatars' way (+Z) at the start.
	var fwd := _bip_rot(a, 0.0) * (frame.inverse() * Vector3.BACK)
	var yaw := Quaternion(Vector3.UP, -atan2(fwd.x, fwd.z))
	var p0 := _bip_pos(a, 0.0)
	var p1 := _bip_pos(a, a.length)
	# Every bone gets a track: one the clip leaves out holds the clip's own rest (which is
	# not the avatars' rest).
	for bone: String in bones:
		var cb := clip_skel.find_bone(bone)
		if cb < 0:
			continue
		var t := _track(a, "Skeleton3D:" + bone, Animation.TYPE_ROTATION_3D)
		var rest := Quaternion(clip_skel.get_bone_rest(cb).basis.orthonormalized())
		var o := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(o, "Skeleton3D:" + bone)
		out.track_set_interpolation_loop_wrap(o, true)
		if bone == "Bip01 Pelvis":
			var po := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(po, "Skeleton3D:" + bone)
			for f in frames + 1:
				var time := minf(f / fps, a.length)
				var local := a.rotation_track_interpolate(t, time) if t >= 0 else rest
				var world := yaw * _bip_rot(a, time) * local
				out.rotation_track_insert_key(o, time, (frame.inverse() * world).normalized())
				# What's left of the root's move: up and down, and the sway about the line walked.
				var p := _bip_pos(a, time)
				var along := p0.lerp(p1, time / a.length) if moving else p0
				var rel := yaw * Vector3(p.x - along.x, p.y - standing, p.z - along.z)
				out.position_track_insert_key(po, time, frame.inverse() * rel)
		elif t < 0:
			out.rotation_track_insert_key(o, 0.0, rest)
		else:
			for k in a.track_get_key_count(t):
				out.rotation_track_insert_key(o, a.track_get_key_time(t, k), a.track_get_key_value(t, k))
	return out


## The time in `a` when the left foot is furthest ahead of the right.
func _left_foot_forward(a: Animation, sk: Skeleton3D) -> float:
	var best := -INF
	var at := 0.0
	for i in 60:
		var time := a.length * i / 60.0
		var d := (_fk(a, sk, sk.find_bone("Bip01 L Foot"), time) - _fk(a, sk, sk.find_bone("Bip01 R Foot"), time)).z
		if d > best:
			best = d
			at = time
	return at


## Where bone `b` is at `time` (skeleton space), from the clip's rotations.
func _fk(a: Animation, sk: Skeleton3D, b: int, time: float) -> Vector3:
	var xf := Transform3D.IDENTITY
	while b >= 0:
		var t := _track(a, "Skeleton3D:" + sk.get_bone_name(b), Animation.TYPE_ROTATION_3D)
		var q := a.rotation_track_interpolate(t, time) if t >= 0 else Quaternion(sk.get_bone_rest(b).basis.orthonormalized())
		xf = Transform3D(Basis(q), sk.get_bone_rest(b).origin) * xf
		b = sk.get_bone_parent(b)
	return xf.origin
