"""MakeHuman data: the base mesh, shape targets (the "macro" sliders and face detail) and
proxy fitting (the high-poly eyes). All the data is CC0 (MakeHuman project).

Coordinates here are MakeHuman's own: decimetres, Y up, the figure facing +Z.
"""
import gzip
import os
from functools import lru_cache

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
BODY_VERTS = 13380  # the body proper; helpers and joint cubes follow


class BaseMesh:
    def __init__(self, path=os.path.join(DATA, "base.obj")):
        verts, uvs = [], []
        self.groups = {}  # name -> list of faces; face = list of (vertex index, uv index)
        cur = "default"
        self.groups[cur] = []
        with open(path) as f:
            for line in f:
                if line.startswith("v "):
                    verts.append([float(x) for x in line.split()[1:4]])
                elif line.startswith("vt "):
                    uvs.append([float(x) for x in line.split()[1:3]])
                elif line.startswith("g "):
                    cur = line.split()[1]
                    self.groups.setdefault(cur, [])
                elif line.startswith("f "):
                    face = []
                    for p in line.split()[1:]:
                        parts = p.split("/")
                        face.append((int(parts[0]) - 1, int(parts[1]) - 1 if len(parts) > 1 and parts[1] else -1))
                    self.groups[cur].append(face)
        self.groups = {k: v for k, v in self.groups.items() if v}
        self.verts = np.array(verts, dtype=np.float64)
        self.uvs = np.array(uvs, dtype=np.float64)

    def group_vertices(self, name):
        return sorted({v for face in self.groups[name] for v, _ in face})

    def cube_center(self, verts, name):
        idx = self.group_vertices(name)
        return verts[idx].mean(axis=0)


@lru_cache(maxsize=None)
def load_target(rel):
    """A target: (vertex indices, deltas) in decimetres."""
    path = os.path.join(DATA, "targets", rel)
    if not path.endswith(".gz"):
        path += ".target.gz"
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    with gzip.open(path, "rt") as f:
        rows = [line.split() for line in f if line.strip() and not line.startswith("#")]
    if not rows:
        return np.zeros(0, dtype=np.int64), np.zeros((0, 3))
    arr = np.array(rows, dtype=np.float64)
    return arr[:, 0].astype(np.int64), arr[:, 1:4]


def _split(value, parts):
    """Linear weights of a slider value between named points, like MakeHuman's macros.
    parts: list of (position, name). Returns {name: weight}."""
    out = {}
    for (p0, n0), (p1, n1) in zip(parts, parts[1:]):
        if p0 <= value <= p1:
            t = (value - p0) / (p1 - p0) if p1 > p0 else 0.0
            if n0:
                out[n0] = out.get(n0, 0.0) + (1.0 - t)
            if n1:
                out[n1] = out.get(n1, 0.0) + t
            break
    return {k: v for k, v in out.items() if v > 1e-6}


def macro_weights(p):
    """Target weights for macro parameters, following MakeHuman's macro modifiers.
    p: dict with gender, age, muscle, weight, height, proportions (0..1) and race weights."""
    g = _split(p["gender"], [(0.0, "female"), (1.0, "male")])
    a = _split(p["age"], [(0.0, "baby"), (0.1875, "child"), (0.5, "young"), (1.0, "old")])
    m = _split(p["muscle"], [(0.0, "minmuscle"), (0.5, "averagemuscle"), (1.0, "maxmuscle")])
    w = _split(p["weight"], [(0.0, "minweight"), (0.5, "averageweight"), (1.0, "maxweight")])
    h = _split(p["height"], [(0.0, "minheight"), (0.5, ""), (1.0, "maxheight")])
    pr = _split(p["proportions"], [(0.0, "uncommonproportions"), (0.5, ""), (1.0, "idealproportions")])
    races = p.get("race", {"caucasian": 1.0})
    total = sum(races.values())
    out = {}
    for gn, gw in g.items():
        for an, aw in a.items():
            for rn, rw in races.items():
                out["macrodetails/%s-%s-%s" % (rn, gn, an)] = out.get("macrodetails/%s-%s-%s" % (rn, gn, an), 0.0) + gw * aw * rw / total
            for mn, mw in m.items():
                for wn, ww in w.items():
                    base = gw * aw * mw * ww
                    out["macrodetails/universal-%s-%s-%s-%s" % (gn, an, mn, wn)] = base
                    for hn, hw in h.items():
                        out["macrodetails/height/%s-%s-%s-%s-%s" % (gn, an, mn, wn, hn)] = base * hw
                    if an != "baby":
                        for prn, prw in pr.items():
                            out["macrodetails/proportions/%s-%s-%s-%s-%s" % (gn, an, mn, wn, prn)] = base * prw
    return {k: v for k, v in out.items() if v > 1e-6}


def apply_targets(base_verts, weights):
    v = base_verts.copy()
    for rel, wt in weights.items():
        try:
            idx, d = load_target(rel)
        except FileNotFoundError:
            continue
        if len(idx):
            v[idx] += d * wt
    return v


def build_verts(mesh, params, detail=None):
    """The base mesh shaped by macro parameters plus optional detail targets
    ({"nose/nose-scale-vert-incr": 0.4, ...})."""
    weights = macro_weights(params)
    if detail:
        weights = dict(weights)
        for k, val in detail.items():
            weights[k] = weights.get(k, 0.0) + val
    return apply_targets(mesh.verts, weights)


# Face detail targets that make one face differ from another (pairs of decr/incr).
FACE_DETAILS = [
    "nose/nose-scale-vert-%s", "nose/nose-scale-horiz-%s", "nose/nose-trans-up|down", "nose/nose-hump-%s",
    "nose/nose-width1-%s", "nose/nose-point-width-%s",
    "mouth/mouth-scale-horiz-%s", "mouth/mouth-lowerlip-height-%s", "mouth/mouth-upperlip-height-%s",
    "chin/chin-prominent-%s", "chin/chin-width-%s", "chin/chin-height-%s",
    "cheek/l-cheek-bones-%s", "head/head-fat-%s", "head/head-scale-horiz-%s", "head/head-scale-vert-%s",
    "eyes/l-eye-size-%s", "eyebrows/eyebrows-trans-up|down", "forehead/forehead-scale-vert-%s",
    "ears/l-ear-scale-%s", "neck/neck-scale-horiz-%s",
]


def _resolve(pattern, sign):
    if "|" in pattern:
        a, b = pattern.split("|")
        base = a.rsplit("-", 1)[0]
        return "%s-%s" % (base, b if sign > 0 else a.rsplit("-", 1)[1])
    return pattern % ("incr" if sign > 0 else "decr")


def random_face(rng, strength=0.6):
    """A random face: detail targets with weights in 0..strength."""
    out = {}
    for pattern in FACE_DETAILS:
        value = rng.uniform(-1.0, 1.0) * strength
        if abs(value) < 0.05:
            continue
        name = _resolve(pattern, 1 if value > 0 else -1)
        # mirror single-side (l-) targets to the right side as well
        out[name] = abs(value)
        if "/l-" in name:
            out[name.replace("/l-", "/r-")] = abs(value)
    # keep only targets that exist
    return {k: v for k, v in out.items() if os.path.exists(os.path.join(DATA, "targets", k + ".target.gz"))}


class Proxy:
    """A MakeHuman proxy (.mhclo), fitted to the base mesh: each proxy vertex is a weighted
    sum of three base vertices plus a scaled offset."""

    def __init__(self, mhclo, obj):
        self.refs, self.weights, self.offsets = [], [], []
        self.scale = {}
        reading = False
        for line in open(mhclo):
            s = line.split()
            if not s or s[0].startswith("#"):
                continue
            if s[0] in ("x_scale", "y_scale", "z_scale"):
                self.scale[s[0][0]] = (int(s[1]), int(s[2]), float(s[3]))
            elif s[0] == "verts":
                reading = True
            elif reading and len(s) == 9:
                self.refs.append([int(s[0]), int(s[1]), int(s[2])])
                self.weights.append([float(s[3]), float(s[4]), float(s[5])])
                self.offsets.append([float(s[6]), float(s[7]), float(s[8])])
            elif reading and len(s) == 1:
                self.refs.append([int(s[0])] * 3)
                self.weights.append([1.0, 0.0, 0.0])
                self.offsets.append([0.0, 0.0, 0.0])
            elif reading:
                reading = False
        self.refs = np.array(self.refs)
        self.weights = np.array(self.weights)
        self.offsets = np.array(self.offsets)
        self.mesh = BaseMesh(obj)

    def fit(self, verts):
        sc = np.ones(3)
        for i, axis in enumerate("xyz"):
            if axis in self.scale:
                a, b, ref = self.scale[axis]
                sc[i] = abs(verts[a, i] - verts[b, i]) / ref
        p = (verts[self.refs] * self.weights[:, :, None]).sum(axis=1)
        return p + self.offsets * sc
