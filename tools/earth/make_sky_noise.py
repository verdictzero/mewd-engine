#!/usr/bin/env python3
"""MEWD — the noise the sky's clouds are made of (EnviroSky,
godot/island/sky/enviro/), made once and kept.

    python3 tools/earth/make_sky_noise.py

  TEX_cloud_shape.png    128^3 as 16 x 8 slices of 128: R a Perlin-Worley
                         (the billows), G B A Worley at three rising
                         frequencies (the erosion's FBM). The cumulus.
  TEX_cloud_detail.png   32^3 as 8 x 4 slices of 32: Worley at three
                         frequencies, for the wisps on the edges.
  TEX_cloud_weather.png  512^2: R where clouds may form (coverage), G a
                         second, slower field for their type, both tiling.
  TEX_cirrus.png         1024^2: streaked FBM for the high ice cloud.
  TEX_moon.png           256^2: a moon's face, maria and craters, grey.

Everything tiles. The 3D ones are imported as Texture3D (3d_texture),
which the .import files written beside them say. The construction is the
usual one for raymarched clouds (Schneider, "The real-time volumetric
cloudscapes of Horizon Zero Dawn", 2015): Perlin remapped by inverted
Worley for a base that billows, Worley octaves to erode it.

Needs numpy and Pillow."""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "godot", "island", "sky", "enviro")


def worley3(n, cells, seed):
    """Tiling 3D Worley (distance to nearest feature), 0..1, n^3."""
    rng = np.random.default_rng(seed)
    feat = rng.random((cells, cells, cells, 3))
    g = (np.arange(n) + 0.5) / n * cells
    x, y, z = np.meshgrid(g, g, g, indexing="ij")
    ix, iy, iz = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
    best = np.full(x.shape, 9.0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                cx, cy, cz = ix + dx, iy + dy, iz + dz
                f = feat[cx % cells, cy % cells, cz % cells]
                d = (cx + f[..., 0] - x) ** 2 + (cy + f[..., 1] - y) ** 2 + (cz + f[..., 2] - z) ** 2
                np.minimum(best, d, out=best)
    d = np.sqrt(best)
    return np.clip(d / 0.9, 0.0, 1.0)


def perlin3(n, cells, seed):
    """Tiling 3D gradient noise, about -1..1, n^3."""
    rng = np.random.default_rng(seed)
    grad = rng.normal(size=(cells, cells, cells, 3))
    grad /= np.linalg.norm(grad, axis=-1, keepdims=True)
    g = np.arange(n) / n * cells
    x, y, z = np.meshgrid(g, g, g, indexing="ij")
    ix, iy, iz = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
    fx, fy, fz = x - ix, y - iy, z - iz

    def fade(t):
        return t * t * t * (t * (t * 6 - 15) + 10)

    u, v, w = fade(fx), fade(fy), fade(fz)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                gr = grad[(ix + dx) % cells, (iy + dy) % cells, (iz + dz) % cells]
                dot = gr[..., 0] * (fx - dx) + gr[..., 1] * (fy - dy) + gr[..., 2] * (fz - dz)
                wt = (u if dx else 1 - u) * (v if dy else 1 - v) * (w if dz else 1 - w)
                out = out + wt * dot
    return out * 1.6


def fbm(fn, n, cells, seed, octaves, gain=0.5):
    acc, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        acc = acc + amp * fn(n, cells * (2 ** o), seed + o * 17)
        tot += amp
        amp *= gain
    return acc / tot


def remap(v, lo, hi, nlo, nhi):
    return nlo + (v - lo) / (hi - lo) * (nhi - nlo)


def slices(vol, across):
    """A cube as a picture of slices, `across` slices to a row."""
    n = vol.shape[0]
    down = n // across
    rows = []
    for r in range(down):
        rows.append(np.concatenate([vol[:, :, r * across + c].T for c in range(across)], axis=1))
    return np.concatenate(rows, axis=0)


def to8(a):
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


IMPORT_3D = """[remap]

importer="3d_texture"
type="CompressedTexture3D"

[deps]

source_file="res://godot/island/sky/enviro/%(name)s"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=1
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=%(h)d
slices/vertical=%(v)d
"""


def noise2(n, cells, seed, octaves, stretch=(1.0, 1.0)):
    rng = np.random.default_rng(seed)
    acc = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        lat = rng.random((int(c * stretch[1]) + 1, int(c * stretch[0]) + 1))
        lat[-1, :] = lat[0, :]
        lat[:, -1] = lat[:, 0]
        im = Image.fromarray((lat * 65535).astype(np.uint16))
        up = np.asarray(im.resize((n + 1, n + 1), Image.BICUBIC), dtype=np.float64)[:n, :n] / 65535.0
        acc += amp * up
        tot += amp
        amp *= 0.55
    return acc / tot


def main():
    os.makedirs(OUT, exist_ok=True)
    n = 128
    print("make_sky_noise: shape 128^3")
    p = fbm(perlin3, n, 4, 1, 4) * 0.5 + 0.5
    w1 = 1.0 - fbm(worley3, n, 6, 11, 3, 0.6)
    pw = np.clip(remap(p, 0.0, 1.0, w1 * 0.9 - 0.25, 1.0), 0.0, 1.0)
    pw = (pw - pw.min()) / (pw.max() - pw.min())
    g = 1.0 - worley3(n, 8, 21)
    b = 1.0 - worley3(n, 16, 31)
    a = 1.0 - worley3(n, 32, 41)
    shape = np.stack([pw, g, b, a], axis=-1)
    pic = np.stack([slices(shape[..., c], 16) for c in range(4)], axis=-1)
    Image.fromarray(to8(pic), "RGBA").save(os.path.join(OUT, "TEX_cloud_shape.png"))
    with open(os.path.join(OUT, "TEX_cloud_shape.png.import"), "w") as f:
        f.write(IMPORT_3D % {"name": "TEX_cloud_shape.png", "h": 16, "v": 8})

    print("make_sky_noise: detail 32^3")
    m = 32
    d = np.stack([1.0 - worley3(m, 4, 51), 1.0 - worley3(m, 8, 61), 1.0 - worley3(m, 16, 71)], axis=-1)
    pic = np.stack([slices(d[..., c], 8) for c in range(3)], axis=-1)
    Image.fromarray(to8(pic), "RGB").save(os.path.join(OUT, "TEX_cloud_detail.png"))
    with open(os.path.join(OUT, "TEX_cloud_detail.png.import"), "w") as f:
        f.write(IMPORT_3D % {"name": "TEX_cloud_detail.png", "h": 8, "v": 4})

    print("make_sky_noise: weather, cirrus, moon")
    cov = noise2(512, 4, 81, 5)
    cov = (cov - cov.min()) / (cov.max() - cov.min())
    typ = noise2(512, 2, 91, 3)
    typ = (typ - typ.min()) / (typ.max() - typ.min())
    Image.fromarray(np.stack([to8(cov), to8(typ), np.zeros_like(to8(cov))], axis=-1), "RGB").save(
        os.path.join(OUT, "TEX_cloud_weather.png"))
    ci = noise2(1024, 3, 101, 6, stretch=(4.0, 1.0))
    ci2 = noise2(1024, 6, 111, 5, stretch=(1.0, 3.0))
    ci = np.clip((ci * 0.7 + ci2 * 0.3 - 0.42) * 2.4, 0.0, 1.0)
    Image.fromarray(to8(ci), "L").save(os.path.join(OUT, "TEX_cirrus.png"))
    # the moon: a disc of grey, darker maria in broad blots, small craters
    k = 256
    yy, xx = np.mgrid[0:k, 0:k] / (k - 1) * 2.0 - 1.0
    maria = noise2(k, 3, 121, 4)
    base = 0.72 - 0.32 * np.clip((maria - 0.45) * 3.0, 0.0, 1.0)
    rng = np.random.default_rng(131)
    for _ in range(90):
        cx, cy, r = rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0.02, 0.12)
        dd = np.hypot(xx - cx, yy - cy) / r
        base -= 0.08 * np.exp(-((dd - 0.85) ** 2) * 30.0) * -1.0 + 0.06 * (dd < 0.8)
    Image.fromarray(to8(np.clip(base, 0.0, 1.0)), "L").save(os.path.join(OUT, "TEX_moon.png"))
    print("make_sky_noise: %s" % os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
