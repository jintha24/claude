class_name CityBuilder
extends RefCounted
## Builds one chunk of the city (CityPlan) as plain data, on any thread.
##
## Detail levels (by distance from the player's chunk, see CityStreamer):
##   0: everything - sash windows with glazing bars, doorcases, steps, railings,
##      shopfronts, chimney pots, collision, the walkable navigation mesh, lamps, doors,
##      shop signs and props
##   1: the same buildings with simple windows and doors, no collision
##   2: masses, roofs, window panes and chimney stacks
## (Further off, CityStreamer draws whole terraces as single boxes.)

const PAINT_COLORS: Array[Color] = [
	Color(0.08, 0.17, 0.12), Color(0.28, 0.07, 0.06), Color(0.04, 0.04, 0.045),
	Color(0.07, 0.10, 0.18), Color(0.55, 0.50, 0.38),
]
const LAMP_SPACING := 27.0


static func build_chunk(plan: CityPlan, c: Vector2i, lod: int) -> Dictionary:
	var g := CityGeo.new()
	g.collide = lod == 0
	var out := {
		"coord": c, "lod": lod, "doors": [], "lamps": [], "labels": [], "pipes": [], "trees": [],
		"props": [],
	}
	var cr := plan.chunk_rect(c)
	_build_roads(g, plan, cr)
	for i in plan.blocks_owned(c):
		var b: Dictionary = plan.blocks[i]
		_build_block(g, plan, b, lod, out)
	out["surfaces"] = g.surfaces
	out["solid"] = g.solid
	out["roofs"] = g.roofs
	out["shadow"] = _shadow_arrays(g.surfaces)
	out["occluder"] = [g.occ_verts, g.occ_idx]
	return out


# ---------------------------------------------------------------------------
# Rectangles
# ---------------------------------------------------------------------------
## `r` minus the `holes`, as a list of rectangles.
static func subtract(r: Rect2, holes: Array) -> Array:
	var parts := [r]
	for h: Rect2 in holes:
		var next := []
		for p: Rect2 in parts:
			if not p.intersects(h):
				next.append(p)
				continue
			var i := p.intersection(h)
			if i.position.y > p.position.y:
				next.append(Rect2(p.position.x, p.position.y, p.size.x, i.position.y - p.position.y))
			if i.end.y < p.end.y:
				next.append(Rect2(p.position.x, i.end.y, p.size.x, p.end.y - i.end.y))
			if i.position.x > p.position.x:
				next.append(Rect2(p.position.x, i.position.y, i.position.x - p.position.x, i.size.y))
			if i.end.x < p.end.x:
				next.append(Rect2(i.end.x, i.position.y, p.end.x - i.end.x, i.size.y))
		parts = next
	return parts.filter(func(p: Rect2) -> bool: return p.size.x > 0.01 and p.size.y > 0.01)


static func road_rects(plan: CityPlan, cr: Rect2) -> Array:
	var city := Rect2(-CityPlan.HALF, -CityPlan.HALF, CityPlan.HALF * 2.0, CityPlan.HALF * 2.0)
	var area := cr.intersection(city)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return []
	var river := Rect2(-CityPlan.HALF - 10.0, CityPlan.RIVER_Z0 - CityPlan.WALK, CityPlan.HALF * 2.0 + 20.0, CityPlan.RIVER_Z1 - CityPlan.RIVER_Z0 + CityPlan.WALK * 2.0)
	var out := subtract(area, [CityPlan.CORE, river])
	for r in plan.extra_roads:
		if r.intersects(cr):
			out.append(r.intersection(cr))
	return out


# ---------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------
static func _build_roads(g: CityGeo, plan: CityPlan, cr: Rect2) -> void:
	g.frame = Transform3D.IDENTITY
	for r: Rect2 in road_rects(plan, cr):
		g.floor_rect("cobble", r, 0.0)
		g.col_box(Vector3(r.size.x, 0.6, r.size.y), Vector3(r.get_center().x, -0.3, r.get_center().y))


# ---------------------------------------------------------------------------
# Blocks
# ---------------------------------------------------------------------------
static func _build_block(g: CityGeo, plan: CityPlan, b: Dictionary, lod: int, out: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var kind: CityPlan.Kind = b["kind"]
	var f := plan.lot_rect(b)
	g.frame = Transform3D.IDENTITY
	# The raised pavement (a granite-kerbed slab the whole block stands on).
	var top := CityPlan.PAVE_TOP
	g.floor_rect("pavement", r, top)
	var y0 := -0.05
	g.quad("curb_granite", Vector3(r.position.x, y0, r.end.y), Vector3(r.end.x, y0, r.end.y), Vector3(r.end.x, top, r.end.y), Vector3(r.position.x, top, r.end.y), Vector3(0, 0, 1))
	g.quad("curb_granite", Vector3(r.end.x, y0, r.position.y), Vector3(r.position.x, y0, r.position.y), Vector3(r.position.x, top, r.position.y), Vector3(r.end.x, top, r.position.y), Vector3(0, 0, -1))
	g.quad("curb_granite", Vector3(r.end.x, y0, r.end.y), Vector3(r.end.x, y0, r.position.y), Vector3(r.end.x, top, r.position.y), Vector3(r.end.x, top, r.end.y), Vector3(1, 0, 0))
	g.quad("curb_granite", Vector3(r.position.x, y0, r.position.y), Vector3(r.position.x, y0, r.end.y), Vector3(r.position.x, top, r.end.y), Vector3(r.position.x, top, r.position.y), Vector3(-1, 0, 0))
	g.col_box(Vector3(r.size.x, 0.45, r.size.y), Vector3(r.get_center().x, top - 0.225, r.get_center().y))
	if lod <= 2:
		_lamps_for(b, f, out)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b["seed"])
	match kind:
		CityPlan.Kind.TERRACE, CityPlan.Kind.FILL, CityPlan.Kind.WAREHOUSE:
			if lod <= 1:
				g.floor_rect("yard", f.grow(-0.2), top + 0.02)
			for lot: Dictionary in plan.lots(b):
				_building(g, lot, lod, out)
			if lod == 0:
				_yard_walls(g, b, f, rng)
		CityPlan.Kind.INFILL:
			_infill(g, f, lod, rng)
		CityPlan.Kind.SQUARE:
			_garden(g, b, f, lod, rng, out, false)
		CityPlan.Kind.PARK:
			_garden(g, b, f, lod, rng, out, true)
		CityPlan.Kind.CHURCH:
			_church(g, b, f, lod, rng, out)
		CityPlan.Kind.LANDMARK:
			_landmark_grounds(g, b, f, lod, rng, out)
	g.frame = Transform3D.IDENTITY


static func _lamps_for(b: Dictionary, f: Rect2, out: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var pave: Array = b["pave"]
	var inset := 0.45
	# Along each side with a pavement, at the kerb, skipping the corners.
	var sides := [
		[pave[CityPlan.Side.N], Vector3(r.position.x, 0, r.position.y + inset), Vector3(r.end.x, 0, r.position.y + inset)],
		[pave[CityPlan.Side.S], Vector3(r.position.x, 0, r.end.y - inset), Vector3(r.end.x, 0, r.end.y - inset)],
		[pave[CityPlan.Side.E], Vector3(r.end.x - inset, 0, r.position.y), Vector3(r.end.x - inset, 0, r.end.y)],
		[pave[CityPlan.Side.W], Vector3(r.position.x + inset, 0, r.position.y), Vector3(r.position.x + inset, 0, r.end.y)],
	]
	if b["kind"] == CityPlan.Kind.SLAB:
		# The ring round the core: lamps along its kerb (the side away from the core).
		var c := r.get_center()
		var core_c := CityPlan.CORE.get_center()
		if r.size.x > r.size.y:
			var z := r.position.y + inset if c.y < core_c.y else r.end.y - inset
			sides = [[1.0, Vector3(r.position.x, 0, z), Vector3(r.end.x, 0, z)]]
		else:
			var x := r.position.x + inset if c.x < core_c.x else r.end.x - inset
			sides = [[1.0, Vector3(x, 0, r.position.y), Vector3(x, 0, r.end.y)]]
	for s: Array in sides:
		if float(s[0]) < 1.5:
			continue
		var a: Vector3 = s[1]
		var e: Vector3 = s[2]
		var length := a.distance_to(e)
		var n := int((length - 8.0) / LAMP_SPACING)
		if n < 1:
			continue
		var step := (length - 8.0) / n
		for k in n + 1:
			var p := a.lerp(e, (4.0 + step * k) / length)
			p.y = CityPlan.PAVE_TOP
			(out["lamps"] as Array).append(p)


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
static func _building(g: CityGeo, lot: Dictionary, lod: int, out: Dictionary) -> void:
	g.frame = lot["xf"]
	if lot["kind"] == "warehouse":
		_warehouse(g, lot, lod, out)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lot["seed"])
	var w: float = lot["w"]
	var d: float = lot["d"]
	var gh: float = lot["gh"]
	var fh: float = lot["fh"]
	var upper: int = lot["upper"]
	var h := gh + upper * fh
	var wall: String = lot["wall"]
	var stone := "stucco_trim" if wall == "stucco" else "stone_trim"
	var paint := "paint%d" % (rng.randi() % PAINT_COLORS.size())
	if lot["kind"] == "pub":
		paint = "paint%d" % [0, 1, 2][rng.randi() % 3]
	# Mass. At a distance the back and bottom are never seen.
	g.box(wall, Vector3(w, h + 0.3, d), Vector3(w * 0.5, (h - 0.3) * 0.5, -d * 0.5))
	g.col_box(Vector3(w, h + 0.3, d), Vector3(w * 0.5, (h - 0.3) * 0.5, -d * 0.5))
	g.occluder_box(Vector3(w - 0.1, h, d - 0.2), Vector3(w * 0.5, h * 0.5, -d * 0.5))
	# String course, dentils and cornice (real ledges to hang from).
	if lod <= 1:
		g.solid_box(stone, Vector3(w, 0.22, 0.14), Vector3(w * 0.5, gh, 0.07))
		g.solid_box(stone, Vector3(w, 0.34, 0.34), Vector3(w * 0.5, h - 0.12, 0.17))
		if lod == 0:
			g.box(stone, Vector3(w, 0.12, 0.18), Vector3(w * 0.5, h - 0.36, 0.09))
	else:
		g.box(stone, Vector3(w, 0.3, 0.3), Vector3(w * 0.5, h - 0.12, 0.15), Basis.IDENTITY, 0x1d)
	# Upper-floor windows.
	var count := maxi(1, int((w - 0.6) / 1.8))
	var spacing := w / count
	for fl in upper:
		var top := fl == upper - 1
		var yf := gh + fl * fh
		var wh := (1.45 if top else 1.8) * fh / 3.0
		var ww := 0.85 if top else 0.95
		for i in count:
			_window(g, rng, spacing * (i + 0.5), yf + 0.75, ww, wh, stone, lod, not top)
	# Windows in the side wall of a corner house.
	var open_sides: int = lot.get("side_open", 0)
	if open_sides != 0:
		var lot_xf: Transform3D = lot["xf"]
		var n_side := maxi(1, int((d - 1.5) / 2.3))
		for side in 2:
			if open_sides & (1 << side) == 0:
				continue
			var sxf := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, 0, -d)) if side == 0 else Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w, 0, 0))
			g.frame = lot_xf * sxf
			for fl in upper:
				var yf := gh + fl * fh
				var wh := (1.45 if fl == upper - 1 else 1.8) * fh / 3.0
				for i in n_side:
					_window(g, rng, d * (i + 0.5) / n_side, yf + 0.75, 0.9, wh, stone, lod, false)
			if lod <= 1:
				g.box(stone, Vector3(d, 0.3, 0.3), Vector3(d * 0.5, h - 0.12, 0.15), Basis.IDENTITY, 0x1d)
		g.frame = lot_xf
	# Ground floor.
	if lot["shop"]:
		_shopfront(g, rng, lot, w, gh, paint, stone, lod, out)
	else:
		_house_front(g, rng, lot, w, gh, paint, stone, count, spacing, lod, out)
	# Roof and chimney stacks on the party walls.
	var rise := g.pitched_roof(w, d, h, 32.0, wall)
	if lod <= 1:
		g.box("ridge", Vector3(w + 0.1, 0.14, 0.26), Vector3(w * 0.5, h + rise + 0.05, -d * 0.5), Basis.IDENTITY, 0x1f)
	var stacks: Array[float] = [0.45]
	if w > 5.0 and rng.randf() > 0.35:
		stacks.append(w - 0.45)
	var brick := "brick_red" if wall == "brick_yellow" and rng.randf() > 0.6 else ("brick_yellow" if wall == "stucco" else wall)
	for sx in stacks:
		var base_y := h + rise - 0.6
		var sh := 2.1
		if lod == 2:
			g.box(brick, Vector3(0.75, sh, 1.5), Vector3(sx, base_y + sh * 0.5, -d * 0.5), Basis.IDENTITY, 0x1f)
			continue
		g.solid_box(brick, Vector3(0.75, sh, 1.5), Vector3(sx, base_y + sh * 0.5, -d * 0.5))
		g.box(stone, Vector3(0.87, 0.1, 1.62), Vector3(sx, base_y + sh + 0.05, -d * 0.5))
		if lod == 0:
			var pots := 2 + rng.randi() % 3
			for p in pots:
				var pz := -d * 0.5 - 0.55 + 1.1 * float(p) / float(maxi(pots - 1, 1))
				var ph := 0.45 + rng.randf() * 0.25
				g.cylinder("terracotta", 0.13, 0.1, ph, Vector3(sx, base_y + sh + 0.1 + ph * 0.5, pz), 6)
	# Rainwater pipe (climbable).
	if lod == 0:
		var px := w - 0.12 if lot["door_left"] else 0.12
		g.box("iron", Vector3(0.09, h, 0.09), Vector3(px, h * 0.5, 0.09), Basis.IDENTITY, 0x0f)
		g.box("iron", Vector3(0.2, 0.22, 0.16), Vector3(px, h - 0.45, 0.1))
		g.box("iron", Vector3(w, 0.1, 0.12), Vector3(w * 0.5, h + 0.02, 0.37))
		if rng.randf() < 0.6:
			(out["pipes"] as Array).append([g.frame * Vector3(px, h * 0.5, 0.09), h])


static func _window(g: CityGeo, rng: RandomNumberGenerator, cx: float, y: float, ww: float, wh: float, stone: String, lod: int, keystone: bool) -> void:
	var yc := y + wh * 0.5
	var pane := "glass_%d" % (rng.randi() % 3)
	if lod == 2:
		g.quad(pane, Vector3(cx - ww * 0.5, y, 0.015), Vector3(cx + ww * 0.5, y, 0.015), Vector3(cx + ww * 0.5, y + wh, 0.015), Vector3(cx - ww * 0.5, y + wh, 0.015), Vector3(0, 0, 1))
		return
	g.box(pane, Vector3(ww, wh, 0.02), Vector3(cx, yc, 0.0), Basis.IDENTITY, 0x01)
	g.solid_box(stone, Vector3(ww + 0.44, 0.24, 0.12), Vector3(cx, y + wh + 0.12, 0.06)) # lintel
	g.solid_box(stone, Vector3(ww + 0.3, 0.07, 0.17), Vector3(cx, y - 0.035, 0.085)) # sill
	if lod == 1:
		g.box("white", Vector3(ww, 0.05, 0.05), Vector3(cx, yc, 0.03), Basis.IDENTITY, 0x1d)
		return
	# Sash frame, meeting rail and glazing bars (a 2-over-2 sash), stone jambs.
	g.box("white", Vector3(0.06, wh, 0.05), Vector3(cx - ww * 0.5 + 0.03, yc, 0.025), Basis.IDENTITY, 0x0d)
	g.box("white", Vector3(0.06, wh, 0.05), Vector3(cx + ww * 0.5 - 0.03, yc, 0.025), Basis.IDENTITY, 0x0d)
	g.box("white", Vector3(ww, 0.06, 0.05), Vector3(cx, y + wh - 0.03, 0.025), Basis.IDENTITY, 0x31)
	g.box("white", Vector3(ww, 0.08, 0.05), Vector3(cx, y + 0.04, 0.025), Basis.IDENTITY, 0x11)
	g.box("white", Vector3(ww, 0.05, 0.06), Vector3(cx, yc, 0.03), Basis.IDENTITY, 0x31)
	g.box("white", Vector3(0.03, wh, 0.04), Vector3(cx, yc, 0.02), Basis.IDENTITY, 0x0d)
	g.box(stone, Vector3(0.14, wh + 0.1, 0.09), Vector3(cx - ww * 0.5 - 0.07, yc, 0.045), Basis.IDENTITY, 0x0d)
	g.box(stone, Vector3(0.14, wh + 0.1, 0.09), Vector3(cx + ww * 0.5 + 0.07, yc, 0.045), Basis.IDENTITY, 0x0d)
	if keystone:
		g.box(stone, Vector3(0.18, 0.32, 0.15), Vector3(cx, y + wh + 0.13, 0.075))


static func _house_front(g: CityGeo, rng: RandomNumberGenerator, lot: Dictionary, w: float, gh: float, paint: String, stone: String, count: int, spacing: float, lod: int, out: Dictionary) -> void:
	var steps := 3
	var floor_y := steps * 0.17
	var door_w := 1.05
	var door_h := 2.3
	var door_x := 0.95 if lot["door_left"] else w - 0.95
	if lod == 2:
		g.quad(paint, Vector3(door_x - door_w * 0.5, floor_y, 0.015), Vector3(door_x + door_w * 0.5, floor_y, 0.015), Vector3(door_x + door_w * 0.5, floor_y + door_h, 0.015), Vector3(door_x - door_w * 0.5, floor_y + door_h, 0.015), Vector3(0, 0, 1))
	else:
		g.box(paint, Vector3(door_w, door_h, 0.06), Vector3(door_x, floor_y + door_h * 0.5, 0.0), Basis.IDENTITY, 0x01)
		g.solid_box(stone, Vector3(door_w + 0.7, 0.32, 0.24), Vector3(door_x, floor_y + door_h + 0.66, 0.12)) # hood
		if lod == 1:
			g.box("curb_granite", Vector3(1.6, floor_y, steps * 0.3), Vector3(door_x, floor_y * 0.5, steps * 0.15))
		(out["doors"] as Array).append([g.frame * Vector3(door_x, 0.0, steps * 0.3 + 0.6), "house"])
	if lod == 0:
		for px: float in [-0.22, 0.22]:
			for py: float in [0.55, 1.55]:
				g.box(paint, Vector3(0.34, 0.75, 0.025), Vector3(door_x + px, floor_y + py, 0.04), Basis.IDENTITY, 0x01)
		g.box("brass", Vector3(0.05, 0.05, 0.06), Vector3(door_x + (0.38 if lot["door_left"] else -0.38), floor_y + 1.05, 0.06))
		g.box("glass_1", Vector3(door_w - 0.1, 0.42, 0.02), Vector3(door_x, floor_y + door_h + 0.26, 0.0), Basis.IDENTITY, 0x01)
		for side: float in [-1.0, 1.0]:
			g.box(stone, Vector3(0.22, door_h + 0.55, 0.16), Vector3(door_x + side * (door_w * 0.5 + 0.11), floor_y + (door_h + 0.55) * 0.5, 0.08), Basis.IDENTITY, 0x1d)
		# The steps, one by one.
		for k in steps:
			var sh := (k + 1) * 0.17
			var sd := (steps - k) * 0.3
			g.solid_box("curb_granite", Vector3(1.6, sh, sd), Vector3(door_x, sh * 0.5, sd * 0.5), Basis.IDENTITY, 0x1f)
		g.box(stone, Vector3(w, 0.55, 0.06), Vector3(w * 0.5, 0.275, 0.03), Basis.IDENTITY, 0x1d) # plinth
	# Ground-floor windows.
	for i in count:
		var cx := spacing * (i + 0.5)
		if absf(cx - door_x) < 1.3:
			continue
		_window(g, rng, cx, floor_y + 0.75, 1.0, 1.95 * gh / 3.4, stone, lod, true)
	# Area railings in front of the house, with a gap at the steps.
	if lod <= 1:
		var rz := 0.95
		for span: Vector2 in [Vector2(0.1, door_x - 0.85), Vector2(door_x + 0.85, w - 0.1)]:
			if span.y - span.x < 0.4:
				continue
			_railing(g, span.x, span.y, rz, 1.05, lod)


## Cast-iron railings along local X at z, from x0 to x1.
static func _railing(g: CityGeo, x0: float, x1: float, z: float, height: float, lod: int) -> void:
	var length := x1 - x0
	g.col_box(Vector3(length, height, 0.06), Vector3((x0 + x1) * 0.5, height * 0.5, z))
	g.box("iron", Vector3(length, 0.035, 0.03), Vector3((x0 + x1) * 0.5, height - 0.08, z))
	if lod == 1:
		# From across the street the bars read as a dark band.
		g.box("iron", Vector3(length, height - 0.1, 0.012), Vector3((x0 + x1) * 0.5, (height - 0.1) * 0.5, z), Basis.IDENTITY, 0x03)
		return
	g.box("iron", Vector3(length, 0.035, 0.03), Vector3((x0 + x1) * 0.5, 0.12, z))
	var bars := int(length / 0.14)
	for k in bars + 1:
		var x := x0 + length * float(k) / float(maxi(bars, 1))
		g.box("iron", Vector3(0.022, height, 0.022), Vector3(x, height * 0.5, z), Basis.IDENTITY, 0x0f)
		g.box("iron", Vector3(0.04, 0.07, 0.04), Vector3(x, height + 0.02, z), Basis(Vector3.UP, PI * 0.25), 0x0f)


static func _shopfront(g: CityGeo, rng: RandomNumberGenerator, lot: Dictionary, w: float, gh: float, paint: String, stone: String, lod: int, out: Dictionary) -> void:
	var door_w := 1.0
	var door_x := 0.85 if lot["door_left"] else w - 0.85
	var pub: bool = lot["kind"] == "pub"
	# Fascia (the sign board) and the display window.
	g.solid_box(paint, Vector3(w - 0.3, 0.55, 0.12), Vector3(w * 0.5, gh - 0.475, 0.2))
	var disp_x0 := 0.3 if not lot["door_left"] else door_x + door_w * 0.5 + 0.05
	var disp_x1 := w - 0.3 if lot["door_left"] else door_x - door_w * 0.5 - 0.05
	var disp_w := disp_x1 - disp_x0
	var disp_c := (disp_x0 + disp_x1) * 0.5
	if lod == 2:
		g.quad("glass_shop", Vector3(disp_x0, 0.6, 0.07), Vector3(disp_x1, 0.6, 0.07), Vector3(disp_x1, 2.6, 0.07), Vector3(disp_x0, 2.6, 0.07), Vector3(0, 0, 1))
		return
	g.box("glass_shop", Vector3(disp_w, 2.0, 0.02), Vector3(disp_c, 1.6, 0.06), Basis.IDENTITY, 0x01)
	g.solid_box(paint, Vector3(disp_w, 0.6, 0.14), Vector3(disp_c, 0.3, 0.07))
	g.box(paint, Vector3(door_w, 2.45, 0.05), Vector3(door_x, 1.225, -0.02), Basis.IDENTITY, 0x01)
	g.col_box(Vector3(w, 2.8, 0.1), Vector3(w * 0.5, 1.4, 0.05))
	(out["doors"] as Array).append([g.frame * Vector3(door_x, 0.0, 0.8), "pub" if pub else "shop"])
	if lod == 0:
		for x: float in [0.15, w - 0.15]:
			g.box(paint, Vector3(0.3, gh - 0.1, 0.18), Vector3(x, (gh - 0.1) * 0.5, 0.09), Basis.IDENTITY, 0x0f)
		g.solid_box(paint, Vector3(w, 0.12, 0.34), Vector3(w * 0.5, gh - 0.14, 0.17))
		g.box("white", Vector3(disp_w, 0.07, 0.08), Vector3(disp_c, 2.25, 0.08))
		var mullions := maxi(1, int(disp_w / 1.1))
		for m in mullions + 1:
			var mx := disp_x0 + disp_w * float(m) / float(mullions)
			g.box("white", Vector3(0.06, 2.0, 0.08), Vector3(mx, 1.6, 0.08), Basis.IDENTITY, 0x0f)
		g.box("glass_shop", Vector3(door_w - 0.25, 1.1, 0.02), Vector3(door_x, 1.65, 0.01), Basis.IDENTITY, 0x01)
		g.box("glass_shop", Vector3(door_w, 0.3, 0.02), Vector3(door_x, 2.6, 0.0), Basis.IDENTITY, 0x01)
		if lot["name"] != "":
			(out["labels"] as Array).append([lot["name"], g.frame * Transform3D(Basis.IDENTITY, Vector3(w * 0.5, gh - 0.475, 0.262)), w - 0.8])
		if pub:
			# Gas lanterns on brackets either side of the door.
			for side: float in [-1.0, 1.0]:
				var lx := clampf(door_x + side * 0.9, 0.3, w - 0.3)
				g.box("iron", Vector3(0.04, 0.04, 0.5), Vector3(lx, gh - 1.0, 0.25))
				g.box("city_lamp", Vector3(0.22, 0.3, 0.22), Vector3(lx, gh - 1.2, 0.5))
		elif rng.randf() < 0.45:
			# A canvas awning over the pavement.
			var o := 1.5
			var drop := 0.55
			var tilt := atan2(drop, o)
			var awn := "awning%d" % (rng.randi() % 4)
			g.box(awn, Vector3(w - 0.4, 0.02, sqrt(o * o + drop * drop)), Vector3(w * 0.5, gh - 0.85 - drop * 0.5, o * 0.5), Basis(Vector3.RIGHT, tilt))
			g.box(awn, Vector3(w - 0.4, 0.25, 0.02), Vector3(w * 0.5, gh - 0.85 - drop - 0.12, o))


static func _warehouse(g: CityGeo, lot: Dictionary, lod: int, out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lot["seed"])
	var w: float = lot["w"]
	var d: float = lot["d"]
	var gh: float = lot["gh"]
	var fh: float = lot["fh"]
	var upper: int = lot["upper"]
	var h := gh + upper * fh
	var wall: String = lot["wall"]
	g.box(wall, Vector3(w, h + 1.2, d), Vector3(w * 0.5, (h + 1.2 - 0.3) * 0.5 - 0.15, -d * 0.5))
	g.col_box(Vector3(w, h + 1.2, d), Vector3(w * 0.5, (h + 1.2 - 0.3) * 0.5 - 0.15, -d * 0.5))
	g.occluder_box(Vector3(w - 0.1, h, d - 0.2), Vector3(w * 0.5, h * 0.5, -d * 0.5))
	# Parapet coping and a low slate roof behind it.
	g.box("stone_trim", Vector3(w + 0.1, 0.25, 0.4), Vector3(w * 0.5, h + 1.0, 0.0), Basis.IDENTITY, 0x1d)
	g.pitched_roof(w, d, h + 0.9, 14.0, wall, "slate", 0.0, false)
	# The loading bay: a column of doors, one per floor, under a cathead beam and hoist.
	var bay_x := w * 0.5
	var doors := "paint%d" % [1, 2, 3][rng.randi() % 3]
	for fl in upper + 1:
		var y := 0.0 if fl == 0 else gh + (fl - 1) * fh + 0.2
		var dh := 3.0 if fl == 0 else 2.3
		if lod == 2:
			g.quad(doors, Vector3(bay_x - 1.1, y, 0.015), Vector3(bay_x + 1.1, y, 0.015), Vector3(bay_x + 1.1, y + dh, 0.015), Vector3(bay_x - 1.1, y + dh, 0.015), Vector3(0, 0, 1))
		else:
			g.box(doors, Vector3(2.2, dh, 0.08), Vector3(bay_x, y + dh * 0.5, 0.0), Basis.IDENTITY, 0x01)
			if fl > 0:
				g.solid_box("stone_trim", Vector3(2.6, 0.18, 0.3), Vector3(bay_x, y - 0.09, 0.15))
	if lod <= 1:
		g.solid_box("wood_dark", Vector3(0.3, 0.3, 1.6), Vector3(bay_x, h + 0.4, 0.8))
		if lod == 0:
			g.box("rope", Vector3(0.04, 3.0, 0.04), Vector3(bay_x, h - 1.2, 1.5), Basis.IDENTITY, 0x0f)
			g.box("iron", Vector3(0.25, 0.3, 0.2), Vector3(bay_x, h - 2.8, 1.5))
	# Rows of small iron-barred windows either side of the bay.
	var per_side := maxi(1, int((w * 0.5 - 2.0) / 2.4))
	for fl in upper + 1:
		var y := 1.0 if fl == 0 else gh + (fl - 1) * fh + 0.7
		var wh := 1.6 if fl == 0 else 1.5
		for side: float in [-1.0, 1.0]:
			for k in per_side:
				var cx := bay_x + side * (2.2 + (k + 0.5) * (w * 0.5 - 2.2) / per_side)
				var pane := "glass_%d" % (rng.randi() % 3)
				if lod == 2:
					g.quad(pane, Vector3(cx - 0.5, y, 0.015), Vector3(cx + 0.5, y, 0.015), Vector3(cx + 0.5, y + wh, 0.015), Vector3(cx - 0.5, y + wh, 0.015), Vector3(0, 0, 1))
					continue
				g.box(pane, Vector3(1.0, wh, 0.02), Vector3(cx, y + wh * 0.5, -0.02), Basis.IDENTITY, 0x01)
				g.solid_box("stone_trim", Vector3(1.3, 0.12, 0.14), Vector3(cx, y - 0.06, 0.07))
				g.box(wall, Vector3(1.36, 0.36, 0.1), Vector3(cx, y + wh + 0.12, 0.05)) # segmental head
				if lod == 0:
					for bx: float in [-0.25, 0.0, 0.25]:
						g.box("iron", Vector3(0.025, wh, 0.025), Vector3(cx + bx, y + wh * 0.5, 0.0), Basis.IDENTITY, 0x0d)
					g.box("iron", Vector3(1.0, 0.03, 0.03), Vector3(cx, y + wh * 0.5, 0.0), Basis.IDENTITY, 0x31)
	if lod == 0:
		var names := ["HAY'S", "BUTLER'S", "CHAMBERS", "ST SAVIOUR'S", "COTTON'S", "MORGAN'S", "GUN", "ANCHOR", "CHERRY GARDEN"]
		var label := "%s WHARF" % names[rng.randi() % names.size()]
		(out["labels"] as Array).append([label, g.frame * Transform3D(Basis.IDENTITY, Vector3(w * 0.5, h - 0.8, 0.03)), minf(w - 2.0, 14.0)])
		(out["doors"] as Array).append([g.frame * Vector3(bay_x, 0.0, 1.0), "work"])


## A plain back building that fills a gap between the old streets (only its roof shows).
static func _infill(g: CityGeo, f: Rect2, lod: int, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(7.5, 10.0)
	g.frame = Transform3D.IDENTITY
	var c := f.get_center()
	g.solid_box("brick_yellow", Vector3(f.size.x, h, f.size.y), Vector3(c.x, h * 0.5, c.y))
	g.occluder_box(Vector3(f.size.x - 0.2, h - 0.2, f.size.y - 0.2), Vector3(c.x, h * 0.5, c.y))
	g.box("lead", Vector3(f.size.x + 0.2, 0.2, f.size.y + 0.2), Vector3(c.x, h + 0.1, c.y))
	if lod <= 1:
		g.solid_box("brick_red", Vector3(0.8, 2.0, 1.4), Vector3(c.x, h + 1.0, c.y))


## Walls between the back yards (brick, 1.9 m: for climbing and hiding behind).
static func _yard_walls(g: CityGeo, _b: Dictionary, f: Rect2, rng: RandomNumberGenerator) -> void:
	g.frame = Transform3D.IDENTITY
	var c := f.get_center()
	if f.size.x < 30.0 or f.size.y < 30.0:
		return
	# A spine wall down the middle of the yards and a few cross walls.
	var along_x := f.size.x > f.size.y
	var length := (f.size.x if along_x else f.size.y) - 26.0
	if length > 4.0:
		var size := Vector3(length, 1.9, 0.35) if along_x else Vector3(0.35, 1.9, length)
		g.solid_box("brick_yellow", size, Vector3(c.x, 0.15 + 0.95, c.y))
	for k in 3:
		var off := rng.randf_range(-0.35, 0.35) * (f.size.x if along_x else f.size.y)
		var span := (f.size.y if along_x else f.size.x) * 0.5 - 14.0
		if span < 2.0:
			continue
		for s: float in [-1.0, 1.0]:
			var p := Vector3(c.x + off, 0.15 + 0.95, c.y + s * span * 0.5) if along_x else Vector3(c.x + s * span * 0.5, 0.15 + 0.95, c.y + off)
			var size := Vector3(0.35, 1.9, span) if along_x else Vector3(span, 1.9, 0.35)
			g.solid_box("brick_red", size, p)


## A garden square (railed lawn with plane trees and paths) or a park.
static func _garden(g: CityGeo, _b: Dictionary, f: Rect2, lod: int, rng: RandomNumberGenerator, out: Dictionary, park: bool) -> void:
	g.frame = Transform3D.IDENTITY
	var inner := f.grow(-0.6)
	g.floor_rect("grass", inner, 0.17)
	var c := inner.get_center()
	var pw := 3.0 if park else 2.2
	g.floor_rect("gravel", Rect2(inner.position.x, c.y - pw * 0.5, inner.size.x, pw), 0.18)
	g.floor_rect("gravel", Rect2(c.x - pw * 0.5, inner.position.y, pw, inner.size.y), 0.18)
	# Railings all round (with gates at the path ends).
	if lod <= 1:
		var y := CityPlan.PAVE_TOP
		for side in 4:
			var along := side < 2
			var z := inner.position.y if side == 0 else inner.end.y
			var x := inner.end.x if side == 2 else inner.position.x
			if along:
				for span: Vector2 in [Vector2(inner.position.x, c.x - 2.0), Vector2(c.x + 2.0, inner.end.x)]:
					g.frame = Transform3D(Basis.IDENTITY, Vector3(0, y, z))
					_railing(g, span.x, span.y, 0.0, 1.3, lod)
			else:
				for span: Vector2 in [Vector2(inner.position.y, c.y - 2.0), Vector2(c.y + 2.0, inner.end.y)]:
					g.frame = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, y, 0))
					_railing(g, span.x, span.y, 0.0, 1.3, lod)
		g.frame = Transform3D.IDENTITY
	# Trees: an avenue inside the railings, and (in the park) clumps across the grass.
	var spacing := 11.0
	for side in 4:
		var a: Vector3
		var e: Vector3
		match side:
			0: a = Vector3(inner.position.x + 4, 0, inner.position.y + 4); e = Vector3(inner.end.x - 4, 0, inner.position.y + 4)
			1: a = Vector3(inner.position.x + 4, 0, inner.end.y - 4); e = Vector3(inner.end.x - 4, 0, inner.end.y - 4)
			2: a = Vector3(inner.end.x - 4, 0, inner.position.y + 4); e = Vector3(inner.end.x - 4, 0, inner.end.y - 4)
			_: a = Vector3(inner.position.x + 4, 0, inner.position.y + 4); e = Vector3(inner.position.x + 4, 0, inner.end.y - 4)
		var n := int(a.distance_to(e) / spacing)
		for k in n + 1:
			var p := a.lerp(e, float(k) / float(maxi(n, 1)))
			if absf(p.x - c.x) < 4.0 or absf(p.z - c.y) < 4.0:
				continue
			p.y = 0.17
			(out["trees"] as Array).append([p, rng.randf_range(0.8, 1.2), rng.randf() * TAU])
	if park:
		var clumps := int(inner.size.x * inner.size.y / 1800.0)
		for k in clumps:
			var p := Vector3(rng.randf_range(inner.position.x + 10, inner.end.x - 10), 0.17, rng.randf_range(inner.position.y + 10, inner.end.y - 10))
			if absf(p.x - c.x) < 5.0 or absf(p.z - c.y) < 5.0:
				continue
			(out["trees"] as Array).append([p, rng.randf_range(0.8, 1.35), rng.randf() * TAU])
		# Benches along the paths.
		for k in 6:
			var t := rng.randf_range(0.1, 0.9)
			var bp := Vector3(lerpf(inner.position.x, inner.end.x, t), 0.18, c.y + pw * 0.5 + 0.8) if k % 2 == 0 else Vector3(c.x + pw * 0.5 + 0.8, 0.18, lerpf(inner.position.y, inner.end.y, t))
			if lod <= 1:
				_bench(g, bp, 0.0 if k % 2 == 0 else PI * 0.5)
	# A statue or a drinking fountain where the paths cross.
	if lod <= 1:
		g.solid_box("stone_trim", Vector3(3.0, 0.5, 3.0), Vector3(c.x, 0.4, c.y))
		g.solid_box("stone_trim", Vector3(1.4, 2.2, 1.4), Vector3(c.x, 1.75, c.y))
		g.box("bronze", Vector3(0.7, 2.0, 0.6), Vector3(c.x, 3.85, c.y))
		g.box("bronze", Vector3(0.45, 0.45, 0.45), Vector3(c.x, 5.05, c.y))


## A park bench: cast-iron ends and wooden slats.
static func _bench(g: CityGeo, p: Vector3, yaw: float) -> void:
	g.frame = Transform3D(Basis(Vector3.UP, yaw), p)
	g.solid_box("wood_dark", Vector3(1.8, 0.06, 0.45), Vector3(0, 0.45, 0))
	g.box("wood_dark", Vector3(1.8, 0.35, 0.05), Vector3(0, 0.75, -0.24), Basis(Vector3.RIGHT, -0.15))
	for x: float in [-0.8, 0.8]:
		g.box("iron", Vector3(0.06, 0.45, 0.5), Vector3(x, 0.225, 0.0))
	g.frame = Transform3D.IDENTITY


## A parish church (Hawksmoor or Wren) in its churchyard.
static func _church(g: CityGeo, _b: Dictionary, f: Rect2, lod: int, rng: RandomNumberGenerator, out: Dictionary) -> void:
	g.frame = Transform3D.IDENTITY
	var inner := f.grow(-0.6)
	g.floor_rect("grass", inner, 0.17)
	var c := inner.get_center()
	var along_x := inner.size.x >= inner.size.y
	var nave_l := minf((inner.size.x if along_x else inner.size.y) - 16.0, 34.0)
	var nave_w := minf((inner.size.y if along_x else inner.size.x) - 16.0, 15.0)
	var yaw := 0.0 if along_x else PI * 0.5
	g.frame = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, CityPlan.PAVE_TOP, c.y))
	var wall := "stone_church"
	var nh := 11.0
	g.solid_box(wall, Vector3(nave_l, nh, nave_w), Vector3(0, nh * 0.5, 0))
	# Roof ridge along the nave (local x).
	g.frame = g.frame * Transform3D(Basis.IDENTITY, Vector3(-nave_l * 0.5, 0, nave_w * 0.5))
	g.pitched_roof(nave_l, nave_w, nh, 35.0, wall, "slate", 0.3)
	g.frame = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, CityPlan.PAVE_TOP, c.y))
	# Tall round-headed windows.
	for side: float in [-1.0, 1.0]:
		var n := int(nave_l / 5.0)
		for k in n:
			var x := -nave_l * 0.5 + (k + 0.5) * nave_l / n
			if lod == 2:
				continue
			g.box("glass_%d" % (k % 3), Vector3(1.4, 4.2, 0.1), Vector3(x, 5.0, side * (nave_w * 0.5 + 0.02)))
	# West tower with a stone spire.
	var tx := -nave_l * 0.5 - 3.5
	var th := 26.0
	g.solid_box(wall, Vector3(7.0, th, 7.0), Vector3(tx, th * 0.5, 0))
	g.box(wall, Vector3(7.8, 0.6, 7.8), Vector3(tx, th + 0.3, 0))
	g.frame = g.frame * Transform3D(Basis.IDENTITY, Vector3(tx, th + 0.6, 0))
	g.cylinder(wall, 3.3, 0.15, 18.0, Vector3(0, 9.0, 0), 8)
	g.frame = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, CityPlan.PAVE_TOP, c.y))
	(out["doors"] as Array).append([g.frame * Vector3(tx - 4.5, -CityPlan.PAVE_TOP, 0), "church"])
	g.frame = Transform3D.IDENTITY
	# Gravestones and railings.
	if lod == 0:
		for k in 30:
			var p := Vector3(rng.randf_range(inner.position.x + 2, inner.end.x - 2), 0.17, rng.randf_range(inner.position.y + 2, inner.end.y - 2))
			if absf(p.x - c.x) < nave_l * 0.5 + 9.0 and absf(p.z - c.y) < nave_w * 0.5 + 3.0:
				continue
			var hs := rng.randf_range(0.6, 1.1)
			g.box("stone_grave", Vector3(0.6, hs, 0.12), Vector3(p.x, p.y + hs * 0.5, p.z), Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)))
	for k in 5:
		var p := Vector3(rng.randf_range(inner.position.x + 3, inner.end.x - 3), 0.17, rng.randf_range(inner.position.y + 3, inner.end.y - 3))
		if absf(p.x - c.x) < nave_l * 0.5 + 9.0 and absf(p.z - c.y) < nave_w * 0.5 + 5.0:
			continue
		(out["trees"] as Array).append([p, rng.randf_range(0.85, 1.2), rng.randf() * TAU])
	if lod <= 1:
		for side in 4:
			var along := side < 2
			if along:
				var z := inner.position.y if side == 0 else inner.end.y
				g.frame = Transform3D(Basis.IDENTITY, Vector3(0, CityPlan.PAVE_TOP, z))
				_railing(g, inner.position.x, inner.end.x, 0.0, 1.3, lod)
			else:
				var x := inner.end.x if side == 2 else inner.position.x
				g.frame = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, CityPlan.PAVE_TOP, 0))
				_railing(g, inner.position.y, inner.end.y, 0.0, 1.3, lod)
		g.frame = Transform3D.IDENTITY


## The grounds round St Paul's and the Palace of Westminster (the buildings themselves are
## built once by CityLandmarks: they are seen from everywhere).
static func _landmark_grounds(g: CityGeo, _b: Dictionary, f: Rect2, _lod: int, rng: RandomNumberGenerator, out: Dictionary) -> void:
	g.frame = Transform3D.IDENTITY
	var inner := f.grow(-0.6)
	g.floor_rect("flags", inner, 0.17)
	for k in 14:
		var p := Vector3(rng.randf_range(inner.position.x + 4, inner.end.x - 4), 0.17, rng.randf_range(inner.position.y + 4, inner.end.y - 4))
		var near := false
		for lm: Vector3 in [CityPlan.ST_PAULS, CityPlan.WESTMINSTER]:
			if absf(p.x - lm.x) < 150.0 and absf(p.z - lm.z) < 60.0:
				near = true
		if not near:
			(out["trees"] as Array).append([p, rng.randf_range(0.9, 1.2), rng.randf() * TAU])


# ---------------------------------------------------------------------------
# Shadows: one position-only copy of the opaque surfaces
# ---------------------------------------------------------------------------
static func _shadow_arrays(surfaces: Dictionary) -> Array:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for key: String in surfaces:
		if key.begins_with("glass") or key in ["yard", "grass", "gravel", "flags", "cobble", "pavement", "city_lamp"]:
			continue
		var s: Array = surfaces[key]
		var base := verts.size()
		verts.append_array(s[0])
		var src: PackedInt32Array = s[3]
		var shifted := PackedInt32Array()
		shifted.resize(src.size())
		for k in src.size():
			shifted[k] = src[k] + base
		idx.append_array(shifted)
	return [verts, idx]


# ---------------------------------------------------------------------------
# Navigation: the pavements and carriageways as a grid of convex cells
# ---------------------------------------------------------------------------
## The walkable ground of the chunks round `center` (radius in chunks) as ONE navigation
## mesh: a single conforming grid, so every cell shares whole edges with its neighbours and
## the navigation map never has to stitch regions together at run time.
static func nav_area(plan: CityPlan, center: Vector2i, radius: int) -> Dictionary:
	var c0 := plan.chunk_rect(center - Vector2i(radius, radius))
	var cr := Rect2(c0.position, Vector2.ONE * CityPlan.CHUNK * (radius * 2 + 1))
	var walk: Array = []
	var seen := {}
	var blockers: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cc := center + Vector2i(dx, dz)
			walk.append_array(road_rects(plan, plan.chunk_rect(cc)))
			for i in plan.blocks_overlapping(cc):
				if seen.has(i):
					continue
				seen[i] = true
				var b: Dictionary = plan.blocks[i]
				var r: Rect2 = (b["rect"] as Rect2).intersection(cr)
				if r.size.x <= 0.0 or r.size.y <= 0.0:
					continue
				walk.append(r)
				blockers.append_array(_kerb_strips(b, cr))
				if b["kind"] != CityPlan.Kind.SLAB:
					# Keep clear of the house fronts: area railings and front steps stand
					# up to 1.3 m out on the pavement.
					var margin := 1.4 if b["kind"] in [CityPlan.Kind.TERRACE, CityPlan.Kind.FILL, CityPlan.Kind.WAREHOUSE] else 0.4
					var f := plan.lot_rect(b).grow(margin).intersection(b["rect"]).intersection(cr)
					if f.size.x > 0.0 and f.size.y > 0.0:
						blockers.append(f)
	return _grid_nav(walk, blockers)


## The lamp-post strip along a block's kerbs (0.7 m), left open for 3.5 m at each corner
## where people cross the road.
static func _kerb_strips(b: Dictionary, cr: Rect2) -> Array:
	var r: Rect2 = b["rect"]
	var pave: Array = b["pave"]
	var out := []
	var w := 0.7
	var gap := 3.5
	if b["kind"] == CityPlan.Kind.SLAB:
		# The ring: the kerb is on the side away from the core.
		var core_c := CityPlan.CORE.get_center()
		var c := r.get_center()
		if r.size.x > r.size.y:
			var z := r.position.y if c.y < core_c.y else r.end.y - w
			out.append(Rect2(r.position.x + gap, z, r.size.x - gap * 2.0, w))
		else:
			var x := r.position.x if c.x < core_c.x else r.end.x - w
			out.append(Rect2(x, r.position.y + gap, w, r.size.y - gap * 2.0))
	else:
		if float(pave[CityPlan.Side.N]) >= 1.5:
			out.append(Rect2(r.position.x + gap, r.position.y, r.size.x - gap * 2.0, w))
		if float(pave[CityPlan.Side.S]) >= 1.5:
			out.append(Rect2(r.position.x + gap, r.end.y - w, r.size.x - gap * 2.0, w))
		if float(pave[CityPlan.Side.W]) >= 1.5:
			out.append(Rect2(r.position.x, r.position.y + gap, w, r.size.y - gap * 2.0))
		if float(pave[CityPlan.Side.E]) >= 1.5:
			out.append(Rect2(r.end.x - w, r.position.y + gap, w, r.size.y - gap * 2.0))
	var clipped := []
	for s: Rect2 in out:
		if s.size.x <= 0.0 or s.size.y <= 0.0:
			continue # a block too short for a strip between its corner gaps
		var i := s.intersection(cr)
		if i.size.x > 0.0 and i.size.y > 0.0:
			clipped.append(i)
	return clipped


static func _grid_nav(walk: Array, blockers: Array) -> Dictionary:
	var xs := {}
	var zs := {}
	for r: Rect2 in walk + blockers:
		xs[snappedf(r.position.x, 0.25)] = true
		xs[snappedf(r.end.x, 0.25)] = true
		zs[snappedf(r.position.y, 0.25)] = true
		zs[snappedf(r.end.y, 0.25)] = true
	var gx: Array = xs.keys()
	var gz: Array = zs.keys()
	gx.sort()
	gz.sort()
	var nx := gx.size() - 1
	var nz := gz.size() - 1
	if nx <= 0 or nz <= 0:
		return {"verts": PackedVector3Array(), "polys": []}
	# Rasterise: 1 = walkable, 0 = not.
	var cells := PackedByteArray()
	cells.resize(nx * nz)
	for pass_i in 2:
		for r: Rect2 in (walk if pass_i == 0 else blockers):
			var i0 := gx.bsearch(snappedf(r.position.x, 0.25))
			var i1 := gx.bsearch(snappedf(r.end.x, 0.25))
			var j0 := gz.bsearch(snappedf(r.position.y, 0.25))
			var j1 := gz.bsearch(snappedf(r.end.y, 0.25))
			for j in range(j0, j1):
				for i in range(i0, i1):
					cells[j * nx + i] = 1 if pass_i == 0 else 0
	var verts := PackedVector3Array()
	var vid := {}
	var polys: Array[PackedInt32Array] = []
	var y := 0.1
	var vert := func(x: float, z: float) -> int:
		var key := Vector2(x, z)
		if not vid.has(key):
			vid[key] = verts.size()
			verts.append(Vector3(x, y, z))
		return vid[key]
	# One quad per walkable cell: every cell shares whole edges with its neighbours.
	for j in nz:
		var z0: float = gz[j]
		var z1: float = gz[j + 1]
		if z1 - z0 < 0.2:
			continue
		for i in nx:
			if cells[j * nx + i] == 0:
				continue
			var x0: float = gx[i]
			var x1: float = gx[i + 1]
			if x1 - x0 < 0.2:
				continue
			# Clockwise seen from above.
			polys.append(PackedInt32Array([vert.call(x0, z0), vert.call(x1, z0), vert.call(x1, z1), vert.call(x0, z1)]))
	return {"verts": verts, "polys": polys}
