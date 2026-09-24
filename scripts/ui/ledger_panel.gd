class_name LedgerPanel
extends Control
## Harry's pocket-book (hold Tab): his purse, lockpicks and arrows, the Legend and his
## notoriety (with Captain Crowe's reward), the loot he's carrying, and his upgrades.

var player: Harry


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var f := UIKit.font()
	var r := Rect2(size.x - 470.0, 110.0, 430.0, size.y - 220.0)
	draw_rect(r, UIKit.PANEL)
	draw_rect(r, UIKit.BRASS, false, 2.0)
	var x := r.position.x + 22.0
	var y := r.position.y + 40.0
	var line := func(text: String, sz: int = 18, c: Color = UIKit.INK) -> void:
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0, sz, c)
		y += sz + 10.0
	line.call("Harry Crane's Pocket-Book", 24, UIKit.BRASS)
	line.call("%s   (%s)" % [GameClock.date_string(), GameClock.clock_string()], 15, UIKit.INK_DIM)
	y += 4.0
	line.call("Purse: %s" % Money.format(player.inventory.money))
	line.call("Lockpicks: %d    Arrows: %d blunt, %d whistle, %d broadhead" % [player.inventory.lockpicks, player.combat.blunt_arrows, player.combat.whistle_arrows, player.combat.broadhead_arrows], 15)
	y += 6.0
	line.call("The Legend: %s" % Progress.rank(), 19, UIKit.BRASS)
	_bar(Rect2(x, y - 6.0, r.size.x - 44.0, 8.0), Progress.legend / 100.0, UIKit.GOOD)
	y += 14.0
	line.call("Given to the poor: %s" % Money.format(Progress.given_total), 15, UIKit.INK_DIM)
	var level: String = ["Unknown to the police", "Wanted: posters are up", "Hunted: extra constables", "A marked man: lie low"][Progress.escalation()]
	line.call("Notoriety: %s" % level, 19, UIKit.RED if Progress.escalation() >= 2 else UIKit.BRASS)
	_bar(Rect2(x, y - 6.0, r.size.x - 44.0, 8.0), Progress.notoriety / 100.0, UIKit.RED)
	y += 14.0
	if Progress.bounty() > 0:
		line.call("Crowe's reward: %s" % Money.format(Progress.bounty()), 15, UIKit.INK_DIM)
	y += 6.0
	line.call("Carrying:", 18, UIKit.BRASS)
	var counts := {}
	for it in player.inventory.items:
		var key := String(it["name"])
		counts[key] = int(counts.get(key, 0)) + 1
	if counts.is_empty():
		line.call("  nothing", 15, UIKit.INK_DIM)
	for k: String in counts:
		if y > r.end.y - 70.0:
			line.call("  ...", 15, UIKit.INK_DIM)
			break
		line.call("  %s%s" % [k, "" if counts[k] == 1 else " x%d" % counts[k]], 15)
	if not Progress.upgrades.is_empty():
		y = maxf(y, r.end.y - 50.0)
		var names: Array[String] = []
		for id: String in Progress.upgrades:
			if Upgrades.CATALOG.has(id):
				names.append(String(Upgrades.CATALOG[id]["name"]))
		line.call("Kit: " + ", ".join(names), 13, UIKit.INK_DIM)


func _bar(rect: Rect2, t: float, c: Color) -> void:
	draw_rect(rect, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(t, 0.0, 1.0), rect.size.y)), c)
	draw_rect(rect, UIKit.BRASS, false, 1.0)
