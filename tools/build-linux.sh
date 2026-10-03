#!/bin/sh
# =====================================================================
# MEWD — the Linux build: one file, the game packed inside it
# (.github/workflows/linux.yml)
# =====================================================================
#
#   tools/build-linux.sh [out.x86_64]
#
# Godot 4.7's Linux x86_64 templates are fetched if they are not there.
# Only those two files are read out of the 1 GB template archive, by
# range request. The export is the "Linux" preset: the Mobile renderer on
# Vulkan, with S3TC/BPTC textures. It runs on Ubuntu 20.04 or later with
# a Vulkan driver (mesa's, or NVIDIA's):
#   chmod +x mewd.x86_64 && ./mewd.x86_64
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${1:-build/linux/mewd.x86_64}"
T="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.stable"
if [ ! -f "$T/linux_release.x86_64" ]; then
  mkdir -p "$T"
  python3 - "$T" <<'PY'
import io, sys, urllib.request, zipfile
url = "https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_export_templates.tpz"
class Remote(io.RawIOBase):
    def __init__(s):
        r = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"))
        s.url, s.n, s.p = r.geturl(), int(r.headers["Content-Length"]), 0
    def seekable(s): return True
    def readable(s): return True
    def tell(s): return s.p
    def seek(s, o, w=0):
        s.p = o if w == 0 else (s.p + o if w == 1 else s.n + o)
        return s.p
    def readinto(s, b):
        if s.p >= s.n: return 0
        e = min(s.n, s.p + len(b)) - 1
        d = urllib.request.urlopen(urllib.request.Request(s.url, headers={"Range": "bytes=%d-%d" % (s.p, e)})).read()
        b[:len(d)] = d
        s.p += len(d)
        return len(d)
z = zipfile.ZipFile(io.BufferedReader(Remote(), buffer_size=1 << 20))
for n in ("linux_release.x86_64", "linux_debug.x86_64", "version.txt"):
    open(sys.argv[1] + "/" + n, "wb").write(z.read("templates/" + n))
PY
fi
"$GODOT" --headless --editor --quit >/dev/null 2>&1 || true   # import, and register the class names
mkdir -p "$(dirname "$OUT")"
"$GODOT" --headless --export-release "Linux" "$OUT"
chmod +x "$OUT"
ls -la "$OUT"
