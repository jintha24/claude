class_name CityGeo
extends RefCounted
## Mesh and collision data for part of the city, built on any thread.
##
## Nothing here creates a Resource or a node: geometry goes into packed arrays, one set per
## material key, which CityStreamer turns into meshes on the main thread. Collision goes
## into triangle lists ("solid" stone and "roof" slate), for one concave shape per chunk.
##
## Shapes are given in a local frame (`frame`, e.g. one building's), in metres. UVs are in
## metres too: the textured world materials are triplanar and ignore them; the slate and
## cobbles, which use UVs, are scaled to match (CityStreamer.material).

## key -> [verts, normals, uvs, indices]
var surfaces := {}
var solid := PackedVector3Array()
var roofs := PackedVector3Array()
## Boxes that hide what's behind them (for occlusion culling): vertices and indices.
var occ_verts := PackedVector3Array()
var occ_idx := PackedInt32Array()
var frame := Transform3D.IDENTITY
## Collision is collected only when true (the nearest detail level).
var collide := false

const _CORNERS := [
	Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
	Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1),
]
# Faces as corner indices (a, b, c, d) and the outward normal.
const _FACES := [
	[[4, 5, 6, 7], Vector3(0, 0, 1)], [[1, 0, 3, 2], Vector3(0, 0, -1)],
	[[5, 1, 2, 6], Vector3(1, 0, 0)], [[0, 4, 7, 3], Vector3(-1, 0, 0)],
	[[3, 7, 6, 2], Vector3(0, 1, 0)], [[0, 1, 5, 4], Vector3(0, -1, 0)],
]


func _surf(key: String) -> Array:
	var s: Variant = surfaces.get(key)
	if s == null:
		s = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]
		surfaces[key] = s
	return s


func vertex_count() -> int:
	var n := 0
	for k: String in surfaces:
		n += (surfaces[k][0] as PackedVector3Array).size()
	return n


## A quad from four points (in `frame`), front side facing `n` (local), UVs given.
func quad_uv(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var s := _surf(key)
	var verts: PackedVector3Array = s[0]
	var base := verts.size()
	var wa := frame * a
	var wb := frame * b
	var wc := frame * c
	var wd := frame * d
	var wn := (frame.basis * n).normalized()
	verts.append(wa)
	verts.append(wb)
	verts.append(wc)
	verts.append(wd)
	var norms: PackedVector3Array = s[1]
	norms.append(wn)
	norms.append(wn)
	norms.append(wn)
	norms.append(wn)
	var uvs: PackedVector2Array = s[2]
	uvs.append(ua)
	uvs.append(ub)
	uvs.append(uc)
	uvs.append(ud)
	var idx: PackedInt32Array = s[3]
	# Godot draws clockwise triangles as front faces.
	if (wb - wa).cross(wc - wa).dot(wn) > 0.0:
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## A quad with UVs in metres along its two edges.
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var u := (b - a).length()
	var v := (d - a).length()
	quad_uv(key, a, b, c, d, n, Vector2(0, 0), Vector2(u, 0), Vector2(u, v), Vector2(0, v))


## A flat rectangle at height y (world axes of `frame`), facing up.
func floor_rect(key: String, r: Rect2, y: float, uv_world := true) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var b := Vector3(r.end.x, y, r.position.y)
	var c := Vector3(r.end.x, y, r.end.y)
	var d := Vector3(r.position.x, y, r.end.y)
	if uv_world:
		quad_uv(key, a, b, c, d, Vector3.UP, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z))
	else:
		quad(key, a, b, c, d, Vector3.UP)


## A box of `size` centred at `center` (local), turned by `basis`. `faces` is a bit mask
## of the faces to draw (+Z, -Z, +X, -X, +Y, -Y); by default all but the bottom.
func box(key: String, size: Vector3, center: Vector3, basis := Basis.IDENTITY, faces := 0x1f) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	p.resize(8)
	for i in 8:
		var c: Vector3 = _CORNERS[i]
		p[i] = center + basis * Vector3(c.x * h.x, c.y * h.y, c.z * h.z)
	for f in 6:
		if faces & (1 << f) == 0:
			continue
		var face: Array = _FACES[f]
		var ids: Array = face[0]
		var n: Vector3 = basis * (face[1] as Vector3)
		var a: Vector3 = p[ids[0]]
		var b: Vector3 = p[ids[1]]
		var c: Vector3 = p[ids[2]]
		var d: Vector3 = p[ids[3]]
		var u := (b - a).length()
		var v := (d - a).length()
		quad_uv(key, a, b, c, d, n, Vector2(0, 0), Vector2(u, 0), Vector2(u, v), Vector2(0, v))


## A solid box: drawn, and part of the collision when `collide` is on.
func solid_box(key: String, size: Vector3, center: Vector3, basis := Basis.IDENTITY, faces := 0x1f) -> void:
	box(key, size, center, basis, faces)
	col_box(size, center, basis)


func col_box(size: Vector3, center: Vector3, basis := Basis.IDENTITY, into_roofs := false) -> void:
	if not collide:
		return
	var h := size * 0.5
	var p: Array[Vector3] = []
	p.resize(8)
	for i in 8:
		var c: Vector3 = _CORNERS[i]
		p[i] = frame * (center + basis * Vector3(c.x * h.x, c.y * h.y, c.z * h.z))
	for f in 6:
		var ids: Array = _FACES[f][0]
		var t := [p[ids[0]], p[ids[1]], p[ids[2]], p[ids[0]], p[ids[2]], p[ids[3]]]
		if into_roofs:
			roofs.append_array(t)
		else:
			solid.append_array(t)


## A box for the occlusion culler (a building's mass, a little inside its walls).
func occluder_box(size: Vector3, center: Vector3) -> void:
	var h := size * 0.5
	var base := occ_verts.size()
	for i in 8:
		var c: Vector3 = _CORNERS[i]
		occ_verts.append(frame * (center + Vector3(c.x * h.x, c.y * h.y, c.z * h.z)))
	for f in 6:
		var ids: Array = _FACES[f][0]
		occ_idx.append_array([base + ids[0], base + ids[1], base + ids[2], base + ids[0], base + ids[2], base + ids[3]])


func col_tri(a: Vector3, b: Vector3, c: Vector3, into_roofs := false) -> void:
	if not collide:
		return
	if into_roofs:
		roofs.append_array([frame * a, frame * b, frame * c])
	else:
		solid.append_array([frame * a, frame * b, frame * c])


## A vertical cylinder (few sides), for pots, posts and columns.
func cylinder(key: String, r_bottom: float, r_top: float, height: float, center: Vector3, sides := 8, cap := true) -> void:
	var y0 := center.y - height * 0.5
	var y1 := center.y + height * 0.5
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var c := Vector3(center.x, 0, center.z)
		quad(key, c + d0 * r_bottom + Vector3(0, y0, 0), c + d1 * r_bottom + Vector3(0, y0, 0),
			c + d1 * r_top + Vector3(0, y1, 0), c + d0 * r_top + Vector3(0, y1, 0), n)
		if cap and r_top > 0.01:
			var t := Vector3(center.x, y1, center.z)
			tri(key, t, c + d1 * r_top + Vector3(0, y1, 0), c + d0 * r_top + Vector3(0, y1, 0), Vector3.UP)


## One triangle, front side facing `n`.
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var s := _surf(key)
	var verts: PackedVector3Array = s[0]
	var base := verts.size()
	var wa := frame * a
	var wb := frame * b
	var wc := frame * c
	var wn := (frame.basis * n).normalized()
	verts.append_array([wa, wb, wc])
	var norms: PackedVector3Array = s[1]
	norms.append_array([wn, wn, wn])
	var uvs: PackedVector2Array = s[2]
	uvs.append_array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
	var idx: PackedInt32Array = s[3]
	if (wb - wa).cross(wc - wa).dot(wn) > 0.0:
		idx.append_array([base, base + 2, base + 1])
	else:
		idx.append_array([base, base + 1, base + 2])


## Two sloping roof planes over a w x d building whose eaves are at height h, ridge along
## local X, with gable ends in `wall_key`. Adds the collision slopes to `roofs`.
func pitched_roof(w: float, d: float, h: float, pitch_deg: float, wall_key: String, slate_key := "slate", overhang := 0.3, gables := true) -> float:
	var run := d * 0.5
	var rise := run * tan(deg_to_rad(pitch_deg))
	var ridge := Vector3(0, h + rise, -run)
	var front_eave := h - overhang * tan(deg_to_rad(pitch_deg))
	var nf := Vector3(0, run, rise).normalized()
	var nb := Vector3(0, run, -rise).normalized()
	var x0 := -0.05
	var x1 := w + 0.05
	var slope := sqrt(run * run + rise * rise)
	var slope_o := slope + overhang / cos(deg_to_rad(pitch_deg))
	# Front slope (from the eave overhang to the ridge).
	quad_uv(slate_key, Vector3(x0, front_eave, overhang), Vector3(x1, front_eave, overhang),
		Vector3(x1, ridge.y, ridge.z), Vector3(x0, ridge.y, ridge.z), nf,
		Vector2(0, slope_o), Vector2(w, slope_o), Vector2(w, 0), Vector2(0, 0))
	quad_uv(slate_key, Vector3(x0, front_eave, -d - overhang), Vector3(x0, ridge.y, ridge.z),
		Vector3(x1, ridge.y, ridge.z), Vector3(x1, front_eave, -d - overhang), nb,
		Vector2(0, slope_o), Vector2(0, 0), Vector2(w, 0), Vector2(w, slope_o))
	if gables:
		for gx: float in [0.0, w]:
			var n := Vector3(-1 if gx == 0.0 else 1, 0, 0)
			tri(wall_key, Vector3(gx, h, 0.0), Vector3(gx, h, -d), Vector3(gx, ridge.y, ridge.z), n)
	col_tri(Vector3(0, h, 0), Vector3(w, h, 0), Vector3(w, ridge.y, ridge.z), true)
	col_tri(Vector3(0, h, 0), Vector3(w, ridge.y, ridge.z), Vector3(0, ridge.y, ridge.z), true)
	col_tri(Vector3(0, h, -d), Vector3(0, ridge.y, ridge.z), Vector3(w, ridge.y, ridge.z), true)
	col_tri(Vector3(0, h, -d), Vector3(w, ridge.y, ridge.z), Vector3(w, h, -d), true)
	col_tri(Vector3(0, h, 0), Vector3(0, ridge.y, ridge.z), Vector3(0, h, -d), true)
	col_tri(Vector3(w, h, 0), Vector3(w, h, -d), Vector3(w, ridge.y, ridge.z), true)
	return rise
