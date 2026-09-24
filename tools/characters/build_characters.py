"""Builds the game's people from CC0 MakeHuman data:
    assets/characters/generated/<outfit>.glb   one skinned model per outfit, with morphs
    assets/characters/textures/*               skin, eyes, cloth and hair textures

Each model is a real human body (MakeHuman base mesh shaped by its targets), the game-engine
skeleton with its skin weights, and a Victorian outfit built on the body. Morph targets give
every townsperson a different build and face: heavy, thin, muscular, old, face_a/b/c.

Usage:  python3 tools/characters/build_characters.py [outfit ...]
(run tools/characters/fetch_data.sh once first). Needs numpy and Pillow.
"""
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from body import Library, BodyState  # noqa: E402
from gltf import GLB  # noqa: E402
from mh import random_face  # noqa: E402
from outfits import OUTFITS, Anatomy, Builder, outfit_pieces  # noqa: E402
import textures  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "characters", "generated")
TEX = os.path.join(ROOT, "assets", "characters", "textures")

MORPHS = ["heavy", "thin", "muscular", "old", "face_a", "face_b", "face_c"]


def morph_params(base, name):
    p = dict(base)
    if name == "heavy":
        p["weight"] = min(base["weight"] + 0.38, 1.0)
    elif name == "thin":
        p["weight"] = max(base["weight"] - 0.32, 0.0)
    elif name == "muscular":
        p["muscle"] = min(base["muscle"] + 0.35, 1.0)
    elif name == "old":
        p["age"] = 0.88 if base["age"] >= 0.5 else base["age"]
    return p


def build(lib, outfit):
    base_params, male = OUTFITS[outfit]
    t0 = time.time()
    base = BodyState(lib, base_params)
    anatomy = Anatomy(base)
    builder = Builder(anatomy)
    pieces = outfit_pieces(outfit, builder, base, male)
    morphs = [] if outfit == "harry" else MORPHS
    variants = []
    for m in morphs:
        detail = None
        if m.startswith("face_"):
            detail = random_face(np.random.default_rng(hash(m) % 1000 + 17), 0.7)
        st = BodyState(lib, morph_params(base_params, m), detail, scale=base.scale)
        variants.append(outfit_pieces(outfit, builder, st, male))
    g = GLB()
    g.add_skeleton(lib.rig.bones, lib.rig.parent, base.heads)
    verts = 0
    for k, p in enumerate(pieces):
        deltas = []
        for v in variants:
            q = v[k]
            if q.positions.shape != p.positions.shape:
                raise RuntimeError("%s/%s: morph topology mismatch" % (outfit, p.name))
            deltas.append(q.positions - p.positions)
        mat = g.material(p.material, double_sided=p.double_sided)
        g.add_mesh(p.name, p.positions, p.normals, p.uvs, p.tris, p.joints, p.weights, mat, p.colors,
                   deltas if deltas else None, morphs if deltas else None)
        verts += p.vertex_count
    path = os.path.join(OUT, outfit + ".glb")
    g.write(path, root_name=outfit)
    print("%-12s %2d pieces %6d verts %5.1f MB  %.1fs" % (outfit, len(pieces), verts, os.path.getsize(path) / 1e6, time.time() - t0))
    return base


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(TEX, exist_ok=True)
    wanted = sys.argv[1:] or list(OUTFITS)
    lib = Library()
    states = {}
    for name in wanted:
        states[name] = build(lib, name)
    if not sys.argv[1:]:
        textures.bake_skin(BodyState(lib, OUTFITS["gentleman"][0]), TEX, "skin_male", True)
        textures.bake_skin(BodyState(lib, OUTFITS["lady"][0]), TEX, "skin_female", False)
        textures.bake_skin(BodyState(lib, OUTFITS["child"][0]), TEX, "skin_child", False, seed=9)
        textures.bake_eyes(TEX)
        textures.bake_cloth(TEX)
        textures.bake_hair(TEX)
        print("textures done")


if __name__ == "__main__":
    main()
