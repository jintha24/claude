"""Geometry pieces built on a BodyState: parts of the body, eyes, lashes and teeth, and
"shells" (clothes made by lifting a region of the body's surface outward, with a hem
round every open edge). Every builder is deterministic in topology, so running it on a
morphed body gives matching vertices for morph targets."""
import numpy as np

from body import tri_faces

HEAD_BONE = "head"


class Piece:
    def __init__(self, name, material, positions, normals, uvs, tris, joints, weights, colors=None, double_sided=False):
        self.name = name
        self.material = material
        self.positions = np.asarray(positions, dtype=np.float64)
        self.normals = np.asarray(normals, dtype=np.float64)
        self.uvs = np.asarray(uvs, dtype=np.float64)
        self.tris = np.asarray(tris, dtype=np.int64)
        self.joints = np.asarray(joints)
        self.weights = np.asarray(weights)
        self.colors = colors if colors is not None else np.ones((len(self.positions), 4))
        self.double_sided = double_sided

    @property
    def vertex_count(self):
        return len(self.positions)


def recompute_normals(positions, tris):
    p0, p1, p2 = positions[tris[:, 0]], positions[tris[:, 1]], positions[tris[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    n = np.zeros_like(positions)
    for j in range(3):
        np.add.at(n, tris[:, j], fn)
    lens = np.linalg.norm(n, axis=1, keepdims=True)
    lens[lens == 0] = 1.0
    return n / lens


def corner_mesh(state, faces):
    """Unique (vertex, uv) corners of `faces` -> (vertex ids, uv ids, triangles)."""
    tris = tri_faces(faces)
    key_index = {}
    vids, uids, out = [], [], []
    for t in tris:
        tri = []
        for v, u in t:
            k = (v, u)
            if k not in key_index:
                key_index[k] = len(vids)
                vids.append(v)
                uids.append(u)
            tri.append(key_index[k])
        out.append(tri)
    return np.array(vids), np.array(uids), np.array(out)


class Topology:
    """Cached corner layout for a face selection (so every morph uses the same order)."""
    cache = {}

    @classmethod
    def of(cls, key, state, faces):
        if key not in cls.cache:
            cls.cache[key] = corner_mesh(state, faces)
        return cls.cache[key]


def body_piece(state, key, faces, name, material, colors_fn=None):
    lib = state.lib
    vids, uids, tris = Topology.of(key, state, faces)
    uv = lib.mesh.uvs[uids].copy()
    uv[:, 1] = 1.0 - uv[:, 1]  # OBJ v-up -> glTF v-down
    pos = state.v[vids]
    nrm = state.n[vids]
    colors = colors_fn(state, vids) if colors_fn else None
    return Piece(name, material, pos, nrm, uv, tris[:, ::-1] if False else tris, lib.joints[vids], lib.weights[vids], colors)


def rigid_weights(state, count, bone):
    j = np.zeros((count, 4), dtype=np.uint16)
    w = np.zeros((count, 4), dtype=np.float32)
    j[:, 0] = state.lib.rig.index[bone]
    w[:, 0] = 1.0
    return j, w


def eyes_piece(state):
    """The high-poly MakeHuman eyes (both), fitted to the eye helpers, riding the head."""
    proxy = state.lib.eyes
    faces = []
    uvs = proxy.mesh.uvs
    for g in proxy.mesh.groups.values():
        for f in g:
            # Skip the cornea: a clear shell mapped to the texture's transparent corner.
            u = np.mean([uvs[c[1]] for c in f], axis=0)
            if not (u[0] > 0.85 and u[1] < 0.15):
                faces.append(f)
    vids, uids, tris = Topology.of("eyes", state, faces)
    uv = proxy.mesh.uvs[uids].copy()
    uv[:, 1] = 1.0 - uv[:, 1]
    pos = state.eye_verts[vids]
    nrm = recompute_normals(state.eye_verts, np.array([[c[0] for c in t] for t in tri_faces(faces)]))[vids]
    j, w = rigid_weights(state, len(vids), HEAD_BONE)
    return Piece("eyes", "eye", pos, nrm, uv, tris, j, w)


def helper_piece(state, groups, name, material, bone=HEAD_BONE, double_sided=True, push=0.0):
    faces = []
    for g in groups:
        faces += state.lib.mesh.groups[g]
    vids, uids, tris = Topology.of("helper:" + name, state, faces)
    uv = state.lib.mesh.uvs[np.maximum(uids, 0)].copy()
    uv[:, 1] = 1.0 - uv[:, 1]
    pos = state.v[vids] + state.n[vids] * push
    j, w = rigid_weights(state, len(vids), bone)
    return Piece(name, material, pos, state.n[vids], uv, tris, j, w, double_sided=double_sided)


def boundary_edges(tris):
    """Edges used by exactly one triangle, oriented as in that triangle."""
    count = {}
    for t in tris:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            k = (min(a, b), max(a, b))
            if k in count:
                count[k][0] += 1
            else:
                count[k] = [1, (a, b)]
    return [e for c, e in count.values() if c == 1]


def drape(state, vids, tris, pos, iterations, lam=0.5, give=0.4):
    """Smooths a garment so cloth hangs over the body instead of clinging to every curve:
    hollows fill in, jagged hem lines straighten, but nothing moves further in than it
    started (so it never sinks into the body). Works on body vertices, so UV seams stay
    closed. Bumps may sink into the cloth by `give` of its thickness."""
    if iterations <= 0:
        return pos
    u, inv = np.unique(vids, return_inverse=True)
    P0 = np.zeros((len(u), 3))
    P0[inv] = pos
    N = state.cloth_n[u]
    B = state.cloth_v[u]
    floor = np.sum((P0 - B) * N, axis=1) * (1.0 - give)
    T = inv[tris]
    e = np.vstack([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]])
    e = np.sort(e, axis=1)
    e = e[e[:, 0] != e[:, 1]]
    uniq, count = np.unique(e, axis=0, return_counts=True)
    border = uniq[count == 1]
    on_border = np.zeros(len(u), dtype=bool)
    on_border[border.ravel()] = True
    # Interior vertices average all their neighbours, border vertices only their border ones.
    ia = ~on_border[uniq[:, 0]]
    ib = ~on_border[uniq[:, 1]]
    rows = np.concatenate([uniq[ia, 0], uniq[ib, 1], border[:, 0], border[:, 1]])
    cols = np.concatenate([uniq[ia, 1], uniq[ib, 0], border[:, 1], border[:, 0]])
    cnt = np.bincount(rows, minlength=len(u)).astype(float)[:, None]
    has = cnt[:, 0] > 0
    P = P0.copy()
    for _ in range(iterations):
        acc = np.zeros_like(P)
        np.add.at(acc, rows, P[cols])
        avg = np.where(has[:, None], acc / np.maximum(cnt, 1.0), P)
        step = avg - P
        # Inside the cloth only move along the normal (keeps the weave's UVs even);
        # the border slides freely so hem lines straighten.
        step = np.where(on_border[:, None], step, np.sum(step * N, axis=1, keepdims=True) * N)
        P = P + lam * step
        below = np.minimum(np.sum((P - B) * N, axis=1) - floor, 0.0)
        P -= below[:, None] * N
    return P[inv]


def edge_rings(vids, tris):
    """For each corner vertex: how many edges away from the open border it is."""
    u, inv = np.unique(vids, return_inverse=True)
    T = inv[tris]
    e = np.sort(np.vstack([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    uniq, count = np.unique(e, axis=0, return_counts=True)
    dist = np.full(len(u), 1e9)
    dist[uniq[count == 1].ravel()] = 0.0
    for _ in range(12):
        nd = dist.copy()
        np.minimum.at(nd, uniq[:, 0], dist[uniq[:, 1]] + 1.0)
        np.minimum.at(nd, uniq[:, 1], dist[uniq[:, 0]] + 1.0)
        if np.array_equal(nd, dist):
            break
        dist = nd
    return np.minimum(dist, 12.0)[inv]


def shell_piece(state, key, faces, name, material, thickness, uv_scale=6.0, hem=0.012, colors_fn=None, weights_override=None, double_sided=True, drape_iterations=3, fade_rings=0, give=0.4):
    """A garment: the surface of `faces` lifted outward by `thickness` (metres, or a
    function (state, vertex ids) -> per-vertex metres), with a hem folded back round every
    open edge so it never looks paper-thin."""
    lib = state.lib
    vids, uids, tris = Topology.of("shell:" + key, state, faces)
    t = thickness(state, vids) if callable(thickness) else np.full(len(vids), thickness)
    pos = drape(state, vids, tris, state.cloth_v[vids] + state.cloth_n[vids] * t[:, None], drape_iterations, give=give)
    uv = lib.mesh.uvs[uids].copy()
    uv[:, 1] = 1.0 - uv[:, 1]
    uv *= uv_scale
    joints = lib.joints[vids].copy()
    weights = lib.weights[vids].copy()
    if weights_override is not None:
        joints, weights = weights_override(state, vids, joints, weights)
    colors = colors_fn(state, vids) if colors_fn else np.ones((len(vids), 4))
    if fade_rings > 0:
        # Thin out towards the edges (hairlines, beards): alpha rises ring by ring.
        colors[:, 3] *= np.clip((edge_rings(vids, tris) + 0.6) / (fade_rings + 0.6), 0.0, 1.0)
    # Hem: for every open edge, a strip turning back in towards the body.
    edges = Topology.cache.get("hem:" + key)
    if edges is None:
        edges = boundary_edges(tris)
        Topology.cache["hem:" + key] = edges
    n_base = len(pos)
    extra_pos, extra_uv, extra_j, extra_w, extra_c, extra_tris = [], [], [], [], [], []
    inner_index = {}
    for a, b in edges:
        for v in (a, b):
            if v not in inner_index:
                inner_index[v] = n_base + len(extra_pos)
                extra_pos.append(pos[v] - state.n[vids[v]] * min(hem, t[v] * 0.8))
                extra_uv.append(uv[v] + np.array([0.0, 0.02]))
                extra_j.append(joints[v])
                extra_w.append(weights[v])
                extra_c.append(colors[v] * np.array([0.7, 0.7, 0.7, 1.0]))
        ia, ib = inner_index[a], inner_index[b]
        extra_tris.append([b, a, ia])
        extra_tris.append([b, ia, ib])
    if extra_pos:
        pos = np.vstack([pos, np.array(extra_pos)])
        uv = np.vstack([uv, np.array(extra_uv)])
        joints = np.vstack([joints, np.array(extra_j)])
        weights = np.vstack([weights, np.array(extra_w)])
        colors = np.vstack([colors, np.array(extra_c)])
        tris = np.vstack([tris, np.array(extra_tris)])
    nrm = recompute_normals(pos, tris)
    piece = Piece(name, material, pos, nrm, uv, tris, joints, weights, colors, double_sided)
    # For layering (see layer_garments): which body vertex each surface vertex sits on,
    # and which surface vertex each hem vertex was folded from.
    piece.base_vids = np.asarray(vids)
    piece.hem_src = np.array(sorted(inner_index, key=inner_index.get), dtype=np.int64)
    return piece


# Dressing order, inner first.
LAYER = {"shirt": 0, "trousers": 1, "gloves": 1, "boots": 2, "waistcoat": 3, "coat": 4, "cuffs": 5, "belt": 5,
         "collar": 6, "neckerchief": 6, "cravat": 7, "shawl": 8}


def layer_garments(state, pieces, gap=0.004):
    """Stacks garments in dressing order (LAYER, inner first): every garment is lifted wherever needed
    so it sits at least `gap` outside everything under it, so no layer shows through the
    one over it (a waistcoat through a coat, a shirt sleeve through a coat sleeve)."""
    top = np.full(len(state.v), -np.inf)
    for p in sorted(pieces, key=lambda q: LAYER.get(q.name, 5)):
        vids = getattr(p, "base_vids", None)
        if vids is None or p.name.startswith(("beard_", "hair")):
            continue
        nb = len(vids)
        B = state.cloth_v[vids]
        N = state.cloth_n[vids]
        h = np.sum((p.positions[:nb] - B) * N, axis=1)
        push = np.maximum(top[vids] + gap - h, 0.0)
        if np.any(push > 0):
            p.positions[:nb] += push[:, None] * N
            if len(p.hem_src):
                p.positions[nb:nb + len(p.hem_src)] += (push[p.hem_src])[:, None] * N[p.hem_src]
            p.normals = recompute_normals(p.positions, p.tris)
        np.maximum.at(top, vids, h + push)
    for p in pieces:
        if getattr(p, "base_vids", None) is not None:
            p.normals = smooth_normals(p.normals, p.tris, 4)
    return pieces


def smooth_normals(normals, tris, iterations):
    """Averages vertex normals with their neighbours: cloth shading without the small
    creases left where the body mesh is dense (nipples, knuckles, the navel)."""
    e = np.vstack([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    e = np.vstack([e, e[:, ::-1]])
    n = normals.copy()
    for _ in range(iterations):
        acc = n.copy()
        np.add.at(acc, e[:, 0], n[e[:, 1]])
        lens = np.linalg.norm(acc, axis=1, keepdims=True)
        n = acc / np.maximum(lens, 1e-9)
    return n
