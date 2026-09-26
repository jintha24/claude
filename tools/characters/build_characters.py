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
from pieces import Piece  # noqa: E402
from gltf import GLB  # noqa: E402
from mh import random_face  # noqa: E402
from outfits import OUTFITS, Anatomy, Builder, outfit_pieces  # noqa: E402
import textures  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "characters", "generated")
TEX = os.path.join(ROOT, "assets", "characters", "textures")

MORPHS = ["heavy", "thin", "muscular", "old", "face_a", "face_b", "face_c"]

# The far body: every piece of an outfit merged into one mesh, drawn beyond ~25 m instead
# of the dozen separate pieces (one draw call instead of twelve, shadows likewise). Each
# vertex carries (colour channel, optional-part group) in its second UV set; the game's
# far-body shader colours the channels per person and hides the beards and hats they
# don't have. Keep in step with CharacterLook.FAR_CHANNELS / FAR_VARIANTS.
FAR_CHANNEL = {"skin": 0, "teeth": 0, "hair": 1, "beard": 1, "lash": 1,
               "coat": 2, "dress": 2, "cassock": 2, "greatcoat": 2,
               "waistcoat": 3, "shawl": 3, "trousers": 4,
               "boots": 5, "belt": 5, "gloves": 5, "hatband": 5, "stockings": 5,
               "shirt": 6, "collar": 6, "eye": 6,
               "cravat": 7, "trim": 7, "buttons": 7, "badge": 7,
               "hat": 8, "cap": 8, "helmet": 8, "bonnet": 8}
FAR_VARIANT = [("beard_full", 1), ("beard_moustache", 2), ("beard_chops", 3), ("hat_top", 4), ("hat_bowler", 5), ("hat_cap", 6), ("hat_bonnet", 7)]
FAR_SKIP = ("lashes", "teeth")
FAR_CELL = 0.025


def far_variant(name):
    for prefix, v in FAR_VARIANT:
        if name.startswith(prefix):
            return v
    return 0


def far_body(pieces, variants):
    """Merges the pieces (and their morph variants) into one far-body piece."""
    keep = [k for k, p in enumerate(pieces) if p.name not in FAR_SKIP]
    pos, nrm, jnt, wts, col, uv2, tris = [], [], [], [], [], [], []
    base = 0
    for k in keep:
        p = pieces[k]
        n = p.vertex_count
        pos.append(p.positions)
        nrm.append(p.normals)
        jnt.append(p.joints)
        wts.append(p.weights)
        col.append(p.colors)
        uv2.append(np.tile([float(FAR_CHANNEL.get(p.material, 2)), float(far_variant(p.name))], (n, 1)))
        tris.append(p.tris + base)
        base += n
    P, N, J, W, C, U2, T = np.vstack(pos), np.vstack(nrm), np.vstack(jnt), np.vstack(wts), np.vstack(col), np.vstack(uv2), np.vstack(tris)
    deltas = [np.vstack([v[k].positions - pieces[k].positions for k in keep]) for v in variants]
    # Seen from 25 m and more: merge the vertices of each piece within 2 cm cells.
    owner = np.concatenate([np.full(pieces[k].vertex_count, i) for i, k in enumerate(keep)])
    cell = np.floor(P / FAR_CELL).astype(np.int64)
    key = ((owner.astype(np.int64) * 4096 + cell[:, 0] + 2048) * 4096 + cell[:, 1] + 2048) * 4096 + cell[:, 2] + 2048
    uniq, inv, counts = np.unique(key, return_inverse=True, return_counts=True)
    m = len(uniq)

    def mean(a):
        out = np.zeros((m, a.shape[1]))
        np.add.at(out, inv, a)
        return out / counts[:, None]
    first = np.zeros(m, dtype=np.int64)
    first[inv[::-1]] = np.arange(len(inv))[::-1]
    nP, nC, nU2 = mean(P), mean(C), U2[first]
    nN = mean(N)
    nN /= np.maximum(np.linalg.norm(nN, axis=1, keepdims=True), 1e-9)
    nT = inv[T]
    nT = nT[(nT[:, 0] != nT[:, 1]) & (nT[:, 1] != nT[:, 2]) & (nT[:, 0] != nT[:, 2])]
    nT = np.unique(nT, axis=0)
    merged = Piece("far_body", "far", nP, nN, np.zeros((m, 2)), nT, J[first], W[first], nC, double_sided=True)
    merged.uv2 = nU2
    return merged, [mean(d) for d in deltas]


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
    if outfit != "harry":
        far, far_deltas = far_body(pieces, variants)
        mat = g.material("far", double_sided=True)
        # Build and age show from afar; face shapes don't.
        keep = [i for i, m in enumerate(morphs) if not m.startswith("face_")]
        g.add_mesh(far.name, far.positions, far.normals, far.uvs, far.tris, far.joints, far.weights, mat, far.colors,
                   [far_deltas[i] for i in keep], [morphs[i] for i in keep], uv2=far.uv2)
        print("  far body: %d verts, %d tris" % (far.vertex_count, len(far.tris)))
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
    lib = Library()
    if sys.argv[1:] == ["--skin"]:
        # Only the skin and eye textures (the models stay as they are).
        textures.bake_skin(BodyState(lib, OUTFITS["gentleman"][0]), TEX, "skin_male", True)
        textures.bake_skin(BodyState(lib, OUTFITS["lady"][0]), TEX, "skin_female", False)
        textures.bake_skin(BodyState(lib, OUTFITS["child"][0]), TEX, "skin_child", False, seed=9)
        textures.bake_eyes(TEX)
        print("skin done")
        return
    wanted = sys.argv[1:] or list(OUTFITS)
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
