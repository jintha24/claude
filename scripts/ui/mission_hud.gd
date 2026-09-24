class_name MissionHUD
extends Control
## The story's part of the HUD:
##  * the active mission's title and objective (top left) and a marker on the objective,
##    with its distance; off screen, the marker sits on the edge pointing the way;
##  * a gold diamond over anyone who has a mission for Harry, with its name;
##  * banners: "Act One", "Mission complete", the end of an act;
##  * during a fist fight, both fighters' balance and the controls.

const INK := Color(0.93, 0.88, 0.76)
const GOLD := Color(0.86, 0.68, 0.36)
const RED := Color(0.8, 0.18, 0.12)

var _banner := ""
var _banner_sub := ""
var _banner_t := 0.0
var _objective_flash := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Story.bus().objective_changed.connect(func(_t: String) -> void: _objective_flash = 1.5)


func banner(text: String, sub: String = "", seconds: float = 4.0) -> void:
	_banner = text
	_banner_sub = sub
	_banner_t = seconds


func _process(delta: float) -> void:
	_banner_t = maxf(_banner_t - delta, 0.0)
	_objective_flash = maxf(_objective_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var font := UIKit.font()
	var cam := get_viewport().get_camera_3d()
	var m := Story.active if Story.is_active() else null
	if m:
		var x := 36.0
		var y := 64.0
		draw_string(font, Vector2(x, y), m.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
		if m.objective != "":
			var col := INK.lerp(Color(1, 0.95, 0.7), clampf(_objective_flash, 0.0, 1.0))
			draw_string(font, Vector2(x, y + 26.0), "- " + m.objective, HORIZONTAL_ALIGNMENT_LEFT, 520.0, 20, col)
		var target := m.objective_position()
		if cam and target != Vector3.INF and not _markers_hidden():
			_draw_marker(cam, target, GOLD, "")
	elif cam:
		for g in get_tree().get_nodes_in_group("mission_givers"):
			var giver := g as MissionGiver
			if giver and giver.is_available():
				var p := giver.marker_position()
				if cam.global_position.distance_to(p) < 90.0:
					_draw_marker(cam, p, GOLD, giver.mission_title(), false)
	if BrawlFight.current and is_instance_valid(BrawlFight.current):
		_draw_brawl(BrawlFight.current)
	if _banner_t > 0.0:
		var a := clampf(_banner_t, 0.0, 1.0) * clampf((4.5 - _banner_t) * 3.0, 0.0, 1.0)
		var w := font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
		var y := size.y * 0.3
		draw_rect(Rect2(0, y - 52, size.x, 96), Color(0, 0, 0, 0.45 * a))
		draw_string(font, Vector2(size.x * 0.5 - w * 0.5, y), _banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(GOLD, a))
		if _banner_sub != "":
			var w2 := font.get_string_size(_banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(font, Vector2(size.x * 0.5 - w2 * 0.5, y + 32), _banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(INK, a))


## Markers are hidden during cutscenes.
func _markers_hidden() -> bool:
	var ui := get_parent() as StoryUI
	return ui != null and ui.cutscene.is_playing()


func _draw_marker(cam: Camera3D, world: Vector3, col: Color, label: String, show_distance: bool = true) -> void:
	var font := UIKit.font()
	var dist := cam.global_position.distance_to(world)
	var behind := cam.is_position_behind(world)
	var p := cam.unproject_position(world)
	var margin := 40.0
	var on_screen := not behind and p.x > margin and p.x < size.x - margin and p.y > margin and p.y < size.y - margin
	if not on_screen:
		var c := size * 0.5
		var d := p - c
		if behind:
			d = -d
		if d.length() < 1.0:
			d = Vector2(0, 1)
		var k := minf((size.x * 0.5 - margin) / maxf(absf(d.x), 0.001), (size.y * 0.5 - margin) / maxf(absf(d.y), 0.001))
		p = c + d * k
		var dir := d.normalized()
		var tip := p + dir * 14.0
		draw_colored_polygon(PackedVector2Array([tip, p + Vector2(-dir.y, dir.x) * 7.0, p - Vector2(-dir.y, dir.x) * 7.0]), Color(col, 0.9))
	var s := 9.0
	var diamond := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	draw_colored_polygon(diamond, Color(col, 0.85))
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(0, 0, 0, 0.6), 1.5, true)
	var text := label
	if show_distance:
		text = "%d m" % int(dist) if label == "" else "%s  %d m" % [label, int(dist)]
	if text != "":
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, p + Vector2(-w * 0.5 + 1, 26), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.7))
		draw_string(font, p + Vector2(-w * 0.5, 25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK, 0.95))


func _draw_brawl(b: BrawlFight) -> void:
	var font := UIKit.font()
	var bw := 320.0
	# The opponent's balance, top centre; Harry's, bottom left.
	var top := Vector2(size.x * 0.5 - bw * 0.5, 40.0)
	draw_string(font, top + Vector2(0, -6), b.foe_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	_bar(Rect2(top, Vector2(bw, 10)), b.foe_balance / 100.0, RED)
	var bottom := Vector2(40.0, size.y - 150.0)
	draw_string(font, bottom + Vector2(0, -6), "HARRY - BALANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	_bar(Rect2(bottom, Vector2(bw * 0.8, 10)), b.harry_balance / 100.0, Color(0.85, 0.78, 0.55))
	var hint := "LMB jab  |  hold LMB: haymaker  |  RMB guard  |  A / D sway aside  |  W / S step"
	var w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5, size.y - 24.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK, 0.7))
	if b.foe_act == BrawlFight.FoeAct.WINDUP:
		var k := clampf(b.foe_t / maxf(b.foe_windup, 0.01), 0.0, 1.0)
		var warn := "!" if b.foe_attack != "haymaker" else "!!"
		draw_string(font, Vector2(size.x * 0.5 - 8.0, size.y * 0.42), warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(RED, 0.4 + 0.6 * k))


func _bar(r: Rect2, v: float, col: Color) -> void:
	draw_rect(r.grow(2.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(v, 0.0, 1.0), r.size.y)), col)
	draw_rect(r.grow(2.0), Color(GOLD, 0.5), false, 1.0)
