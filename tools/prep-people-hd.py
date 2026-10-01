#!/usr/bin/env python3
"""MEWD — the crowd at 128 pixels across, for the Godot build.

    python3 tools/prep-people-hd.py /path/to/galvarius

tools/prep-people.mjs brings the shoppers over from github.com/verdictzero
/galvarius for the classic build, boxed down ten to one so a sprite is one
unit to the pixel. This one keeps far more of them: the same seventeen
drawings, trimmed to their own pixels, laid into equal cells exactly as
prep-people lays the small ones (centred across, standing on the bottom),
into assets/people/shoppers_hd.png.

The cell is the classic one (40 x 64 world units) at the artist's own
scale, 575 pixels to a 62-unit adult (371 x 594), then, at the user's
request, shrunk so its short axis is SHORT = 128 pixels and the long one
in proportion: 128 x 205. Every drawing is shrunk by that one factor
(Lanczos), so every person is the same size in the world as before and
the same height against every other. The game draws the strip by fraction
(render/standees.gd, `texel`), mipmapped, so it does not shimmer far off.

Needs Pillow."""
import os
import sys

from PIL import Image

PEOPLE = [
    'taco_dude_1', 'taco_dude_2', 'taco_dude_3',
    'taco_fatty_1', 'taco_fatty_2', 'taco_fatty_3',
    'taco_girl_1', 'taco_girl_2', 'taco_girl_3', 'taco_girl_5', 'taco_girl_6',
    'taco_girl_7', 'taco_girl_8', 'taco_girl_9', 'taco_girl_10',
    'taco_ssbbw_walmart_edition_1', 'aerobics_girl_1',
]
THEIR_ADULT = 575
ADULT = 62
CELL = (40, 64)
K = THEIR_ADULT / ADULT
FULL = (CELL[0] * K, CELL[1] * K)
SHORT = 128
S = SHORT / min(FULL)
CW, CH = round(FULL[0] * S), round(FULL[1] * S)


def trimmed(path):
    im = Image.open(path).convert('RGBA')
    # everything that is not (nearly) transparent, as prep-people's trim
    a = im.getchannel('A').point(lambda v: 255 if v > 8 else 0)
    box = a.getbbox()
    im = im.crop(box) if box else im
    size = (max(1, round(im.width * S)), max(1, round(im.height * S)))
    return im.resize(size, Image.LANCZOS)


def main():
    if len(sys.argv) < 2:
        sys.exit('usage: prep-people-hd.py /path/to/galvarius')
    src = os.path.join(sys.argv[1], 'galvarius_godot', 'assets', 'NPCs')
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    out = Image.new('RGBA', (CW * len(PEOPLE), CH), (0, 0, 0, 0))
    for k, stem in enumerate(PEOPLE):
        im = trimmed(os.path.join(src, stem + '.png'))
        if im.width > CW or im.height > CH:
            sys.exit(f'{stem}: {im.width}x{im.height} does not fit a {CW}x{CH} cell')
        out.alpha_composite(im, (k * CW + (CW - im.width) // 2, CH - im.height))
    path = os.path.join(root, 'assets', 'people', 'shoppers_hd.png')
    out.save(path, optimize=True)
    print(f'assets/people/shoppers_hd.png: {len(PEOPLE)} x {CW}x{CH} ({out.width}x{out.height}), '
          f'{os.path.getsize(path) // 1024}K')


if __name__ == '__main__':
    main()
