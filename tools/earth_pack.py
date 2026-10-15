#!/usr/bin/env python3
"""MEWD — the look of a real place: high-resolution PBR ground and plants.

    python3 tools/earth_pack.py textures     # the twelve ground layers
    python3 tools/earth_pack.py models       # the plants' 3D models (cache only)
    python3 tools/earth_pack.py billboards   # render them (Godot, xvfb) and finish
    python3 tools/earth_pack.py all

At the user's request: "high res pbr textures on the map, but still use
billboard vegetation, albeit high res". Everything here is CC0, from Poly
Haven (polyhaven.com) and ambientCG (ambientcg.com), and lands in
godot/island/earth/:

  textures/TEX_earth_albedo.webp   the twelve layers' colour (RGB) and height
                                   (A), 2048 px each, four across and three
                                   down: a Texture2DArray of twelve
  textures/TEX_earth_nra.webp      their normal (RG, OpenGL convention),
                                   roughness (B) and ambient occlusion (A),
                                   laid out the same
  textures/TEX_earth_rock_*.webp   the rock layer on its own, for the cliff
  textures/TEX_earth_water_normal.png  a tiling wave normal map, made here
  sprites/SPRITE_earth_*.png       the plants, rendered side-on from the
                                   models at 1024 px (trees) and 512 px, with
                                   a `_burn.png` beside each for the
                                   billboard shader's fire

The layer order is tools/earth_fetch.py's LAYERS and EarthField's L_*.
`--res 1k` halves every texture, for a lighter build.

Models are fetched into tools/.earth-cache/models/ and never committed; only
the rendered sprites are. Rendering needs Godot 4.7 (`godot` on the PATH or
$GODOT) and a display, or xvfb-run.

Needs numpy and Pillow."""
import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

try:
    import numpy as np
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("earth_pack: needs numpy and Pillow (pip install numpy pillow)")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".earth-cache")
OUT = os.path.join(ROOT, "godot", "island", "earth")
UA = {"User-Agent": "mewd-engine-earth/1.0 (+https://github.com/verdictzero/mewd-engine)"}

# (layer, source, asset, metres a tile covers on the ground)
LAYERS = [
    ("grass", "acg", "Grass004", 3.0),
    ("forest", "ph", "forrest_ground_01", 3.5),
    ("rock", "acg", "Rock030", 8.0),
    ("scree", "ph", "gray_rocks", 4.0),
    ("sand", "ph", "coast_sand_01", 4.0),
    ("soil", "ph", "brown_mud_dry", 3.5),
    ("snow", "ph", "snow_01", 5.0),
    ("mud", "ph", "brown_mud_02", 3.5),
    ("paving", "ph", "asphalt_02", 4.0),
    ("dry", "acg", "Ground037", 3.5),
    ("moss", "ph", "mossy_rock", 4.0),
    ("bed", "ph", "ganges_river_pebbles", 2.5),
]

# (Left out, having been tried: shrub_01 and shrub_04, a row of small
# plants in one mesh that cannot be drawn one at a time; wild_rooibos_bush,
# whose leaves render black; grass_bermuda_01, whose first part is a flat
# card of dead grass; the third tuft of grass_medium_01, whose curled
# leaf tips render black and stood out in the meadows as black tufts.)
#
# The plants: (Poly Haven model, class, the yaws it is drawn from, sprite
# size, how far the camera looks down in degrees, how many of the plants
# in it to draw — Poly Haven ships its shrubs and grasses several to a
# model, side by side). The classes are
# VegScatter's: conifer and broadleaf trees, bushes, ferns (the low growth),
# grass (GrassScatter's tufts).
PLANTS = [
    ("fir_tree_01", "conifer", (0, 120, 240), (512, 1024), 0, 1),
    ("fir_sapling_medium", "conifer", (0,), (512, 1024), 0, 3),
    ("pine_sapling_small", "conifer", (0,), (512, 1024), 0, 2),
    ("island_tree_01", "broadleaf", (0, 120), (1024, 1024), 0, 1),
    ("island_tree_02", "broadleaf", (0, 120), (1024, 1024), 0, 1),
    ("island_tree_03", "broadleaf", (0,), (1024, 1024), 0, 1),
    ("fir_sapling", "bush", (0,), (512, 512), 4, 3),
    ("searsia_lucida", "bush", (0, 120), (512, 512), 6, 1),
    ("didelta_spinosa", "bush", (0,), (512, 512), 6, 2),
    ("shrub_02", "bush", (0,), (512, 512), 6, 2),
    ("shrub_03", "bush", (0,), (512, 512), 6, 1),
    ("fern_02", "fern", (0,), (512, 512), 10, 3),
    ("nettle_plant", "fern", (0,), (512, 512), 10, 1),
    ("celandine_01", "fern", (0,), (512, 512), 10, 1),
    ("grass_medium_01", "grass", (0,), (512, 256), 8, 2),
    ("grass_medium_02", "grass", (0,), (512, 256), 8, 2),
    ("dandelion_01", "grass", (0,), (512, 256), 8, 1),
]


def log(*a):
    print("earth_pack:", *a, flush=True)


def get(url, path=None):
    if path and os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    for i in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=600) as r:
                body = r.read()
            break
        except Exception as e:
            if i == 4:
                raise
            log("retrying %s (%s)" % (url, e))
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".part", "wb") as f:
            f.write(body)
        os.replace(path + ".part", path)
    return body


# ------------------------------------------------------------------ textures

def _maps_ph(asset, res):
    files = json.loads(get("https://api.polyhaven.com/files/" + asset))
    out = {}
    for key, name in (("Diffuse", "color"), ("nor_gl", "normal"), ("Rough", "rough"),
                      ("AO", "ao"), ("Displacement", "height")):
        if key not in files:
            continue
        url = files[key][res]["jpg"]["url"]
        out[name] = Image.open(io.BytesIO(get(url, os.path.join(CACHE, "tex", asset, url.split("/")[-1]))))
    return out


def _maps_acg(asset, res):
    res = res.upper()
    z = get("https://ambientcg.com/get?file=%s_%s-JPG.zip" % (asset, res),
            os.path.join(CACHE, "tex", "%s_%s-JPG.zip" % (asset, res)))
    zf = zipfile.ZipFile(io.BytesIO(z))
    out = {}
    for suffix, name in (("_Color.jpg", "color"), ("_NormalGL.jpg", "normal"),
                         ("_Roughness.jpg", "rough"), ("_AmbientOcclusion.jpg", "ao"),
                         ("_Displacement.jpg", "height")):
        for n in zf.namelist():
            if n.endswith(suffix):
                out[name] = Image.open(io.BytesIO(zf.read(n)))
    return out


def textures(res):
    px = 2048 if res == "2k" else 1024
    cols, rows = 4, 3
    alb = Image.new("RGBA", (px * cols, px * rows))
    nra = Image.new("RGBA", (px * cols, px * rows))
    tdir = os.path.join(OUT, "textures")
    os.makedirs(tdir, exist_ok=True)
    scales = []
    for i, (layer, src, asset, metres) in enumerate(LAYERS):
        log("%-7s %s:%s" % (layer, src, asset))
        m = (_maps_ph if src == "ph" else _maps_acg)(asset, res)

        def gray(key, default):
            if key not in m:
                return Image.new("L", (px, px), default)
            return m[key].convert("L").resize((px, px), Image.LANCZOS)

        col = m["color"].convert("RGB").resize((px, px), Image.LANCZOS)
        nrm = m["normal"].convert("RGB").resize((px, px), Image.LANCZOS)
        hgt = gray("height", 128)
        # the height's range stretched to the whole byte, so every layer's
        # bumps weigh the same in the shader's height blend
        h = np.asarray(hgt).astype(np.float32)
        lo, hi = np.percentile(h, 1), np.percentile(h, 99)
        hgt = Image.fromarray(np.clip((h - lo) / max(hi - lo, 1.0) * 255.0, 0, 255).astype(np.uint8))
        r, g, b = col.split()
        x, y = (i % cols) * px, (i // cols) * px
        alb.paste(Image.merge("RGBA", (r, g, b, hgt)), (x, y))
        nr, ng, _ = nrm.split()
        nra.paste(Image.merge("RGBA", (nr, ng, gray("rough", 200), gray("ao", 255))), (x, y))
        scales.append(metres)
        if layer == "rock":
            col.save(os.path.join(tdir, "TEX_earth_rock_albedo.webp"), quality=82, method=3)
            nrm.save(os.path.join(tdir, "TEX_earth_rock_normal.webp"), quality=92, method=3)
    log("saving the atlases")
    alb.save(os.path.join(tdir, "TEX_earth_albedo.webp"), quality=82, alpha_quality=70, method=3)
    nra.save(os.path.join(tdir, "TEX_earth_nra.webp"), quality=80, alpha_quality=70, method=3)
    water_normal(os.path.join(tdir, "TEX_earth_water_normal.png"))
    # each atlas imported as a Texture2DArray, four across and three down
    for name, srgb in (("TEX_earth_albedo.webp", True), ("TEX_earth_nra.webp", False)):
        with open(os.path.join(tdir, name + ".import"), "w") as f:
            f.write(LAYERED_IMPORT % {"name": name, "pack": 0 if srgb else 1})
    # and the rock on its own, for the cut face: compressed and mipmapped, or
    # a wall seen from any distance glitters
    for name in ("TEX_earth_rock_albedo.webp", "TEX_earth_rock_normal.webp"):
        with open(os.path.join(tdir, name + ".import"), "w") as f:
            f.write(TEXTURE_IMPORT % {"name": name})
    with open(os.path.join(tdir, "layers.json"), "w") as f:
        json.dump({"layers": [l[0] for l in LAYERS], "sources": ["%s:%s" % (l[1], l[2]) for l in LAYERS],
                   "metres": scales, "px": px, "licence": "CC0 (Poly Haven, ambientCG)"}, f, indent=1)
    log("textures done: %s" % os.path.relpath(tdir, ROOT))


LAYERED_IMPORT = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="res://godot/island/earth/textures/%(name)s"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=%(pack)d
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=4
slices/vertical=3
"""


TEXTURE_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://godot/island/earth/textures/%(name)s"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
detect_3d/compress_to=0
"""


def water_normal(path, n=1024, seed=7):
    """A tiling normal map of small waves: a random spectrum falling off
    with frequency, made periodic by the FFT itself."""
    rng = np.random.default_rng(seed)
    k = np.fft.fftfreq(n) * n
    kx, ky = np.meshgrid(k, k)
    kk = np.hypot(kx, ky)
    kk[0, 0] = 1.0
    amp = np.exp(-(kk / 90.0) ** 2) / kk ** 1.6
    amp[0, 0] = 0.0
    # a little wind: more energy across one direction than along it
    amp *= 0.55 + 0.45 * (np.abs(kx) / kk)
    spec = amp * (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n)))
    h = np.real(np.fft.ifft2(spec))
    h /= np.abs(h).max()
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    s = 40.0
    nx, ny, nz = -gx * s, -gy * s, np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / l, -ny / l, nz / l], axis=-1) * 0.5 + 0.5
    Image.fromarray((rgb * 255).astype(np.uint8)).save(path)


# -------------------------------------------------------------------- models

def models():
    mdir = os.path.join(CACHE, "models")
    manifest = []
    for asset, cls, yaws, size, pitch, variants in PLANTS:
        files = json.loads(get("https://api.polyhaven.com/files/" + asset))
        g = files["gltf"]["1k"]["gltf"]
        base = os.path.join(mdir, asset)
        total = g["size"] + sum(v["size"] for v in g["include"].values())
        log("%-20s %-9s %5.1f MB" % (asset, cls, total / 1e6))
        get(g["url"], os.path.join(base, g["url"].split("/")[-1]))
        for rel, inc in g["include"].items():
            get(inc["url"], os.path.join(base, rel))
        manifest.append({"id": asset, "class": cls, "yaws": list(yaws), "size": list(size),
                         "pitch": pitch, "variants": variants,
                         "gltf": os.path.join(base, g["url"].split("/")[-1])})
    with open(os.path.join(mdir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    log("models in %s" % os.path.relpath(mdir, ROOT))


# ---------------------------------------------------------------- billboards

def billboards():
    mdir = os.path.join(CACHE, "models")
    raw = os.path.join(CACHE, "sprites")
    os.makedirs(raw, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot47") or shutil.which("godot")
    if not godot:
        sys.exit("earth_pack: Godot 4.7 is not on the PATH (or set $GODOT)")
    cmd = [godot, "--path", ROOT, "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
           "--script", "res://tools/earth_billboards.gd", "--",
           os.path.join(mdir, "manifest.json"), raw]
    if not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x1024x24"] + cmd
    log("rendering: " + " ".join(cmd))
    subprocess.run(cmd, check=True)
    finish_sprites(raw)


def finish_sprites(raw):
    """Trim each render to its plant, down from twice the size (Lanczos),
    hard alpha with the fringe's colour pulled in, a burn map beside it."""
    sdir = os.path.join(OUT, "sprites")
    os.makedirs(sdir, exist_ok=True)
    with open(os.path.join(CACHE, "models", "manifest.json")) as f:
        manifest = json.load(f)
    made = []
    for m in manifest:
        renders = sorted(f for f in os.listdir(raw) if f.startswith(m["id"] + "_") and f.endswith(".png")
                         and f[len(m["id"]) + 1:-4].replace("_", "").isdigit())
        if not renders:
            log("no renders of %s" % m["id"])
        for fname in renders:
            src = os.path.join(raw, fname)
            im = Image.open(src).convert("RGBA")
            w, h = m["size"]
            a = np.asarray(im).astype(np.float32) / 255.0
            # premultiply before the downscale so the fringe does not go dark
            pre = a.copy()
            pre[..., :3] *= pre[..., 3:4]
            small = np.stack([np.asarray(Image.fromarray((pre[..., c] * 255).astype(np.uint8)).resize(
                (w, h), Image.LANCZOS)).astype(np.float32) / 255.0 for c in range(4)], axis=-1)
            al = small[..., 3]
            rgb = small[..., :3] / np.maximum(al[..., None], 1e-4)
            # bleed the colour out past the edge, and the plant's mean colour
            # everywhere else, so no mip of it goes dark at the fringe
            solid = al > 0.02
            rgb = bleed(rgb, solid)
            if solid.any():
                mean = rgb[solid].mean(axis=0)
                far = ~np.asarray(Image.fromarray((solid * 255).astype(np.uint8)).filter(
                    ImageFilter.MaxFilter(25))).astype(bool)
                rgb[far] = mean
            out = np.concatenate([np.clip(rgb, 0, 1), (al > 0.45)[..., None].astype(np.float32)], axis=-1)
            name = "SPRITE_earth_%s_%s" % (m["class"], fname[:-4])
            Image.fromarray((out * 255).astype(np.uint8)).save(os.path.join(sdir, name + ".png"))
            burn_map(out).save(os.path.join(sdir, name + "_burn.png"))
            made.append({"name": name, "class": m["class"], "model": m["id"]})
    with open(os.path.join(sdir, "sprites.json"), "w") as f:
        json.dump({"sprites": made, "licence": "rendered from CC0 Poly Haven models"}, f, indent=1)
    log("%d sprites in %s" % (len(made), os.path.relpath(sdir, ROOT)))


def bleed(rgb, solid, steps=12):
    rgb = rgb.copy()
    known = solid.copy()
    for _ in range(steps):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(known.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            k = np.roll(known, (dy, dx), axis=(0, 1))
            acc += np.roll(rgb, (dy, dx), axis=(0, 1)) * k[..., None]
            cnt += k
        grow = (~known) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][..., None]
        known = known | grow
    return rgb


def burn_map(sprite):
    """The billboard shader's burn description (SHADER_veg_billboard.gdshader):
    R ember, G char, B order (base first, fringe early, ragged), A foliage."""
    h, w = sprite.shape[:2]
    rgb, al = sprite[..., :3], sprite[..., 3]
    rng = np.random.default_rng(h * 131 + w)
    noise = np.asarray(Image.fromarray((rng.random((h // 8 + 2, w // 8 + 2)) * 255).astype(np.uint8)).resize(
        (w, h), Image.BICUBIC)).astype(np.float32) / 255.0
    rows = np.where(al.any(axis=1))[0]
    top, bot = (rows.min(), rows.max()) if rows.size else (0, h - 1)
    y = np.arange(h, dtype=np.float32)[:, None]
    order = np.clip((bot - y) / max(bot - top, 1), 0, 1) * np.ones((1, w), np.float32)
    inner = np.asarray(Image.fromarray((al * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(9))).astype(np.float32) / 255.0
    order = np.clip(order * 0.8 + 0.2 * noise - 0.12 * (1.0 - inner), 0, 1)
    green = np.clip((rgb[..., 1] - 0.5 * (rgb[..., 0] + rgb[..., 2])) * 4.0 + 0.3, 0, 1)
    dark = 1.0 - rgb.mean(axis=-1)
    ember = np.clip((noise - 0.62) * 4.0, 0, 1) * (1.0 - green * 0.6)
    char = np.clip(0.7 + 0.3 * dark, 0, 1)
    out = np.stack([ember, char, order, green], axis=-1) * al[..., None]
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("what", choices=["textures", "models", "billboards", "sprites", "all"])
    ap.add_argument("--res", choices=["1k", "2k"], default="2k")
    a = ap.parse_args()
    if a.what in ("textures", "all"):
        textures(a.res)
    if a.what in ("models", "all"):
        models()
    if a.what in ("billboards", "all"):
        billboards()
    if a.what == "sprites":
        finish_sprites(os.path.join(CACHE, "sprites"))


if __name__ == "__main__":
    main()
