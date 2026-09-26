"""Textures for the characters, painted in code:
  * skin: painted straight onto the body's UV layout from its 3D anatomy (mottled tone,
    flushed cheeks, nose, ears and knuckles, lips, eyelids, eyebrows, a man's stubble,
    nails), with a pore normal map. The game tints it per person (fair to dark).
  * eyes: MakeHuman's brown eye, recoloured to hazel, blue and grey.
  * cloth: tileable wool twill, tweed, linen, corduroy, leather, felt and silk, as grey
    detail maps the game tints to each garment's colour, with normal maps.
  * hair: strands (for hair, beards and moustaches), with alpha at the edges.
"""
import gzip
import json
import os

import numpy as np
from PIL import Image

from mh import DATA, BODY_VERTS
from body import tri_faces


# ---------------------------------------------------------------------------
# Noise
# ---------------------------------------------------------------------------
class Noise3:
    def __init__(self, seed, size=48):
        self.g = np.random.default_rng(seed).random((size, size, size))
        self.size = size

    def __call__(self, p):
        s = self.size
        pf = np.floor(p)
        f = p - pf
        f = f * f * (3.0 - 2.0 * f)
        i = pf.astype(np.int64) % s
        j = (i + 1) % s
        g = self.g
        x0, y0, z0 = i[:, 0], i[:, 1], i[:, 2]
        x1, y1, z1 = j[:, 0], j[:, 1], j[:, 2]
        fx, fy, fz = f[:, 0], f[:, 1], f[:, 2]
        c000, c100 = g[x0, y0, z0], g[x1, y0, z0]
        c010, c110 = g[x0, y1, z0], g[x1, y1, z0]
        c001, c101 = g[x0, y0, z1], g[x1, y0, z1]
        c011, c111 = g[x0, y1, z1], g[x1, y1, z1]
        x00 = c000 + (c100 - c000) * fx
        x10 = c010 + (c110 - c010) * fx
        x01 = c001 + (c101 - c001) * fx
        x11 = c011 + (c111 - c011) * fx
        y0_ = x00 + (x10 - x00) * fy
        y1_ = x01 + (x11 - x01) * fy
        return (y0_ + (y1_ - y0_) * fz) * 2.0 - 1.0

    def fbm(self, p, octaves=4):
        total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
        for o in range(octaves):
            total = total + self(p * freq + o * 17.3) * amp
            norm += amp
            amp *= 0.5
            freq *= 2.03
        return total / norm


def tile_noise(size, cells, seed):
    """Periodic 2D value noise (tiles seamlessly)."""
    rng = np.random.default_rng(seed)
    g = rng.random((cells, cells))
    y, x = np.mgrid[0:size, 0:size] / size * cells
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x1 = (x0 + 1) % cells
    y1 = (y0 + 1) % cells
    x0 %= cells
    y0 %= cells
    a = g[y0, x0] + (g[y0, x1] - g[y0, x0]) * fx
    b = g[y1, x0] + (g[y1, x1] - g[y1, x0]) * fx
    return (a + (b - a) * fy) * 2 - 1


def tile_fbm(size, cells, seed, octaves=4):
    out = np.zeros((size, size))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        if c > size:
            break
        out += tile_noise(size, c, seed + o) * amp
        norm += amp
        amp *= 0.5
    return out / norm


def height_to_normal(h, strength):
    """Tangent-space normal map (tiling gradients) from a height field."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    n = np.dstack([-dx * strength, dy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)


def save_rgb(arr, path, quality=None):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    if path.endswith(".jpg"):
        img.save(path, quality=quality or 92)
    else:
        img.save(path, optimize=True)


# ---------------------------------------------------------------------------
# UV-space rasteriser
# ---------------------------------------------------------------------------
def rasterize(uv_tris, attr_tris, size):
    """uv_tris: (T,3,2) in [0,1] (glTF, v down); attr_tris: (T,3,C). -> (size,size,C), mask."""
    C = attr_tris.shape[2]
    img = np.zeros((size, size, C))
    mask = np.zeros((size, size), dtype=bool)
    for t in range(len(uv_tris)):
        p = uv_tris[t] * size - 0.5
        x0 = max(int(np.floor(p[:, 0].min())), 0)
        x1 = min(int(np.ceil(p[:, 0].max())), size - 1)
        y0 = max(int(np.floor(p[:, 1].min())), 0)
        y1 = min(int(np.ceil(p[:, 1].max())), size - 1)
        if x1 < x0 or y1 < y0:
            continue
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        px, py = xs.ravel().astype(np.float64), ys.ravel().astype(np.float64)
        (ax, ay), (bx, by), (cx, cy) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        w0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        w1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
        if not inside.any():
            continue
        a = attr_tris[t]
        vals = w0[inside, None] * a[0] + w1[inside, None] * a[1] + w2[inside, None] * a[2]
        img[py[inside].astype(int), px[inside].astype(int)] = vals
        mask[py[inside].astype(int), px[inside].astype(int)] = True
    return img, mask


def dilate(img, mask, passes=6):
    img = img.copy()
    mask = mask.copy()
    for _ in range(passes):
        acc = np.zeros_like(img)
        cnt = np.zeros(mask.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            m = np.roll(mask, (dy, dx), axis=(0, 1))
            acc += np.roll(img, (dy, dx), axis=(0, 1)) * m[..., None]
            cnt += m
        fill = (~mask) & (cnt > 0)
        img[fill] = acc[fill] / cnt[fill][:, None]
        mask = mask | fill
    return img


def region_faces(name):
    d = json.load(gzip.open(os.path.join(DATA, "regions", name + ".json.gz")))
    return {int(k) for k in d.keys()}


# ---------------------------------------------------------------------------
# Skin
# ---------------------------------------------------------------------------
def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def soften(mask, size, radius):
    """A mask over the texture (flat), blurred in UV space so its edges fade."""
    from PIL import ImageFilter
    img = Image.fromarray((np.clip(mask, 0, 1).reshape(size, size) * 255).astype(np.uint8))
    img = img.filter(ImageFilter.GaussianBlur(radius))
    return (np.asarray(img).astype(np.float64) / 255.0).reshape(-1)


def blob(P, c, r):
    d2 = ((P - c) ** 2).sum(axis=1)
    return np.exp(-d2 / (r * r))


def bake_skin(state, out_dir, name, male, size=1024, seed=7):
    """Paints the skin of the body in `state` (a BodyState) into <name>.jpg."""
    lib = state.lib
    mesh = lib.mesh
    body_faces = mesh.groups["body"]
    lips, eyelids, face, scalp = (region_faces(r) for r in ("lips_solid", "eyelids_solid", "face_solid", "scalp_solid"))
    uv_list, attr_list = [], []
    for fi, f in enumerate(body_faces):
        flag = [1.0 if fi in lips else 0.0, 1.0 if fi in eyelids else 0.0, 1.0 if fi in face else 0.0, 1.0 if fi in scalp else 0.0]
        for tri in tri_faces([f]):
            uv = np.array([mesh.uvs[u] for _, u in tri])
            uv[:, 1] = 1.0 - uv[:, 1]
            P = np.array([state.v[v] for v, _ in tri])
            N = np.array([state.n[v] for v, _ in tri])
            bone = np.array([[lib.rig.index[lib.dominant[v]]] for v, _ in tri], dtype=float)
            attr = np.hstack([P, N, np.tile(flag, (3, 1)), bone])
            uv_list.append(uv)
            attr_list.append(attr)
    img, mask = rasterize(np.array(uv_list), np.array(attr_list), size)
    img = dilate(img, mask, 8)
    flat = img.reshape(-1, img.shape[2])
    P, N = flat[:, 0:3], flat[:, 3:6]
    lipsm, lidm, facem, scalpm = flat[:, 6], flat[:, 7], flat[:, 8], flat[:, 9]
    bone = np.rint(flat[:, 10]).astype(int)
    names = np.array(lib.rig.bones)[np.clip(bone, 0, len(lib.rig.bones) - 1)]
    nz = Noise3(seed)
    # Landmarks from the joint cubes and the face.
    cube = state.cube
    eye_l, eye_r, mouth, jaw = cube("joint-l-eye"), cube("joint-r-eye"), cube("joint-mouth"), cube("joint-jaw")
    head_v = state.v[:BODY_VERTS]
    front = np.argmin(head_v[:, 2] + np.where(head_v[:, 1] > eye_l[1] - 0.08, 0, 9) + np.abs(head_v[:, 0]) * 3)
    nose_tip = head_v[front]
    base = np.array([0.84, 0.66, 0.56])
    col = np.tile(base, (len(flat), 1))
    mott = nz.fbm(P * 9.0, 4)
    fine = nz.fbm(P * 60.0 + 3.1, 3)
    # Uneven tone: warmer and cooler patches, never one flat colour (that reads as wax).
    col *= (1.0 + 0.12 * mott + 0.05 * fine)[:, None]
    warm = nz.fbm(P * 5.0 + 11.0, 3)
    col = col * (1.0 + np.outer(warm, np.array([0.035, -0.01, -0.04])))
    # Blood near the surface: cheeks, nose, ears, lips, knuckles, elbows, knees.
    red = np.zeros(len(flat))
    for side in (-1, 1):
        cheek = np.array([side * 0.042, eye_l[1] - 0.035, eye_l[2] + 0.004])
        red += blob(P, cheek, 0.028) * (0.55 if not male else 0.45)
        ear = np.array([side * 0.075, eye_l[1] - 0.01, eye_l[2] + 0.085])
        red += blob(P, ear, 0.03) * 0.5
    red += blob(P, nose_tip, 0.018) * 0.55
    for bn, amount in (("hand", 0.35), ("index", 0.25), ("middle", 0.25), ("ring", 0.25), ("pinky", 0.25), ("thumb", 0.2)):
        red += np.char.startswith(names.astype(str), bn) * amount
    for jn in ("lowerarm_l", "lowerarm_r", "calf_l", "calf_r"):
        red += blob(P, state.joint(jn), 0.04) * 0.3
    red = np.clip(red, 0, 1)
    col = col * (1 - red[:, None] * 0.45) + np.array([0.80, 0.42, 0.40]) * red[:, None] * 0.45
    # Lips.
    # Lips: only a little darker and rosier than the face, with soft edges (a hard-edged
    # pink patch is what makes a mannequin's mouth).
    lip_col = np.array([0.70, 0.45, 0.43]) if not male else np.array([0.66, 0.47, 0.43])
    lip = soften(lipsm, size, 2.5) * (0.85 + 0.15 * fine) * 0.7
    col = col * (1 - lip[:, None]) + (col * 0.35 + lip_col * 0.65) * lip[:, None]
    # Eyelids a touch darker and pinker; the eye socket a little shadowed.
    lid = soften(lidm, size, 1.5)
    col = col * (1 - lid[:, None] * 0.16) + np.array([0.62, 0.44, 0.42]) * lid[:, None] * 0.16
    for e in (eye_l, eye_r):
        # Shadow in the socket and under the eye, a little violet-brown.
        sock = blob(P, e + np.array([0, -0.006, 0.0]), 0.024)
        under = blob(P, e + np.array([0, -0.017, -0.004]), 0.014)
        shade = np.clip(sock * 0.16 + under * 0.12, 0, 0.3)
        col = col * (1 - shade[:, None]) + col * np.array([0.72, 0.6, 0.62]) * shade[:, None]
    # Eyebrows: dense short strokes along each brow ridge.
    brow = np.zeros(len(flat))
    for e in (eye_l, eye_r):
        rel = P - e
        side = np.sign(e[0]) if e[0] != 0 else 1.0
        along = rel[:, 0] * side  # outward from the nose
        arch = 0.020 + 0.004 * np.sin(np.clip(along / 0.05, 0, 1) * np.pi)
        m = smoothstep(-0.020, -0.012, along) * (1 - smoothstep(0.030, 0.040, along))
        m *= 1 - smoothstep(0.0035, 0.0065, np.abs(rel[:, 1] - arch))
        m *= (rel[:, 2] < 0.02) * (N[:, 2] < 0.2)
        brow = np.maximum(brow, m)
    strokes = 0.5 + 0.5 * nz(P * np.array([900.0, 140.0, 900.0]))
    brow_col = np.array([0.22, 0.16, 0.11])
    bm = np.clip(brow * (0.55 + 0.6 * strokes), 0, 1) * facem.clip(0, 1)
    col = col * (1 - bm[:, None] * 0.85) + brow_col * bm[:, None] * 0.85
    # A man's shaved beard shadow.
    if male:
        beard = facem * smoothstep(nose_tip[1] - 0.005, nose_tip[1] - 0.02, P[:, 1])
        beard *= 1 - smoothstep(0.035, 0.07, np.abs(P[:, 0]) - np.clip(eye_l[1] - P[:, 1], 0, 1) * 0.3)
        beard *= (1 - lipsm).clip(0, 1)
        beard += smoothstep(jaw[1] + 0.01, jaw[1] - 0.03, P[:, 1]) * (P[:, 1] > state.joint("neck_01")[1]) * 0.8
        beard = soften(np.clip(beard, 0, 1), size, 4.0)
        stubble = np.clip(0.5 + 0.8 * nz(P * 900.0), 0, 1)
        beard = beard * (0.45 + 0.55 * stubble)
        col = col * (1 - beard[:, None] * 0.13) + col * np.array([0.62, 0.6, 0.62]) * beard[:, None] * 0.13
    # Nails: pale pink at the finger tips (the last joints, backs of the fingers).
    tips = np.isin(names, [f + "_03_l" for f in ("index", "middle", "ring", "pinky", "thumb")] + [f + "_03_r" for f in ("index", "middle", "ring", "pinky", "thumb")])
    col = np.where(tips[:, None], col * 0.85 + np.array([0.86, 0.72, 0.68]) * 0.15, col)
    # Palms and soles lighter.
    palm = (np.char.startswith(names.astype(str), "hand") & (N[:, 1] > 0.3)) | np.isin(names, ["ball_l", "ball_r"])
    col = np.where(palm[:, None], col * 1.06, col)
    albedo = col.reshape(size, size, 3)
    # Pores, fine capillaries and freckles: skin is never an even tone close up.
    pores = tile_noise(size, 384, seed + 31) * 0.5 + tile_noise(size, 192, seed + 32) * 0.5
    albedo = albedo * (1.0 - 0.07 * np.clip(pores, 0, 1))[..., None]
    capil = np.clip(tile_fbm(size, 48, seed + 33, 3) * 2.0 - 0.6, 0, 1)
    albedo = albedo * (1.0 - capil[..., None] * np.array([0.0, 0.06, 0.05]))
    freck = (tile_noise(size, 256, seed + 34) > 0.78) * np.clip(tile_fbm(size, 8, seed + 35, 2) + 0.2, 0, 1)
    albedo = albedo * (1.0 - freck[..., None] * np.array([0.05, 0.1, 0.12]))
    save_rgb(albedo, os.path.join(out_dir, name + ".jpg"))
    # Pores and fine lines as a normal map; oilier nose, forehead and lips in the roughness.
    height = pores * 0.7 + tile_noise(size, 96, seed + 36) * 0.3
    Image.fromarray(height_to_normal(height, 2.2)).save(os.path.join(out_dir, name + "_n.png"), optimize=True)
    tzone = (blob(P, nose_tip, 0.03) + blob(P, np.array([0.0, eye_l[1] + 0.045, eye_l[2] - 0.01]), 0.035)).clip(0, 1)
    rough = 0.66 - 0.12 * tzone - 0.2 * soften(lipsm, size, 2.0) + 0.04 * fine
    rough = rough.reshape(size, size) + 0.05 * (np.clip(pores, 0, 1) - 0.5)
    r8 = (np.clip(rough, 0.3, 0.9) * 255).astype(np.uint8)
    Image.fromarray(r8).save(os.path.join(out_dir, name + "_r.png"), optimize=True)
    return albedo


# ---------------------------------------------------------------------------
# Eyes, cloth, hair
# ---------------------------------------------------------------------------
def bake_eyes(out_dir):
    src = Image.open(os.path.join(DATA, "eyes", "brown_eye.png")).convert("RGBA").resize((512, 512), Image.LANCZOS)
    arr = np.asarray(src).astype(np.float64) / 255.0
    rgb = arr[..., :3]
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    iris = (sat > 0.18) & (mx > 0.05) & (mx < 0.95)
    lum = rgb.mean(axis=2, keepdims=True)
    variants = {"eye_brown": np.array([0.42, 0.27, 0.15]), "eye_hazel": np.array([0.55, 0.45, 0.22]), "eye_blue": np.array([0.32, 0.48, 0.66]), "eye_grey": np.array([0.47, 0.52, 0.55])}
    for name, tint in variants.items():
        out = rgb.copy()
        if tint is not None:
            recol = np.clip(lum * 1.9 * tint, 0, 1)
            out = np.where(iris[..., None], recol, rgb)
        Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(os.path.join(out_dir, name + ".png"), optimize=True)


def bake_cloth(out_dir, size=512):
    y, x = np.mgrid[0:size, 0:size] / size
    fibre = tile_fbm(size, 64, 3, 3)
    cloths = {}
    # Wool twill: fine diagonal ribs.
    tw = np.sin((x + y) * 2 * np.pi * 96) * 0.5 + 0.5
    cloths["wool"] = (0.78 + 0.07 * (tw - 0.5) + 0.05 * fibre + 0.04 * tile_fbm(size, 8, 4, 3), tw * 0.6 + fibre * 0.4, 3.0)
    # Tweed: coarse twill with coloured-looking flecks.
    tw2 = np.sin((x - y) * 2 * np.pi * 48) * 0.5 + 0.5
    fleck = (tile_noise(size, 256, 5) > 0.72).astype(float)
    cloths["tweed"] = (0.72 + 0.10 * (tw2 - 0.5) + 0.12 * fleck - 0.06 * (tile_noise(size, 256, 6) > 0.8) + 0.06 * fibre, tw2 * 0.7 + fleck * 0.3, 4.0)
    # Linen: plain weave with slubs.
    weave = (np.sin(x * 2 * np.pi * 128) * np.sin(y * 2 * np.pi * 128)) * 0.5 + 0.5
    slub = tile_fbm(size, 16, 7, 2)
    cloths["linen"] = (0.86 + 0.05 * (weave - 0.5) + 0.05 * slub + 0.03 * fibre, weave * 0.8 + slub * 0.2, 2.0)
    # Corduroy: vertical wales.
    wale = np.abs(np.sin(x * 2 * np.pi * 40))
    cloths["corduroy"] = (0.70 + 0.16 * wale + 0.04 * fibre, wale, 5.0)
    # Leather: cellular grain and scuffs.
    grain = tile_fbm(size, 64, 8, 3)
    scuff = tile_fbm(size, 6, 9, 3)
    cloths["leather"] = (0.62 + 0.08 * grain + 0.12 * scuff, grain * 0.8 + scuff * 0.2, 2.5)
    # Felt (hats): soft, fine.
    cloths["felt"] = (0.74 + 0.05 * tile_fbm(size, 128, 10, 2) + 0.03 * fibre, tile_fbm(size, 128, 10, 2), 1.2)
    # Silk (ladies' dresses): smooth with a faint moire.
    moire = np.sin((x * 3 + np.sin(y * 2 * np.pi * 4) * 0.02) * 2 * np.pi * 120) * 0.5 + 0.5
    cloths["silk"] = (0.84 + 0.03 * moire + 0.02 * fibre, moire * 0.3, 0.6)
    for name, (alb, height, strength) in cloths.items():
        save_rgb(np.dstack([alb, alb, alb]), os.path.join(out_dir, "cloth_" + name + ".jpg"))
        Image.fromarray(height_to_normal(height, strength)).save(os.path.join(out_dir, "cloth_" + name + "_n.png"), optimize=True)


def bake_hair(out_dir, size=512):
    y, x = np.mgrid[0:size, 0:size] / size
    strands = tile_noise(size, 256, 21) * 0.5 + tile_noise(size, 128, 22) * 0.3
    # Stretch along v: strands run down the texture.
    s = np.zeros((size, size))
    for k in range(6):
        s += np.roll(strands, k * 7, axis=0)
    s /= 6
    streak = np.sin(x * 2 * np.pi * 180 + tile_noise(size, 16, 23) * 6) * 0.5 + 0.5
    alb = 0.62 + 0.18 * s + 0.12 * (streak - 0.5)
    alpha = np.clip(0.55 + 0.8 * (tile_noise(size, 512, 24) * 0.5 + 0.5) - 0.2, 0, 1)
    rgba = np.dstack([alb, alb, alb, alpha])
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(out_dir, "hair.png"), optimize=True)
    Image.fromarray(height_to_normal(streak * 0.7 + s * 0.3, 3.0)).save(os.path.join(out_dir, "hair_n.png"), optimize=True)
