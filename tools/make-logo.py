#!/usr/bin/env python3
"""MEWD — the logo, cut out of the user's picture (tools/art/mewd_logo_source.jpg:
the white webbed MEWD on grainy black), with a black stroke round it.

    python3 tools/make-logo.py [source]

The picture is blown up 4x (smooth) and its brightness is the logo's cover:
black is clear, white is the logo, levels set so the grain of the black
ground goes and the webs' thin strands stay. Specks of grain left on their
own (a piece of the cover not touching the logo's bulk) are dropped. The
logo is white; under it a STROKE, the cover grown by STROKE px, black,
soft at its edge. Written trimmed to its box at the widths the game reads:

    assets/logo/mewd-480/960/1440/1951.webp   the title (title.gd: 1440)
    godot/data/splash.png                     the boot splash (960)

then tools/make-icons.py makes the icons from mewd-1951. Needs Pillow,
numpy and scipy."""
from PIL import Image, ImageFilter
import numpy as np
from scipy import ndimage
import os, sys, subprocess

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "tools/art/mewd_logo_source.jpg")
UP = 4
LO, HI = 0.30, 0.62      # brightness: under LO clear, over HI solid
MIN_SPECK = 900          # px (at 4x): a lone piece smaller than this is grain
STROKE = 14              # px at 4x of the source, ~3.5 px of the 512 picture


def main():
    src = Image.open(SRC).convert("L")
    big = src.resize((src.width * UP, src.height * UP), Image.LANCZOS)
    lum = np.asarray(big, dtype=np.float32) / 255.0
    cover = np.clip((lum - LO) / (HI - LO), 0.0, 1.0)
    # the pieces: any cover at all, those touching nothing big dropped
    solid = cover > 0.05
    lab, n = ndimage.label(solid, structure=np.ones((3, 3)))
    sizes = ndimage.sum(solid, lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes >= MIN_SPECK
    cover = cover * keep[lab]
    # the stroke: the cover grown, soft at its edge
    yy, xx = np.mgrid[-STROKE:STROKE + 1, -STROKE:STROKE + 1]
    disk = (xx * xx + yy * yy) <= STROKE * STROKE
    grown = ndimage.grey_dilation(cover, footprint=disk)
    grown = np.asarray(Image.fromarray((grown * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255.0
    grown = np.maximum(grown, cover)
    # white over black: colour = white where the logo is, black in the stroke
    a = grown
    rgb = np.where(a[..., None] > 0, (cover / np.maximum(a, 1e-6))[..., None], 0.0)
    out = np.dstack([rgb * 255, rgb * 255, rgb * 255, a * 255]).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(out, "RGBA")
    im = im.crop(im.getbbox())
    d = os.path.join(ROOT, "assets/logo")
    for w in (480, 960, 1440, 1951):
        h = round(im.height * w / im.width)
        im.resize((w, h), Image.LANCZOS).save(os.path.join(d, "mewd-%d.webp" % w), lossless=True)
    h = round(im.height * 960 / im.width)
    im.resize((960, h), Image.LANCZOS).save(os.path.join(ROOT, "godot/data/splash.png"))
    print("logo %dx%d written" % im.size)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools/make-icons.py")], check=True)


if __name__ == "__main__":
    main()
