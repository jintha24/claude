"""Bakes the world's surface textures: photo-like, weathered, tileable PBR sets written to
assets/textures/<material>/ (albedo *_diff, normal *_nor_gl, *_rough, *_ao and, for
cobbles, *_disp), where MaterialLibrary picks them up in place of the plain run-time
procedural textures. Real photo-scanned sets from Poly Haven or ambientCG unzipped into
the same folders replace these.

What makes them read as real rather than plastic: every brick, sett and slab different
in colour and wear; chipped edges and pitted faces; recessed, crumbling joints; soot,
rain streaks, efflorescence and grime; and roughness that varies across the surface
instead of one value.

Usage: python3 tools/textures/bake_world.py [material ...]   (needs numpy and Pillow)
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "characters"))
from textures import tile_fbm, tile_noise  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
N = 1024


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def grid():
    y, x = np.mgrid[0:N, 0:N] / N
    return x, y


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blur(a, radius):
    """Gaussian blur that wraps round the edges (so the texture still tiles)."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    kernel = np.exp(-2.0 * (np.pi * radius) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * kernel))


def rand_per(ids, seed, n=1):
    """A random value (or n) for each integer id: per brick, per sett, per slab."""
    rng = np.random.default_rng(seed)
    table = rng.random((int(ids.max()) + 1, n))
    out = table[ids]
    return out[..., 0] if n == 1 else out


def streaks(seed, cells=24, stretch=10):
    """Vertical rain streaks and soot runs (tileable): noise stretched down the wall."""
    a = tile_noise(N, cells, seed)
    b = tile_noise(N, cells * 2, seed + 1)
    # Stretch along y by sampling rows sparsely and smoothing.
    s = (a * 0.65 + b * 0.35)
    s = blur(s, 1.0)
    cols = s[::stretch, :]
    rep = np.repeat(cols, stretch, axis=0)[:N]
    return blur(rep, 3.0)


def cavity_ao(h, strength=2.5, radius=6.0):
    """Ambient occlusion from the height field: hollows darker."""
    return np.clip(1.0 - np.maximum(blur(h, radius) - h, 0.0) * strength, 0.25, 1.0)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * N
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * N
    n = np.dstack([-dx * strength, dy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def save(folder, name, albedo, height, rough, ao, normal_strength, disp=False):
    d = os.path.join(OUT, folder)
    os.makedirs(d, exist_ok=True)
    img = lambda a: Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    img(albedo).save(os.path.join(d, name + "_diff.jpg"), quality=90)
    img(normal_from_height(height, normal_strength)).save(os.path.join(d, name + "_nor_gl.jpg"), quality=94)
    img(rough).save(os.path.join(d, name + "_rough.jpg"), quality=90)
    img(ao).save(os.path.join(d, name + "_ao.jpg"), quality=90)
    if disp:
        img((height - height.min()) / max(np.ptp(height), 1e-6)).save(os.path.join(d, name + "_disp.png"), optimize=True)
    print("  %-14s -> assets/textures/%s/" % (name, folder))


def hsv_jitter(base, per, amount_v=0.18, amount_h=0.03, amount_s=0.12):
    """base colour (3,) jittered per region by `per` (…,3) randoms in 0..1."""
    import colorsys
    h, s, v = colorsys.rgb_to_hsv(*base)
    hh = (h + (per[..., 0] - 0.5) * 2 * amount_h) % 1.0
    ss = np.clip(s * (1 + (per[..., 1] - 0.5) * 2 * amount_s), 0, 1)
    vv = np.clip(v * (1 + (per[..., 2] - 0.5) * 2 * amount_v), 0, 1)
    # vectorised hsv -> rgb
    i = np.floor(hh * 6).astype(int) % 6
    f = hh * 6 - np.floor(hh * 6)
    p, q, t = vv * (1 - ss), vv * (1 - ss * f), vv * (1 - ss * (1 - f))
    r = np.choose(i, [vv, q, p, p, t, vv])
    g = np.choose(i, [t, vv, vv, q, p, p])
    b = np.choose(i, [p, p, t, vv, vv, q])
    return np.dstack([r, g, b])


# ---------------------------------------------------------------------------
# Brick: London stock (yellow) and red, stretcher bond, 1.5 m square
# ---------------------------------------------------------------------------
def brick(folder, base, mortar, seed, soot=0.35):
    x, y = grid()
    courses, per_course = 18, 6
    row = np.floor(y * courses).astype(int)
    u = x * per_course + 0.5 * (row % 2) + (tile_fbm(N, 16, seed + 1, 2) * 0.012)
    col = np.floor(u).astype(int) % per_course
    fu = u - np.floor(u)
    fv = y * courses - row
    ids = row * per_course + col
    # Distance to the joint in millimetres (brick 250 x 83 mm with the joint).
    du = np.minimum(fu, 1 - fu) * 250.0
    dv = np.minimum(fv, 1 - fv) * 83.3
    edge_noise = tile_fbm(N, 64, seed + 2, 3) * 3.0
    d = np.minimum(du, dv) + edge_noise
    face = smooth(4.0, 9.0, d)                  # 1 on the brick face, 0 in the joint
    chips = (tile_fbm(N, 48, seed + 3, 3) > 0.42) & (d < 14.0)
    face = np.where(chips, face * 0.35, face)
    pits = tile_fbm(N, 256, seed + 4, 2)
    height = face * (0.8 + pits * 0.06) + (1 - face) * (0.25 + tile_fbm(N, 128, seed + 5, 3) * 0.08)
    per = rand_per(ids, seed + 6, 3)
    col_b = hsv_jitter(np.array(base), per, 0.16, 0.012, 0.1)
    mottled = 1.0 + tile_fbm(N, 96, seed + 7, 4)[..., None] * 0.18
    burnt = (rand_per(ids, seed + 8) > 0.9)[..., None]
    col_b = np.where(burnt, col_b * np.array([0.62, 0.58, 0.6]), col_b) * mottled
    col_m = np.array(mortar)[None, None, :] * (1.0 + tile_fbm(N, 128, seed + 9, 3)[..., None] * 0.15)
    albedo = col_b * face[..., None] + col_m * (1 - face[..., None])
    # Weathering: soot patina, rain streaks, efflorescence, grime in the joints.
    patina = 1.0 - soot * np.clip(tile_fbm(N, 6, seed + 10, 4) * 0.8 + 0.35, 0, 1)
    rain = 1.0 - 0.18 * np.clip(streaks(seed + 11) * 2.2, 0, 1)
    salt = np.clip(tile_fbm(N, 12, seed + 12, 4) * 2.5 - 0.9, 0, 1) * 0.25
    albedo = albedo * (patina * rain)[..., None]
    albedo = albedo + salt[..., None] * (np.array([0.85, 0.83, 0.78]) - albedo)
    ao = cavity_ao(height, 3.0, 5.0)
    albedo *= (0.55 + 0.45 * ao)[..., None]
    rough = np.clip(0.86 + pits * 0.06 + (1 - face) * 0.08 - salt * 0.1, 0, 1)
    save(folder, folder, albedo, height, rough, ao, 0.012)


# ---------------------------------------------------------------------------
# Granite setts (the road): rows of rounded blocks, 2 m square, with parallax height
# ---------------------------------------------------------------------------
def setts():
    x, y = grid()
    rows, per_row = 20, 10                       # 100 x 200 mm setts
    row = np.floor(y * rows).astype(int)
    offs = rand_per(row % rows, 3) * 0.9
    u = x * per_row + offs + tile_fbm(N, 16, 4, 2) * 0.06
    col = np.floor(u).astype(int) % per_row
    fu, fv = u - np.floor(u), y * rows - row + tile_fbm(N, 24, 13, 2) * 0.05
    ids = row * per_row + col
    # Hand-dressed setts: each a little different in size, corners worn round.
    shrink = rand_per(ids, 14, 2) * 4.0
    du = np.minimum(fu, 1 - fu) * 200.0 - shrink[..., 0]
    dv = np.minimum(fv, 1 - fv) * 100.0 - shrink[..., 1]
    d = -np.log(np.exp(-du / 6.0) + np.exp(-dv / 6.0)) * 6.0 + tile_fbm(N, 64, 5, 3) * 6.0
    dome = np.sqrt(np.clip(d / 45.0, 0, 1))
    face = smooth(3.0, 9.0, d)
    height = face * (0.55 + 0.45 * dome + tile_fbm(N, 256, 6, 2) * 0.04) + (1 - face) * 0.08
    per = rand_per(ids, 7, 3)
    tones = np.array([[0.44, 0.43, 0.42], [0.47, 0.43, 0.41], [0.41, 0.42, 0.44], [0.5, 0.49, 0.46]])
    pick = (rand_per(ids, 15) * len(tones)).astype(int).clip(0, len(tones) - 1)
    base = tones[pick] * (0.85 + per[..., :1] * 0.3)
    speck = (tile_noise(N, 512, 8) > 0.55) * 0.12 - (tile_noise(N, 512, 9) > 0.65) * 0.14
    worn = 1.0 + dome[..., None] * 0.08          # polished tops a shade lighter
    albedo = base * (1 + speck[..., None]) * worn
    joint = np.array([0.16, 0.13, 0.1]) * (1 + tile_fbm(N, 128, 10, 3)[..., None] * 0.4)
    albedo = albedo * face[..., None] + joint * (1 - face[..., None])
    grime = np.clip(tile_fbm(N, 8, 11, 4) * 0.9 + 0.3, 0, 1)
    dung = np.clip(tile_fbm(N, 24, 12, 3) * 3.0 - 1.3, 0, 1)
    albedo = albedo * (1 - 0.3 * grime)[..., None]
    albedo = albedo + dung[..., None] * (np.array([0.22, 0.17, 0.1]) - albedo) * 0.6
    ao = cavity_ao(height, 2.2, 6.0)
    albedo *= (0.5 + 0.5 * ao)[..., None]
    rough = np.clip(0.9 - dome * face * 0.3 + (1 - face) * 0.08, 0, 1)
    save("cobblestone", "cobblestone", albedo, height, rough, ao, 0.02, disp=True)


# ---------------------------------------------------------------------------
# York stone flagstones (pavements), 2 m square
# ---------------------------------------------------------------------------
def flagstones():
    x, y = grid()
    rows = 3
    row = np.floor(y * rows).astype(int)
    widths = [3, 2, 3]
    u = x * np.choose(row % 3, widths) + rand_per(row, 20) * 0.7
    col = np.floor(u).astype(int)
    fu, fv = u - np.floor(u), y * rows - row
    ids = row * 8 + col % 8
    du = np.minimum(fu, 1 - fu) * 650.0
    dv = np.minimum(fv, 1 - fv) * 667.0
    d = np.minimum(du, dv) + tile_fbm(N, 48, 21, 3) * 6.0
    face = smooth(3.0, 8.0, d)
    tilt = (rand_per(ids, 22) - 0.5) * 0.08 * (fu - 0.5)
    bedding = tile_fbm(N, 8, 23, 5)
    height = face * (0.7 + tilt + tile_fbm(N, 192, 24, 3) * 0.05) + (1 - face) * 0.2
    per = rand_per(ids, 25, 3)
    albedo = hsv_jitter(np.array([0.6, 0.56, 0.49]), per, 0.14, 0.03, 0.25)
    albedo = albedo * (1 + bedding[..., None] * 0.15)
    stains = np.clip(tile_fbm(N, 10, 26, 4) * 1.6 - 0.2, 0, 1)
    albedo = albedo * (1 - 0.35 * stains)[..., None]
    crack_d = np.abs(tile_fbm(N, 6, 27, 5))
    cracks = smooth(0.012, 0.0, crack_d) * (tile_fbm(N, 4, 28, 3) > 0.1)
    height = height - cracks * 0.06
    albedo = albedo * (1 - cracks * 0.45)[..., None]
    joint = np.array([0.17, 0.15, 0.12])
    albedo = albedo * face[..., None] + joint * (1 - face[..., None])
    ao = cavity_ao(height, 2.5, 5.0)
    albedo *= (0.55 + 0.45 * ao)[..., None]
    rough = np.clip(0.82 + stains * 0.1 + (1 - face) * 0.1, 0, 1)
    save("pavement", "pavement", albedo, height, rough, ao, 0.01)


# ---------------------------------------------------------------------------
# Render / stucco / plaster: pale, tinted per building by the game
# ---------------------------------------------------------------------------
def render(folder, base, seed, dirt=0.3, streak=0.25, crack=True):
    trowel = tile_fbm(N, 24, seed, 4)
    grain = tile_fbm(N, 384, seed + 1, 2)
    height = trowel * 0.15 + grain * 0.05
    albedo = np.array(base)[None, None, :] * (1 + trowel[..., None] * 0.05 + grain[..., None] * 0.04)
    patches = blur(np.clip(tile_fbm(N, 4, seed + 2, 4) * 1.1 + 0.35, 0, 1), 12.0)
    rain = np.clip(streaks(seed + 3, 20, 14) * 2.5, 0, 1)
    albedo = albedo * (1 - dirt * patches * 0.35 - streak * rain)[..., None]
    if crack:
        cracks = smooth(0.006, 0.0, np.abs(tile_fbm(N, 5, seed + 4, 5))) * (tile_fbm(N, 3, seed + 5, 3) > 0.15)
        height = height - cracks * 0.04
        albedo = albedo * (1 - cracks * 0.35)[..., None]
    ao = cavity_ao(height, 3.0, 4.0)
    rough = np.clip(0.88 + grain * 0.05 - rain * 0.05, 0, 1)
    save(folder, folder, albedo, height, rough, ao, 0.004)


# ---------------------------------------------------------------------------
# Portland stone (dressings, columns): fine, shelly, sooty
# ---------------------------------------------------------------------------
def portland():
    grain = tile_fbm(N, 256, 40, 3)
    shells = (tile_noise(N, 200, 41) > 0.72) * 0.08
    beds = tile_fbm(N, 4, 42, 5)
    albedo = np.array([0.8, 0.78, 0.72])[None, None, :] * (1 + grain[..., None] * 0.05 + shells[..., None] + beds[..., None] * 0.06)
    soot = np.clip(tile_fbm(N, 6, 43, 5) * 1.5 + 0.1, 0, 1)
    rain = np.clip(streaks(44, 18, 16) * 2.4, 0, 1)
    # Portland weathers white where rain washes it and black where it doesn't.
    albedo = albedo * (1 - 0.45 * soot * (1 - rain))[..., None]
    height = grain * 0.08 + beds * 0.1 - shells * 0.5
    ao = cavity_ao(height, 3.0, 3.0)
    rough = np.clip(0.8 + grain * 0.05, 0, 1)
    save("stone_trim", "stone_trim", albedo, height, rough, ao, 0.005)


# ---------------------------------------------------------------------------
# Welsh slate roof, 2 m square
# ---------------------------------------------------------------------------
def slates():
    x, y = grid()
    rows, per_row = 10, 8
    row = np.floor(y * rows).astype(int)
    u = x * per_row + 0.5 * (row % 2)
    col = np.floor(u).astype(int) % per_row
    fu, fv = u - np.floor(u), y * rows - row
    ids = row * per_row + col
    gap = smooth(0.0, 0.03, np.minimum(fu, 1 - fu)) * smooth(0.0, 0.05, fv)
    lap = fv                                       # each slate lifts towards its lower edge
    height = (0.3 + lap * 0.5) * gap + tile_fbm(N, 128, 50, 3) * 0.04
    per = rand_per(ids, 51, 3)
    albedo = hsv_jitter(np.array([0.23, 0.25, 0.28]), per, 0.25, 0.04, 0.3)
    albedo = albedo * (1 + tile_fbm(N, 64, 52, 3)[..., None] * 0.12)
    lichen = np.clip(tile_fbm(N, 16, 53, 4) * 3.0 - 1.4, 0, 1)
    albedo = albedo + lichen[..., None] * (np.array([0.45, 0.46, 0.33]) - albedo) * 0.5
    albedo = albedo * (0.35 + 0.65 * gap)[..., None]
    ao = cavity_ao(height, 2.5, 6.0)
    rough = np.clip(0.7 + tile_fbm(N, 64, 54, 2) * 0.1 + lichen * 0.2, 0, 1)
    save("slate_roof", "slate_roof", albedo, height, rough, ao, 0.01)


# ---------------------------------------------------------------------------
# Wood: weathered planks, and painted joinery
# ---------------------------------------------------------------------------
def planks(folder, base, seed, painted=None):
    x, y = grid()
    boards = 6
    b = np.floor(x * boards).astype(int)
    fu = x * boards - b
    per = rand_per(b, seed, 3)
    stretch_noise = blur(tile_fbm(N, 64, seed + 1, 4), 1.0)
    grain = np.sin((y * 40 + stretch_noise * 3.0 + per[..., 0] * 10) * np.pi * 2) * 0.5 + 0.5
    grain = blur(grain, 0.8)
    knots = np.clip(tile_fbm(N, 20, seed + 2, 3) * 3 - 1.8, 0, 1)
    edge = smooth(0.0, 0.03, np.minimum(fu, 1 - fu))
    height = edge * (0.6 + grain * 0.05 - knots * 0.1) + (1 - edge) * 0.1
    wood = hsv_jitter(np.array(base), per, 0.2, 0.03, 0.2) * (0.85 + grain[..., None] * 0.2) * (1 - knots[..., None] * 0.35)
    if painted is None:
        albedo = wood * (0.4 + 0.6 * edge)[..., None]
        rough = np.clip(0.82 + grain * 0.05, 0, 1)
    else:
        chips = np.clip(tile_fbm(N, 32, seed + 3, 4) * 3 - 1.9, 0, 1)
        paint = np.array(painted)[None, None, :] * (1 + tile_fbm(N, 128, seed + 4, 2)[..., None] * 0.04)
        albedo = paint * (1 - chips[..., None]) + wood * chips[..., None]
        albedo *= (0.6 + 0.4 * edge)[..., None]
        height = height + (1 - chips) * 0.05
        rough = np.clip(0.55 + chips * 0.3 + grain * 0.03, 0, 1)
    dirt = np.clip(tile_fbm(N, 8, seed + 5, 4) * 1.2 + 0.2, 0, 1)
    albedo *= (1 - 0.2 * dirt)[..., None]
    ao = cavity_ao(height, 2.5, 4.0)
    save(folder, folder, albedo, height, rough, ao, 0.006)


def granite_kerb():
    grain = tile_fbm(N, 384, 60, 2)
    speck = (tile_noise(N, 400, 61) > 0.6) * 0.15 - (tile_noise(N, 400, 62) > 0.7) * 0.2
    albedo = np.array([0.52, 0.51, 0.5])[None, None, :] * (1 + speck[..., None] + grain[..., None] * 0.06)
    wear = np.clip(tile_fbm(N, 8, 63, 4) * 1.3 + 0.2, 0, 1)
    albedo *= (1 - 0.3 * wear)[..., None]
    height = grain * 0.06 + speck * 0.1
    ao = cavity_ao(height, 3.0, 3.0)
    rough = np.clip(0.75 + grain * 0.08 - wear * 0.1, 0, 1)
    save("curb_granite", "curb_granite", albedo, height, rough, ao, 0.005)


def hay():
    """Loose straw: thousands of stalks drawn at every angle over dark shadowed gaps."""
    from PIL import ImageDraw
    rng = np.random.default_rng(80)
    col_img = Image.new("RGB", (N, N), (40, 32, 18))
    h_img = Image.new("L", (N, N), 0)
    dc, dh = ImageDraw.Draw(col_img), ImageDraw.Draw(h_img)
    for layer in range(4):
        for _ in range(1400):
            x0, y0 = rng.random(2) * N
            ang = rng.random() * np.pi
            length = rng.uniform(40, 170)
            w = int(rng.integers(2, 5))
            x1, y1 = x0 + np.cos(ang) * length, y0 + np.sin(ang) * length
            shade = rng.uniform(0.55, 1.0) * (0.7 + 0.1 * layer)
            c = tuple(int(v * shade) for v in (206, 172, 98) if True)
            hv = int(80 + 40 * layer + rng.integers(0, 30))
            for ox in (-N, 0, N):
                for oy in (-N, 0, N):
                    dc.line((x0 + ox, y0 + oy, x1 + ox, y1 + oy), fill=c, width=w)
                    dh.line((x0 + ox, y0 + oy, x1 + ox, y1 + oy), fill=hv, width=w)
    albedo = np.asarray(col_img).astype(np.float64) / 255.0
    height = blur(np.asarray(h_img).astype(np.float64) / 255.0, 0.8)
    old = np.clip(tile_fbm(N, 8, 86, 4) * 1.5, 0, 1)[..., None]
    albedo = albedo * (1 - old * 0.3)
    ao = cavity_ao(height, 2.5, 4.0)
    albedo *= (0.6 + 0.4 * ao)[..., None]
    rough = np.clip(0.75 + (1 - height) * 0.2, 0, 1)
    save("hay", "hay", albedo, height, rough, ao, 0.012)


BAKES = {
    "hay": hay,
    "brick_yellow": lambda: brick("brick_yellow", (0.66, 0.56, 0.4), (0.56, 0.54, 0.5), 11, soot=0.45),
    "brick_red": lambda: brick("brick_red", (0.52, 0.25, 0.17), (0.6, 0.58, 0.54), 23, soot=0.3),
    "cobblestone": setts,
    "pavement": flagstones,
    "stucco": lambda: render("stucco", (0.86, 0.83, 0.76), 31, dirt=0.35, streak=0.22),
    "plaster": lambda: render("plaster", (0.9, 0.88, 0.82), 97, dirt=0.15, streak=0.08, crack=False),
    "stone_trim": portland,
    "slate_roof": slates,
    "wood_planks": lambda: planks("wood_planks", (0.42, 0.31, 0.21), 70),
    "floorboards": lambda: planks("floorboards", (0.36, 0.22, 0.12), 71),
    "wood_painted": lambda: planks("wood_painted", (0.4, 0.3, 0.2), 72, painted=(0.93, 0.92, 0.9)),
    "curb_granite": granite_kerb,
}


def main():
    wanted = sys.argv[1:] or list(BAKES)
    for name in wanted:
        BAKES[name]()


if __name__ == "__main__":
    main()
