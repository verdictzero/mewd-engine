#!/usr/bin/env python3
"""
MEWD — build the texture pack

    tools/build-texpack.py SRC [SRC ...]

Each SRC is a folder of PNGs the user handed over (the Archive.zip and
textures.7z sets, unpacked). Everything in it, at any depth, goes into
assets/textures as NAME.png; the folder it sat in becomes its GROUP in
the editor's texture browser. Six faces of a skybox (NAME_up, _dn, _fr
or _ft, _bk, _lf, _rt, with or without a trailing 2) are not textures:
they are turned into ONE panorama each in assets/skies, which is what the
sky sphere wears (js/sky.js). Then js/texpack-data.js is written, the
list js/texpack.js reads — keeping the rows tools/prep-vandre.py put in
it (group vandre/...), which come from another repository.

WHAT IS DONE TO A PICTURE ON THE WAY, and it is only ever lossless or
a resize:
  - an alpha channel with nothing in it is dropped
  - anything longer than MAX_SIDE on a side is halved until it is not
  - it is saved optimised, and kept in whichever of the two encodings
    (as it was, or re-encoded) is smaller
  - an animation run longer than PALETTE_RUN frames is palettised to 256
    colours, frame by frame, and halved if it is wider than 512: a
    75-frame test pattern at full size and colour is 24 megabytes, and
    at 423 by 240 in 256 colours it is a test pattern still

THE SKYBOXES are joined by LOOKING, not by trusting their names: every
tool that ever wrote one had its own idea of which face is "left". The
four sides are put in the order whose touching edges match best, and the
top and bottom are turned, of the eight ways they can be, to the one that
meets the sides. A box with alpha in it is laid on black.

Needs Pillow and numpy. The output is committed; this is here so it can
be made again.
"""
import json, os, re, sys
from itertools import permutations
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
TEX = os.path.join(ROOT, 'assets', 'textures')
SKY = os.path.join(ROOT, 'assets', 'skies')
DATA = os.path.join(ROOT, 'js', 'texpack-data.js')
MAX_SIDE = 2048
PALETTE_RUN = 30
SKY_W, SKY_H = 2048, 1024

# The first archive was flat: its groups, by what the pictures are.
FLAT_GROUPS = [
    (r'^(CONC_|XTX_|DIAG_|CAUTSTR|PARKLOT)', 'concrete'),
    (r'^(DEVPAN|DR1_|EYEDO|REACTB|OP|TERMPAN|KEYBOARD|MONITOR|REDLIGHT|DOOR0)', 'ops room'),
    (r'^(GRASS[0-9]|IVY|LAWNTEST|MOSS|DIRT_|ROCK_)', 'nature'),
    (r'^(CLOUDS|MNTN|TREELINE|RUINLINE)', 'background'),
]
# World units per pixel: the pack is drawn at twice Doom's resolution,
# except where a picture says otherwise (see js/texpack.js).
ONE_TO_ONE = re.compile(r'^(DR1_|\d+TEST$|DEBUG\d+$|OFCCUB02$)')
SKY_FACE = re.compile(r'^(.*?)[_]?(up|dn|fr|ft|bk|lf|rt)2?$', re.I)


def group_of(rel, name):
    d = os.path.dirname(rel).replace(os.sep, '/')
    if d:
        return d.split('/', 1)[-1] if d.startswith('textures/') else d
    for pat, g in FLAT_GROUPS:
        if re.match(pat, name):
            return g
    return 'misc'


def save_small(im, dst, src_path=None):
    im.save(dst, optimize=True)
    if src_path and os.path.getsize(src_path) < os.path.getsize(dst):
        with open(src_path, 'rb') as f, open(dst, 'wb') as g:
            g.write(f.read())


def prepare(path, palettise):
    im = Image.open(path)
    im.load()
    orig_w = im.width
    changed = False
    if im.mode == 'P' and 'transparency' in im.info:
        im = im.convert('RGBA'); changed = True
    elif im.mode not in ('RGB', 'RGBA', 'P', 'L'):
        im = im.convert('RGBA'); changed = True
    if im.mode == 'RGBA':
        a = np.asarray(im)[..., 3]
        if a.min() == 255:
            im = im.convert('RGB'); changed = True
    while max(im.size) > MAX_SIDE:
        im = im.resize((im.width // 2, im.height // 2), Image.NEAREST); changed = True
    if palettise and im.width > 512:
        im = im.resize((im.width // 2, im.height // 2), Image.NEAREST); changed = True
    if palettise and im.mode == 'RGB':
        im = im.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE); changed = True
    masked = False
    if im.mode == 'RGBA':
        masked = bool((np.asarray(im)[..., 3] < 128).any())
    return im, changed, masked, orig_w / im.width


# ---------------------------------------------------------------- skies
def variants(a):
    out = []
    for f in (False, True):
        b = a[:, ::-1] if f else a
        for r in range(4):
            out.append(np.rot90(b, r))
    return out


def build_pano(ring, up, dn, W, H):
    n = ring[0].shape[0]
    j, i = np.mgrid[0:H, 0:W]
    th = (i + 0.5) / W * 2 * np.pi - np.pi / 4
    ph = np.pi / 2 - (j + 0.5) / H * np.pi
    x = np.cos(ph) * np.sin(th); y = np.sin(ph); z = np.cos(ph) * np.cos(th)
    out = np.zeros((H, W, 3), np.float32); fid = np.full((H, W), -1)
    k = np.floor((th + np.pi / 4) / (np.pi / 2)).astype(int) % 4
    a = th - k * np.pi / 2
    a = (a + np.pi) % (2 * np.pi) - np.pi
    u = np.tan(a); v = np.tan(ph) / np.cos(a)
    side = np.abs(v) <= 1
    for f in range(4):
        m = side & (k == f)
        c = ((u[m] + 1) / 2 * n).clip(0, n - 1).astype(int)
        r = ((1 - v[m]) / 2 * n).clip(0, n - 1).astype(int)
        out[m] = ring[f][r, c]; fid[m] = f
    for img, sgn, fi in ((up, 1, 4), (dn, -1, 5)):
        m = (~side) & (np.sign(y) == sgn)
        c = ((x[m] / abs(y[m]) + 1) / 2 * n).clip(0, n - 1).astype(int)
        r = ((1 - sgn * z[m] / abs(y[m])) / 2 * n).clip(0, n - 1).astype(int)
        out[m] = img[r, c]; fid[m] = fi
    return out, fid


def seam(out, fid, which):
    dv = np.abs(out[1:] - out[:-1]).mean(-1)
    ch = (fid[1:] != fid[:-1]) & ((fid[1:] == which) | (fid[:-1] == which))
    return dv[ch].mean() if ch.any() else 0


def load_face(p):
    im = Image.open(p).convert('RGBA')
    a = np.asarray(im).astype(np.float32)
    return a[..., :3] * (a[..., 3:] / 255.0)          # laid on black


def make_sky(name, faces):
    F = {k: load_face(p) for k, p in faces.items()}
    front = 'fr' if 'fr' in F else 'ft'
    others = [k for k in ('bk', 'lf', 'rt')]
    d = lambda a, b: np.abs(a - b).mean()
    best = None
    if 'rt' not in F:
        # A BOX WITH A SIDE MISSING (nsky1 came without its rt). The side
        # is made from the two it sits between, in the order every other
        # box in the pack has (front, left, back, right): the back
        # mirrored, so its right edge is this one's left, faded into the
        # front mirrored, so its left edge is this one's right.
        n = F[front].shape[1]
        w = np.linspace(0, 1, n)[None, :, None]
        F['rt'] = (1 - w) * F['bk'][:, ::-1] + w * F[front][:, ::-1]
        print(f'sky {name}: no rt face, made from bk and {front}')
        best = (0, [front, 'lf', 'bk', 'rt'], False)
    for flip in (False, True):
        for p in (permutations(others) if best is None or best[0] else []):
            ring = [front, *p]
            fs = [F[k][:, ::-1] if flip else F[k] for k in ring]
            s = sum(d(fs[i][:, -1], fs[(i + 1) % 4][:, 0]) for i in range(4))
            if best is None or s < best[0]:
                best = (s, ring, flip)
    _, order, flip = best
    ring = [F[k][:, ::-1] if flip else F[k] for k in order]
    U, D = variants(F['up']), variants(F['dn'])
    small = [r[::4, ::4] for r in ring]
    Us, Ds = [u[::4, ::4] for u in U], [x[::4, ::4] for x in D]
    cu = [seam(*build_pano(small, u, Ds[0], 512, 256), 4) for u in Us]
    cd = [seam(*build_pano(small, Us[0], x, 512, 256), 5) for x in Ds]
    out, _ = build_pano(ring, U[int(np.argmin(cu))], D[int(np.argmin(cd))], SKY_W, SKY_H)
    im = Image.fromarray(out.clip(0, 255).astype(np.uint8))
    arr = np.asarray(im)
    if arr.max() - arr.min() < 8:                    # a flat colour: no need for the size
        im = im.resize((512, 256), Image.NEAREST)
    im.save(os.path.join(SKY, name + '.png'), optimize=True)
    print(f'sky {name}: ring {order}{" flipped" if flip else ""}, seams up {min(cu):.1f} dn {min(cd):.1f}')
    return name


# ---------------------------------------------------------------- main
def main(srcs):
    os.makedirs(TEX, exist_ok=True); os.makedirs(SKY, exist_ok=True)
    found = {}
    for src in srcs:
        for r, _, fs in os.walk(src):
            for f in sorted(fs):
                if f.lower().endswith('.png'):
                    p = os.path.join(r, f)
                    found[os.path.splitext(f)[0]] = (p, os.path.relpath(p, src))
    # the skyboxes first: six faces with the same stem
    boxes = {}
    for n, (p, rel) in found.items():
        m = SKY_FACE.match(n)
        if m and ('sky' in rel.lower() or 'SKY' in n.upper()):
            face = m.group(2).lower()
            boxes.setdefault(m.group(1).rstrip('_').upper(), {})[face] = p
    skies = []
    for name, faces in sorted(boxes.items()):
        if len(faces) >= 5 and {'up', 'dn', 'bk', 'lf'} <= faces.keys() and faces.keys() & {'fr', 'ft'}:
            skies.append(make_sky(name, faces))
            for p in faces.values():
                found = {k: v for k, v in found.items() if v[0] != p}
    # the runs: a stem and a number, more than one of them
    names = sorted(found)
    stems = {}
    for n in names:
        m = re.match(r'^(.*?)(\d+)$', n)
        if m:
            stems.setdefault(m.group(1), []).append(n)
    rows = []
    for n in names:
        p, rel = found[n]
        run_len = next((len(v) for s, v in stems.items() if n in v), 1)
        im, changed, masked, shrunk = prepare(p, run_len > PALETTE_RUN)
        dst = os.path.join(TEX, n + '.png')
        if changed:
            save_small(im, dst)
        else:
            save_small(im, dst, p)
        # a picture made smaller covers the wall it did before, in
        # bigger texels: its scale is of the picture as it was drawn
        k = (1 if ONE_TO_ONE.match(n) else 0.5) * shrunk
        rows.append([n, im.width, im.height, k, 1 if masked else 0, group_of(rel, n)])
    # the vandre project's ground (tools/prep-vandre.py) is not in the
    # archives: its rows are carried over from the list as it stands, so
    # rebuilding the pack does not drop them
    if os.path.exists(DATA):
        have = {r[0] for r in rows}
        body = re.search(r'PACK_LIST = \[\n(.*?)\];', open(DATA).read(), re.S)
        for l in (body.group(1).splitlines() if body else []):
            r = json.loads(l.strip().rstrip(',')) if l.strip() else None
            if r and r[5].startswith('vandre/') and r[0] not in have:
                rows.append(r)
        rows.sort(key=lambda r: r[0])
    with open(DATA, 'w') as f:
        f.write('/* GENERATED by tools/build-texpack.py — do not edit by hand.\n'
                '   [name, width px, height px, world units per px, masked, group] */\n')
        f.write('export const PACK_LIST = [\n')
        for r in rows:
            f.write('  ' + json.dumps(r) + ',\n')
        f.write('];\n')
        f.write('export const PACK_SKIES = ' + json.dumps(skies) + ';\n')
    tot = sum(os.path.getsize(os.path.join(TEX, r[0] + '.png')) for r in rows)
    print(f'{len(rows)} textures, {tot / 1e6:.1f} MB; {len(skies)} skies')


if __name__ == '__main__':
    main(sys.argv[1:])
