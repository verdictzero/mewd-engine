#!/usr/bin/env python3
"""A real place on Earth, cut out as a square and made an island.

    python3 tools/earth_fetch.py oeschinen --lat 46.4986 --lon 7.7270 \
        --size 3000 --title "OESCHINENSEE" --register

At the user's request: "take coordinates on earth and within defined
boundaries (a square) render terrain faithfully using the chunk based
terrain system ... using open source map data to define height, water level
and vegetation / biomes". This is the half of that which runs once, off the
engine: it fetches the open data for a square `--size` metres on a side round
`--lat`/`--lon`, works it into the grids the engine's EarthField reads
(godot/island/scripts/world/SCRIPT_earth_field.gd), and writes them to
godot/island/earth/<name>/. The island system does the rest the way it does
for golf's islands: the chunk mesher, the bakes, the plants and the cliff
all round into the cloud.

THE DATA, all open, all fetched over plain HTTPS with no key:

  HEIGHT     the AWS Terrain Tiles ("Terrarium" PNGs, s3.amazonaws.com/
             elevation-tiles-prod): SRTM, GMTED, ETOPO1 and the national
             lidar sets where there are any, merged by Mapzen. Or, with
             --dem copernicus, Copernicus GLO-30 (a surface model, so the
             canopy is in it). Either way bicubic down to a 2 m grid.
  COVER      ESA WorldCover 10 m 2021 v200 (CC BY 4.0): eleven classes of
             what is actually on the ground — trees, shrubs, grass, crops,
             built-up, bare, snow and ice, water, wetland, mangrove, moss —
             read straight out of its cloud-optimised GeoTIFFs by range
             request.
  OSM        OpenStreetMap (ODbL) through the Overpass API: the shorelines
             of lakes and rivers, the rivers and streams themselves, the
             roads, tracks and paths, the railways, the buildings, the
             forests' leaf type, and the rock, scree, sand and wetland
             polygons that sharpen what WorldCover says. Optional: with no
             Overpass server answering (--no-osm, or every mirror down),
             WorldCover's own water and cover stand alone.

WHAT IT MAKES, all on one square grid centred on the coordinates, x east and
z south, in metres (a local tangent plane; at ten kilometres the error is
centimetres):

  height.grid   the ground, every 2 m, metres above sea level: the DEM with
                every lake, river and sea bed carved under its water and the
                banks held up out of it
  water.grid    the water's surface, every 4 m, metres above sea level, NaN
                where there is none — flat on a lake, level 0 on the sea,
                falling with the valley on a river
  wkind.grid    which water: 0 none, 1 sea, 2 lake, 3 river
  cover.grid    twelve surface weights every 4 m, the ground's twelve PBR
                layers: grass, forest floor, rock, scree, sand, soil, snow,
                mud, paving, dry scrub, moss and the bed under the water
  veg.grid      four plant densities every 4 m: trees, the conifer share of
                them, bushes, grass tufts
  region.json   where it all came from, how to read it, the water bodies,
                the attribution the licences ask for, a digest the bakes key
                themselves on
  preview/      pictures of each, for people (Godot ignores the folder)

and with --register, the field (ISLANDFIELD_earth_<name>.tres), the scene
(earth_<name>.tscn, from the template) and an entry in Islands.LIST, so the
viewer lists it. Bake it after (tools/bake_island.gd --map=earth_<name>).

The downloads are kept in tools/.earth-cache/ (gitignored), so running it
again, or for an overlapping square, costs nothing.

Needs numpy and Pillow (pip install numpy pillow)."""
import argparse
import datetime
import hashlib
import io
import json
import math
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from collections import deque

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("earth_fetch: needs numpy and Pillow (pip install numpy pillow)")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".earth-cache")
EARTH = os.path.join(ROOT, "godot", "island", "earth")
UA = "fenrir-earth/1.0 (+https://github.com/verdictzero/mewd-engine)"

# The twelve surface layers, in the order cover.grid and the terrain
# shader's texture arrays hold them. Keep in step with SCRIPT_earth_field.gd
# (`L_*`) and tools/earth_pack.py (`LAYERS`).
LAYERS = ["grass", "forest", "rock", "scree", "sand", "soil",
          "snow", "mud", "paving", "dry", "moss", "bed"]
L = {n: i for i, n in enumerate(LAYERS)}

# ESA WorldCover's classes, as surface layers (weights, summing to one).
WC_LAYERS = {
    10: {"forest": 1.0},                      # tree cover
    20: {"dry": 0.7, "grass": 0.3},           # shrubland
    30: {"grass": 1.0},                       # grassland
    40: {"soil": 0.55, "grass": 0.45},        # cropland: earth, half green
    50: {"paving": 0.6, "grass": 0.4},        # built-up: streets and gardens
    60: {"scree": 0.75, "rock": 0.25},        # bare / sparse vegetation
    70: {"snow": 1.0},                        # snow and ice
    80: {"bed": 1.0},                         # permanent water
    90: {"mud": 0.5, "grass": 0.5},           # herbaceous wetland
    95: {"mud": 0.6, "forest": 0.4},          # mangroves
    100: {"moss": 0.7, "scree": 0.3},         # moss and lichen
    0: {"grass": 1.0},                        # no data
}

OVERPASS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
# Switzerland's own mirror answers for Switzerland only, and answers an
# empty map anywhere else, so it is only asked about squares inside it.
OVERPASS_CH = "https://overpass.osm.ch/api/interpreter"
CH_BOX = (45.8, 5.9, 47.85, 10.5)


def log(*a):
    print("earth:", *a, flush=True)


# ------------------------------------------------------------------ fetching

def _cache_path(key, ext):
    h = hashlib.sha1(key.encode()).hexdigest()
    return os.path.join(CACHE, h[:2], h[2:22] + ext)


def http(url, data=None, headers=None, tries=5, timeout=180, cache_ext=None,
         allow_404=True):
    """GET (or POST `data`), retried with backoff, cached on disk when
    `cache_ext` is given. None for a 404 when `allow_404`."""
    key = url + "|" + (data.decode() if data else "") + "|" + json.dumps(headers or {})
    path = _cache_path(key, cache_ext) if cache_ext else None
    if path and os.path.exists(path):
        with open(path, "rb") as f:
            body = f.read()
        return None if body == b"\x00MISSING" else body
    h = {"User-Agent": UA}
    h.update(headers or {})
    err = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers=h)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read()
            break
        except urllib.error.HTTPError as e:
            if e.code == 404 and allow_404:
                body = None
                break
            if e.code in (400, 401, 403):
                raise
            err = e
        except Exception as e:  # network trouble: reset, timeout, refused
            err = e
        time.sleep(min(2 ** (i + 1), 30))
    else:
        raise RuntimeError("%s: %s" % (url, err))
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(b"\x00MISSING" if body is None else body)
    return body


def http_range(url, start, length):
    return http(url, headers={"Range": "bytes=%d-%d" % (start, start + length - 1)},
                cache_ext=".bin")


# ------------------------------------------------------------- the geometry

def metres_per_degree(lat):
    """WGS84 metres per degree of latitude and of longitude at `lat`."""
    p = math.radians(lat)
    mlat = (111132.92 - 559.82 * math.cos(2 * p) + 1.175 * math.cos(4 * p)
            - 0.0023 * math.cos(6 * p))
    mlon = (111412.84 * math.cos(p) - 93.5 * math.cos(3 * p)
            + 0.118 * math.cos(5 * p))
    return mlat, mlon


class Square:
    """The region: a square `size` metres on a side round (lat0, lon0), on
    a grid of `res` metres, vertex-centred (the first and last samples lie
    on the square's edges), x east and z south."""

    def __init__(self, lat0, lon0, size, res):
        self.lat0, self.lon0, self.size, self.res = lat0, lon0, size, res
        self.half = size / 2.0
        self.n = int(round(size / res)) + 1
        self.mlat, self.mlon = metres_per_degree(lat0)
        self.coords = -self.half + np.arange(self.n) * res
        self.X, self.Z = np.meshgrid(self.coords, self.coords)

    def latlon(self, dx=0.0, dz=0.0):
        return (self.lat0 - (self.Z + dz) / self.mlat,
                self.lon0 + (self.X + dx) / self.mlon)

    def local(self, lat, lon):
        return ((np.asarray(lon) - self.lon0) * self.mlon,
                (self.lat0 - np.asarray(lat)) * self.mlat)

    def bbox(self, margin):
        dlat = (self.half + margin) / self.mlat
        dlon = (self.half + margin) / self.mlon
        return (self.lat0 - dlat, self.lon0 - dlon, self.lat0 + dlat, self.lon0 + dlon)


def bicubic(img, u, v):
    """Catmull-Rom sample of `img` at pixel coordinates (u across, v down),
    with pixel (i, j)'s centre at (i, j)."""
    h, w = img.shape
    u = np.clip(u, 1.0, w - 3.0001)
    v = np.clip(v, 1.0, h - 3.0001)
    iu = np.floor(u).astype(np.int64)
    iv = np.floor(v).astype(np.int64)
    fu = u - iu
    fv = v - iv

    def weights(t):
        t2 = t * t
        t3 = t2 * t
        return ((-t3 + 2 * t2 - t) * 0.5, (3 * t3 - 5 * t2 + 2) * 0.5,
                (-3 * t3 + 4 * t2 + t) * 0.5, (t3 - t2) * 0.5)

    wu = weights(fu)
    wv = weights(fv)
    out = np.zeros(u.shape, np.float64)
    for j in range(4):
        row = np.zeros(u.shape, np.float64)
        for i in range(4):
            row += wu[i] * img[iv + j - 1, iu + i - 1]
        out += wv[j] * row
    return out


def value_noise(shape, cell, seed, octaves=2):
    """Smooth noise in about [-1, 1] over a grid of `shape`, features
    `cell` samples across: random lattices, bicubic up."""
    rng = np.random.default_rng(seed)
    out = np.zeros(shape, np.float64)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = max(cell / (2 ** o), 2.0)
        gh = int(shape[0] / c) + 4
        gw = int(shape[1] / c) + 4
        lat = rng.uniform(-1.0, 1.0, (gh, gw))
        jj, ii = np.mgrid[0:shape[0], 0:shape[1]]
        out += amp * bicubic(lat, ii / c + 1.0, jj / c + 1.0)
        total += amp
        amp *= 0.5
    return out / total


def box_blur(a, r):
    """Mean over a (2r+1)-square, edges clamped. Separable, by running sums."""
    if r <= 0:
        return a.astype(np.float64)
    a = a.astype(np.float64)
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        p = np.pad(a, pad, mode="edge")
        c = np.cumsum(p, axis=axis)
        if axis == 0:
            a = (c[2 * r + 1:, :] - c[:-2 * r - 1, :]) / (2 * r + 1)
        else:
            a = (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)
    return a


def shift(a, sh, fill):
    """`a` moved by sh = (rows, columns), `fill` brought in at the edge it
    leaves — np.roll would wrap the far edge round onto it, and a tarn on the
    square's east edge came back on its west edge, three hundred metres up."""
    dy, dx = sh
    h, w = a.shape[:2]
    out = np.full_like(a, fill)
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
        a[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def blur(a, sigma_px):
    """About a Gaussian of `sigma_px`: three box passes."""
    if sigma_px <= 0.3:
        return a.astype(np.float64)
    r = max(int(round(math.sqrt(12.0 * sigma_px * sigma_px / 3.0 + 1.0) / 2.0 - 0.5)), 1)
    out = a
    for _ in range(3):
        out = box_blur(out, r)
    return out


def chamfer(feature, step):
    """Distance from every cell to the nearest True cell of `feature`, in
    the units of `step` — a (1, sqrt 2) chamfer in two sweeps, each row's
    run along itself done at once by a running minimum."""
    big = 1e9
    d = np.where(feature, 0.0, big)
    h, w = d.shape
    idx = np.arange(w, dtype=np.float64)
    diag = math.sqrt(2.0)

    def along(row):
        # d'[x] = min over k of d[k] + |x - k|, both ways
        left = np.minimum.accumulate(row - idx) + idx
        right = (np.minimum.accumulate((row + idx)[::-1]))[::-1] - idx
        return np.minimum(row, np.minimum(left, right))

    for rng in (range(h), range(h - 1, -1, -1)):
        prev = None
        for y in rng:
            row = d[y]
            if prev is not None:
                cand = prev + 1.0
                cand[1:] = np.minimum(cand[1:], prev[:-1] + diag)
                cand[:-1] = np.minimum(cand[:-1], prev[1:] + diag)
                row = np.minimum(row, cand)
            row = along(row)
            d[y] = row
            prev = row
    return d * step


def label(mask):
    """4-connected components of a boolean grid: (labels, count), labels
    counting from 1, by runs and a union-find over them."""
    h, w = mask.shape
    parent = []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    runs = []          # per row: (starts, ends, ids)
    for y in range(h):
        row = mask[y].astype(np.int8)
        dd = np.diff(np.concatenate(([0], row, [0])))
        starts = np.nonzero(dd == 1)[0]
        ends = np.nonzero(dd == -1)[0]          # exclusive
        ids = list(range(len(parent), len(parent) + len(starts)))
        parent.extend(ids)
        if y > 0 and len(starts):
            ps, pe, pid = runs[-1]
            j = 0
            for s, e, i in zip(starts, ends, ids):
                while j < len(ps) and pe[j] <= s:
                    j += 1
                k = j
                while k < len(ps) and ps[k] < e:
                    ra, rb = find(i), find(pid[k])
                    if ra != rb:
                        parent[max(ra, rb)] = min(ra, rb)
                    k += 1
        runs.append((starts, ends, ids))
    out = np.zeros((h, w), np.int32)
    roots = {}
    for y, (starts, ends, ids) in enumerate(runs):
        for s, e, i in zip(starts, ends, ids):
            r = find(i)
            if r not in roots:
                roots[r] = len(roots) + 1
            out[y, s:e] = roots[r]
    return out, len(roots)


def smoothstep(a, b, x):
    t = np.clip((x - a) / max(b - a, 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# -------------------------------------------------------------- the DEM

def terrarium(sq, zoom):
    """Ground height at every grid sample, from the AWS Terrain Tiles."""
    lat, lon = sq.latlon()
    n = 2 ** zoom
    px = (lon + 180.0) / 360.0 * n * 256.0
    py = (1.0 - np.arcsinh(np.tan(np.radians(lat))) / math.pi) / 2.0 * n * 256.0
    tx0, tx1 = int((px.min() - 4) // 256), int((px.max() + 4) // 256)
    ty0, ty1 = int((py.min() - 4) // 256), int((py.max() + 4) // 256)
    tiles = (tx1 - tx0 + 1) * (ty1 - ty0 + 1)
    log("height: %d Terrarium tiles at zoom %d (%.1f m a pixel here)"
        % (tiles, zoom, 40075016.7 * math.cos(math.radians(sq.lat0)) / (n * 256)))
    mosaic = np.zeros(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256), np.float64)
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            url = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png" % (
                zoom, tx % n, ty)
            body = http(url, cache_ext=".png")
            if body is None:
                continue
            im = np.asarray(Image.open(io.BytesIO(body)).convert("RGB")).astype(np.float64)
            h = im[..., 0] * 256.0 + im[..., 1] + im[..., 2] / 256.0 - 32768.0
            mosaic[(ty - ty0) * 256:(ty - ty0 + 1) * 256,
                   (tx - tx0) * 256:(tx - tx0 + 1) * 256] = h
    return bicubic(mosaic, px - tx0 * 256 - 0.5, py - ty0 * 256 - 0.5)


class COG:
    """Just enough of a cloud-optimised GeoTIFF reader for WorldCover and
    Copernicus: the first image, tiled, deflate (or none), predictors 1-3,
    classic TIFF or BigTIFF, fetched a tile at a time by range request."""

    TYPES = {1: ("B", 1), 2: ("c", 1), 3: ("H", 2), 4: ("I", 4), 5: ("II", 8),
             6: ("b", 1), 8: ("h", 2), 9: ("i", 4), 11: ("f", 4), 12: ("d", 8),
             16: ("Q", 8), 17: ("q", 8)}

    def __init__(self, url):
        self.url = url
        head = http_range(url, 0, 65536)
        if head is None:
            raise FileNotFoundError(url)
        self.head = head
        self.bo = "<" if head[:2] == b"II" else ">"
        magic = struct.unpack(self.bo + "H", head[2:4])[0]
        self.big = magic == 43
        if self.big:
            ifd = struct.unpack(self.bo + "Q", head[8:16])[0]
        else:
            ifd = struct.unpack(self.bo + "I", head[4:8])[0]
        self.tags = self._ifd(ifd)
        t = self.tags
        self.w, self.h = int(t[256][0]), int(t[257][0])
        self.tw, self.th = int(t[322][0]), int(t[323][0])
        self.bits = int(t[258][0])
        self.fmt = int(t.get(339, [1])[0])
        self.comp = int(t.get(259, [1])[0])
        self.pred = int(t.get(317, [1])[0])
        self.offsets = t[324]
        self.counts = t[325]
        self.across = (self.w + self.tw - 1) // self.tw
        sx, sy = t[33550][0], t[33550][1]
        ti, tj, tx, ty = t[33922][0], t[33922][1], t[33922][3], t[33922][4]
        # GTRasterTypeGeoKey (1025): 2 = the tiepoint is a pixel's centre
        point = False
        keys = t.get(34735)
        if keys:
            for k in range(4, len(keys), 4):
                if keys[k] == 1025 and keys[k + 3] == 2:
                    point = True
        self.sx, self.sy = sx, sy
        # longitude / latitude of pixel (0, 0)'s CENTRE
        self.x0 = tx - ti * sx + (0.0 if point else 0.5 * sx)
        self.y0 = ty + tj * sy - (0.0 if point else 0.5 * sy)
        nd = t.get(42113)
        self.nodata = float(nd.strip("\x00")) if isinstance(nd, str) and nd.strip("\x00") else None
        if self.fmt == 3:
            self.dtype = np.dtype(self.bo + "f%d" % (self.bits // 8))
        elif self.fmt == 2:
            self.dtype = np.dtype(self.bo + "i%d" % (self.bits // 8))
        else:
            self.dtype = np.dtype(self.bo + "u%d" % (self.bits // 8))
        self._tiles = {}

    def _bytes(self, off, n):
        if off + n <= len(self.head):
            return self.head[off:off + n]
        return http_range(self.url, off, n)

    def _ifd(self, off):
        bo = self.bo
        if self.big:
            cnt = struct.unpack(bo + "Q", self._bytes(off, 8))[0]
            esz, base = 20, off + 8
        else:
            cnt = struct.unpack(bo + "H", self._bytes(off, 2))[0]
            esz, base = 12, off + 2
        raw = self._bytes(base, cnt * esz)
        tags = {}
        for i in range(cnt):
            e = raw[i * esz:(i + 1) * esz]
            if self.big:
                tag, typ, n = struct.unpack(bo + "HHQ", e[:12])
                inline, vbytes = 8, e[12:20]
            else:
                tag, typ, n = struct.unpack(bo + "HHI", e[:8])
                inline, vbytes = 4, e[8:12]
            if typ not in self.TYPES:
                continue
            code, sz = self.TYPES[typ]
            total = sz * n
            if total <= inline:
                data = vbytes[:total]
            else:
                p = struct.unpack(bo + ("Q" if self.big else "I"), vbytes)[0]
                data = self._bytes(p, total)
            if typ == 2:
                tags[tag] = data.decode("latin-1")
            elif typ == 5:
                v = struct.unpack(bo + "I" * (2 * n), data)
                tags[tag] = [v[k] / max(v[k + 1], 1) for k in range(0, 2 * n, 2)]
            else:
                tags[tag] = list(struct.unpack(bo + code * n, data))
        return tags

    def tile(self, tx, ty):
        k = (tx, ty)
        if k in self._tiles:
            return self._tiles[k]
        i = ty * self.across + tx
        off, cnt = int(self.offsets[i]), int(self.counts[i])
        fill = self.nodata if self.nodata is not None else 0
        if cnt == 0:
            a = np.full((self.th, self.tw), fill, np.float64)
        else:
            raw = http_range(self.url, off, cnt)
            if self.comp in (8, 32946):
                raw = zlib.decompress(raw)
            elif self.comp != 1:
                raise RuntimeError("%s: compression %d is not read here" % (self.url, self.comp))
            bps = self.bits // 8
            if self.pred == 3:
                b = np.frombuffer(raw, np.uint8).reshape(self.th, self.tw * bps)
                b = np.cumsum(b, axis=1, dtype=np.uint8)
                # the bytes of a row are stored most significant plane first
                planes = b.reshape(self.th, bps, self.tw).transpose(0, 2, 1)
                a = np.ascontiguousarray(planes).view(">f%d" % bps).reshape(
                    self.th, self.tw).astype(np.float64)
            else:
                a = np.frombuffer(raw, self.dtype).reshape(self.th, self.tw)
                if self.pred == 2:
                    a = np.cumsum(a, axis=1, dtype=a.dtype)
                a = a.astype(np.float64)
        self._tiles[k] = a
        return a

    def window(self, c0, r0, c1, r1):
        """Pixels [c0, c1) x [r0, r1), clipped to the image."""
        c0, r0 = max(c0, 0), max(r0, 0)
        c1, r1 = min(c1, self.w), min(r1, self.h)
        out = np.zeros((max(r1 - r0, 0), max(c1 - c0, 0)), np.float64)
        if out.size == 0:
            return out, c0, r0
        for ty in range(r0 // self.th, (r1 - 1) // self.th + 1):
            for tx in range(c0 // self.tw, (c1 - 1) // self.tw + 1):
                t = self.tile(tx, ty)
                ys, xs = ty * self.th, tx * self.tw
                a0, a1 = max(r0, ys), min(r1, ys + self.th)
                b0, b1 = max(c0, xs), min(c1, xs + self.tw)
                out[a0 - r0:a1 - r0, b0 - c0:b1 - c0] = t[a0 - ys:a1 - ys, b0 - xs:b1 - xs]
        return out, c0, r0


def _hemi(v, pos, neg, width):
    return ("%s%0*d" % (pos if v >= 0 else neg, width, abs(v)))


def worldcover(sq, dx, dz):
    """How much of each WorldCover class is at every grid sample: each
    class's 10 m pixels as a 0/1 map, sampled bilinearly at points pushed
    about by (dx, dz) metres — soft edges that wander, instead of a
    staircase of 10 m pixels. {class: fraction}."""
    lat, lon = sq.latlon(dx, dz)
    out = {}
    for la in range(int(math.floor(lat.min() / 3.0)) * 3, int(math.floor(lat.max() / 3.0)) * 3 + 1, 3):
        for lo in range(int(math.floor(lon.min() / 3.0)) * 3, int(math.floor(lon.max() / 3.0)) * 3 + 1, 3):
            name = "ESA_WorldCover_10m_2021_v200_%s%s_Map" % (_hemi(la, "N", "S", 2), _hemi(lo, "E", "W", 3))
            url = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/%s.tif" % name
            inside = (lat >= la) & (lat < la + 3) & (lon >= lo) & (lon < lo + 3)
            if not inside.any():
                continue
            try:
                cog = COG(url)
            except FileNotFoundError:
                log("cover: no WorldCover tile %s (open sea?)" % name)
                continue
            u = (lon - cog.x0) / cog.sx
            v = (cog.y0 - lat) / cog.sy
            c0, c1 = int(math.floor(u[inside].min())) - 1, int(math.ceil(u[inside].max())) + 2
            r0, r1 = int(math.floor(v[inside].min())) - 1, int(math.ceil(v[inside].max())) + 2
            win, wc0, wr0 = cog.window(c0, r0, c1, r1)
            log("cover: %s, %d x %d pixels" % (name, win.shape[1], win.shape[0]))
            uu = np.clip(u[inside] - wc0, 0.0, win.shape[1] - 1.001)
            vv = np.clip(v[inside] - wr0, 0.0, win.shape[0] - 1.001)
            iu, iv = np.floor(uu).astype(np.int64), np.floor(vv).astype(np.int64)
            fu, fv = uu - iu, vv - iv
            iu1 = np.minimum(iu + 1, win.shape[1] - 1)
            iv1 = np.minimum(iv + 1, win.shape[0] - 1)
            for c in np.unique(win).astype(int):
                ind = (win == c).astype(np.float32)
                f = ((ind[iv, iu] * (1 - fu) + ind[iv, iu1] * fu) * (1 - fv)
                     + (ind[iv1, iu] * (1 - fu) + ind[iv1, iu1] * fu) * fv)
                a = out.setdefault(c, np.zeros(lat.shape, np.float32))
                a[inside] = f
    if not out:
        out[0] = np.ones(lat.shape, np.float32)
    return out


def copernicus(sq):
    """Ground height from Copernicus GLO-30 (a surface model: the canopy
    and the roofs are in it)."""
    lat, lon = sq.latlon()
    first = None
    tiles = []
    for la in range(int(math.floor(lat.min())), int(math.floor(lat.max())) + 1):
        for lo in range(int(math.floor(lon.min())), int(math.floor(lon.max())) + 1):
            name = "Copernicus_DSM_COG_10_%s_00_%s_00_DEM" % (_hemi(la, "N", "S", 2), _hemi(lo, "E", "W", 3))
            url = "https://copernicus-dem-30m.s3.amazonaws.com/%s/%s.tif" % (name, name)
            try:
                cog = COG(url)
            except FileNotFoundError:
                continue
            tiles.append(cog)
            first = first or cog
    if first is None:
        log("height: no Copernicus tile here; the sea, at 0")
        return np.zeros(lat.shape)
    sx, sy = first.sx, first.sy
    gc = (lon + 180.0) / sx
    gr = (90.0 - lat) / sy
    c0, c1 = int(gc.min()) - 3, int(gc.max()) + 4
    r0, r1 = int(gr.min()) - 3, int(gr.max()) + 4
    mosaic = np.zeros((r1 - r0, c1 - c0))
    for cog in tiles:
        oc = int(round((cog.x0 + 180.0) / sx))
        orow = int(round((90.0 - cog.y0) / sy))
        win, wc0, wr0 = cog.window(c0 - oc, r0 - orow, c1 - oc, r1 - orow)
        if win.size == 0:
            continue
        a, b = wr0 + orow - r0, wc0 + oc - c0
        mosaic[a:a + win.shape[0], b:b + win.shape[1]] = win
    log("height: Copernicus GLO-30, %d tile(s)" % len(tiles))
    return bicubic(mosaic, gc - c0, gr - r0)


# --------------------------------------------------------------- OSM

def overpass(sq, endpoints):
    s, w, n, e = sq.bbox(60.0)
    bb = "(%.6f,%.6f,%.6f,%.6f)" % (s, w, n, e)
    q = ("[out:json][timeout:240];("
         'wr["natural"~"^(water|wood|scrub|heath|grassland|bare_rock|scree|shingle|sand|beach|glacier|wetland|fell|tundra|mud)$"]%(b)s;'
         'wr["water"]%(b)s;'
         'wr["waterway"]%(b)s;'
         'wr["landuse"]%(b)s;'
         'wr["leisure"~"^(park|pitch|golf_course|garden|playground)$"]%(b)s;'
         'way["highway"]%(b)s;'
         'way["railway"~"^(rail|light_rail|narrow_gauge|tram|funicular)$"]%(b)s;'
         'wr["building"]%(b)s;'
         'way["aeroway"~"^(runway|taxiway|apron)$"]%(b)s;'
         ");out geom;") % {"b": bb}
    data = ("data=" + urllib.parse.quote(q)).encode()
    for ep in endpoints:
        try:
            log("osm: asking %s" % ep)
            body = http(ep, data=data, tries=2, timeout=240, cache_ext=".json", allow_404=False)
            doc = json.loads(body)
            els = doc.get("elements", [])
            log("osm: %d ways and relations" % len(els))
            return els
        except Exception as ex:
            log("osm: %s did not answer (%s)" % (ep, str(ex)[:120]))
    log("osm: no Overpass server answered; WorldCover alone")
    return None


def _rings(el):
    """The closed rings of a way or a multipolygon relation, as lists of
    (lat, lon), each tagged outer or inner."""
    if el["type"] == "way":
        g = el.get("geometry") or []
        pts = [(p["lat"], p["lon"]) for p in g if p]
        if len(pts) >= 3:
            return [("outer", pts)]
        return []
    chains = {"outer": [], "inner": []}
    for m in el.get("members", []):
        if m.get("type") != "way" or not m.get("geometry"):
            continue
        role = "inner" if m.get("role") == "inner" else "outer"
        pts = [(p["lat"], p["lon"]) for p in m["geometry"] if p]
        if len(pts) >= 2:
            chains[role].append(pts)
    out = []
    for role, parts in chains.items():
        parts = [list(p) for p in parts]
        while parts:
            ring = parts.pop(0)
            changed = True
            while ring[0] != ring[-1] and changed:
                changed = False
                for i, p in enumerate(parts):
                    if p[0] == ring[-1]:
                        ring += p[1:]
                    elif p[-1] == ring[-1]:
                        ring += p[-2::-1]
                    elif p[-1] == ring[0]:
                        ring = p[:-1] + ring
                    elif p[0] == ring[0]:
                        ring = p[::-1][:-1] + ring
                    else:
                        continue
                    parts.pop(i)
                    changed = True
                    break
            if len(ring) >= 3:
                out.append((role, ring))
    return out


def fill_rings(sq, rings, out, value=1.0):
    """Even-odd scan fill of rings (local metres) into `out` (max)."""
    edges = []
    for ring in rings:
        x, z = ring[:, 0], ring[:, 1]
        edges.append(np.stack([x, z, np.roll(x, -1), np.roll(z, -1)], axis=1))
    if not edges:
        return
    e = np.concatenate(edges)
    e = e[e[:, 1] != e[:, 3]]
    if len(e) == 0:
        return
    res, half, n = sq.res, sq.half, sq.n
    zmin, zmax = min(e[:, 1].min(), e[:, 3].min()), max(e[:, 1].max(), e[:, 3].max())
    j0 = max(int(math.ceil((zmin + half) / res)), 0)
    j1 = min(int(math.floor((zmax + half) / res)), n - 1)
    za, zb = np.minimum(e[:, 1], e[:, 3]), np.maximum(e[:, 1], e[:, 3])
    for j in range(j0, j1 + 1):
        zc = -half + j * res
        act = (za <= zc) & (zb > zc)
        if not act.any():
            continue
        ea = e[act]
        t = (zc - ea[:, 1]) / (ea[:, 3] - ea[:, 1])
        xs = np.sort(ea[:, 0] + t * (ea[:, 2] - ea[:, 0]))
        for k in range(0, len(xs) - 1, 2):
            i0 = max(int(math.ceil((xs[k] + half) / res)), 0)
            i1 = min(int(math.floor((xs[k + 1] + half) / res)), n - 1)
            if i1 >= i0:
                np.maximum(out[j, i0:i1 + 1], value, out=out[j, i0:i1 + 1])


def stroke_line(sq, pts, width, out, value=1.0):
    """A polyline (local metres) `width` wide, antialiased, into `out` (max)."""
    res, half, n = sq.res, sq.half, sq.n
    r = width * 0.5
    for k in range(len(pts) - 1):
        ax, az = pts[k]
        bx, bz = pts[k + 1]
        i0 = max(int(math.floor((min(ax, bx) - r - res + half) / res)), 0)
        i1 = min(int(math.ceil((max(ax, bx) + r + res + half) / res)), n - 1)
        j0 = max(int(math.floor((min(az, bz) - r - res + half) / res)), 0)
        j1 = min(int(math.ceil((max(az, bz) + r + res + half) / res)), n - 1)
        if i1 < i0 or j1 < j0:
            continue
        xs = -half + np.arange(i0, i1 + 1) * res
        zs = -half + np.arange(j0, j1 + 1) * res
        X, Z = np.meshgrid(xs, zs)
        dx, dz = bx - ax, bz - az
        l2 = dx * dx + dz * dz
        t = np.clip(((X - ax) * dx + (Z - az) * dz) / max(l2, 1e-9), 0.0, 1.0)
        d = np.hypot(X - (ax + t * dx), Z - (az + t * dz))
        cov = np.clip((r + res * 0.5 - d) / res, 0.0, 1.0) * value
        sub = out[j0:j1 + 1, i0:i1 + 1]
        np.maximum(sub, cov, out=sub)


ROAD_WIDTH = {"motorway": 14, "trunk": 12, "primary": 10, "secondary": 8, "tertiary": 7,
              "motorway_link": 7, "trunk_link": 7, "primary_link": 6, "secondary_link": 6,
              "tertiary_link": 5, "unclassified": 5, "residential": 5.5, "living_street": 5,
              "service": 3.5, "pedestrian": 5, "track": 3.0, "path": 1.4, "footway": 1.6,
              "cycleway": 2.0, "bridleway": 1.6, "steps": 1.6, "road": 5}
UNPAVED_HW = {"track", "path", "bridleway", "footway"}
PAVED = {"paved", "asphalt", "concrete", "concrete:plates", "paving_stones", "sett",
         "cobblestone", "metal", "wood"}
UNPAVED = {"unpaved", "gravel", "fine_gravel", "dirt", "earth", "ground", "grass",
           "compacted", "mud", "sand", "pebblestone", "rock"}
STREAM_MAX = 4.0
WATERWAY_WIDTH = {"river": 12.0, "canal": 8.0, "stream": 2.5, "ditch": 1.5, "drain": 1.5,
                  "tidal_channel": 6.0}


def _width(tags, default):
    w = tags.get("width", "")
    m = re.match(r"^\s*([0-9.]+)", w)
    if m:
        try:
            return max(float(m.group(1)), 0.5)
        except ValueError:
            pass
    return default


def rasterise_osm(sq, els):
    """Every OSM layer the region uses, on the 2 m grid."""
    shape = (sq.n, sq.n)
    lay = {k: np.zeros(shape, np.float32) for k in (
        "water", "water_river", "water_lake", "water_sea", "waterway", "river_line", "stream",
        "paved", "unpaved", "rail", "building", "conifer_on", "broad_on",
        "rock", "scree", "sand", "wetland", "glacier", "grass", "farm", "built",
        "scrub", "forest")}

    def loc(pts):
        lat = np.array([p[0] for p in pts])
        lon = np.array([p[1] for p in pts])
        x, z = sq.local(lat, lon)
        return np.stack([x, z], axis=1)

    for el in els:
        tags = el.get("tags", {})
        if not tags:
            continue
        nat, lu, ww = tags.get("natural"), tags.get("landuse"), tags.get("waterway")
        hw, rw = tags.get("highway"), tags.get("railway")
        area_tag = (nat == "water" or "water" in tags or ww == "riverbank"
                    or lu in ("reservoir", "basin"))
        line_way = el["type"] == "way" and (hw or rw or (ww in WATERWAY_WIDTH))
        if line_way and not area_tag and tags.get("area") != "yes":
            if tags.get("tunnel") not in (None, "no") or tags.get("bridge") not in (None, "no"):
                continue
            if tags.get("layer", "0").startswith("-") and not ww:
                continue
            g = el.get("geometry") or []
            pts = loc([(p["lat"], p["lon"]) for p in g if p])
            if len(pts) < 2:
                continue
            if ww:
                # a stream narrower than the 4 m water grid is a pebbled
                # channel, not a sliver of water broken into fragments
                wd = _width(tags, WATERWAY_WIDTH[ww])
                if wd < STREAM_MAX:
                    stroke_line(sq, pts, max(wd, 1.5) + 1.0, lay["stream"])
                    continue
                stroke_line(sq, pts, wd, lay["waterway"])
                if ww in ("river", "canal"):
                    stroke_line(sq, pts, wd, lay["river_line"])
            elif hw:
                if hw in ("proposed", "construction", "raceway", "elevator", "corridor", "via_ferrata", "platform"):
                    continue
                wd = _width(tags, ROAD_WIDTH.get(hw, 3.0))
                surf = tags.get("surface", "")
                paved = surf in PAVED or (surf not in UNPAVED and hw not in UNPAVED_HW)
                if hw == "track" and surf not in PAVED:
                    paved = False
                stroke_line(sq, pts, wd, lay["paved" if paved else "unpaved"])
            elif rw:
                stroke_line(sq, pts, 4.0 if rw in ("rail", "narrow_gauge") else 3.0, lay["rail"])
            continue
        rings = _rings(el)
        if not rings:
            continue
        outer = [loc(r) for role, r in rings if role == "outer"]
        inner = [loc(r) for role, r in rings if role == "inner"]
        if el["type"] == "way" and (el["geometry"][0] != el["geometry"][-1]):
            continue    # an unclosed way is a line, not an area
        target = []
        if area_tag:
            target.append("water")
            wt = tags.get("water", "")
            if wt in ("river", "stream", "canal", "stream_pool", "rapids", "oxbow") or ww == "riverbank":
                target.append("water_river")
            elif wt in ("sea", "bay", "lagoon", "strait") or nat in ("bay", "strait"):
                target.append("water_sea")
            else:
                target.append("water_lake")
        elif "building" in tags and tags.get("building") != "no":
            if tags.get("location") in ("underground",):
                continue
            target.append("building")
        else:
            if nat == "wood" or lu == "forest":
                target.append("forest")
                lt = tags.get("leaf_type", "")
                if lt == "needleleaved":
                    target.append("conifer_on")
                elif lt == "broadleaved":
                    target.append("broad_on")
                elif lt == "mixed":
                    target += ["conifer_on", "broad_on"]
            if nat == "bare_rock":
                target.append("rock")
            if nat in ("scree", "shingle") or lu == "quarry":
                target.append("scree")
            if nat in ("sand", "beach"):
                target.append("sand")
            if nat in ("wetland", "mud"):
                target.append("wetland")
            if nat == "glacier":
                target.append("glacier")
            if nat in ("grassland", "fell", "tundra") or lu in ("meadow", "grass", "village_green", "recreation_ground") \
                    or tags.get("leisure") in ("park", "pitch", "golf_course", "garden"):
                target.append("grass")
            if nat in ("scrub", "heath"):
                target.append("scrub")
            if lu in ("farmland", "allotments", "orchard", "vineyard", "plant_nursery"):
                target.append("farm")
            if lu in ("residential", "commercial", "industrial", "retail", "railway", "garages", "construction"):
                target.append("built")
        if not target:
            continue
        buf = np.zeros(shape, np.float32)
        fill_rings(sq, outer + inner, buf)
        for t in target:
            np.maximum(lay[t], buf, out=lay[t])
    return lay


# ---------------------------------------------------------------- the work

def build(args):
    sq = Square(args.lat, args.lon, args.size, 2.0)
    n = sq.n
    log("%s: %.0f m square round %.5f, %.5f, %d x %d samples at 2 m"
        % (args.name, args.size, args.lat, args.lon, n, n))

    # ---- height
    if args.dem == "copernicus":
        dem = copernicus(sq)
    else:
        dem = terrarium(sq, args.zoom)
    log("height: %.1f .. %.1f m" % (dem.min(), dem.max()))

    # ---- what is on the ground
    if args.smooth > 0.0:
        # the DEMs under the tiles are 30 m data brought up to 6 m, and it
        # shows as a 30 m checker on every slope; there is nothing real
        # that fine in them to lose
        dem = blur(dem, args.smooth / 2.0)
    warp_x = value_noise((n, n), 12.0, 11, 3) * 7.0
    warp_z = value_noise((n, n), 12.0, 12, 3) * 7.0
    frac = worldcover(sq, warp_x, warp_z)
    classes = sorted(frac)
    stack = np.stack([frac[c] for c in classes])
    wc = np.asarray(classes, np.int32)[np.argmax(stack, axis=0)]
    log("cover: " + ", ".join("%d %.0f%%" % (c, 100.0 * float(frac[c].mean())) for c in classes))

    def wcf(*cs):
        """The share of these classes at every sample."""
        a = np.zeros((n, n), np.float64)
        for c in cs:
            if c in frac:
                a += frac[c]
        return a

    osm = None
    if not args.no_osm:
        eps = list(args.overpass or OVERPASS)
        if not args.overpass and CH_BOX[0] <= args.lat <= CH_BOX[2] and CH_BOX[1] <= args.lon <= CH_BOX[3]:
            eps.insert(0, OVERPASS_CH)
        els = overpass(sq, eps)
        if els is not None:
            osm = rasterise_osm(sq, els)
    zero = np.zeros((n, n), np.float32)
    O = osm if osm is not None else {}

    def o(k):
        return O.get(k, zero)

    # ---- water
    wc_water = wcf(80)
    osm_water = np.maximum(o("water"), o("waterway"))
    if osm is not None and osm_water.max() > 0.0:
        # OSM's shorelines are drawn by hand to the metre; WorldCover's are
        # 10 m pixels. Where OSM has water, it is believed; WorldCover only
        # adds water OSM has never heard of (well away from any of OSM's).
        near_osm = chamfer(osm_water >= 0.5, 2.0) < 30.0
        wc_water = np.where(near_osm, 0.0, wc_water)
    water_f = np.maximum(wc_water, osm_water)
    wmask = water_f >= 0.5
    lab, count = label(wmask)
    log("water: %d bodies before the speckle goes" % count)

    d_in = chamfer(~wmask, 2.0)          # inside water: metres to land
    d_out = chamfer(wmask, 2.0)          # on land: metres to water

    # a label and the land just round each body: three steps out
    ring_lab = lab.copy()
    for _ in range(3):
        grow = ring_lab.copy()
        for sh in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            moved = shift(ring_lab, sh, 0)
            take = (grow == 0) & (moved > 0)
            grow[take] = moved[take]
        ring_lab = grow
    ring = (ring_lab > 0) & (lab == 0)

    surface = np.full((n, n), np.nan)
    climb = np.zeros((n, n), np.float64)
    kind = np.zeros((n, n), np.uint8)
    bed = dem.copy()
    bodies = []
    touches_edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])).tolist())
    for b in range(1, count + 1):
        m = lab == b
        px = int(m.sum())
        area = px * 4.0
        if area < 60.0:
            wmask[m] = False
            lab[m] = 0
            continue
        rh = dem[ring & (ring_lab == b)]
        if rh.size == 0:
            rh = dem[m]
        inside = dem[m]
        dmax = float(d_in[m].max())
        p15 = float(np.percentile(rh, 15))
        river_votes = float(o("water_river")[m].mean() + o("river_line")[m].mean()
                            + 0.5 * o("waterway")[m].mean())
        lake_votes = float(o("water_lake")[m].mean())
        sea_votes = float(o("water_sea")[m].mean())
        elong = area / (math.pi * max(dmax, 1.0) ** 2)
        if (sea_votes > 0.3 or (p15 < 2.5 and (b in touches_edge or area > 2e5))) and float(np.percentile(rh, 5)) < 6.0:
            k, level = 1, 0.0
        elif river_votes > max(lake_votes, 0.2) or (lake_votes < 0.2 and elong > 6.0 and dmax < 60.0):
            k, level = 3, None
        else:
            k = 2
            med = float(np.median(inside))
            level = med if abs(med - p15) < 2.0 else p15
            level -= 0.1
        if k == 2:
            # A LAKE'S ARM THAT CLIMBS AWAY FROM IT — an outflow or an inflow
            # the maps drew joined to the lake — is not the lake: its ground
            # stands metres over the lake's level, and given that level it
            # would be cut into a trench. It is taken out of the water and
            # left a stream's pebbled channel.
            # (a small tarn on a slope the DEM never flattened has most of its
            # ground over a level read off its lowest shore: that level is the
            # wrong one, and the tarn's own middle height is the better guess)
            if float((dem[m] > level + 2.5).mean()) > 0.3:
                level = float(np.median(dem[m])) - 0.3
            high = m & (dem > level + 2.5)
            if high.any():
                climb[high] = 1.0
                wmask[high] = False
                lab[high] = 0
                m = m & ~high
                if float(m.sum()) * 4.0 < 60.0:
                    wmask[m] = False
                    lab[m] = 0
                    continue
                area = float(m.sum()) * 4.0
        if k == 3:
            # a river's surface falls with its banks: the banks' heights
            # relaxed across it (Jacobi), then smoothed along it
            ys, xs = np.nonzero(m | (ring & (ring_lab == b)))
            y0, y1 = max(ys.min() - 1, 0), min(ys.max() + 2, n)
            x0, x1 = max(xs.min() - 1, 0), min(xs.max() + 2, n)
            mm = m[y0:y1, x0:x1]
            rr = ring[y0:y1, x0:x1] & (ring_lab[y0:y1, x0:x1] == b)
            s = np.where(rr, dem[y0:y1, x0:x1], np.nan)
            seed = np.nanmean(s) if np.isfinite(s).any() else float(np.median(inside))
            s = np.where(mm, seed, s)
            known = mm | rr
            for _ in range(int(min(max(dmax, 4.0) * 3.0, 400.0))):
                p = np.pad(s, 1, mode="edge")
                kp = np.pad(known, 1, mode="constant")
                acc = np.zeros_like(s)
                wsum = np.zeros_like(s)
                for a, c in ((0, 1), (2, 1), (1, 0), (1, 2)):
                    v = p[a:a + s.shape[0], c:c + s.shape[1]]
                    kk = kp[a:a + s.shape[0], c:c + s.shape[1]]
                    acc += np.where(kk, v, 0.0)
                    wsum += kk
                s = np.where(mm, acc / np.maximum(wsum, 1.0), s)
            sm = blur(np.where(mm, s, 0.0), 3.0) / np.maximum(blur(mm.astype(np.float64), 3.0), 1e-6)
            s = np.where(mm, np.minimum(s, sm) - 0.25, np.nan)
            surface[y0:y1, x0:x1] = np.where(mm, s, surface[y0:y1, x0:x1])
            level_out = float(np.nanmedian(s[mm]))
        else:
            surface[m] = level
            level_out = level
        kind[m] = k
        # the bed: the DEM where it already lies below the water (a sea's
        # soundings, a lidar lake), carved where the DEM is the flat top
        # of the water, which is all most of them are
        if k == 2:
            deep = float(np.clip(dmax * 0.2, 2.0, 35.0))
            t = np.clip(d_in[m] / max(0.6 * dmax, 1.0), 0.0, 1.0)
            depth = 0.4 + deep * t * (2.0 - t)
        elif k == 3:
            deep = float(np.clip(dmax * 0.3, 0.8, 4.0))
            depth = np.minimum(0.4 + d_in[m] * 0.5, deep)
        else:
            depth = np.minimum(0.5 + d_in[m] * 0.05, 30.0)
        sb = surface[m] - depth
        bed[m] = np.maximum(np.minimum(dem[m], sb), surface[m] - 80.0)
        name = ""
        bodies.append({"id": b, "kind": ["", "sea", "lake", "river"][k], "level": round(level_out, 2),
                       "area_m2": round(area), "half_width_m": round(dmax, 1)})
    log("water: " + (", ".join("%s %.0f m2 at %.1f m" % (q["kind"], q["area_m2"], q["level"]) for q in bodies) or "none"))

    # the banks held up out of the water they hold, and the water carried a
    # few metres onto them so the mesh's edge always lies under the ground
    near = np.full((n, n), np.nan)
    near[wmask] = surface[wmask]
    for _ in range(4):
        p = np.pad(near, 1, mode="constant", constant_values=np.nan)
        for a, c in ((0, 1), (2, 1), (1, 0), (1, 2)):
            v = p[a:a + n, c:c + n]
            take = np.isnan(near) & np.isfinite(v)
            near[take] = v[take]
    height = np.where(wmask, bed, dem)
    stream = np.clip(blur(np.maximum(o("stream"), climb), 0.7), 0.0, 1.0) * (~wmask)
    height = height - 0.6 * stream
    bank = (~wmask) & np.isfinite(near)
    lift = near + 0.2 + 0.12 * d_out
    height = np.where(bank, np.maximum(height, lift), height)
    water_ext = near        # the surface, four steps past the shore
    kind_ext = kind.copy()
    for _ in range(4):
        grow = kind_ext.copy()
        for sh in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            mv = shift(kind_ext, sh, 0)
            take = (grow == 0) & (mv > 0)
            grow[take] = mv[take]
        kind_ext = grow
    kind_ext[np.isnan(water_ext)] = 0

    # ---- the surface layers
    W = np.zeros((len(LAYERS), n, n), np.float64)
    for c in classes:
        for lay, v in WC_LAYERS.get(c, {"grass": 1.0}).items():
            W[L[lay]] += v * frac[c]
    if osm is not None:
        nonforest = 1.0 - wcf(10, 95, 80)
        edge_noise = value_noise((n, n), 6.0, 41, 2) * 0.5 + value_noise((n, n), 30.0, 43, 2)

        def soft(k):
            # a hand-drawn polygon's straight sides, worn into an outline that
            # wanders tens of metres, not only a few
            return smoothstep(0.25, 0.75, blur(o(k), 5.0) + 0.35 * edge_noise)

        def push(layer, amount):
            a = np.clip(amount, 0.0, 1.0)
            W[:] *= (1.0 - a)[None]
            W[L[layer]] += a

        push("rock", 0.8 * soft("rock") * nonforest)
        push("scree", 0.8 * soft("scree") * nonforest)
        push("sand", soft("sand") * nonforest)
        push("mud", 0.6 * soft("wetland") * wcf(20, 30, 40, 90))
        push("snow", soft("glacier") * wcf(60, 70, 0, 100))
        push("soil", 0.4 * soft("farm") * wcf(30))
    for k in range(len(LAYERS)):
        W[k] = blur(W[k], 1.0)
    gy, gx = np.gradient(dem, 2.0)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    slope_s = blur(slope, 1.0)
    steep = smoothstep(36.0, 50.0, slope_s)
    steep_snow = smoothstep(52.0, 62.0, slope_s)
    rough = value_noise((n, n), 10.0, 21, 2)
    scree_slope = smoothstep(28.0, 40.0, slope_s) * np.clip(0.55 + 0.6 * rough, 0.0, 1.0) * (1.0 - steep)
    snow = W[L["snow"]].copy()
    rock_amt = np.where(snow > 0.5, steep_snow, steep)
    W *= (1.0 - rock_amt)[None]
    W[L["rock"]] += rock_amt
    grassy = W[L["grass"]] + W[L["dry"]] + W[L["moss"]]
    moved = grassy * scree_slope * 0.5
    for lay in ("grass", "dry", "moss"):
        W[L[lay]] *= (1.0 - scree_slope * 0.5)
    W[L["scree"]] += moved
    # shores: a beach on the sea, a pebble rim on a lake or a river
    shore = np.clip(1.0 - d_out / 7.0, 0.0, 1.0) * (~wmask) * np.isfinite(near)
    shore *= (height < np.nan_to_num(near, nan=-1e9) + 2.5)
    sea_near = (kind_ext == 1)
    for lay, where in (("sand", sea_near), ("scree", ~sea_near)):
        a = shore * where * 0.75
        W *= (1.0 - a)[None]
        W[L[lay]] += a
    # roads, rails and buildings on top, sharp
    for lay, amount in (("scree", 0.85 * stream), ("soil", o("unpaved")), ("scree", o("rail")),
                        ("paving", o("paved")), ("paving", o("building"))):
        a = np.clip(amount, 0.0, 1.0)
        W *= (1.0 - a)[None]
        W[L[lay]] += a
    # under the water, the bed (sand in the sea, near its shore)
    sea_bed = (kind == 1)
    W[:, wmask] = 0.0
    W[L["bed"]][wmask & ~sea_bed] = 1.0
    sbl = np.clip(1.0 - d_in / 60.0, 0.0, 1.0)
    W[L["sand"]][sea_bed] = sbl[sea_bed]
    W[L["bed"]][sea_bed] = 1.0 - sbl[sea_bed]
    W = np.maximum(W, 0.0)
    W /= np.maximum(W.sum(axis=0), 1e-6)[None]

    # ---- the plants
    tree = blur(wcf(10) + 0.6 * wcf(95), 1.0)
    clear = np.clip(o("paved") + o("unpaved") + o("rail") + o("building"), 0.0, 1.0)
    clear = np.clip(blur(clear, 1.0) * 2.0, 0.0, 1.0)
    no_plant = np.clip(clear + wmask + W[L["rock"]] + W[L["snow"]] + W[L["paving"]] * 0.8
                       + W[L["sand"]], 0.0, 1.0)
    tree = np.clip(tree * (1.0 - no_plant) * (1.0 - smoothstep(34.0, 46.0, slope_s)), 0.0, 1.0)
    # the conifer share: OSM's leaf type where it is mapped; otherwise the
    # climate's guess, firs climbing in over the beeches with altitude and
    # with latitude
    alat = abs(args.lat)
    lo = float(np.clip(1500.0 - 25.0 * (alat - 20.0), 0.0, 2600.0))
    hi = lo + 700.0
    guess = np.clip(smoothstep(lo, hi, dem) + smoothstep(52.0, 60.0, alat), 0.0, 1.0)
    guess = np.clip(guess + 0.25 * value_noise((n, n), 40.0, 31, 2), 0.0, 1.0)
    con_on, brd_on = blur(o("conifer_on"), 2.0), blur(o("broad_on"), 2.0)
    mapped = np.clip(con_on + brd_on, 0.0, 1.0)
    told = con_on / np.maximum(con_on + brd_on, 1e-6)
    conifer = guess * (1.0 - mapped) + told * mapped
    edge = np.clip(blur(tree, 4.0) * (1.0 - tree) * 3.0, 0.0, 1.0)
    bush = (0.85 * wcf(20) + 0.12 * W[L["grass"]]
            + 0.4 * edge + 0.3 * W[L["mud"]] + 0.25 * o("scrub") + 0.15 * W[L["moss"]]
            + 0.35 * np.clip(blur(stream, 3.0) * 2.0, 0.0, 1.0) * (1.0 - stream))
    bush = np.clip(bush * (1.0 - no_plant) * (1.0 - smoothstep(38.0, 50.0, slope_s)), 0.0, 1.0)
    grass = (W[L["grass"]] + 0.45 * W[L["soil"]] + 0.85 * W[L["mud"]] + 0.5 * W[L["moss"]]
             + 0.6 * W[L["dry"]] + 0.2 * W[L["forest"]] + 0.25 * W[L["scree"]])
    grass = np.clip(grass * (1.0 - no_plant), 0.0, 1.0)

    # ---- out
    # the island's y = 0: a metre under the lowest ground, so the cliff all
    # round always falls from the edge, never climbs (a sea's surface then
    # stands at -datum)
    datum = math.floor(float(height.min()) - 1.0)
    out = os.path.join(EARTH, args.name)
    os.makedirs(os.path.join(out, "preview"), exist_ok=True)
    open(os.path.join(out, "preview", ".gdignore"), "w").close()
    hmin, hmax = float(height.min()), float(height.max())
    scale = max((hmax - hmin) / 65000.0, 0.001)
    q = np.clip(np.round((height - hmin) / scale), 0, 65535).astype("<u2")
    files = {}
    files["height.grid"] = write_grid(os.path.join(out, "height.grid"), q, 1)

    def at4(a):
        return a[::2, ::2]

    # water at 4 m: any water in the 2 m neighbourhood keeps the cell wet
    w2 = water_ext
    w4 = at4(w2).copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            sh = shift(w2, (dy, dx), np.nan)[::2, ::2]
            take = np.isnan(w4) & np.isfinite(sh)
            w4[take] = sh[take]
    k4 = at4(kind_ext).copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            sh = shift(kind_ext, (dy, dx), 0)[::2, ::2]
            take = (k4 == 0) & (sh > 0)
            k4[take] = sh[take]
    k4[np.isnan(w4)] = 0
    files["water.grid"] = write_grid(os.path.join(out, "water.grid"), w4.astype("<f4"), 3)
    files["wkind.grid"] = write_grid(os.path.join(out, "wkind.grid"), k4.astype(np.uint8), 2)
    Wq = np.clip(np.round(np.stack([blur(W[k], 0.6)[::2, ::2] for k in range(len(LAYERS))], axis=-1) * 255.0),
                 0, 255).astype(np.uint8)
    # three RGBA planes one above the other, four layers each: each plane is
    # a picture the terrain shader can take as it stands
    n4 = Wq.shape[0]
    planes = np.concatenate([Wq[..., 4 * k:4 * k + 4] for k in range(3)], axis=0)
    files["cover.grid"] = write_grid(os.path.join(out, "cover.grid"), planes, 2)
    V = np.stack([at4(blur(tree, 0.8)), at4(conifer), at4(blur(bush, 0.8)), at4(blur(grass, 0.8))], axis=-1)
    files["veg.grid"] = write_grid(os.path.join(out, "veg.grid"),
                                   np.clip(np.round(V * 255.0), 0, 255).astype(np.uint8), 2)
    digest = hashlib.sha256()
    for k in sorted(files):
        digest.update(files[k].encode())
    region = {
        "name": args.name,
        "title": args.title or args.name.upper(),
        "lat": args.lat, "lon": args.lon, "size": float(args.size),
        "datum": datum,
        "height": {"file": "height.grid", "n": n, "res": 2.0, "offset": hmin, "scale": scale,
                   "min": round(hmin, 2), "max": round(hmax, 2)},
        "water": {"file": "water.grid", "kind": "wkind.grid", "n": w4.shape[0], "res": 4.0},
        "cover": {"file": "cover.grid", "n": n4, "res": 4.0, "planes": 3, "layers": LAYERS},
        "veg": {"file": "veg.grid", "n": V.shape[0], "res": 4.0,
                "channels": ["tree", "conifer", "bush", "grass"]},
        "bodies": bodies,
        "sources": {
            "height": ("Copernicus GLO-30 DEM (ESA, Copernicus programme)" if args.dem == "copernicus"
                       else "AWS Terrain Tiles, Terrarium, zoom %d (Mapzen: SRTM, GMTED, ETOPO1, "
                            "national lidar)" % args.zoom),
            "cover": "ESA WorldCover 10 m 2021 v200 (CC BY 4.0)",
            "osm": "OpenStreetMap contributors (ODbL), via Overpass" if osm is not None else "not used",
        },
        "attribution": "Height: %s. Land cover: © ESA WorldCover project 2021 / Contains modified "
                       "Copernicus Sentinel data (2021) processed by ESA WorldCover consortium. "
                       "Map data: © OpenStreetMap contributors." % (
                           "Copernicus DEM © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018"
                           if args.dem == "copernicus" else "Mapzen Terrain Tiles"),
        "digest": digest.hexdigest()[:24],
        "made": datetime.date.today().isoformat(),
        "tool": "tools/earth_fetch.py",
    }
    with open(os.path.join(out, "region.json"), "w") as f:
        json.dump(region, f, indent=1)
    previews(out, height, dem, W, V, w2, wmask)
    log("wrote %s (digest %s)" % (os.path.relpath(out, ROOT), region["digest"]))
    if args.register:
        register(args, region)


def write_grid(path, arr, typ):
    """MEWDGRD1, then width, height (u32), type (u8: 1 u16, 2 u8, 3 f32),
    channels (u8), two pad bytes, the raw little-endian samples' length
    (u32), then the samples, zlib'd. Returns the samples' SHA-256."""
    a = np.ascontiguousarray(arr)
    h, w = a.shape[:2]
    ch = a.shape[2] if a.ndim == 3 else 1
    raw = a.tobytes()
    with open(path, "wb") as f:
        f.write(b"MEWDGRD1")
        f.write(struct.pack("<IIBBHI", w, h, typ, ch, 0, len(raw)))
        f.write(zlib.compress(raw, 9))
    return hashlib.sha256(raw).hexdigest()


COLOURS = {"grass": (96, 140, 60), "forest": (52, 82, 40), "rock": (120, 116, 110),
           "scree": (160, 154, 140), "sand": (214, 196, 150), "soil": (130, 100, 70),
           "snow": (240, 244, 250), "mud": (90, 80, 60), "paving": (90, 90, 96),
           "dry": (150, 140, 90), "moss": (110, 120, 80), "bed": (50, 80, 110)}


def previews(out, height, dem, W, V, water, wmask):
    p = os.path.join(out, "preview")
    gy, gx = np.gradient(height, 2.0)
    shade = np.clip(0.55 + 0.45 * (-gx * 0.7 + gy * 0.7) / np.sqrt(1 + gx * gx + gy * gy) * 2.0, 0, 1)
    hn = (height - height.min()) / max(height.max() - height.min(), 1e-6)
    rgb = np.stack([0.35 + 0.6 * hn, 0.45 + 0.4 * hn, 0.3 + 0.55 * hn], axis=-1) * shade[..., None]
    rgb[wmask] = rgb[wmask] * 0.4 + np.array([0.15, 0.3, 0.5]) * 0.6
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(p, "height.png"))
    cols = np.array([COLOURS[n] for n in LAYERS], np.float64) / 255.0
    cov = np.tensordot(np.moveaxis(W, 0, -1), cols, axes=([2], [0])) * (0.6 + 0.4 * shade[..., None])
    Image.fromarray((np.clip(cov, 0, 1) * 255).astype(np.uint8)).save(os.path.join(p, "cover.png"))
    vv = np.stack([V[..., 0] * (1 - V[..., 1]), V[..., 0] * V[..., 1] * 0.7 + V[..., 3] * 0.3, V[..., 2]], axis=-1)
    Image.fromarray((np.clip(vv, 0, 1) * 255).astype(np.uint8)).save(os.path.join(p, "veg.png"))


TEMPLATE = "oeschinen"


def _no_uid(text):
    """A copied scene or resource keeps no UID: Godot gives it its own."""
    return re.sub(r'^(\[gd_(?:scene|resource)[^\]]*?) uid="uid://[a-z0-9]+"', r"\1", text, flags=re.M)


def register(args, region):
    """The field, the scene and the Islands entry, so the viewer lists it.
    The field and the scene are the sample region's (Oeschinensee) with
    the paths and the size changed."""
    name = args.name
    key = "earth_" + name
    edir = os.path.join(EARTH, name)
    tdir = os.path.join(EARTH, TEMPLATE)
    tkey = "earth_" + TEMPLATE
    field_path = "res://godot/island/earth/%s/ISLANDFIELD_%s.tres" % (name, key)
    scene_path = "res://godot/island/earth/%s/%s.tscn" % (name, key)
    if name != TEMPLATE:
        try:
            with open(os.path.join(tdir, "ISLANDFIELD_%s.tres" % tkey)) as f:
                tres = f.read()
            with open(os.path.join(tdir, "%s.tscn" % tkey)) as f:
                tscn = f.read()
        except OSError:
            sys.exit("earth_fetch: --register copies godot/island/earth/%s's field and scene, "
                     "which are missing" % TEMPLATE)
        tres = _no_uid(tres).replace("res://godot/island/earth/%s" % TEMPLATE,
                                     "res://godot/island/earth/" + name)
        tres = re.sub(r"hub_radius = [0-9.]+", "hub_radius = %.1f" % (region["size"] / 2.0), tres)
        with open(os.path.join(edir, "ISLANDFIELD_%s.tres" % key), "w") as f:
            f.write(tres)
        old = "res://godot/island/earth/%s/ISLANDFIELD_%s.tres" % (TEMPLATE, tkey)
        tscn = _no_uid(tscn)
        tscn = re.sub(r' uid="uid://[a-z0-9]+"( path="%s")' % re.escape(old), r"\1", tscn)
        tscn = tscn.replace(old, field_path)
        with open(os.path.join(edir, "%s.tscn" % key), "w") as f:
            f.write(tscn)
    islands = os.path.join(ROOT, "godot", "scripts", "level", "islands.gd")
    with open(islands) as f:
        src = f.read()
    if '"key": "%s"' % key in src:
        log("islands.gd already lists %s" % key)
        return
    entry = ('\t# %s, from tools/earth_fetch.py: %.5f, %.5f, a %.0f m square\n'
             '\t{"key": "%s", "title": "%s", "scene": "%s",\n'
             '\t\t"blurb": "a real place: %.5f, %.5f", "palette": false,\n'
             '\t\t"sky": {"hour": 18.75, "day": 196, "weather": "fair"},\n'
             '\t\t"knee": 0.6,\n'
             '\t\t"grade": {"filmic": 1.0, "warmth": 0.2, "contrast": 0.14, "saturation": 1.05,\n'
             '\t\t\t"vibrance": 0.2, "split": 0.6, "lift": 0.04, "vignette": 0.32, "grain": 0.035}},\n'
             % (region["title"], region["lat"], region["lon"], region["size"], key, region["title"],
                scene_path, region["lat"], region["lon"]))
    i = src.index("const LIST := [")
    j = src.index("\n]", i)
    # the entry before ours needs its comma
    k = len(src[:j].rstrip())
    if src[k - 1] == "}":
        src = src[:k] + "," + src[k:]
        j += 1
    src = src[:j + 1] + entry + src[j + 1:]
    with open(islands, "w") as f:
        f.write(src)
    log("islands.gd: added %s; bake it with\n"
        "  godot --headless --script res://tools/bake_island.gd -- --map=%s" % (key, key))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", help="the region's name: lower case, letters, digits and _")
    ap.add_argument("--lat", type=float, required=True, help="the square's centre, degrees north")
    ap.add_argument("--lon", type=float, required=True, help="the square's centre, degrees east")
    ap.add_argument("--size", type=float, default=2500.0,
                    help="its side in metres, a multiple of 4, at most 6000 (2500)")
    ap.add_argument("--title", help="what the viewer calls it (NAME)")
    ap.add_argument("--dem", choices=["terrarium", "copernicus"], default="terrarium")
    ap.add_argument("--zoom", type=int, default=14, help="Terrarium zoom, 10-15 (14)")
    ap.add_argument("--smooth", type=float, default=8.0,
                    help="metres of blur on the DEM against its 30 m checker; 0 none (8)")
    ap.add_argument("--no-osm", action="store_true", help="WorldCover only, no OpenStreetMap")
    ap.add_argument("--overpass", action="append", help="an Overpass endpoint to ask first (repeatable)")
    ap.add_argument("--register", action="store_true",
                    help="also write the field, the scene and the Islands.LIST entry")
    args = ap.parse_args()
    if not re.match(r"^[a-z][a-z0-9_]*$", args.name):
        sys.exit("earth_fetch: the name is lower case letters, digits and _")
    if args.size < 256 or args.size > 6000 or int(args.size) % 4:
        sys.exit("earth_fetch: --size is 256 to 6000 m, a multiple of 4 (golf's islands are 2500)")
    build(args)


if __name__ == "__main__":
    main()
