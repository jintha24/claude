class_name PickpocketHUD
extends Control
## Pickpocketing and loot on the HUD:
##  * "[E] Pick pocket - a gentleman" when a mark is within reach from behind
##  * the timing bar: sweet spot, sweeping hand marker, stage pips, the victim's suspicion
##  * toasts for stolen goods and a small purse readout that fades after a while

const INK := Color(0.93, 0.88, 0.76)
const BRASS := Color(0.72, 0.56, 0.3)
const GOOD := Color(0.45, 0.7, 0.35)
const RED := Color(0.85, 0.15, 0.1)

var player: Harry
var font: Font

var _toasts: Array[Dictionary] = []
var _purse_alpha := 0.0
var _purse_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p: Harry) -> void:
	player = p
	p.inventory.item_added.connect(func(item: Dictionary) -> void:
		_toast("Stolen: %s (worth about %s)" % [item["name"], Money.format(int(item["value"]))]))
	p.inventory.money_changed.connect(func(_m: int) -> void:
		_purse_timer = 5.0)
	p.thievery.attempt_finished.connect(func(success: bool, loot: Array) -> void:
		if success:
			var coins := 0
			for it in loot:
				if it["kind"] == "coins":
					coins += int(it["value"])
			if coins > 0:
				_toast("Coins: %s" % Money.format(coins))
			elif loot.is_empty():
				_toast("Empty pockets.")
		else:
			_toast("Caught in the act!", RED))


func _toast(text: String, color: Color = INK) -> void:
	_toasts.append({"text": text, "time": 4.0, "color": color})
	if _toasts.size() > 4:
		_toasts.pop_front()


func _process(delta: float) -> void:
	for t in _toasts:
		t["time"] = float(t["time"]) - delta
	_toasts = _toasts.filter(func(t: Dictionary) -> bool: return float(t["time"]) > 0.0)
	_purse_timer = maxf(_purse_timer - delta, 0.0)
	_purse_alpha = move_toward(_purse_alpha, 1.0 if _purse_timer > 0.0 else 0.0, delta * 2.0)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var f := font if font else ThemeDB.fallback_font
	var th := player.thievery
	var center := Vector2(size.x * 0.5, size.y * 0.72)
	if th.victim != null:
		_draw_minigame(f, th, center)
	elif th.prompt_target != null and not player.is_aiming():
		var who: String = {"gentleman": "a gentleman", "lady": "a lady", "merchant": "a trader", "worker": "a working man"}.get(th.prompt_target.victim_class, "someone")
		var text := "[E] Pick pocket - %s" % who
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(f, center - Vector2(w * 0.5, 0) + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0, 0.8))
		draw_string(f, center - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	# Toasts, top-right.
	var y := 90.0
	for t in _toasts:
		var a := clampf(float(t["time"]), 0.0, 1.0)
		var text: String = t["text"]
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var p := Vector2(size.x - w - 40.0, y)
		draw_string(f, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0, 0, 0, 0.8 * a))
		draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(t["color"], a))
		y += 28.0
	if _purse_alpha > 0.01:
		var purse := "Purse: %s" % Money.format(player.inventory.money)
		var w2 := f.get_string_size(purse, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(f, Vector2(size.x - w2 - 40.0, 56.0), purse, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(BRASS, _purse_alpha))


func _draw_minigame(f: Font, th: HarryThievery, center: Vector2) -> void:
	var bar := Rect2(center - Vector2(160, 8), Vector2(320, 16))
	draw_rect(bar.grow(3), Color(0, 0, 0, 0.6))
	draw_rect(bar, Color(0.12, 0.1, 0.08, 0.9))
	var zx := bar.position.x + bar.size.x * (th.zone_center - th.zone_width * 0.5)
	draw_rect(Rect2(Vector2(zx, bar.position.y), Vector2(bar.size.x * th.zone_width, bar.size.y)), Color(GOOD, 0.85))
	var mx := bar.position.x + bar.size.x * th.marker
	draw_rect(Rect2(Vector2(mx - 2, bar.position.y - 6), Vector2(4, bar.size.y + 12)), INK)
	draw_rect(bar, BRASS, false, 1.5)
	# Stage pips.
	for i in th.stages:
		var pc := bar.position + Vector2(bar.size.x * 0.5 + (i - (th.stages - 1) * 0.5) * 18.0, -22.0)
		draw_circle(pc, 5.0, GOOD if i < th.stage else Color(INK, 0.4))
	var label := "Unhook the chain..." if th.stages == 2 and th.stage == 0 else "Lift it..."
	draw_string(f, bar.position + Vector2(0, -34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	# The mark's growing suspicion.
	var s := th.victim.suspicion if th.victim else 0.0
	var sb := Rect2(bar.position + Vector2(0, 28), Vector2(bar.size.x * s, 4))
	draw_rect(Rect2(bar.position + Vector2(0, 28), Vector2(bar.size.x, 4)), Color(0, 0, 0, 0.5))
	draw_rect(sb, INK.lerp(RED, s))
	draw_string(f, bar.position + Vector2(0, 50), "Press E in the green. Crowds widen it.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK, 0.7))
