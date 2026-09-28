#!/usr/bin/env python3
"""
MEWD — bring the vandre project's plants and ground over

    tools/prep-vandre.py /path/to/vandre

The user's Godot project, github.com/verdictzero/vandre, has a set of
biomes — desert, meadow, pine barrens, savanna, wasteland, farmland,
tundra, arctic — each with a checkered ground texture and a handful of
painted plant sprites. They are the user's own, and this turns them into
the two formats this game already has for those two things, so the
editor can put them down like any other:

  THE GROUND goes into the texture pack (js/texpack.js): every picture
  in vandre/assets/textures/terrain and every *_terrain_checkered.png in
  vandre/assets/biomeAssetsNewFormat, as assets/textures/NAME.png under
  a Doom-style name of eight characters or fewer, in the group
  "vandre/terrain" (the grounds) or "vandre/city" (the metal and
  concrete plates). They go through build-texpack.py's own prepare() —
  an empty alpha dropped, saved optimised — and are worn at the pack's
  scale, two pixels to the unit, so a 256-pixel checker is 128 units
  and one square of it is 64, a floor cell. Their rows are merged into
  js/texpack-data.js (build-texpack.py carries them over when it
  regenerates that file from the archives). Two pictures in the terrain
  folder are the same picture as another — grass_checkered.png is
  new_meadow_grass_checkered_v5.png, and grass_checkered_legacy.tga is
  the .png beside it — and each goes in once.

  THE PLANTS go into assets/forest as the pair every plant in the wood
  is (js/forest.js): an ALBEDO and a BURN MAP, made exactly the way
  tools/bake-plants.mjs makes them for the street trees — cropped to the
  artwork, resampled carrying alpha, alpha thresholded, and the burn map
  worked out from the albedo (green is leaf, the rest is wood, fire
  climbs from the foot). The artwork is already cut out, so there is no
  chroma key. The tile is a power of two on each side, the nearest to
  the artwork's own proportions with its long side at most 256 and no
  more texels than a fir of the wood's (128 by 256), so a fern that is
  twice as wide as it is tall is 256 by 128, a fir is 128 by 256 like
  the wood's own and a round crown is 128 square (256 if it was painted
  big: the meadow's great trees and the wasteland's); the true proportions
  go in KINDS as `aspect`. The .tga meadow set is read by Pillow like the rest.

  WHAT IS NOT DONE HERE is the KINDS rows themselves: how tall a plant
  stands and whether it blocks is a decision, and it is made in
  js/forest.js. This prints each plant's name, tile and aspect so the
  rows can be checked against it.

Skipped: *.import (Godot's), the empty biome folders, and
sprites/foliage/new_meadow/__old (the superseded meadow set).

Needs Pillow and numpy. The output is committed; this is here so it can
be made again.
"""
import importlib.util, json, math, os, re, sys
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
TEX = os.path.join(ROOT, 'assets', 'textures')
FOREST = os.path.join(ROOT, 'assets', 'forest')
DATA = os.path.join(ROOT, 'js', 'texpack-data.js')

# build-texpack.py's own picture handling, so the pack is one format
_spec = importlib.util.spec_from_file_location('build_texpack', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build-texpack.py'))
BT = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(BT)

# ---------------------------------------------------------------- ground
# (file under vandre/assets, pack name, group)
TERRAIN = [
    ('biomeAssetsNewFormat/arctic/arctic_terrain_checkered.png',               'ARCTIC1',  'vandre/terrain'),
    ('biomeAssetsNewFormat/farmland/farmland_terrain_checkered.png',           'FARMLND1', 'vandre/terrain'),
    ('biomeAssetsNewFormat/frozen_tundra/frozen_tundra_terrain_checkered.png', 'FROZEN1',  'vandre/terrain'),
    ('biomeAssetsNewFormat/tundra/tundra_terrain_checkered.png',               'TUNDRA1',  'vandre/terrain'),
    ('textures/terrain/candyland_terrain_checkered.png',                       'CANDY1',   'vandre/terrain'),
    ('textures/terrain/grass_checkered.jpg',                                   'GRASCHK1', 'vandre/terrain'),
    ('textures/terrain/grass_checkered_legacy.png',                            'GRASCHK2', 'vandre/terrain'),  # = the .tga
    ('textures/terrain/molten_checkered.png',                                  'MOLTEN1',  'vandre/terrain'),
    ('textures/terrain/new_meadow_grass_checkered.png',                        'MEADOW1',  'vandre/terrain'),
    ('textures/terrain/new_meadow_grass_checkered_v2.png',                     'MEADOW2',  'vandre/terrain'),
    ('textures/terrain/new_meadow_grass_checkered_v3.png',                     'MEADOW3',  'vandre/terrain'),
    ('textures/terrain/new_meadow_grass_checkered_v4.png',                     'MEADOW4',  'vandre/terrain'),
    ('textures/terrain/new_meadow_grass_checkered_v5.png',                     'MEADOW5',  'vandre/terrain'),  # = grass_checkered.png
    ('textures/terrain/pine_barrens_terrain.png',                              'PINEBAR1', 'vandre/terrain'),
    ('textures/terrain/sand_checkered.jpg',                                    'SAND1',    'vandre/terrain'),
    ('textures/terrain/savanna_grass_terrain.png',                             'SAVANNA1', 'vandre/terrain'),
    ('textures/terrain/wasteland_terrain.png',                                 'WASTE1',   'vandre/terrain'),
    ('textures/terrain/city_concrete_plate.jpg',                               'CITYCON1', 'vandre/city'),
    ('textures/terrain/city_metal_plate.jpg',                                  'CITYMET1', 'vandre/city'),
    ('textures/terrain/city_metal_plate_2.jpg',                                'CITYMET2', 'vandre/city'),
    ('textures/terrain/city_skirt_metal_plate.jpg',                            'CITYSKRT', 'vandre/city'),
]

# ---------------------------------------------------------------- plants
# (file under vandre/assets, KINDS name). The name is the file name in
# assets/forest and the KINDS name in js/forest.js, the same string on
# purpose, as bake-plants.mjs has it: the biome, then the vandre stem.
F = 'sprites/foliage/'
PLANTS = [
    *[(F + 'desert/' + s + '.png', 'desert_' + s.replace('desert_', '')) for s in
      ['big_cactus_1', 'cactus_5', 'cactus_6', 'creosote_bush_5', 'creosote_bush_6', 'dead_creosote_bush_5',
       'dead_creosote_bush_6', 'desert_bush_1', 'desert_bush_2', 'small_cactus_1', 'small_cactus_2']],
    *[(F + 'meadow/' + s + '.tga', 'meadow_' + s.lower()) for s in
      ['bush_var_A', 'bush_var_B', 'grass_var_A', 'grass_var_B', 'tree_big', 'tree_medium', 'tree_really_big']],
    *[(F + 'new_meadow/' + s + '.png', 'new_meadow_' + s.replace('new_meadow_', '').replace('_inter', '')) for s in
      ['fern_1_inter', 'fern_2_inter', 'fern_3_inter', 'fern_4_inter', 'new_meadow_bush_1', 'new_meadow_bush_2',
       'new_meadow_bush_3', 'new_meadow_bush_4', 'new_meadow_flower_1', 'new_meadow_flower_2', 'new_meadow_grass_1',
       'new_meadow_grass_2', 'new_meadow_grass_tall_1', 'new_meadow_tree_1', 'new_meadow_tree_2', 'new_meadow_tree_3']],
    *[(F + 'new_pine_barrens/' + s + '.png', 'pine_' + s) for s in
      ['fern_1', 'fern_2', 'fern_3', 'fern_4', 'fir_tree_1', 'fir_tree_2', 'fir_tree_3', 'fir_tree_4', 'forest_bush_1',
       'forest_bush_2', 'forest_bush_3', 'juvenile_fir_tree_1', 'juvenile_fir_tree_2', 'juvenile_fir_tree_4']],
    (F + 'pine_barrens/pine_barrens_tree.png', 'pine_barrens_tree'),
    *[(F + 'savanna/' + s + '.png', s.replace('grasss', 'grass')) for s in
      ['savanna_grass_short_1', 'savanna_grass_short_2', 'savanna_grass_tall_1', 'savanna_grasss_tall_2', 'savanna_tree_1']],
    *[(F + 'wasteland/' + s + '.png', s) for s in
      ['wasteland_bush_1', 'wasteland_small_tree_1', 'wasteland_tree', 'wasteland_tree_big_2', 'wasteland_tree_big_3',
       'wasteland_tree_small_2']],
    *[('biomeAssetsNewFormat/farmland/wheat_plant_%d.png' % i, 'farm_wheat_%d' % i) for i in range(1, 5)],
    *[('biomeAssetsNewFormat/tundra/tundra_bush_%d.png' % i, 'tundra_bush_%d' % i) for i in range(1, 6)],
]
TILE_MAX = 256
TILE_AREA = 128 * 256


def alpha_bounds(a):
    """The opaque box, ignoring a few stray texels at the edges (as
    bake-plants.mjs's alphaBounds does)."""
    m = a[..., 3] >= 128
    col, row = m.sum(0), m.sum(1)
    def span(v, lo=3):
        idx = np.nonzero(v > lo)[0]
        return (int(idx[0]), int(idx[-1])) if len(idx) else (0, len(v) - 1)
    x0, x1 = span(col); y0, y1 = span(row)
    return x0, y0, x1, y1


def pow2(v):
    return max(32, 2 ** int(round(math.log2(max(1, v)))))


def tile_for(w, h):
    """No bigger than the wood's firs, 128 by 256: a square plant is 128
    square like the wood's bushes, a wide one 256 by 128."""
    s = min(1.0, TILE_MAX / max(w, h))
    W, H = pow2(w * s), pow2(h * s)
    # a big crown painted at 512 keeps 256 square: it stands taller than
    # any fir, and a 128 tile would be a blur at the foot of it
    cap = 256 * 256 if min(w, h) >= 250 else TILE_AREA
    while W * H > cap:
        if W == H: W, H = W // 2, H // 2
        elif W > H: W //= 2
        else: H //= 2
    return W, H


def resample(im, W, H):
    """Colour weighted by coverage (premultiplied), a box filter, and the
    alpha thresholded once: the renderer alpha-tests at 0.5 and a soft
    edge is a hard edge in a random place."""
    pm = im.convert('RGBa').resize((W, H), Image.BOX)
    a = np.asarray(pm.convert('RGBA')).copy()
    cov = np.asarray(pm)[..., 3]
    a[..., 3] = np.where(cov > 110, 255, 0)
    a[a[..., 3] == 0, :3] = 0
    return a


def noise(x, y, seed):
    s = np.sin(x * 127.1 + y * 311.7 + seed) * 43758.5453
    return s - np.floor(s)


def burn_map(al):
    """bake-plants.mjs's burnMap: R coals, G char, B order (when it
    catches — distance from the foot, with a little noise), A foliage."""
    h, w = al.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    r, g, b = (al[..., i].astype(np.float64) for i in range(3))
    leaf = np.clip((g - np.maximum(r, b) * 0.86) / 26, 0, 1)
    fx, fy = w / 2, h - 1
    far = math.hypot(max(fx, w - fx), h)
    d = np.hypot((x - fx) * 0.72, (y - fy)) / far
    jit = (noise(x, y, 11) - 0.5) * 0.10 + (noise(np.floor(x / 8), np.floor(y / 8), 29) - 0.5) * 0.16
    order = np.clip(d * (1.35 if w == h else 1.06) + jit, 0, 1)
    out = np.zeros((h, w, 4), np.uint8)
    on = al[..., 3] >= 128
    out[..., 0] = np.where(on, np.round(255 * (0.30 + 0.55 * (1 - leaf))), 0)
    out[..., 1] = np.where(on, np.round(255 * (0.55 + 0.45 * leaf)), 0)
    out[..., 2] = np.where(on, np.round(255 * order), 0)
    out[..., 3] = np.where(on, np.round(255 * leaf), 0)
    return out


def do_terrain(src):
    rows = []
    for rel, name, group in TERRAIN:
        p = os.path.join(src, rel)
        im, changed, masked, shrunk = BT.prepare(p, False)
        dst = os.path.join(TEX, name + '.png')
        BT.save_small(im, dst, p if (not changed and p.endswith('.png')) else None)
        rows.append([name, im.width, im.height, 0.5 * shrunk, 1 if masked else 0, group])
        print(f'{name:9s} {im.width}x{im.height} {os.path.getsize(dst) // 1024:4d} KB  {group:15s} <- {rel}')
    # merge into the list build-texpack.py wrote: ours replaced, in name order
    txt = open(DATA).read()
    body = re.search(r'export const PACK_LIST = \[\n(.*?)\];', txt, re.S).group(1)
    old = [json.loads(l.strip().rstrip(',')) for l in body.splitlines() if l.strip()]
    mine = {r[0] for r in rows}
    allrows = sorted([r for r in old if r[0] not in mine] + rows, key=lambda r: r[0])
    new_body = ''.join('  ' + json.dumps(r) + ',\n' for r in allrows)
    txt = txt.replace(body, new_body)
    open(DATA, 'w').write(txt)
    print(f'{len(rows)} textures into the pack, {len(allrows)} in it now')


def do_plants(src):
    tot = 0
    for rel, name in PLANTS:
        im = Image.open(os.path.join(src, rel)).convert('RGBA')
        a = np.asarray(im)
        x0, y0, x1, y1 = alpha_bounds(a)
        crop = im.crop((x0, y0, x1 + 1, y1 + 1))
        W, H = tile_for(crop.width, crop.height)
        al = resample(crop, W, H)
        bm = burn_map(al)
        for suffix, arr in (('', al), ('_burn', bm)):
            dst = os.path.join(FOREST, f'{name}{suffix}.png')
            Image.fromarray(arr, 'RGBA').save(dst, optimize=True)
            tot += os.path.getsize(dst)
        solid = (al[..., 3] > 128).mean() * 100
        print(f'{name:28s} artwork {crop.width}x{crop.height} -> {W}x{H}, aspect {crop.width / crop.height:.3f}, {solid:.0f}% plant')
    print(f'{len(PLANTS)} plants, {2 * len(PLANTS)} files into assets/forest, {tot / 1e6:.2f} MB')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: prep-vandre.py /path/to/vandre')
    src = os.path.join(sys.argv[1], 'assets')
    do_terrain(src)
    do_plants(src)
