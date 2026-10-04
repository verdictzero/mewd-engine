#!/usr/bin/env python3
"""MEWD — THE DROP POD'S TEXTURES DE-RESSED AND DITHERED (at the user's
request: "appropriately de-res the model's textures and apply RGB 32 32
32 bayer dithering to the color textures (after resize)").

Reads a GLB, shrinks every image in it — the colour maps (base colour,
emissive) to COLOUR_SIZE across, the rest (metal/rough, normal, AO) to
DATA_SIZE — and ORDERED-DITHERS the colour maps to 32 levels a channel
(5 bits: RGB 32 32 32) with an 8x8 Bayer matrix, after the resize, so
the dither is at the texels' own scale. The data maps are only shrunk:
dither on a normal map is noise in the lighting. Writes the GLB back
with the new images, everything else as it was.

    python3 tools/pod-textures.py in.glb out.glb
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

COLOUR_SIZE = 512
DATA_SIZE = 256
LEVELS = 32

BAYER8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21]], dtype=np.float32) / 64.0


def dither(im: Image.Image) -> Image.Image:
    """32 levels a channel, the Bayer threshold deciding each texel's round."""
    rgba = im.convert("RGBA")
    a = np.asarray(rgba).astype(np.float32)
    h, w = a.shape[:2]
    t = np.tile(BAYER8, (h // 8 + 1, w // 8 + 1))[:h, :w] - 0.5
    rgb = a[..., :3] / 255.0 * (LEVELS - 1)
    q = np.clip(np.floor(rgb + t[..., None] + 0.5), 0, LEVELS - 1)
    a[..., :3] = q / (LEVELS - 1) * 255.0
    out = Image.fromarray(a.astype(np.uint8), "RGBA")
    return out if im.mode == "RGBA" else out.convert(im.mode)


def is_colour(name: str, gltf: dict, index: int) -> bool:
    """a base colour or emissive map, by what the materials use it for"""
    for m in gltf.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        for key in (pbr.get("baseColorTexture"), m.get("emissiveTexture")):
            if key is not None and gltf["textures"][key["index"]]["source"] == index:
                return True
    return False


def main(src: str, dst: str) -> None:
    d = open(src, "rb").read()
    ln = struct.unpack("<I", d[12:16])[0]
    gltf = json.loads(d[20:20 + ln])
    off = 20 + ln
    cl = struct.unpack("<I", d[off:off + 4])[0]
    bin0 = d[off + 8:off + 8 + cl]
    views = gltf["bufferViews"]
    # every buffer view copied over, the images' replaced
    new_bin = bytearray()
    new_views = []
    image_views = {img["bufferView"]: i for i, img in enumerate(gltf["images"])}
    for vi, bv in enumerate(views):
        start = bv.get("byteOffset", 0)
        data = bin0[start:start + bv["byteLength"]]
        if vi in image_views:
            idx = image_views[vi]
            im = Image.open(io.BytesIO(data))
            colour = is_colour(gltf["images"][idx]["name"], gltf, idx)
            size = COLOUR_SIZE if colour else DATA_SIZE
            if max(im.size) > size:
                im = im.resize((size, size * im.size[1] // im.size[0]), Image.LANCZOS)
            if colour:
                im = dither(im)
            buf = io.BytesIO()
            im.save(buf, "PNG", optimize=True)
            data = buf.getvalue()
            print("  %-70s %s -> %dx%d%s, %d KB" % (gltf["images"][idx]["name"], "colour" if colour else "data",
                im.size[0], im.size[1], ", dithered" if colour else "", len(data) // 1024))
        while len(new_bin) % 4:
            new_bin.append(0)
        nv = dict(bv)
        nv["byteOffset"] = len(new_bin)
        nv["byteLength"] = len(data)
        new_views.append(nv)
        new_bin += data
    while len(new_bin) % 4:
        new_bin.append(0)
    gltf["bufferViews"] = new_views
    gltf["buffers"][0]["byteLength"] = len(new_bin)
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(new_bin)
    out = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js \
        + struct.pack("<II", len(new_bin), 0x004E4942) + bytes(new_bin)
    open(dst, "wb").write(out)
    print("%s: %d KB -> %d KB" % (dst, len(d) // 1024, len(out) // 1024))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
