#!/usr/bin/env python3
"""MEWD — CANDY LAND's gingerbread house, made ready for the game (at the
user's request: scattered round the town squares).

The house as it came (godot/island/candy/source/model/MODEL_candyLandHouse.glb,
the second cut) is painted on a 512 x 512 sheet, cut out — clear round the
paintings — with its painted material set to alpha BLEND, and its one node
called "...-col" (which Godot would turn into a physics body nobody asks
for). This writes godot/island/candy/models/MODEL_candyLandHouse.glb: the
cut-out kept, but as an alpha MASK (cut, not blended: no sorting, drawn
with everything else that is solid), the colour under the clear part
filled with the painting's own edge colour so the cut's edge and the
mipmaps show gingerbread, not black; the node plain. The mesh is untouched.
(A sheet with no alpha — the first cut, on a green screen — has its green
taken for the clear part.)

  python3 tools/candy-house-glb.py
"""
import io, json, struct, os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "godot/island/candy/source/model/MODEL_candyLandHouse.glb")
OUT = os.path.join(ROOT, "godot/island/candy/models/MODEL_candyLandHouse.glb")
SIZE = 512

def read_glb(path):
    f = open(path, "rb").read()
    jl = struct.unpack("<I", f[12:16])[0]
    j = json.loads(f[20:20 + jl])
    o = 20 + jl
    bl = struct.unpack("<I", f[o:o + 4])[0]
    return j, f[o + 8:o + 8 + bl]

def bleed(im):
    """Every clear pixel (green-screen, on a sheet with no alpha) given the
    colour of the nearest painted one; the alpha kept, or made."""
    a = np.asarray(im.convert("RGBA")).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    if "A" in im.getbands():
        green = a[..., 3] < 128
        alpha = a[..., 3].astype(np.uint8)
    else:
        green = g > np.maximum(r, b) + 12
        alpha = ((~green) * 255).astype(np.uint8)
    rgb = Image.fromarray(a[..., :3].astype(np.uint8))
    mask = Image.fromarray(((~green) * 255).astype(np.uint8))
    # grow the paintings outward a few pixels at a time over the green
    for _ in range(64):
        if mask.getextrema()[0] == 255:
            break
        m = np.asarray(mask) > 0
        # a mean of the painted neighbours, not the brightest
        ca = np.asarray(rgb).astype(np.float32) * m[..., None]
        k = ImageFilter.BoxBlur(1)
        num = np.stack([np.asarray(Image.fromarray(ca[..., c].astype(np.uint8)).filter(k)).astype(np.float32) for c in range(3)], -1)
        den = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(k)).astype(np.float32) / 255.0
        fill = num / np.maximum(den[..., None], 1e-3)
        new = (~m) & (den > 0.01)
        out = np.asarray(rgb).copy()
        out[new] = np.clip(fill[new], 0, 255).astype(np.uint8)
        rgb = Image.fromarray(out)
        mask = Image.fromarray(((m | new) * 255).astype(np.uint8))
    out = rgb.convert("RGBA")
    out.putalpha(Image.fromarray(alpha))
    return out

def main():
    j, binbuf = read_glb(SRC)
    img = j["images"][0]
    bv = j["bufferViews"][img["bufferView"]]
    o = bv.get("byteOffset", 0)
    im = Image.open(io.BytesIO(binbuf[o:o + bv["byteLength"]]))
    im = bleed(im if im.size == (SIZE, SIZE) else im.resize((SIZE, SIZE), Image.LANCZOS))
    png = io.BytesIO()
    im.save(png, "PNG", optimize=True)
    # the buffer again, the sheet's view swapped for the new one
    chunks = []
    off = 0
    for i, v in enumerate(j["bufferViews"]):
        s = v.get("byteOffset", 0)
        data = png.getvalue() if i == img["bufferView"] else binbuf[s:s + v["byteLength"]]
        v["byteOffset"] = off
        v["byteLength"] = len(data)
        pad = (-len(data)) % 4
        chunks.append(data + b"\0" * pad)
        off += len(data) + pad
    newbin = b"".join(chunks)
    j["buffers"][0]["byteLength"] = len(newbin)
    img["name"] = "TEXTURE_candyLandHouse"
    for m in j["materials"]:
        m.pop("alphaMode", None)
        m.pop("alphaCutoff", None)
    j["materials"][0]["alphaMode"] = "MASK"
    j["materials"][0]["alphaCutoff"] = 0.5
    j["materials"][0]["name"] = "MATERIAL_candyLandHouse"
    for n in j["nodes"]:
        n["name"] = n["name"].replace("-col", "")
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    out = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(newbin))
    out += struct.pack("<I", len(js)) + b"JSON" + js
    out += struct.pack("<I", len(newbin)) + b"BIN\0" + newbin
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "wb").write(out)
    print("wrote %s (%d KB)" % (OUT, len(out) // 1024))

if __name__ == "__main__":
    main()
