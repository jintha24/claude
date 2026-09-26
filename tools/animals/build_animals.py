"""Builds the game's animals: assets/animals/<species>.glb, each one skinned body (sculpted
from its anatomy, tools/animals/species.py), its eyes and its hair (mane, tail, ...), on
the standard quadruped skeleton that scripts/animals/quadruped_rig.gd walks.

Usage:  python3 tools/animals/build_animals.py [species ...]
Needs numpy, scikit-image, fast-simplification and Pillow.
"""
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "characters"))

from gltf import GLB  # noqa: E402
from sculpt import sphere  # noqa: E402
from species import SPECIES  # noqa: E402

OUT = os.path.join(ROOT, "assets", "animals")


def hair_mesh(a, bone_index, body=None):
    """Hair cards: each fringe a ribbon of strands, in a few layers for body. Roots inside
    the body are pushed out on to its surface."""
    if body is not None:
        for h in a.hair:
            for _ in range(3):
                d = body.sdf(h.roots)
                h.roots = h.roots - body.normals(h.roots) * (d[:, None] + 0.004)
    vs, ns, uvs, idx, js, ws, cs = [], [], [], [], [], [], []
    rows = 5
    for h in a.hair:
        n = len(h.roots)
        tangent = np.gradient(h.roots, axis=0) if n > 1 else np.array([[1.0, 0, 0]])
        if h.ring:
            tangent = np.roll(h.roots, -1, axis=0) - np.roll(h.roots, 1, axis=0)
        tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-9)
        for layer in range(h.layers):
            base = len(vs)
            side = (layer - (h.layers - 1) * 0.5) * h.width * 0.35
            for i in range(n):
                d = h.direction[i] / np.linalg.norm(h.direction[i])
                across = np.cross(d, tangent[i])
                if np.linalg.norm(across) < 1e-6:
                    across = np.array([1.0, 0, 0])
                across /= np.linalg.norm(across)
                length = float(h.length[i] if h.length.ndim else h.length) * (1.0 - 0.12 * layer)
                for r in range(rows + 1):
                    t = r / rows
                    # Strands hang, heavier towards the tips.
                    p = h.roots[i] + d * length * t + np.array([0, -0.08 * length * t * t, 0]) + across * side * (0.4 + t)
                    vs.append(p)
                    ns.append(across if layer != 1 else -across)
                    uvs.append([i / max(n - 1, 1) * n * 0.25 + layer * 0.33, t])
                    cs.append(h.mask * (1.0 - t) + h.tip_mask * t)
                    j = np.zeros(4, int)
                    w = np.zeros(4)
                    j[0], j[1] = bone_index[h.bones[i]], bone_index[h.tip_bones[i]]
                    w[0], w[1] = 1.0 - t, t
                    if j[0] == j[1]:
                        w[0], w[1] = 1.0, 0.0
                    js.append(j)
                    ws.append(w)
            for i in range(n if h.ring else n - 1):
                for r in range(rows):
                    if i == n - 1:
                        a0 = base + i * (rows + 1) + r
                        b0 = base + r
                        idx += [[a0, b0, a0 + 1], [a0 + 1, b0, b0 + 1]]
                        continue
                    a0 = base + i * (rows + 1) + r
                    b0 = a0 + rows + 1
                    idx += [[a0, b0, a0 + 1], [a0 + 1, b0, b0 + 1]]
    if not vs:
        return None
    vs = np.array(vs)
    if body is not None:
        # Hair lies over the body, never through it.
        for _ in range(3):
            d = body.sdf(vs)
            inside = d < 0.012
            if not inside.any():
                break
            vs[inside] += body.normals(vs[inside]) * (0.012 - d[inside])[:, None]
    return vs, np.array(ns), np.array(uvs), np.array(idx), np.array(js), np.array(ws), np.array(cs)


def hair_texture(path):
    """Strands of hair (white; the shader colours it), thinning to wispy tips."""
    from PIL import Image
    rng = np.random.default_rng(7)
    w, h = 256, 512
    img = np.zeros((h, w, 4), np.float32)
    img[..., :3] = 1.0
    alpha = np.zeros((h, w), np.float32)
    for _ in range(900):
        x = rng.uniform(0, w)
        length = rng.uniform(0.55, 1.0) * h
        drift = rng.normal(0, 6)
        width = rng.uniform(0.6, 1.8)
        ys = np.arange(int(length))
        xs = x + drift * (ys / h) ** 2
        strength = rng.uniform(0.5, 1.0)
        for dx in range(-2, 3):
            xi = np.clip((xs + dx).astype(int), 0, w - 1)
            fall = np.clip(1.0 - np.abs(xs + dx - xi - 0.5) / width, 0, 1)
            tip = np.clip((length - ys) / (0.25 * length), 0, 1)
            alpha[ys, xi] = np.maximum(alpha[ys, xi], strength * fall * tip)
    img[..., 3] = alpha
    # Shade within the hair so strands read.
    shade = 0.75 + 0.25 * rng.random((1, w))
    img[..., :3] *= shade[..., None]
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)


def build(name):
    t0 = time.time()
    a = SPECIES[name]()
    body = a.body()
    verts, faces, normals = body.mesh(a.voxel, a.tris)
    bone_index = {b: i for i, b in enumerate(a.names)}
    joints, weights = body.skin(verts, bone_index, a.sigma)
    colors = a.paint(verts, normals, joints, weights, a.names)
    colors[:, 3] = body.occlusion(verts, normals, a.voxel * 12)
    glb = GLB()
    glb.add_skeleton(a.names, a.parents, np.array(a.heads))
    uv = np.zeros((len(verts), 2))
    # (uv: side-on, for the fur's direction in the shader)
    uv[:, 0] = verts[:, 2]
    uv[:, 1] = -verts[:, 1]
    glb.add_mesh("Body", verts, normals, uv, faces, joints, weights, glb.material("coat"), colors=colors)
    # Eyes: dark, wet spheres following the head.
    ev, ef, en, ej, ew = [], [], [], [], []
    for c, r in a.eyes:
        v, f, n = sphere(c, r)
        ef.append(f + sum(len(x) for x in ev))
        ev.append(v)
        en.append(n)
    if ev:
        v = np.concatenate(ev)
        j = np.zeros((len(v), 4), int)
        j[:, 0] = bone_index["head"]
        w = np.zeros((len(v), 4))
        w[:, 0] = 1.0
        glb.add_mesh("Eyes", v, np.concatenate(en), np.zeros((len(v), 2)), np.concatenate(ef), j, w, glb.material("eye"))
    hm = hair_mesh(a, bone_index, body)
    if hm:
        v, n, u, f, j, w, c = hm
        glb.add_mesh("Hair", v, n, u, f, j, w, glb.material("hair", double_sided=True), colors=c)
    for part_name, part_body, voxel, tris, material in a.extra:
        pv, pf, pn = part_body.mesh(voxel, tris)
        pj, pw = part_body.skin(pv, bone_index, a.sigma)
        glb.add_mesh(part_name, pv, pn, np.zeros((len(pv), 2)), pf, pj, pw, glb.material(material))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    glb.write(path, root_name=name)
    print("%-10s %6d tris  %5d verts  %2d bones  %.1f s" % (name, len(faces), len(verts), len(a.names), time.time() - t0))


def main():
    names = sys.argv[1:] or list(SPECIES)
    os.makedirs(OUT, exist_ok=True)
    tex = os.path.join(OUT, "hair.png")
    if not os.path.exists(tex):
        hair_texture(tex)
    for n in names:
        build(n)


if __name__ == "__main__":
    main()
