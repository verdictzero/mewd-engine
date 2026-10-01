#!/usr/bin/env python3
"""MEWD — every icon, from the MEWD logo (assets/logo/mewd-1951.webp).

    python3 tools/make-icons.py

The logo is wide and an icon is square, so it is laid across the middle
of a square of the boot splash's dark teal, nearly edge to edge:

    icon.png                        512  the project's icon: the desktop
                                         window and taskbar, the web
                                         build's favicon and home-screen
                                         icon (manifest.webmanifest), and
                                         the Android launcher where a
                                         device does not use adaptive icons
    godot/data/icons/main_192.png   192  Android's launcher icon
    godot/data/icons/fg_432.png     432  Android's adaptive icon: the logo
    godot/data/icons/bg_432.png     432  alone, within the middle 264
                                         (the part every mask keeps), over
                                         the teal

Needs Pillow."""
from PIL import Image
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
BG = (11, 19, 20, 255)          # the boot splash's #0b1314


def logo():
    im = Image.open(os.path.join(ROOT, "assets/logo/mewd-1951.webp")).convert("RGBA")
    return im.crop(im.getbbox())


def placed(size, width, bg):
    """The logo `width` wide, in the middle of a `size` square."""
    lg = logo()
    h = round(lg.height * width / lg.width)
    lg = lg.resize((width, h), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), bg)
    out.alpha_composite(lg, ((size - width) // 2, (size - h) // 2))
    return out


def main():
    placed(512, 480, BG).save(os.path.join(ROOT, "icon.png"))
    d = os.path.join(ROOT, "godot/data/icons")
    os.makedirs(d, exist_ok=True)
    placed(192, 180, BG).save(os.path.join(d, "main_192.png"))
    placed(432, 264, (0, 0, 0, 0)).save(os.path.join(d, "fg_432.png"))
    Image.new("RGBA", (432, 432), BG).save(os.path.join(d, "bg_432.png"))
    print("icons written")


if __name__ == "__main__":
    main()
