#!/usr/bin/env python3
"""MEWD — the fetus launcher's shot (assets/things/fetus.png), at the
user's request ("make this weapon fire the fetus"; "i just want the fetus
sprite"): the user's own picture (tools/art/fetus.png, 1066 x 1273, its
own alpha), the fetus in its sac. Cut to 128 wide, resized with the alpha
premultiplied, the alpha cut back to 1 bit at a half and the colour bled
out into the clear pixels, as the pickups' are. FetusLauncher draws it as
a card turned to the eye (fetus_card.gdshader) and tears it into pieces
where it lands (SpriteChunks).

    python3 -I tools/fetus-art.py
"""
import numpy as np
from PIL import Image

SRC = "tools/art/fetus.png"
OUT = "assets/things/fetus.png"
W = 128


def bleed(a):
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
    return a


im = Image.open(SRC).convert("RGBA")
h = round(im.height * W / im.width)
a = np.asarray(im).astype(np.float32) / 255
al = a[..., 3:4]
pm = Image.fromarray((np.concatenate([a[..., :3] * al, al], -1) * 255 + 0.5).astype(np.uint8), "RGBA")
r = np.asarray(pm.resize((W, h), Image.LANCZOS)).astype(np.float32) / 255
al2 = r[..., 3:4]
rgb = np.where(al2 > 1e-3, r[..., :3] / np.maximum(al2, 1e-3), 0)
out = bleed(np.concatenate([np.clip(rgb, 0, 1), (al2 > 0.5).astype(np.float32)], -1))
Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT)
print(OUT, (W, h))
