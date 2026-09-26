"""Sculpting animal bodies: anatomy as signed-distance shapes (ellipsoids and round cones
for muscles, bones and joints) blended smoothly, turned into a mesh (marching cubes),
thinned to a game budget, and skinned to the skeleton by which shapes each vertex belongs
to. Only numpy, scikit-image and fast-simplification."""
import numpy as np
from skimage.measure import marching_cubes
import fast_simplification


def _rot(yaw=0.0, pitch=0.0, roll=0.0):
    """Rotation matrix: roll about Z, then pitch about X, then yaw about Y."""
    cy, sy = np.cos(yaw), np.sin(yaw)
    cx, sx = np.cos(pitch), np.sin(pitch)
    cz, sz = np.cos(roll), np.sin(roll)
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return ry @ rx @ rz


class Shape:
    """One anatomical shape. `owner`: bone name, or {bone: share}. `k`: how softly it
    blends into what is already there (metres)."""

    def __init__(self, owner, k):
        self.owner = owner if isinstance(owner, dict) else {owner: 1.0}
        self.k = k

    def sdf(self, p):
        raise NotImplementedError

    def bounds(self):
        raise NotImplementedError


def value_noise(p, freq):
    """Smooth 3D value noise in [-1, 1] (a sheep's fleece)."""
    q = p * freq
    i = np.floor(q)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)

    def h(o):
        v = (i + o) @ np.array([127.1, 311.7, 74.7])
        return np.modf(np.sin(v) * 43758.5453)[0] * 2.0 - 1.0

    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * h(np.array([dx, dy, dz], float))
    return out


class Ellipsoid(Shape):
    def __init__(self, c, r, owner, k=0.05, rot=(0.0, 0.0, 0.0), lumpy=0.0):
        super().__init__(owner, k)
        self.c = np.asarray(c, float)
        self.r = np.asarray(r, float)
        self.m = _rot(*rot)
        self.lumpy = lumpy

    def sdf(self, p):
        q = (p - self.c) @ self.m  # into the ellipsoid's frame
        k0 = np.linalg.norm(q / self.r, axis=1)
        k1 = np.linalg.norm(q / (self.r * self.r), axis=1)
        d = k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
        if self.lumpy > 0.0:
            # Fleece: locks of wool, lumpy at two scales.
            d = d - self.lumpy * (0.6 * value_noise(p, 28.0) + 0.4 * value_noise(p, 61.0))
        return d

    def bounds(self):
        e = self.r.max() + self.lumpy
        return self.c - e, self.c + e


class Cone(Shape):
    """A round cone from a (radius ra) to b (radius rb); `flat` squeezes it sideways
    (x) - a neck is deeper than it is wide."""

    def __init__(self, a, b, ra, rb, owner, k=0.03, flat=1.0):
        super().__init__(owner, k)
        self.a = np.asarray(a, float)
        self.b = np.asarray(b, float)
        self.ra, self.rb = float(ra), float(rb)
        self.flat = flat

    def sdf(self, p):
        if self.flat != 1.0:
            p = p.copy()
            mid = (self.a + self.b) * 0.5
            p[:, 0] = mid[0] + (p[:, 0] - mid[0]) / self.flat
        a, b, r1, r2 = self.a, self.b, self.ra, self.rb
        ba = b - a
        l2 = ba @ ba
        rr = r1 - r2
        a2 = l2 - rr * rr
        il2 = 1.0 / l2
        pa = p - a
        y = pa @ ba
        z = y - l2
        x = pa * l2 - y[:, None] * ba
        x2 = np.einsum("ij,ij->i", x, x)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        d = np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2,
                     np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1,
                              (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1))
        return d * min(1.0, self.flat)

    def bounds(self):
        r = max(self.ra, self.rb)
        return np.minimum(self.a, self.b) - r, np.maximum(self.a, self.b) + r


def smin(a, b, k):
    if k <= 0.0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


class Body:
    """A body: shapes blended in order, optionally cut flat at the ground."""

    def __init__(self, shapes, ground=None):
        self.shapes = shapes
        self.ground = ground

    def sdf(self, p):
        d = None
        for s in self.shapes:
            ds = s.sdf(p)
            d = ds if d is None else smin(d, ds, s.k)
        if self.ground is not None:
            d = np.maximum(d, self.ground - p[:, 1])
        return d

    def bounds(self, margin):
        lo = np.min([s.bounds()[0] for s in self.shapes], axis=0) - margin
        hi = np.max([s.bounds()[1] for s in self.shapes], axis=0) + margin
        return lo, hi

    def normals(self, p, eps=1e-3):
        n = np.zeros_like(p)
        for i in range(3):
            e = np.zeros(3)
            e[i] = eps
            n[:, i] = self.sdf(p + e) - self.sdf(p - e)
        return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)

    def mesh(self, voxel, target_tris):
        lo, hi = self.bounds(voxel * 3)
        axes = [np.arange(lo[i], hi[i] + voxel, voxel) for i in range(3)]
        shape = tuple(len(a) for a in axes)
        vol = np.empty(shape, np.float32)
        # A slab of x at a time (memory).
        yy, zz = np.meshgrid(axes[1], axes[2], indexing="ij")
        for ix, x in enumerate(axes[0]):
            pts = np.stack([np.full(yy.size, x), yy.ravel(), zz.ravel()], axis=1)
            vol[ix] = self.sdf(pts).reshape(yy.shape)
        verts, faces, _, _ = marching_cubes(vol, level=0.0, spacing=(voxel, voxel, voxel))
        verts = verts + lo
        if len(faces) > target_tris:
            verts, faces = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32),
                                                        target_reduction=1.0 - target_tris / len(faces))
        verts = verts.astype(np.float64)
        # Settle the thinned vertices back on to the surface, and take the true normals.
        for _ in range(2):
            n = self.normals(verts)
            verts = verts - n * self.sdf(verts)[:, None]
        normals = self.normals(verts)
        faces = _outward(verts, faces, normals)
        return verts, faces, normals

    def occlusion(self, verts, normals, reach):
        """Ambient occlusion from the distance field: how much the surface is hemmed in
        (between the legs, under the belly, in the elbow)."""
        occ = np.zeros(len(verts))
        w = 1.0
        for i in range(1, 6):
            h = reach * i / 5.0
            d = self.sdf(verts + normals * h)
            occ += w * np.clip(h - d, 0.0, None) / h
            w *= 0.6
        return np.clip(1.0 - occ * 0.55, 0.3, 1.0)

    def skin(self, verts, bone_index, sigma):
        """Four bone weights per vertex: shared between the shapes the vertex is closest
        to, each shape's share going to its bones."""
        n = len(verts)
        ds = np.stack([s.sdf(verts) for s in self.shapes], axis=1)
        best = ds.min(axis=1, keepdims=True)
        w_shape = np.exp(-(ds - best) / sigma)
        w_shape[(ds - best) > 5.0 * sigma] = 0.0
        nb = len(bone_index)
        w_bone = np.zeros((n, nb))
        for si, s in enumerate(self.shapes):
            for bone, share in s.owner.items():
                w_bone[:, bone_index[bone]] += w_shape[:, si] * share
        order = np.argsort(-w_bone, axis=1)[:, :4]
        weights = np.take_along_axis(w_bone, order, axis=1)
        weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-9)
        return order.astype(np.int32), weights


def _outward(verts, faces, normals):
    """Winds every triangle counter-clockwise seen from outside."""
    a, b, c = verts[faces[:, 0]], verts[faces[:, 1]], verts[faces[:, 2]]
    fn = np.cross(b - a, c - a)
    vn = normals[faces].sum(axis=1)
    flip = np.einsum("ij,ij->i", fn, vn) < 0.0
    faces = faces.copy()
    faces[flip] = faces[flip][:, [0, 2, 1]]
    return faces


def sphere(center, radius, rings=10, segs=14):
    """A UV sphere (eyes)."""
    vs, ns = [], []
    for i in range(rings + 1):
        t = np.pi * i / rings
        for j in range(segs + 1):
            u = 2 * np.pi * j / segs
            n = np.array([np.sin(t) * np.cos(u), np.cos(t), np.sin(t) * np.sin(u)])
            vs.append(np.asarray(center) + n * radius)
            ns.append(n)
    idx = []
    for i in range(rings):
        for j in range(segs):
            a = i * (segs + 1) + j
            b = a + segs + 1
            idx += [[a, a + 1, b], [a + 1, b + 1, b]]
    verts, normals, faces = np.array(vs), np.array(ns), np.array(idx)
    return verts, _outward(verts, faces, normals), normals
