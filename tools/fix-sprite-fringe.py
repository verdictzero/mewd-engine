#!/usr/bin/env python3
"""MEWD — take the matte off a sprite strip's edge (at the user's request:
the people had "a weird sparkly outline").

The strips were cut out onto a clear background by tools that left the
half-clear texels of the edge the colour of the drawing MIXED WITH THE
BACKGROUND (black, mostly): a texel 60% coat and 40% nothing came out 60%
as bright as the coat. Drawn with a cut-out at half alpha, every one of
those is a dark bead round the drawing, and under a nearest-texel fetch
the beads come and go as the sprite sways. This gives every texel that is
not fully opaque the colour of the NEAREST fully opaque texel, within
`RADIUS`, and leaves its alpha alone: the edge keeps its shape and loses
the matte. (Godot's own fix_alpha_border does the same for the texels
that are wholly clear, and only those.)

    tools/fix-sprite-fringe.py assets/people/*.png
"""
import sys
import numpy as np
from PIL import Image

RADIUS = 4
OPAQUE = 250


def fix(path):
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    alpha = a[..., 3]
    rgb = a[..., :3].astype(np.int32)
    opaque = alpha >= OPAQUE
    want = (alpha < OPAQUE) & (alpha > 0)
    if not want.any():
        print("%s: no fringe" % path)
        return
    h, w = alpha.shape
    # the nearest opaque texel, by growing rings: a ring's texels overwrite
    # nothing already claimed by a nearer one
    best_d = np.full((h, w), 1e9)
    out = rgb.copy()
    pad = RADIUS
    op_p = np.pad(opaque, pad)
    rgb_p = np.pad(rgb, ((pad, pad), (pad, pad), (0, 0)))
    for dy in range(-RADIUS, RADIUS + 1):
        for dx in range(-RADIUS, RADIUS + 1):
            d = dx * dx + dy * dy
            if d == 0:
                continue
            o = op_p[pad + dy:pad + dy + h, pad + dx:pad + dx + w]
            c = rgb_p[pad + dy:pad + dy + h, pad + dx:pad + dx + w]
            take = want & o & (d < best_d)
            best_d[take] = d
            out[take] = c[take]
    fixed = want & (best_d < 1e9)
    before = rgb[fixed].mean()
    a[..., :3] = out.astype(np.uint8)
    Image.fromarray(a).save(path)
    print("%s: %d edge texels recoloured (mean %.0f -> %.0f), %d too far from the drawing left" % (
        path, fixed.sum(), before, out[fixed].mean(), (want & ~fixed).sum()))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        fix(p)
