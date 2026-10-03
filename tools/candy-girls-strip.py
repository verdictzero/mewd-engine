#!/usr/bin/env python3
"""MEWD — the candy girls' strip (assets/people/candy_girls.png), at the
user's request for CANDY LAND: every flavour's front then her back, in
States.CANDY_FLAVOURS order, each cut from the artist's 256 x 382 picture
(godot/island/candy/source/npc) to 192 x 287: resized with the alpha
premultiplied, the alpha cut back to 1 bit at a half, and the colour bled
out into the clear pixels so the mipmaps do not draw a dark rim.

    python3 tools/candy-girls-strip.py
"""
import numpy as np
from PIL import Image

SRC = "godot/island/candy/source/npc/SPRITE_npc_%sGirl_%s.png"
OUT = "assets/people/candy_girls.png"
# (keep in step with States.CANDY_FLAVOURS)
FLAVOURS = ["blueberry", "cherryCola", "grape", "lemon", "lime", "mint", "strawberry", "vanilla", "orange"]
W, H = 192, 287


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


def cut(im):
    a = np.asarray(im.convert("RGBA")).astype(np.float32) / 255
    al = a[..., 3:4]
    pm = np.concatenate([a[..., :3] * al, al], -1)
    r = np.asarray(Image.fromarray((pm * 255).astype(np.uint8), "RGBA").resize((W, H), Image.LANCZOS)).astype(np.float32) / 255
    al2 = r[..., 3:4]
    rgb = np.where(al2 > 1e-3, r[..., :3] / np.maximum(al2, 1e-3), 0)
    out = np.concatenate([np.clip(rgb, 0, 1), (al2 > 0.5).astype(np.float32)], -1)
    return bleed(Image.fromarray((out * 255).astype(np.uint8), "RGBA"))


strip = Image.new("RGBA", (W * 2 * len(FLAVOURS), H))
for i, f in enumerate(FLAVOURS):
    for j, side in enumerate(["front", "back"]):
        strip.paste(cut(Image.open(SRC % (f, side))), ((i * 2 + j) * W, 0))
strip.save(OUT)
print(OUT, strip.size)
