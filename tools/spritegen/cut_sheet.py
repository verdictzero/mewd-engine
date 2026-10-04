#!/usr/bin/env python3
"""MEWD — CUT AN IMAGE MODEL'S SHEET INTO THE GAME'S STRIP (the other half
of pose_sheet.py: that one makes the template the model fills in, this
one reads the filled sheet back off the template's manifest).

    python3 tools/spritegen/cut_sheet.py NAME IMAGE [IMAGE ...] [options]

    NAME                the sprite's name: the strip is assets/people/
                        <name>.png and the cells are <NAME><letter><view>
    IMAGE               what the model returned, any size; each file's
                        name must contain its sheet's name (sheet01-walk,
                        sheet03-death ...) so it is cut by the right
                        manifest: rename the downloads so, e.g.
                        myguy.sheet01-walk.png
    --manifest DIR      where the templates and their JSON are (default
                        tools/spritegen/out, every profile)
    --profile P         mewd (default), doom, mewd-civ, civ, mewd-civ-
                        noprops or civ-noprops: which manifest cuts a
                        sheet name two profiles share (the troops' 01 to
                        04, the civilians' 01 to 05, and more between a
                        civilian set and its no-props twin), when the
                        picture is not the exact size of either; a civ-
                        sheet always falls to a civ profile
    --cells DIR         also write every cell on its own (PNG, keyed and
                        trimmed, at game scale)
    --height PX         a standing figure's height in the strip
                        (default 60, the SWAT's, in a 64 cell)
    --cell PX           the strip's square cell (default 64)
    --no-strip          only the cells
    --key RRGGBB        the ground colour to key out; default: measured
                        off each cell's border, which copes with a model
                        that returned a near-magenta or a JPEG

WHAT IT DOES, per cell of each sheet: cuts the figure box by the
manifest's fractions (so a 1024 or a 4096 return cuts the same), keys
the ground out by HOW MAGENTA each pixel is (the halo a JPEG leaves is
unmixed, as tools/prep-troops.mjs does), drops specks, trims to the
figure, and scales it by ONE factor for the whole set (the manifest's
pixels-per-metre against --height, so a corpse is as long as the man
was tall and a crouch is as low as it should be). The alpha is cut to
one bit at a half and the colour bled into the clear texels, as
tools/candy-girls-strip.py does, so the mipmaps do not draw a rim.

THE STRIP is the troops' contract (states.gd TROOPS, render/standees.gd):
the turned frames A B C D E F G, five views each in view order (1 head
on, 2 quarter, 3 side, 4 three-quarters-back, 5 back), then the flat
frames H to W, one each, every cell `--cell` square with the figure
centred and standing on the bottom, a frame marked `air` in the
manifest kept at its height above the ground line instead. The letters
come off the profile's own manifest, so a civilian set is laid the same
way with its own: A to K turned (walk, flee, stand, cower, hands up),
L to Z flat (death, gibs). A frame the images do not cover is left
clear and named in the report. An eight-view sheet's views 6, 7, 8 are
not used by the strip (the game mirrors 2, 3, 4) but are written with
--cells.

Needs Pillow and numpy."""
import argparse
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
VIEWS = 5


def letters_of(sheets):
    """The turned and the flat frame letters of a profile, in order, off
    its sheets' lettered cells (the troops' ABCDEFG / HIJKLMNOPQRSTUVW)."""
    turn, flat = set(), set()
    for s in sheets:
        for c in s["cells"]:
            if c["letter"]:
                (turn if c["view"] else flat).add(c["letter"])
    return "".join(sorted(turn)), "".join(sorted(flat))


def key_alpha(rgb, key):
    """How much of each pixel is the ground, 0..1, and the colour with
    the ground unmixed out of it."""
    r, g, b = [rgb[..., i].astype(np.float32) for i in range(3)]
    kr, kg, kb = [float(v) for v in key]
    if kr > 180 and kb > 180 and kg < 90:
        # magenta: measured as prep-troops does, which survives a JPEG
        ground = np.clip((np.minimum(r, b) - g - 20) / 80, 0, 1)
    else:
        d = np.max(np.abs(rgb.astype(np.float32) - np.array(key, np.float32)), axis=-1)
        ground = np.clip((90 - d) / 66, 0, 1)
    a = 1 - ground
    out = np.zeros(rgb.shape[:2] + (4,), np.float32)
    safe = np.maximum(a, 1e-3)[..., None]
    out[..., :3] = np.clip((rgb.astype(np.float32) - ground[..., None] * np.array(key, np.float32)) / safe, 0, 255)
    out[..., 3] = a * 255
    out[a <= 0.02] = 0
    return out


def border_key(rgb):
    """The ground colour, as the median of the crop's outer ring."""
    h, w = rgb.shape[:2]
    m = max(2, int(min(h, w) * 0.03))
    ring = np.concatenate([rgb[:m].reshape(-1, 3), rgb[-m:].reshape(-1, 3), rgb[:, :m].reshape(-1, 3), rgb[:, -m:].reshape(-1, 3)])
    return [int(v) for v in np.median(ring, axis=0)]


def despeckle(a, min_px):
    """Drop every opaque blob smaller than min_px pixels (a stray dot
    of label text, a fleck of halo), by a flood fill."""
    opaque = a[..., 3] > 127
    h, w = opaque.shape
    seen = np.zeros_like(opaque)
    ys, xs = np.nonzero(opaque)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        stack, blob = [(y0, x0)], []
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            blob.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(blob) < min_px:
            for y, x in blob:
                a[y, x] = 0
    return a


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


def shrink(a, scale):
    """A keyed cell at the game's scale: premultiplied box filter, the
    alpha cut to one bit at a half, the colour bled out."""
    im = Image.fromarray(a.astype(np.uint8), "RGBA")
    if scale < 1:
        f = np.asarray(im).astype(np.float32) / 255
        al = f[..., 3:4]
        pm = np.concatenate([f[..., :3] * al, al], -1)
        size = (max(1, round(im.width * scale)), max(1, round(im.height * scale)))
        r = np.asarray(Image.fromarray((pm * 255).astype(np.uint8), "RGBA").resize(size, Image.BOX)).astype(np.float32) / 255
        al2 = r[..., 3:4]
        rgb = np.where(al2 > 1e-3, r[..., :3] / np.maximum(al2, 1e-3), 0)
        f = np.concatenate([np.clip(rgb, 0, 1), (al2 > 0.5).astype(np.float32)], -1)
        im = Image.fromarray((f * 255).astype(np.uint8), "RGBA")
    else:
        f = np.asarray(im).copy()
        f[..., 3] = np.where(f[..., 3] > 127, 255, 0)
        im = Image.fromarray(f, "RGBA")
    return bleed(im)


def cut(sheet, image, args):
    """Every cell of one returned sheet -> {tag: (image, ground_offset)}."""
    im = Image.open(image).convert("RGB")
    W, H = im.size
    px_per_m = sheet["cells"][0]["px_per_m"] * W / sheet["width"]
    scale = (args.height / 1.80) / px_per_m
    out = {}
    for c in sheet["cells"]:
        x0, y0, x1, y1 = c["figure"]
        # inside the grid lines
        bx0, by0, bx1, by1 = int(x0 * W) + 3, int(y0 * H) + 2, int(x1 * W) - 3, int(y1 * H) - 3
        rgb = np.asarray(im.crop((bx0, by0, bx1, by1)))
        key = [int(args.key[i:i + 2], 16) for i in (0, 2, 4)] if args.key else border_key(rgb)
        a = key_alpha(rgb, key)
        a = despeckle(a, max(4, int(0.0004 * a.shape[0] * a.shape[1])))
        opaque = a[..., 3] > 127
        if not opaque.any():
            print("  %s: nothing in the cell" % c["tag"])
            continue
        ys, xs = np.nonzero(opaque)
        t, b, l, r = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        fig = shrink(a[t:b, l:r], scale)
        ground = (c["ground"] * H - by0 - b) * scale  # the figure's bottom above the ground line, in strip px
        out[c["tag"]] = (fig, ground, c)
    print("%s: %d cells, %.3f px/px, key %s" % (os.path.basename(image), len(out), scale, "measured" if not args.key else args.key))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("name")
    ap.add_argument("images", nargs="+")
    ap.add_argument("--manifest", default=os.path.join(HERE, "out"))
    ap.add_argument("--cells")
    ap.add_argument("--height", type=float, default=60.0)
    ap.add_argument("--cell", type=int, default=64)
    ap.add_argument("--no-strip", action="store_true")
    ap.add_argument("--strip", help="the strip's path (default assets/people/<name>.png)")
    ap.add_argument("--key", help="RRGGBB ground colour; default measured")
    ap.add_argument("--profile", choices=("mewd", "doom", "mewd-civ", "civ", "mewd-civ-noprops", "civ-noprops"), default="mewd",
                    help="which profile's manifest to cut a sheet name two profiles share by (default mewd; "
                         "a civ- sheet falls to mewd-civ)")
    args = ap.parse_args()
    name = args.name.upper()
    sheets = []
    for j in sorted(glob.glob(os.path.join(args.manifest, "sheet*.json")) + glob.glob(os.path.join(args.manifest, "*", "sheet*.json"))):
        m = json.load(open(j))
        sheets.append(dict(m["sheets"][0], profile=m.get("profile", ""), kind=m.get("kind", "troop")))
    if not sheets:
        sys.exit("no sheet manifests under %s: run pose_sheet.py first" % args.manifest)
    cells = {}
    used = []
    for image in args.images:
        base = os.path.basename(image)
        match = [s for s in sheets if ("sheet%02d-%s" % (s["sheet"], s["name"])) in base]
        if not match:
            names = sorted({"sheet%02d-%s" % (s["sheet"], s["name"]) for s in sheets})
            sys.exit("%s: which sheet is it? name the file after one of: %s" % (base, ", ".join(names)))
        if len(match) > 1:
            # the same sheet in two profiles: the one the picture is the
            # exact size of, else the profile asked for (a civilian
            # sheet under the civilian twin of it), else the shape
            W, H = Image.open(image).size
            want = args.profile
            if match[0]["kind"] == "civilian" and "civ" not in want:
                want = want + "-civ" if want == "mewd" else "civ"
            exact = [s for s in match if (s["width"], s["height"]) == (W, H)]
            prof = [s for s in match if s["profile"] == want]
            match = exact or prof or match
            match.sort(key=lambda s: abs((s["width"] / s["height"]) / (W / H) - 1))
        used.append(match[0])
        cells.update(cut(match[0], image, args))
    # the strip's letters: the whole profile's, so a sheet not given is
    # reported missing rather than silently left out
    profile = used[0]["profile"]
    TURN, FLAT = letters_of([s for s in sheets if s["profile"] == profile])
    kind = used[0]["kind"]
    if args.cells:
        os.makedirs(args.cells, exist_ok=True)
        for tag, (fig, ground, c) in cells.items():
            fn = "%s%s%d.png" % (name, c["letter"], c["view"]) if c["letter"] else "%s_%s_%d_%d.png" % (name, c["anim"], c["frame"], c["view"])
            fig.save(os.path.join(args.cells, fn))
        print("%d cells in %s" % (len(cells), args.cells))
    if args.no_strip:
        return
    # the strip
    n = len(TURN) * VIEWS + len(FLAT)
    S = args.cell
    strip = Image.new("RGBA", (S * n, S), (0, 0, 0, 0))
    missing, over = [], []
    slots = [(l, v) for l in TURN for v in range(1, VIEWS + 1)] + [(l, 0) for l in FLAT]
    for k, (letter, view) in enumerate(slots):
        tag = "%s%d" % (letter, view) if view else letter
        if tag not in cells:
            missing.append(tag)
            continue
        fig, ground, c = cells[tag]
        if fig.width > S or fig.height > S:
            over.append("%s %dx%d" % (tag, fig.width, fig.height))
            fig.thumbnail((S, S), Image.NEAREST)
        y = S - fig.height
        if c["air"]:
            y = max(0, int(round(S - fig.height - ground)))
        strip.alpha_composite(fig, (k * S + (S - fig.width) // 2, y))
    path = args.strip or os.path.join(ROOT, "assets", "people", name.lower() + ".png")
    strip.save(path, optimize=True)
    print("%s: %d cells of %dx%d (%dx%d)" % (os.path.relpath(path, ROOT), n, S, S, strip.width, strip.height))
    if missing:
        print("  not covered by the images given, left clear: %s" % ", ".join(missing))
    if over:
        print("  too big for the cell, shrunk to fit (lower --height?): %s" % ", ".join(over))
    if kind == "civilian":
        print("  a civilian strip (walk %s, flee %s, stand %s, cower %s, hands up %s; death %s, gibs %s): the game has no"
              " state table for one yet (states.gd _troop is the troops'); its TROOPS-shaped line would be:"
              % (TURN[0:4], TURN[4:8], TURN[8], TURN[9], TURN[10], FLAT[:7], FLAT[7:]))
    else:
        print("  states.gd TROOPS line:")
    print('    "%s": {"sprite": "%s", "turn": "%s", "flat": "%s", "views": %d, "strip": "%s"},' % (name, name, TURN, FLAT, VIEWS, name.lower()))
    print("  standees.gd _ready:")
    print('    _strip("%s", "res://assets/people/%s.png", Vector2(%d, %d))' % (name, name.lower(), S, S))


if __name__ == "__main__":
    main()
