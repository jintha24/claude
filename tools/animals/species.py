"""The animals, as anatomy: where the joints are (a side view, in metres, the animal
standing square and facing -Z, its right side to +X) and the shapes laid over them.

A quadruped's skeleton is always the same set of bones, so one rig can walk them all:
  pelvis - spine - chest - neck1 - neck2 - head (ear.L, ear.R), tail1..tail4
  front legs: shoulder, upperarm (point of shoulder), forearm (elbow), fcannon (knee),
              fpastern (fetlock), fhoof (coronet or paw)
  hind legs:  thigh (hip joint), shin (stifle), hcannon (hock), hpastern (fetlock),
              hhoof (coronet or paw)
"""
import numpy as np

from sculpt import Body, Cone, Ellipsoid

SIDES = (("L", -1.0), ("R", 1.0))
FRONT = ["shoulder", "upperarm", "forearm", "fcannon", "fpastern", "fhoof"]
HIND = ["thigh", "shin", "hcannon", "hpastern", "hhoof"]


def v3(x, yz):
    return np.array([x, yz[0], yz[1]], float)


class Animal:
    """What the builder needs: joints, shapes, eyes, hair and the coat's masks."""

    def __init__(self, name):
        self.name = name
        self.names, self.parents, self.heads = [], [], []
        self.shapes = []
        self.eyes = []  # (centre, radius)
        self.hair = []  # card strips, see Hair
        self.extra = []  # other solid parts: (name, Body, voxel, tris, material)
        self.voxel = 0.012
        self.tris = 12000
        self.ground = 0.0
        self.sigma = 0.03
        self.paint = None

    def bone(self, name, parent, pos):
        self.names.append(name)
        self.parents.append(self.names.index(parent) if parent else -1)
        self.heads.append(np.asarray(pos, float))

    def pos(self, name):
        return self.heads[self.names.index(name)]

    def body(self):
        return Body(self.shapes, ground=self.ground)


class Hair:
    """A fringe of hair cards: `roots` (N,3) along a line, each strand hanging `length`
    along `direction` (per root), `width` wide; `bones`: which bone each root follows,
    and (optionally) a bone the tips follow."""

    def __init__(self, roots, direction, length, width, bones, tip_bones=None, curl=0.0, ring=False, layers=3, mask=(0, 0, 0, 0), tip_mask=None):
        self.roots = np.asarray(roots, float)
        self.direction = np.asarray(direction, float)
        self.length = np.asarray(length, float)
        self.width = width
        self.bones = bones
        self.tip_bones = tip_bones or bones
        self.curl = curl
        self.ring = ring
        self.layers = layers
        # Colour masks (as for the coat: R points, G marks, B pale, A the coat's own colour;
        # all 0 = the species' hair colour), at the root and at the tip.
        self.mask = np.asarray(mask, float)
        self.tip_mask = np.asarray(mask if tip_mask is None else tip_mask, float)


def quadruped(a, p):
    """Lays out the standard quadruped from `p` (a dict of joint positions and radii)."""
    a.bone("pelvis", None, v3(0, p["pelvis"]))
    a.bone("spine", "pelvis", v3(0, p["spine"]))
    a.bone("chest", "spine", v3(0, p["chest"]))
    a.bone("neck1", "chest", v3(0, p["neck"][0]))
    a.bone("neck2", "neck1", v3(0, p["neck"][1]))
    a.bone("head", "neck2", v3(0, p["neck"][2]))
    for s, x in SIDES:
        a.bone("ear." + s, "head", np.asarray(p["ear"][0], float) * [x, 1, 1])
    prev = "pelvis"
    for i, t in enumerate(p["tail"]):
        a.bone("tail%d" % (i + 1), prev, v3(0, t))
        prev = "tail%d" % (i + 1)
    for s, x in SIDES:
        fx, hx = p["front_x"] * x, p["hind_x"] * x
        parent = "chest"
        for i, b in enumerate(FRONT):
            px = fx * (0.55 if b == "shoulder" else 1.0)
            a.bone(b + "." + s, parent, v3(px, p["front"][i]))
            parent = b + "." + s
        parent = "pelvis"
        for i, b in enumerate(HIND):
            a.bone(b + "." + s, parent, v3(hx, p["hind"][i]))
            parent = b + "." + s
    # The trunk.
    for c, r, owner, k, rot in p["trunk"]:
        if isinstance(c[0], (list, tuple)):
            continue
        a.shapes.append(Ellipsoid(v3(0, c), r, owner, k, rot))
    # Neck.
    n = [v3(0, q) for q in p["neck"]]
    nr = p["neck_r"]
    a.shapes.append(Cone(n[0], n[1], nr[0], nr[1], "neck1", k=p.get("neck_k", 0.1), flat=p["neck_flat"]))
    a.shapes.append(Cone(n[1], n[2], nr[1], nr[2], "neck2", k=0.05, flat=p["neck_flat"]))
    # Head.
    for sh in p["head"]:
        a.shapes.append(sh)
    # Ears.
    for s, x in SIDES:
        base, tip, r = p["ear"]
        a.shapes.append(Cone(np.asarray(base) * [x, 1, 1], np.asarray(tip) * [x, 1, 1], r, r * 0.25, "ear." + s, k=0.015, flat=0.55))
        e = p["eye"]
        a.eyes.append((np.asarray(e[0]) * [x, 1, 1], e[1]))
    # Tail (the bony part; long hair is added as cards).
    tr = p["tail_r"]
    for i in range(len(p["tail"]) - 1):
        a.shapes.append(Cone(v3(0, p["tail"][i]), v3(0, p["tail"][i + 1]), tr[i], tr[i + 1], "tail%d" % (i + 1), k=0.03 if i == 0 else 0.01))
    # Legs: a tapering cone per segment, a knuckle at every joint shared by the bones
    # either side, and the muscles on top.
    for s, x in SIDES:
        for chain, names, key in ((FRONT, FRONT, "front"), (HIND, HIND, "hind")):
            pts = [a.pos(b + "." + s) for b in names] + [v3((p["front_x"] if key == "front" else p["hind_x"]) * x, p[key + "_toe"])]
            radii = p[key + "_r"]
            start = 1 if key == "front" else 0  # the shoulder blade is a muscle, not a limb
            for i in range(start, len(names)):
                owner = names[i] + "." + s
                a.shapes.append(Cone(pts[i], pts[i + 1], radii[i], radii[i + 1], owner, k=p.get("leg_k", 0.03)))
                if i > start:
                    a.shapes.append(Ellipsoid(pts[i], [radii[i] * 1.15] * 3, {names[i - 1] + "." + s: 0.5, owner: 0.5}, k=0.02))
        for c, r, owner, k, rot in p["muscles"]:
            cc = np.array([c[0] * x, c[1], c[2]])
            a.shapes.append(Ellipsoid(cc, r, owner.replace("S", s) if owner.endswith(".S") else owner, k, (-rot[0] * x, rot[1], -rot[2] * x)))


def horse():
    a = Animal("horse")
    a.voxel = 0.013
    a.tris = 16000
    a.sigma = 0.035
    head = [
        Ellipsoid([0, 1.97, -1.34], [0.105, 0.095, 0.13], "head", 0.06),  # cranium
        Ellipsoid([0, 1.8, -1.3], [0.12, 0.15, 0.13], "head", 0.1, (0, 0.45, 0)),  # cheeks
        Cone([0, 1.95, -1.43], [0, 1.62, -1.65], 0.1, 0.068, "head", k=0.09, flat=0.9),  # face
        Ellipsoid([0, 1.95, -1.42], [0.115, 0.035, 0.05], "head", 0.03),  # brow over the eyes
        Ellipsoid([0, 1.615, -1.675], [0.064, 0.058, 0.062], "head", 0.06),  # muzzle
        Ellipsoid([0, 1.565, -1.645], [0.046, 0.03, 0.05], "head", 0.04),  # lower lip / chin
    ]
    for x in (-1, 1):
        # The jawbones, from the round of the cheek down to the chin.
        head.append(Cone([x * 0.06, 1.76, -1.34], [x * 0.03, 1.58, -1.62], 0.075, 0.04, "head", k=0.07))
    for x in (-1, 1):
        head.append(Ellipsoid([x * 0.05, 1.63, -1.705], [0.018, 0.024, 0.026], "head", 0.03))  # nostrils
    p = {
        "pelvis": (1.45, 0.5), "spine": (1.45, 0.0), "chest": (1.45, -0.45),
        "neck": [(1.45, -0.78), (1.72, -1.02), (2.0, -1.24)],
        "neck_r": (0.33, 0.22, 0.125), "neck_flat": 0.6, "neck_k": 0.18,
        "ear": ([0.06, 2.06, -1.26], [0.08, 2.22, -1.24], 0.036),
        "eye": ([0.105, 1.935, -1.42], 0.027),
        "tail": [(1.55, 0.9), (1.47, 0.97), (1.36, 1.0), (1.1, 1.05)],
        "tail_r": (0.075, 0.06, 0.045, 0.03),
        "front_x": 0.17, "hind_x": 0.16,
        # shoulder blade top, point of shoulder, elbow, knee, fetlock, coronet
        "front": [(1.5, -0.5), (1.2, -0.78), (0.97, -0.6), (0.53, -0.6), (0.22, -0.6), (0.08, -0.66)],
        "front_toe": (0.0, -0.7),
        "front_r": [0.0, 0.12, 0.085, 0.055, 0.045, 0.05, 0.062],
        # hip joint, stifle, hock, fetlock, coronet
        "hind": [(1.3, 0.55), (0.98, 0.36), (0.6, 0.72), (0.22, 0.67), (0.08, 0.62)],
        "hind_toe": (0.0, 0.58),
        "hind_r": [0.17, 0.12, 0.06, 0.045, 0.05, 0.062],
        "trunk": [
            ((1.24, 0.0), (0.3, 0.34, 0.6), "spine", 0.12, (0, 0, 0)),  # barrel
            ((1.22, -0.52), (0.26, 0.37, 0.36), "chest", 0.14, (0, 0, 0)),  # chest
            ((1.44, -0.45), (0.17, 0.2, 0.32), "chest", 0.12, (0, -0.2, 0)),  # withers
            ((1.37, 0.55), (0.25, 0.27, 0.42), "pelvis", 0.12, (0, 0.1, 0)),  # rump
            ((1.1, -0.2), (0.28, 0.22, 0.4), "spine", 0.14, (0, 0, 0)),  # girth / belly
        ],
        "muscles": [
            # shoulder over the blade, forearm, second thigh, gaskin, quarters
            ((0.15, 1.3, -0.6), (0.085, 0.25, 0.15), "shoulder.S", 0.14, (0, 0.35, 0)),
            ((0.17, 0.84, -0.61), (0.065, 0.15, 0.08), "forearm.S", 0.04, (0, 0, 0)),
            ((0.17, 1.16, 0.52), (0.13, 0.26, 0.26), {"pelvis": 0.4, "thigh.S": 0.6}, 0.1, (0, -0.2, 0)),
            ((0.16, 0.84, 0.54), (0.07, 0.17, 0.1), "shin.S", 0.06, (0, -0.4, 0)),
        ],
        "leg_k": 0.035,
        "head": head,
    }
    quadruped_sided(a, p)
    # The crest: the arch along the top of the neck.
    a.shapes.append(Ellipsoid([0, 1.83, -0.98], [0.1, 0.13, 0.34], {"neck1": 0.5, "neck2": 0.5}, 0.12, (0, 0.72, 0)))
    # Mane: locks along the crest from the poll to the withers, falling over to the
    # right; the forelock between the ears; the tail's long hair all down the dock.
    rng = np.random.default_rng(3)
    crest = np.array([a.pos("head") + [0, 0.05, 0.05], a.pos("neck2") + [0, 0.2, 0.06], a.pos("neck1") + [0, 0.3, 0.12], a.pos("chest") + [0, 0.18, -0.05]])
    roots = _along(crest, 44)
    t = np.linspace(0, 1, len(roots))
    tufts(a, roots, [[0.55, -0.8, 0.08]] * len(roots), 0.18 + 0.1 * np.sin(t * np.pi), 0.035,
          [_nearest(a, r, ["head", "neck2", "neck1", "chest"]) for r in roots], rng)
    fl = a.pos("head") + [0, 0.06, -0.04]
    tufts(a, _along(np.array([fl + [-0.035, 0, 0], fl + [0.035, 0, 0]]), 6), [[0, -0.55, -0.85]] * 6, 0.17, 0.03, ["head"] * 6, rng)
    dock = _along(np.array([a.pos("tail1") + [0, -0.02, 0.02], a.pos("tail2"), a.pos("tail3")]), 12)
    roots, dirs, bones = [], [], []
    for i, c in enumerate(dock):
        for k in range(4):
            ang = rng.uniform(0, 2 * np.pi)
            roots.append(c + np.array([np.cos(ang), 0.0, np.sin(ang)]) * 0.04)
            dirs.append([np.cos(ang) * 0.12 + rng.normal(0, 0.05), -1.0, 0.22 + np.sin(ang) * 0.1])
            bones.append("tail2" if i < 6 else "tail3")
    tufts(a, roots, dirs, rng.uniform(0.7, 0.95, len(roots)), 0.045, bones, rng, tip_bones=["tail4"] * len(roots))
    a.paint = paint_horse
    return a


def quadruped_sided(a, p):
    """quadruped(), with muscle owners given per side ("x.S" or {"x.S": share})."""
    muscles = p["muscles"]
    p = dict(p)
    p["muscles"] = []
    quadruped(a, p)
    for s, x in SIDES:
        for c, r, owner, k, rot in muscles:
            if isinstance(owner, dict):
                own = {b.replace(".S", "." + s): v for b, v in owner.items()}
            else:
                own = owner.replace(".S", "." + s)
            a.shapes.append(Ellipsoid(np.array([c[0] * x, c[1], c[2]]), r, own, k, (rot[0] * x, rot[1], rot[2] * x)))


def tufts(a, roots, dirs, lengths, width, bones, rng, tip_bones=None, mask=(0, 0, 0, 0), tip_mask=None):
    """Locks of hair: one narrow ribbon per root, hanging along its direction (a little
    of each lock's own way)."""
    lengths = np.broadcast_to(np.asarray(lengths, float), (len(roots),))
    for i, r in enumerate(roots):
        d = np.asarray(dirs[i], float) + rng.normal(0, 0.06, 3)
        d /= np.linalg.norm(d)
        across = np.cross(d, [0.0, 0.0, 1.0] if abs(d[2]) < 0.9 else [1.0, 0.0, 0.0])
        across /= np.linalg.norm(across)
        w = width * rng.uniform(0.7, 1.3)
        pair = np.array([r - across * w * 0.5, r + across * w * 0.5])
        tb = (tip_bones or bones)[i]
        m = mask[i] if isinstance(mask, list) else mask
        tm = tip_mask[i] if isinstance(tip_mask, list) else tip_mask
        a.hair.append(Hair(pair, [d, d], [lengths[i] * rng.uniform(0.85, 1.1)] * 2, w, [bones[i]] * 2, [tb] * 2, layers=1, mask=m, tip_mask=tm))


def _along(pts, n):
    """n points spaced evenly along a polyline."""
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    out = []
    for d in np.linspace(0, cum[-1], n):
        i = min(np.searchsorted(cum, d, side="right") - 1, len(seg) - 1)
        t = (d - cum[i]) / max(seg[i], 1e-9)
        out.append(pts[i] * (1 - t) + pts[i + 1] * t)
    return np.array(out)


def _nearest(a, p, bones):
    return min(bones, key=lambda b: np.linalg.norm(a.pos(b) - p))


# ---------------------------------------------------------------------------
# Coats. Each returns RGBA masks per vertex: R = the dark "points" (legs, mane, muzzle),
# G = white markings, B = the paler parts (belly, rump patch), A = occlusion (set later).
# The game's shader picks the actual colours, so one model can be bay, chestnut or grey.
def _w(weights, joints, names, bone_names):
    """How much each vertex belongs to any of `bone_names`."""
    idx = [names.index(b) for b in bone_names if b in names]
    out = np.zeros(len(weights))
    for i in idx:
        out += (weights * (joints == i)).sum(axis=1)
    return out


def paint_horse(v, n, joints, weights, names):
    lower = _w(weights, joints, names, [b + "." + s for b in ("fcannon", "fpastern", "fhoof", "hcannon", "hpastern", "hhoof") for s in "LR"])
    y = v[:, 1]
    # Dark from the knees and hocks down, fading up the cannon.
    points = np.clip(lower * 1.2, 0, 1) * np.clip((0.62 - y) / 0.2, 0, 1)
    head = _w(weights, joints, names, ["head"])
    muzzle = head * np.clip((1.66 - y) / 0.1, 0, 1)
    points = np.maximum(points, muzzle * 0.7)
    tail = _w(weights, joints, names, ["tail2", "tail3", "tail4"])
    points = np.maximum(points, tail)
    # A white blaze down the face.
    face = head * (np.abs(v[:, 0]) < 0.03) * (n[:, 2] < -0.2) * (y > 1.62) * (y < 1.98)
    marks = np.clip(face * 1.0, 0, 1)
    # Paler belly and inside the legs.
    pale = np.clip((-n[:, 1] - 0.3) * 1.5, 0, 1) * (y > 0.8) * 0.5
    return np.stack([points, marks, pale, np.ones(len(v))], axis=1)





def _scaled(p, k):
    """A copy of a layout dict `p` with every length multiplied by `k`."""
    out = {}
    for key, v in p.items():
        if key in ("neck_flat",):
            out[key] = v
        elif key in ("trunk", "muscles"):
            out[key] = [(tuple(np.asarray(c) * k), tuple(np.asarray(r) * k), o, kk * k, rot) for c, r, o, kk, rot in v]
        elif key == "head":
            out[key] = v
        elif key in ("ear", "eye"):
            out[key] = tuple(np.asarray(x) * k if not np.isscalar(x) else x * k for x in v)
        elif isinstance(v, (list, tuple)) and len(v) and isinstance(v[0], (list, tuple)):
            out[key] = [tuple(np.asarray(x) * k) for x in v]
        elif isinstance(v, (list, tuple)):
            out[key] = tuple(np.asarray(v) * k)
        else:
            out[key] = v * k
    return out


# ---------------------------------------------------------------------------
# Red deer: the hind (1.1 m at the shoulder), slender, long-legged, big-eared, with a pale
# rump; the stag bigger, thick-necked and maned, with his antlers.
def deer(stag=False):
    a = Animal("stag" if stag else "deer")
    k = 1.12 if stag else 1.0
    a.voxel = 0.009 * k
    a.tris = 12000
    a.sigma = 0.025 * k
    head = [
        Ellipsoid([0, 1.55, -0.86], [0.062, 0.06, 0.08], "head", 0.04),  # cranium
        Ellipsoid([0, 1.47, -0.88], [0.058, 0.075, 0.075], "head", 0.05, (0, 0.5, 0)),  # cheeks
        Cone([0, 1.53, -0.93], [0, 1.36, -1.1], 0.058, 0.032, "head", k=0.05, flat=0.9),  # face
        Ellipsoid([0, 1.34, -1.11], [0.034, 0.034, 0.04], "head", 0.03),  # muzzle
        Ellipsoid([0, 1.31, -1.08], [0.026, 0.02, 0.035], "head", 0.02),  # chin
    ]
    for x in (-1, 1):
        head.append(Cone([x * 0.035, 1.45, -0.88], [x * 0.018, 1.33, -1.07], 0.04, 0.02, "head", k=0.04))
    p = {
        "pelvis": (1.02, 0.35), "spine": (1.02, 0.0), "chest": (1.03, -0.32),
        "neck": [(1.06, -0.52), (1.3, -0.68), (1.55, -0.8)],
        "neck_r": (0.19 if stag else 0.16, 0.12 if stag else 0.095, 0.07), "neck_flat": 0.72, "neck_k": 0.1,
        "ear": ([0.045, 1.6, -0.83], [0.13, 1.71, -0.79], 0.05),
        "eye": ([0.058, 1.555, -0.925], 0.018),
        "tail": [(1.07, 0.6), (1.02, 0.66), (0.95, 0.69), (0.9, 0.7)],
        "tail_r": (0.045, 0.035, 0.022, 0.015),
        "front_x": 0.1, "hind_x": 0.095,
        "front": [(1.07, -0.33), (0.86, -0.5), (0.7, -0.4), (0.38, -0.4), (0.14, -0.4), (0.05, -0.43)],
        "front_toe": (0.0, -0.47),
        "front_r": [0.0, 0.075, 0.05, 0.03, 0.024, 0.028, 0.033],
        "hind": [(0.93, 0.4), (0.68, 0.24), (0.43, 0.5), (0.14, 0.46), (0.05, 0.43)],
        "hind_toe": (0.0, 0.4),
        "hind_r": [0.11, 0.075, 0.034, 0.024, 0.028, 0.033],
        "trunk": [
            ((0.9, 0.0), (0.19, 0.22, 0.42), "spine", 0.1, (0, 0, 0)),
            ((0.88, -0.32), (0.15, 0.24, 0.24), "chest", 0.1, (0, 0, 0)),
            ((1.02, -0.3), (0.1, 0.12, 0.2), "chest", 0.08, (0, -0.2, 0)),
            ((0.97, 0.36), (0.16, 0.17, 0.27), "pelvis", 0.1, (0, 0.1, 0)),
            ((0.79, -0.06), (0.16, 0.12, 0.28), "spine", 0.1, (0, 0, 0)),
        ],
        "muscles": [
            ((0.1, 0.9, -0.42), (0.055, 0.16, 0.1), "shoulder.S", 0.08, (0, 0.35, 0)),
            ((0.1, 0.6, -0.41), (0.038, 0.09, 0.05), "forearm.S", 0.03, (0, 0, 0)),
            ((0.1, 0.84, 0.37), (0.085, 0.18, 0.18), {"pelvis": 0.4, "thigh.S": 0.6}, 0.08, (0, -0.2, 0)),
            ((0.095, 0.58, 0.4), (0.042, 0.1, 0.06), "shin.S", 0.04, (0, -0.4, 0)),
        ],
        "leg_k": 0.022,
        "head": head,
    }
    if k != 1.0:
        p = _scaled(p, k)
        for sh in head:
            if isinstance(sh, Ellipsoid):
                sh.c *= k
                sh.r *= k
                sh.k *= k
            else:
                sh.a *= k
                sh.b *= k
                sh.ra *= k
                sh.rb *= k
                sh.k *= k
        p["head"] = head
    quadruped_sided(a, p)
    rng = np.random.default_rng(11 if stag else 5)
    if stag:
        # The rutting stag's shaggy neck: long dark hair down the throat and round the neck.
        roots = []
        for t in np.linspace(0.1, 0.9, 16):
            c = a.pos("neck1") * (1 - t) + a.pos("head") * t
            for ang in np.linspace(-2.2, 2.2, 5):
                roots.append(c + np.array([np.sin(ang) * 0.09, -np.cos(ang) * 0.1, 0.0]) * k)
        dirs = [[r[0] - _nearest_on_neck(a, r)[0], -1.0, 0.1] for r in roots]
        tufts(a, roots, dirs, 0.12 * k, 0.035, [_nearest(a, r, ["neck1", "neck2", "head"]) for r in roots], rng)
        a.extra.append(("Antlers", _antlers(a, k), 0.005, 5000, "horn"))
    # The short tail.
    tail = a.pos("tail2")
    tufts(a, [tail + [x, 0, 0] for x in (-0.02, 0, 0.02)], [[0, -1.0, 0.2]] * 3, 0.1 * k, 0.04, ["tail2"] * 3, rng, tip_bones=["tail4"] * 3, mask=(0, 0, 0, 1))
    a.paint = paint_deer
    return a


def _nearest_on_neck(a, r):
    return min([a.pos("neck1"), a.pos("neck2"), a.pos("head")], key=lambda q: np.linalg.norm(q - r))


def _antlers(a, k):
    """A royal's antlers: each beam sweeping up, back and out, with brow, bez and trez tines
    forward and a crown of three at the top."""
    h = a.pos("head")
    shapes = []
    for x in (-1, 1):
        def P(dx, dy, dz):
            return h + np.array([x * dx, dy, dz]) * k
        beam = [P(0.045, 0.06, -0.05), P(0.12, 0.28, 0.02), P(0.22, 0.5, 0.09), P(0.28, 0.7, 0.07), P(0.3, 0.85, 0.0)]
        radii = [0.026, 0.022, 0.018, 0.015, 0.011]
        for i in range(len(beam) - 1):
            shapes.append(Cone(beam[i], beam[i + 1], radii[i] * k, radii[i + 1] * k, "head", k=0.01))
        tines = [
            (P(0.07, 0.1, -0.05), P(0.1, 0.16, -0.28), 0.014),  # brow
            (P(0.1, 0.2, -0.01), P(0.14, 0.26, -0.22), 0.012),  # bez
            (P(0.2, 0.46, 0.08), P(0.22, 0.54, -0.14), 0.012),  # trez
            (P(0.27, 0.66, 0.07), P(0.24, 0.86, 0.1), 0.01),  # crown
            (P(0.29, 0.74, 0.05), P(0.36, 0.9, -0.05), 0.009),
            (P(0.3, 0.8, 0.02), P(0.28, 0.98, -0.02), 0.009),
        ]
        for a0, b0, r in tines:
            shapes.append(Cone(a0, b0, r * k, 0.003 * k, "head", k=0.012))
        shapes.append(Ellipsoid(P(0.045, 0.06, -0.05), [0.034 * k] * 3, "head", 0.01))  # the burr
    return Body(shapes)


def paint_deer(v, n, joints, weights, names):
    y = v[:, 1]
    top = max(y.max(), 1e-3)
    # A pale rump patch round the tail, the belly and inside the legs.
    tail = _w(weights, joints, names, ["tail1", "tail2", "tail3", "tail4"])
    pelvis = _w(weights, joints, names, ["pelvis"])
    rump = np.clip((n[:, 2] - 0.2) * 2.0, 0, 1) * np.clip(pelvis + tail, 0, 1) * (y > 0.45 * top)
    belly = np.clip((-n[:, 1] - 0.35) * 1.8, 0, 1) * (y > 0.35 * top)
    inner = np.clip(-np.sign(v[:, 0]) * n[:, 0] * 1.5, 0, 1) * (y < 0.7 * top) * (y > 0.25 * top) * 0.6
    pale = np.clip(np.maximum.reduce([rump, belly, inner]), 0, 1)
    # Dark: the nose, the hooves, a line down the back of the neck.
    head = _w(weights, joints, names, ["head"])
    nose = head * np.clip((v[:, 2] - v[:, 2].min() - 0.03 * top) * -40.0 + 1.0, 0, 1)
    hooves = _w(weights, joints, names, ["fhoof.L", "fhoof.R", "hhoof.L", "hhoof.R"])
    points = np.clip(np.maximum(nose, hooves), 0, 1)
    marks = np.zeros(len(v))
    return np.stack([points, marks, pale, np.ones(len(v))], axis=1)


# ---------------------------------------------------------------------------
# The red fox: small (38 cm at the shoulder), slim, black-stockinged, white-chested, with
# its big white-tipped brush.
def fox():
    a = Animal("fox")
    a.voxel = 0.0045
    a.tris = 9000
    a.sigma = 0.012
    head = [
        Ellipsoid([0, 0.49, -0.45], [0.05, 0.045, 0.055], "head", 0.02),
        Ellipsoid([0, 0.46, -0.44], [0.055, 0.042, 0.045], "head", 0.025),  # cheek ruff
        Cone([0, 0.48, -0.48], [0, 0.445, -0.6], 0.03, 0.011, "head", k=0.02),  # the long muzzle
        Ellipsoid([0, 0.445, -0.6], [0.011, 0.011, 0.012], "head", 0.008),  # nose
        Cone([0, 0.455, -0.47], [0, 0.435, -0.58], 0.02, 0.008, "head", k=0.015),  # lower jaw
    ]
    p = {
        "pelvis": (0.36, 0.2), "spine": (0.37, 0.0), "chest": (0.38, -0.18),
        "neck": [(0.37, -0.22), (0.44, -0.33), (0.49, -0.42)],
        "neck_r": (0.055, 0.04, 0.033), "neck_flat": 0.85, "neck_k": 0.035,
        "ear": ([0.028, 0.52, -0.44], [0.044, 0.585, -0.435], 0.022),
        "eye": ([0.028, 0.5, -0.5], 0.008),
        "tail": [(0.37, 0.3), (0.32, 0.42), (0.25, 0.54), (0.19, 0.64)],
        "tail_r": (0.025, 0.022, 0.018, 0.012),
        "front_x": 0.042, "hind_x": 0.04,
        "front": [(0.38, -0.19), (0.3, -0.25), (0.24, -0.21), (0.1, -0.21), (0.04, -0.22), (0.015, -0.235)],
        "front_toe": (0.0, -0.26),
        "front_r": [0.0, 0.026, 0.017, 0.011, 0.009, 0.011, 0.012],
        "hind": [(0.33, 0.24), (0.24, 0.16), (0.12, 0.28), (0.04, 0.26), (0.015, 0.245)],
        "hind_toe": (0.0, 0.225),
        "hind_r": [0.04, 0.024, 0.012, 0.009, 0.011, 0.012],
        "trunk": [
            ((0.32, 0.0), (0.058, 0.062, 0.16), "spine", 0.035, (0, 0, 0)),
            ((0.31, -0.16), (0.056, 0.082, 0.08), "chest", 0.035, (0, 0, 0)),
            ((0.34, 0.18), (0.058, 0.058, 0.09), "pelvis", 0.035, (0, 0.1, 0)),
        ],
        "muscles": [
            ((0.04, 0.33, -0.21), (0.022, 0.06, 0.04), "shoulder.S", 0.03, (0, 0.35, 0)),
            ((0.04, 0.3, 0.22), (0.03, 0.065, 0.065), {"pelvis": 0.4, "thigh.S": 0.6}, 0.03, (0, -0.2, 0)),
        ],
        "leg_k": 0.012,
        "head": head,
    }
    quadruped_sided(a, p)
    rng = np.random.default_rng(21)
    # The brush: long hair all along the tail, red, the last of it white.
    roots, dirs, bones, masks, tips = [], [], [], [], []
    chain = np.array([a.pos("tail1"), a.pos("tail2"), a.pos("tail3"), a.pos("tail4")])
    pts = _along(chain, 30)
    for i, c in enumerate(pts):
        t = i / (len(pts) - 1)
        for j in range(6):
            ang = rng.uniform(0, 2 * np.pi)
            out = np.array([np.cos(ang), np.sin(ang) * 0.8, 0.3])
            roots.append(c + out * 0.012)
            dirs.append(out * 1.3 + np.array([0, -0.3, 0.8]))
            bones.append(_nearest(a, c, ["tail1", "tail2", "tail3", "tail4"]))
            masks.append((0, 0, 0, 1))
            tips.append((0, 1, 0, 0) if t > 0.82 else (0, 0, 0, 1))
    tufts(a, roots, dirs, 0.05 + 0.035 * np.sin(np.linspace(0, np.pi, len(roots))), 0.018, bones, rng, mask=masks, tip_mask=tips)
    a.paint = paint_fox
    return a


def paint_fox(v, n, joints, weights, names):
    y = v[:, 1]
    lower = _w(weights, joints, names, [b + "." + s for b in ("forearm", "fcannon", "fpastern", "fhoof", "hcannon", "hpastern", "hhoof") for s in "LR"])
    # Black stockings from the elbow and hock down, black backs to the ears.
    points = np.clip(lower * 1.3, 0, 1) * np.clip((0.22 - y) / 0.06, 0, 1)
    ears = _w(weights, joints, names, ["ear.L", "ear.R"])
    points = np.maximum(points, ears * np.clip(n[:, 2] * 2.0, 0, 1))
    # White throat, chest, cheeks and belly.
    head = _w(weights, joints, names, ["head", "neck2"])
    under = np.clip((-n[:, 1] - 0.1) * 2.0, 0, 1)
    white = np.maximum(under * (y > 0.2) * (v[:, 2] < 0.1), head * np.clip(-n[:, 1] * 2.5, 0, 1))
    return np.stack([points, np.clip(white, 0, 1), np.zeros(len(v)), np.ones(len(v))], axis=1)


# ---------------------------------------------------------------------------
# The rabbit: 40 cm, all haunch and ears, bounding.
def rabbit():
    a = Animal("rabbit")
    a.voxel = 0.003
    a.tris = 5000
    a.sigma = 0.008
    head = [
        Ellipsoid([0, 0.225, -0.185], [0.034, 0.034, 0.042], "head", 0.015),
        Ellipsoid([0, 0.21, -0.19], [0.036, 0.03, 0.035], "head", 0.015),
        Ellipsoid([0, 0.205, -0.225], [0.022, 0.022, 0.024], "head", 0.012),
    ]
    p = {
        "pelvis": (0.14, 0.09), "spine": (0.15, 0.0), "chest": (0.15, -0.08),
        "neck": [(0.17, -0.12), (0.2, -0.15), (0.225, -0.165)],
        "neck_r": (0.04, 0.032, 0.028), "neck_flat": 0.9, "neck_k": 0.025,
        "ear": ([0.014, 0.25, -0.17], [0.026, 0.335, -0.125], 0.019),
        "eye": ([0.03, 0.228, -0.2], 0.0085),
        "tail": [(0.15, 0.15), (0.155, 0.17), (0.15, 0.18), (0.145, 0.185)],
        "tail_r": (0.018, 0.02, 0.017, 0.01),
        "front_x": 0.028, "hind_x": 0.035,
        "front": [(0.16, -0.08), (0.11, -0.1), (0.08, -0.09), (0.035, -0.1), (0.014, -0.105), (0.006, -0.11)],
        "front_toe": (0.0, -0.125),
        "front_r": [0.0, 0.017, 0.012, 0.008, 0.007, 0.008, 0.008],
        "hind": [(0.12, 0.1), (0.08, 0.05), (0.04, 0.14), (0.015, 0.09), (0.006, 0.04)],
        "hind_toe": (0.0, 0.0),
        "hind_r": [0.03, 0.02, 0.01, 0.009, 0.009, 0.008],
        "trunk": [
            ((0.14, 0.02), (0.065, 0.075, 0.12), "spine", 0.025, (0, 0, 0)),
            ((0.13, -0.08), (0.052, 0.06, 0.055), "chest", 0.025, (0, 0, 0)),
            ((0.12, 0.09), (0.07, 0.075, 0.075), "pelvis", 0.025, (0, 0, 0)),
        ],
        "muscles": [
            ((0.035, 0.09, 0.08), (0.03, 0.05, 0.06), {"pelvis": 0.3, "thigh.S": 0.7}, 0.02, (0, 0, 0)),
        ],
        "leg_k": 0.008,
        "head": head,
    }
    quadruped_sided(a, p)
    a.paint = paint_rabbit
    return a


def paint_rabbit(v, n, joints, weights, names):
    y = v[:, 1]
    tail = _w(weights, joints, names, ["tail1", "tail2", "tail3", "tail4"])
    under = np.clip((-n[:, 1] - 0.2) * 2.0, 0, 1)
    pale = np.clip(np.maximum(under, tail * 1.2), 0, 1)
    ears = _w(weights, joints, names, ["ear.L", "ear.R"])
    points = ears * np.clip((y - 0.31) * 60.0, 0, 1)
    return np.stack([points, np.zeros(len(v)), pale, np.ones(len(v))], axis=1)


# ---------------------------------------------------------------------------
# Dogs: a street mongrel (50 cm at the shoulder) and a mastiff guard dog (70 cm, heavy,
# broad-headed, short-muzzled).
def dog(heavy=False):
    a = Animal("mastiff" if heavy else "dog")
    k = 1.38 if heavy else 1.0
    w = 1.25 if heavy else 1.0  # breadth
    a.voxel = 0.006 * k
    a.tris = 10000
    a.sigma = 0.015 * k
    mz = 0.75 if heavy else 1.0  # muzzle length
    head = [
        Ellipsoid([0, 0.67, -0.5], [0.06 * w, 0.055 * w, 0.07], "head", 0.025),
        Ellipsoid([0, 0.64, -0.5], [0.052 * w, 0.05 * w, 0.055], "head", 0.03),
        Cone([0, 0.64, -0.55], [0, 0.61, -0.55 - 0.13 * mz], 0.04 * w, 0.026 * w, "head", k=0.025),
        Ellipsoid([0, 0.615, -0.55 - 0.135 * mz], [0.018 * w, 0.016, 0.014], "head", 0.01),  # nose
        Cone([0, 0.6, -0.54], [0, 0.59, -0.53 - 0.12 * mz], 0.028 * w, 0.02 * w, "head", k=0.02),  # jaw
    ]
    if heavy:
        head.append(Ellipsoid([0, 0.59, -0.56], [0.055, 0.04, 0.05], "head", 0.03))  # jowls
    p = {
        "pelvis": (0.5, 0.28), "spine": (0.5, 0.0), "chest": (0.5, -0.24),
        "neck": [(0.52, -0.34), (0.6, -0.42), (0.66, -0.46)],
        "neck_r": (0.1 * w, 0.075 * w, 0.058 * w), "neck_flat": 0.85, "neck_k": 0.06,
        "ear": ([0.04, 0.71, -0.48], [0.075, 0.7, -0.53], 0.03),
        "eye": ([0.036, 0.685, -0.545], 0.011),
        "tail": [(0.52, 0.3), (0.56, 0.4), (0.55, 0.5), (0.5, 0.57)],
        "tail_r": (0.025, 0.02, 0.015, 0.01),
        "front_x": 0.07 * w, "hind_x": 0.065 * w,
        "front": [(0.52, -0.24), (0.4, -0.31), (0.3, -0.25), (0.1, -0.26), (0.04, -0.27), (0.015, -0.29)],
        "front_toe": (0.0, -0.31),
        "front_r": [0.0, 0.05 * w, 0.035 * w, 0.02 * w, 0.018 * w, 0.022 * w, 0.022 * w],
        "hind": [(0.44, 0.3), (0.3, 0.22), (0.14, 0.36), (0.05, 0.33), (0.015, 0.31)],
        "hind_toe": (0.0, 0.29),
        "hind_r": [0.07 * w, 0.045 * w, 0.022 * w, 0.018 * w, 0.022 * w, 0.022 * w],
        "trunk": [
            ((0.43, 0.0), (0.1 * w, 0.11 * w, 0.22), "spine", 0.05, (0, 0, 0)),
            ((0.42, -0.21), (0.1 * w, 0.14 * w, 0.13), "chest", 0.05, (0, 0, 0)),
            ((0.5, -0.22), (0.06 * w, 0.07, 0.1), "chest", 0.04, (0, -0.2, 0)),
            ((0.46, 0.25), (0.09 * w, 0.09, 0.11), "pelvis", 0.05, (0, 0.1, 0)),
        ],
        "muscles": [
            ((0.07, 0.42, -0.26), (0.04 * w, 0.1, 0.06), "shoulder.S", 0.04, (0, 0.35, 0)),
            ((0.065, 0.36, 0.27), (0.05 * w, 0.1, 0.1), {"pelvis": 0.4, "thigh.S": 0.6}, 0.04, (0, -0.2, 0)),
        ],
        "leg_k": 0.015,
        "head": head,
    }
    if k != 1.0:
        p = _scaled(p, k)
        for sh in head:
            if isinstance(sh, Ellipsoid):
                sh.c *= k
                sh.r *= k
                sh.k *= k
            else:
                sh.a *= k
                sh.b *= k
                sh.ra *= k
                sh.rb *= k
                sh.k *= k
        p["head"] = head
    quadruped_sided(a, p)
    a.paint = paint_dog
    return a


def paint_dog(v, n, joints, weights, names):
    y = v[:, 1]
    top = max(y.max(), 1e-3)
    head = _w(weights, joints, names, ["head"])
    front = v[:, 2] - v[:, 2].min()
    muzzle = head * np.clip(1.0 - front / (0.12 * top), 0, 1)
    points = np.clip(muzzle, 0, 1)
    # White chest and paws (the "marks"), paler belly.
    paws = _w(weights, joints, names, [b + "." + s for b in ("fpastern", "fhoof", "hpastern", "hhoof") for s in "LR"])
    chest = _w(weights, joints, names, ["chest", "neck1"]) * np.clip(-n[:, 2] * 1.5, 0, 1) * np.clip(-n[:, 1] + 0.3, 0, 1)
    marks = np.clip(np.maximum(paws, chest), 0, 1)
    pale = np.clip((-n[:, 1] - 0.3) * 1.5, 0, 1) * (y > 0.25 * top)
    return np.stack([points, marks, pale, np.ones(len(v))], axis=1)


# ---------------------------------------------------------------------------
# The sheep: a round, lumpy fleece on thin legs, the face and legs bare (white or black).
def sheep():
    a = Animal("sheep")
    a.voxel = 0.008
    a.tris = 12000
    a.sigma = 0.02
    head = [
        Ellipsoid([0, 0.86, -0.64], [0.052, 0.058, 0.07], "head", 0.03),
        Cone([0, 0.84, -0.68], [0, 0.74, -0.82], 0.048, 0.03, "head", k=0.03),
        Ellipsoid([0, 0.73, -0.83], [0.03, 0.03, 0.035], "head", 0.02),
    ]
    p = {
        "pelvis": (0.72, 0.35), "spine": (0.72, 0.0), "chest": (0.72, -0.3),
        "neck": [(0.72, -0.45), (0.8, -0.55), (0.86, -0.61)],
        "neck_r": (0.12, 0.08, 0.055), "neck_flat": 0.85, "neck_k": 0.06,
        "ear": ([0.045, 0.87, -0.62], [0.13, 0.85, -0.6], 0.024),
        "eye": ([0.045, 0.855, -0.7], 0.012),
        "tail": [(0.74, 0.46), (0.66, 0.52), (0.58, 0.54), (0.54, 0.55)],
        "tail_r": (0.035, 0.03, 0.022, 0.015),
        "front_x": 0.08, "hind_x": 0.08,
        "front": [(0.7, -0.3), (0.48, -0.38), (0.38, -0.3), (0.2, -0.31), (0.07, -0.31), (0.025, -0.33)],
        "front_toe": (0.0, -0.35),
        "front_r": [0.0, 0.05, 0.034, 0.02, 0.017, 0.019, 0.021],
        "hind": [(0.62, 0.38), (0.42, 0.26), (0.24, 0.42), (0.07, 0.4), (0.025, 0.38)],
        "hind_toe": (0.0, 0.36),
        "hind_r": [0.07, 0.045, 0.021, 0.017, 0.019, 0.021],
        "trunk": [
            ((0.62, 0.0), (0.25, 0.25, 0.5), "spine", 0.12, (0, 0, 0)),
            ((0.6, -0.3), (0.21, 0.25, 0.26), "chest", 0.12, (0, 0, 0)),
            ((0.64, 0.3), (0.23, 0.24, 0.29), "pelvis", 0.12, (0, 0, 0)),
            ((0.74, -0.46), (0.14, 0.16, 0.16), {"chest": 0.5, "neck1": 0.5}, 0.1, (0, 0, 0)),
        ],
        "muscles": [],
        "leg_k": 0.02,
        "head": head,
    }
    quadruped_sided(a, p)
    # The fleece: the body shapes made lumpy.
    for sh in a.shapes:
        if isinstance(sh, Ellipsoid) and sh.r.max() > 0.12:
            sh.lumpy = 0.018
    a.paint = paint_sheep
    return a


def paint_sheep(v, n, joints, weights, names):
    # Bare face and legs: the "points" colour (black or white faced); the rest fleece.
    y = v[:, 1]
    head = _w(weights, joints, names, ["head", "ear.L", "ear.R"])
    legs = _w(weights, joints, names, [b + "." + s for b in ("forearm", "fcannon", "fpastern", "fhoof", "shin", "hcannon", "hpastern", "hhoof") for s in "LR"])
    bare = np.clip(np.maximum(head * 1.2, legs * np.clip((0.45 - y) / 0.1, 0, 1)), 0, 1)
    hooves = _w(weights, joints, names, ["fhoof.L", "fhoof.R", "hhoof.L", "hhoof.R"])
    return np.stack([bare, np.zeros(len(v)), hooves, np.ones(len(v))], axis=1)


# ---------------------------------------------------------------------------
# The cow: a Shorthorn (1.35 m, 2.2 m long), deep and heavy, with dewlap, udder, short
# horns and a long tail with its switch.
def cow():
    a = Animal("cow")
    a.voxel = 0.013
    a.tris = 16000
    a.sigma = 0.035
    head = [
        Ellipsoid([0, 1.28, -1.25], [0.14, 0.11, 0.12], "head", 0.05),
        Ellipsoid([0, 1.15, -1.28], [0.125, 0.14, 0.14], "head", 0.07, (0, 0.4, 0)),
        Cone([0, 1.24, -1.32], [0, 0.98, -1.5], 0.115, 0.095, "head", k=0.07, flat=0.95),
        Ellipsoid([0, 0.95, -1.52], [0.105, 0.085, 0.09], "head", 0.05),
    ]
    p = {
        "pelvis": (1.36, 0.62), "spine": (1.32, 0.0), "chest": (1.33, -0.55),
        "neck": [(1.22, -0.85), (1.27, -1.05), (1.3, -1.2)],
        "neck_r": (0.3, 0.22, 0.15), "neck_flat": 0.62, "neck_k": 0.15,
        "ear": ([0.12, 1.28, -1.21], [0.26, 1.25, -1.19], 0.045),
        "eye": ([0.115, 1.2, -1.33], 0.02),
        "tail": [(1.4, 0.98), (1.25, 1.03), (0.95, 1.05), (0.62, 1.06)],
        "tail_r": (0.05, 0.035, 0.025, 0.02),
        "front_x": 0.2, "hind_x": 0.19,
        "front": [(1.3, -0.55), (0.95, -0.8), (0.72, -0.62), (0.4, -0.62), (0.14, -0.62), (0.05, -0.66)],
        "front_toe": (0.0, -0.72),
        "front_r": [0.0, 0.13, 0.095, 0.058, 0.05, 0.055, 0.07],
        "hind": [(1.2, 0.64), (0.86, 0.44), (0.5, 0.74), (0.14, 0.7), (0.05, 0.66)],
        "hind_toe": (0.0, 0.62),
        "hind_r": [0.18, 0.12, 0.058, 0.05, 0.055, 0.07],
        "trunk": [
            ((1.02, 0.0), (0.38, 0.44, 0.7), "spine", 0.14, (0, 0, 0)),
            ((1.0, -0.55), (0.32, 0.42, 0.38), "chest", 0.14, (0, 0, 0)),
            ((1.3, 0.62), (0.3, 0.24, 0.42), "pelvis", 0.1, (0, 0, 0)),
            ((1.28, -0.5), (0.2, 0.2, 0.3), "chest", 0.12, (0, 0, 0)),
            ((0.82, -0.85), (0.08, 0.22, 0.13), {"chest": 0.5, "neck1": 0.5}, 0.1, (0, 0, 0)),  # dewlap
            ((0.58, 0.45), (0.13, 0.12, 0.15), "spine", 0.08, (0, 0, 0)),  # udder
        ],
        "muscles": [
            ((0.2, 0.84, 0.6), (0.12, 0.26, 0.24), {"pelvis": 0.4, "thigh.S": 0.6}, 0.1, (0, -0.2, 0)),
        ],
        "leg_k": 0.035,
        "head": head,
    }
    quadruped_sided(a, p)
    for x in (-1, 1):
        for dx, dz in ((0.05, -0.05), (0.05, 0.05)):
            a.shapes.append(Cone([x * dx, 0.5, 0.45 + dz], [x * dx, 0.4, 0.45 + dz], 0.015, 0.01, "spine", k=0.02))
    rng = np.random.default_rng(31)
    # The switch at the end of the tail.
    end = a.pos("tail4")
    tufts(a, [end + [np.cos(t) * 0.02, 0, np.sin(t) * 0.02] for t in np.linspace(0, 6.28, 10)], [[0, -1.0, 0.05]] * 10, 0.28, 0.04, ["tail4"] * 10, rng)
    # Short horns.
    horns = []
    h = a.pos("head")
    for x in (-1, 1):
        horns.append(Cone(h + [x * 0.1, 0.08, -0.03], h + [x * 0.21, 0.1, -0.1], 0.035, 0.022, "head", k=0.01))
        horns.append(Cone(h + [x * 0.21, 0.1, -0.1], h + [x * 0.25, 0.17, -0.2], 0.022, 0.006, "head", k=0.01))
    a.extra.append(("Horns", Body(horns), 0.005, 1500, "horn"))
    a.paint = paint_cow
    return a


def paint_cow(v, n, joints, weights, names):
    from sculpt import value_noise
    y = v[:, 1]
    # Shorthorn: roan and white patches (the "marks"), the udder and belly pale.
    patches = np.clip((value_noise(v, 2.2) + value_noise(v, 5.0) * 0.4) * 3.0 - 0.1, 0, 1)
    head = _w(weights, joints, names, ["head"])
    face = head * np.clip(-n[:, 2] * 1.5, 0, 1)
    marks = np.clip(np.maximum(patches, face), 0, 1)
    pale = np.clip((-n[:, 1] - 0.3) * 1.5, 0, 1) * (y > 0.4)
    hooves = _w(weights, joints, names, ["fhoof.L", "fhoof.R", "hhoof.L", "hhoof.R"])
    return np.stack([hooves, marks, pale, np.ones(len(v))], axis=1)


SPECIES = {
    "horse": horse, "deer": deer, "stag": lambda: deer(True), "fox": fox, "rabbit": rabbit,
    "dog": dog, "mastiff": lambda: dog(True), "sheep": sheep, "cow": cow,
}
