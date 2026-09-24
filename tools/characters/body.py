"""A shaped person in game space: metres, Y up, facing -Z, feet at y = 0, normalised to a
standing height of 1.78 m (the game scales each character to its own height).

Everything that is built on a person (its skin, clothes, hat, hair) is a function of a
BodyState, so the same builder run on a morphed body (heavier, older, another face) gives
the same topology with moved vertices: the difference is a glTF morph target."""
import numpy as np

from mh import BODY_VERTS, BaseMesh, Proxy, build_verts, DATA
from rig import Rig
import os

STANDARD_HEIGHT = 1.78


def tri_faces(faces):
    """Quads/triangles -> triangles, keeping (vertex, uv) corners."""
    out = []
    for f in faces:
        for k in range(1, len(f) - 1):
            out.append((f[0], f[k], f[k + 1]))
    return out


def vertex_normals(verts, faces):
    n = np.zeros_like(verts)
    for f in faces:
        idx = [c[0] for c in f]
        p = verts[idx]
        for k in range(1, len(idx) - 1):
            fn = np.cross(p[k] - p[0], p[k + 1] - p[0])
            for j in (0, k, k + 1):
                n[idx[j]] += fn
    lens = np.linalg.norm(n, axis=1, keepdims=True)
    lens[lens == 0] = 1.0
    return n / lens


def fast_vertex_normals(verts, tris_v):
    """tris_v: (T,3) vertex indices."""
    p0, p1, p2 = verts[tris_v[:, 0]], verts[tris_v[:, 1]], verts[tris_v[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    n = np.zeros_like(verts)
    for j in range(3):
        np.add.at(n, tris_v[:, j], fn)
    lens = np.linalg.norm(n, axis=1, keepdims=True)
    lens[lens == 0] = 1.0
    return n / lens


class Library:
    """Loaded once: the base mesh, the rig, the eye proxy."""

    def __init__(self):
        self.mesh = BaseMesh()
        self.rig = Rig()
        self.eyes = Proxy(os.path.join(DATA, "eyes", "high-poly.mhclo"), os.path.join(DATA, "eyes", "high-poly.obj"))
        self.joints, self.weights = self.rig.vertex_weights(len(self.mesh.verts))
        self.dominant = self.rig.dominant_bone(self.joints, self.weights)
        # All triangles of every group that's drawn, for normals.
        self.draw_groups = ["body", "helper-tights", "helper-skirt", "helper-hair", "helper-l-eye", "helper-r-eye"]
        tris = []
        for g in self.draw_groups:
            tris += [[c[0] for c in t] for t in tri_faces(self.mesh.groups[g])]
        self.normal_tris = np.array(tris)
        self.ground_cube = "joint-ground"


class BodyState:
    def __init__(self, lib: Library, params, detail=None, scale=None):
        self.lib = lib
        self._params, self._detail = params, detail
        v = build_verts(lib.mesh, params, detail)
        ground = lib.mesh.cube_center(v, lib.ground_cube)
        body_top = v[:BODY_VERTS, 1].max()
        # MakeHuman units -> metres, turned round to face -Z, feet on the ground.
        g = np.empty_like(v)
        g[:, 0] = -(v[:, 0] - ground[0])
        g[:, 1] = v[:, 1] - ground[1]
        g[:, 2] = -(v[:, 2] - ground[2])
        self.mh = v
        self._ground = ground
        self.scale = scale if scale is not None else STANDARD_HEIGHT / (body_top - ground[1])
        self.v = g * self.scale
        self.n = fast_vertex_normals(self.v, lib.normal_tris)
        heads = lib.rig.joint_positions(lib.mesh, v)
        hg = np.empty_like(heads)
        hg[:, 0] = -(heads[:, 0] - ground[0])
        hg[:, 1] = heads[:, 1] - ground[1]
        hg[:, 2] = -(heads[:, 2] - ground[2])
        self.heads = hg * self.scale
        eyes = lib.eyes.fit(v)
        e = np.empty_like(eyes)
        e[:, 0] = -(eyes[:, 0] - ground[0])
        e[:, 1] = eyes[:, 1] - ground[1]
        e[:, 2] = -(eyes[:, 2] - ground[2])
        self.eye_verts = e * self.scale

    @property
    def cloth_v(self):
        """The skin that clothes are fitted to: the same body without nipples or pectoral
        definition (MakeHuman's own targets), so they never print through a garment;
        women's busts a little rounder, as a corset shapes them."""
        if getattr(self, "_cloth_v", None) is None:
            detail = dict(self._detail or {})
            detail["breast/nipple-point-decr"] = 1.0
            detail["breast/nipple-size-decr"] = 1.0
            detail["torso/torso-muscle-pectoral-decr"] = 1.0
            if self._params.get("gender", 1.0) < 0.5:
                detail["breast/breast-point-decr"] = 0.7
            v = build_verts(self.lib.mesh, self._params, detail)
            g = self._ground
            c = np.empty_like(v)
            c[:, 0] = -(v[:, 0] - g[0])
            c[:, 1] = v[:, 1] - g[1]
            c[:, 2] = -(v[:, 2] - g[2])
            self._cloth_v = c * self.scale
            self._cloth_n = fast_vertex_normals(self._cloth_v, self.lib.normal_tris)
        return self._cloth_v

    @property
    def cloth_n(self):
        self.cloth_v
        return self._cloth_n

    def to_game(self, p):
        """A MakeHuman-space point -> game space."""
        g = self._ground
        return np.array([-(p[0] - g[0]), p[1] - g[1], -(p[2] - g[2])]) * self.scale

    def cube(self, name):
        """Centre of a MakeHuman joint cube (joint-l-eye, joint-mouth, ...) in game space."""
        return self.to_game(self.lib.mesh.cube_center(self.mh, name))

    def joint(self, name):
        return self.heads[self.lib.rig.index[name]]
