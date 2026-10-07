#!/usr/bin/env python3
"""MEWD — the pickups' strip (assets/things/pickups.png), at the user's
request ("implement these pickups"): the twelve pictures from the user's
mewd_pickups.zip, each painted on a green screen at 2048 x 2048, keyed
out (how much greener a pixel is than its red and blue, eased from solid
to clear, and the green spill pulled down to the larger of the two),
cut to what is left, set on the floor of a 128 x 128 cell (bottom
centred: an item sits on the ground), resized with the alpha
premultiplied, the alpha cut back to 1 bit at a half and the colour bled
out into the clear pixels, as the candy girls' strip is
(tools/candy-girls-strip.py). The cells go in Pickups.KINDS order.

    python3 -I tools/pickups-strip.py <folder of the zip's pictures>
    python3 -I tools/pickups-strip.py --cell=N <picture>   (one cell anew)

Cell 10, the cerebral bore's ammo, is the user's later "BORE" crate
(tools/art/pickup_bore_ammo.jpg), not the zip's bio vats.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

OUT = "assets/things/pickups.png"
CELL = 128
# (keep in step with Pickups.KINDS)
FILES = [
    "health.jpeg", "health_big.jpeg", "armor.jpeg", "armor_big.jpeg",
    "small_ammo.jpeg", "large_ammo.jpeg", "energy_ammo.jpeg", "large_energy_ammo",
    "rocket_ammo.jpeg", "mini_nuke_ammo.jpeg", "bio_gun_ammo.jpeg", "arc_maw_alien_energy_ammo.jpeg",
]


def bleed(img):
    a = np.asarray(img).astype(np.float32)
    known = a[..., 3] > 127
    rgb = a[..., :3].copy()
    for _ in range(12):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        n = np.zeros(known.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * k[..., None]
            n += k
        new = (~known) & (n > 0)
        rgb[new] = acc[new] / n[new][:, None]
        known |= new
    a[..., :3] = rgb
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def key(im):
    a = np.asarray(im.convert("RGB")).astype(np.float32) / 255
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = g - np.maximum(r, b)
    alpha = 1.0 - np.clip((green - 0.12) / 0.26, 0.0, 1.0)
    g = np.minimum(g, np.maximum(r, b) + 0.04)
    out = Image.fromarray((np.stack([r, g, b, alpha], -1) * 255 + 0.5).astype(np.uint8), "RGBA")
    # the jpeg's fringe: the edge in by two pixels
    out.putalpha(out.getchannel("A").filter(ImageFilter.MinFilter(5)))
    al = np.asarray(out.getchannel("A")) > 24
    # (rows and columns with more than a few solid pixels: the arc maw's
    # picture has two stray rows along its top)
    rows = np.where(al.sum(1) > 8)[0]
    cols = np.where(al.sum(0) > 8)[0]
    return out.crop((cols[0], rows[0], cols[-1] + 1, rows[-1] + 1))


def cut(im):
    w, h = im.size
    s = (CELL - 4) / max(w, h)
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    a = np.asarray(im).astype(np.float32) / 255
    al = a[..., 3:4]
    pm = np.concatenate([a[..., :3] * al, al], -1)
    r = np.asarray(Image.fromarray((pm * 255 + 0.5).astype(np.uint8), "RGBA").resize((nw, nh), Image.LANCZOS)).astype(np.float32) / 255
    al2 = r[..., 3:4]
    rgb = np.where(al2 > 1e-3, r[..., :3] / np.maximum(al2, 1e-3), 0)
    small = np.concatenate([np.clip(rgb, 0, 1), (al2 > 0.5).astype(np.float32)], -1)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.paste(Image.fromarray((small * 255 + 0.5).astype(np.uint8), "RGBA"), ((CELL - nw) // 2, CELL - 1 - nh))
    return bleed(cell)


# ONE CELL OVER AGAIN, from a picture of its own (at the user's request:
# the cerebral bore's ammo, "BORE", in place of the bio vats):
#     python3 -I tools/pickups-strip.py --cell=10 <picture>
if sys.argv[1].startswith("--cell="):
    i = int(sys.argv[1][7:])
    strip = Image.open(OUT).convert("RGBA")
    strip.paste(Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)), (i * CELL, 0))
    strip.paste(cut(key(Image.open(sys.argv[2]))), (i * CELL, 0))
    strip.save(OUT)
    print(OUT, strip.size, "cell", i)
    sys.exit(0)

src = sys.argv[1]
strip = Image.new("RGBA", (CELL * len(FILES), CELL))
for i, f in enumerate(FILES):
    strip.paste(cut(key(Image.open(os.path.join(src, f)))), (i * CELL, 0))
strip.save(OUT)
print(OUT, strip.size)
