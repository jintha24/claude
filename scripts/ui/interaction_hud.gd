class_name InteractionHUD
extends Control
## Doors, locks, windows and valuables on the HUD:
##  * the "[E] Open the study door" prompt for whatever Harry is facing
##  * a progress bar while E is held (slipping a catch, cutting a painting from its frame)
##  * the lever-lock minigame: a vertical slot per lever, the gate lit in brass, the pick's
##    rising and falling tip, and set levers shown as pins
##  * a count of lockpicks, and short notes ("A pick snapped!", "Detector tripped!")

const INK := Color(0.93, 0.88, 0.76)
const BRASS := Color(0.72, 0.56, 0.3)
const GOOD := Color(0.45, 0.7, 0.35)
const RED := Color(0.85, 0.15, 0.1)
const NOTES := {
	"slip": ["The lever slipped back.", Color(0.93, 0.88, 0.76)],
	"pick_broke": ["A pick snapped!", Color(0.85, 0.15, 0.1)],
	"jammed": ["Detector tripped - the lock has jammed!", Color(0.85, 0.15, 0.1)],
	"opened": ["The bolt slides back.", Color(0.45, 0.7, 0.35)],
	"no_picks": ["No lockpicks left.", Color(0.85, 0.15, 0.1)],
}

var player: Harry
var font: Font

var _note := ""
var _note_color := INK
var _note_time := 0.0
var _flash := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p: Harry) -> void:
	player = p
	p.interaction.lock_event.connect(func(e: String) -> void:
		if e == "lever":
			_flash = 0.25
		elif NOTES.has(e):
			_note = NOTES[e][0]
			_note_color = NOTES[e][1]
			_note_time = 2.5)


func _process(delta: float) -> void:
	_note_time = maxf(_note_time - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var f := font if font else ThemeDB.fallback_font
	var it := player.interaction
	var center := Vector2(size.x * 0.5, size.y * 0.72)
	match it.mode:
		HarryInteraction.Mode.LOCKPICK:
			_draw_lock(f, it, center)
		HarryInteraction.Mode.HOLD:
			_draw_hold(f, it, center)
		HarryInteraction.Mode.NONE:
			if it.prompt != "" and player.thievery.prompt_target == null and not player.is_aiming():
				_text(f, "[E] " + it.prompt, center, 20, INK, true)
	if _note_time > 0.0:
		_text(f, _note, center + Vector2(0, -120), 18, Color(_note_color, clampf(_note_time, 0.0, 1.0)), true)


func _draw_hold(f: Font, it: HarryInteraction, center: Vector2) -> void:
	var bar := Rect2(center - Vector2(140, 5), Vector2(280, 10))
	draw_rect(bar.grow(3), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * it.hold_progress, bar.size.y)), BRASS)
	draw_rect(bar, BRASS, false, 1.5)
	_text(f, it.hold_label + "...", center + Vector2(0, -22), 18, INK, true)
	_text(f, "Keep holding E", center + Vector2(0, 30), 14, Color(INK, 0.7), true)


func _draw_lock(f: Font, it: HarryInteraction, center: Vector2) -> void:
	var lock := it.lock
	if lock == null:
		return
	var slot_h := 150.0
	var slot_w := 26.0
	var gap := 14.0
	var total := lock.levers * slot_w + (lock.levers - 1) * gap
	var x0 := center.x - total * 0.5
	var top := center.y - slot_h - 10.0
	draw_rect(Rect2(x0 - 16, top - 36, total + 32, slot_h + 90), Color(0.05, 0.045, 0.04, 0.75))
	for i in lock.levers:
		var r := Rect2(x0 + i * (slot_w + gap), top, slot_w, slot_h)
		draw_rect(r, Color(0.14, 0.12, 0.1, 0.95))
		if i < it.lever:
			# A set lever: held at its gate.
			draw_rect(Rect2(r.position + Vector2(3, r.size.y * 0.45), Vector2(r.size.x - 6, 10)), GOOD)
		elif i == it.lever:
			# The gate (0 = bottom, 1 = top of the slot) and the pick's tip.
			var gy0 := r.end.y - r.size.y * (it.zone_center + it.zone_width * 0.5)
			draw_rect(Rect2(Vector2(r.position.x, gy0), Vector2(r.size.x, r.size.y * it.zone_width)), Color(BRASS, 0.55 + 0.4 * float(_flash > 0.0)))
			var my := r.end.y - r.size.y * it.marker
			draw_rect(Rect2(Vector2(r.position.x - 4, my - 2), Vector2(r.size.x + 8, 4)), INK)
		draw_rect(r, BRASS, false, 1.2)
	var title := "%s - lever %d of %d" % [lock.describe(), mini(it.lever + 1, lock.levers), lock.levers]
	_text(f, title, Vector2(center.x, top - 14), 16, INK, true)
	var hint := "E when the pick is in the gate.  Move away to give up."
	if lock.detector:
		hint = "Detector lock: one slip and it jams for good."
	_text(f, hint, Vector2(center.x, top + slot_h + 26), 14, Color(INK, 0.75) if not lock.detector else Color(RED, 0.9), true)
	_text(f, "Lockpicks: %d" % player.inventory.lockpicks, Vector2(center.x, top + slot_h + 46), 14, Color(BRASS, 0.9), true)


func _text(f: Font, text: String, pos: Vector2, fsize: int, color: Color, centered: bool) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := pos - Vector2(w * 0.5 if centered else 0.0, 0)
	draw_string(f, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, 0.8 * color.a))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
