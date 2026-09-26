"""Game-sized textures for the Rocketbox people (MIT, Microsoft).

    python3 tools/rocketbox/textures.py <Rocketbox checkout> Name [Name ...]

For each avatar (Assets/Avatars/*/<Name>/Textures) writes assets/characters/rocketbox/<Name>/:
  head.jpg, body.jpg          colour (head 1536 px: faces are what people look at)
  head_n.jpg, body_n.jpg      normal maps
  head_r.png, body_r.png      roughness (from the specular maps)
  hair.png                    the hair, lashes and brows sheet, with its alpha
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "characters", "rocketbox")


def find(tex_dir, suffix):
    hits = [p for p in glob.glob(os.path.join(tex_dir, "*" + suffix)) if "facial" not in os.path.basename(p)]
    return hits[0] if hits else None


def save_jpg(src, dst, size, quality=88):
    im = Image.open(src).convert("RGB")
    if im.size[0] > size:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(dst, quality=quality, optimize=True)


def save_rough(src, dst, size):
    im = Image.open(src).convert("L")
    if im.size[0] > size:
        im = im.resize((size, size), Image.LANCZOS)
    spec = np.asarray(im).astype(np.float64) / 255.0
    rough = np.clip(0.92 - spec * 1.6, 0.32, 0.95)
    Image.fromarray((rough * 255).astype(np.uint8)).save(dst, optimize=True)


def convert(root, name):
    dirs = glob.glob(os.path.join(root, "Assets", "Avatars", "*", name, "Textures"))
    if not dirs:
        raise SystemExit("no textures for " + name)
    tex = dirs[0]
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    for part, size in (("head", 1536), ("body", 1024)):
        save_jpg(find(tex, "_%s_color.tga" % part), os.path.join(out, part + ".jpg"), size)
        save_jpg(find(tex, "_%s_normal.tga" % part), os.path.join(out, part + "_n.jpg"), 1024, 92)
        save_rough(find(tex, "_%s_specular.tga" % part), os.path.join(out, part + "_r.png"), 512)
    op = find(tex, "_opacity_color.tga")
    if op:
        im = Image.open(op).convert("RGBA")
        if im.size[0] > 1024:
            im = im.resize((1024, 1024), Image.LANCZOS)
        im.save(os.path.join(out, "hair.png"), optimize=True)
    total = sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out))
    print("%-22s %.1f MB" % (name, total / 1e6))


if __name__ == "__main__":
    for n in sys.argv[2:]:
        convert(sys.argv[1], n)
