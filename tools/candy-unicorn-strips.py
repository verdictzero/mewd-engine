#!/usr/bin/env python3
"""MEWD — the candy unicorns' strips (assets/people/candy_unicorn.png and
candy_foal.png), at the user's request for CANDY LAND: each animal's
front, side and back (godot/island/candy/source/creature) in one strip,
every cell as wide as the widest view and the picture stood on the cell's
floor in the middle of it, the alpha cut to 1 bit and the colour bled out
into the clear pixels so the mipmaps draw no rim. Standees "UNI"/"FOAL"
pick the view; the side faces right and is mirrored for the other flank.

    python3 tools/candy-unicorn-strips.py
"""
import numpy as np
from PIL import Image

SRC = "godot/island/candy/source/creature/SPRITE_creature_%s_%s.png"


def bleed(img):
    a = np.asarray(img).astype(np.float32)
    known = a[..., 3] > 127
    a[..., 3] = np.where(known, 255, 0)
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


for name, out in (("candyUnicorn", "assets/people/candy_unicorn.png"), ("candyUnicornFoal", "assets/people/candy_foal.png")):
    views = [Image.open(SRC % (name, v)).convert("RGBA") for v in ("front", "side", "back")]
    w = max(v.width for v in views)
    h = max(v.height for v in views)
    strip = Image.new("RGBA", (w * 3, h))
    for i, v in enumerate(views):
        strip.paste(v, (i * w + (w - v.width) // 2, h - v.height))
    strip = bleed(strip)
    strip.save(out)
    print(out, strip.size, "cell", (w, h))
