#!/bin/sh
# =====================================================================
# MEWD — the Godot build for the web (WebGL 2), into a folder
# =====================================================================
#
#   tools/build-web.sh [outdir]          (default build/web)
#
# Godot 4.3's Web export (export_presets.cfg, "Web"): the Compatibility
# renderer on WebGL 2, and NO THREADS — a page gets threads only when
# the server sends the cross-origin-isolation headers, and GitHub Pages
# sends none (the editor compiles in place when there are no threads).
# Needs Godot 4.3 on the path (or $GODOT) and its web export templates
# in ~/.local/share/godot/export_templates/4.3.stable/ — the CI
# (.github/workflows/pages.yml) fetches both.
#
# The site (the CI's publish job) is this at the root and the web build
# in js/ (tools/build-site.sh) under classic/.
set -eu

cd "$(dirname "$0")/.."
OUT="${1:-build/web}"
GODOT="${GODOT:-godot}"

mkdir -p build "$OUT"
# build/ is the export's, never the project's
[ -f build/.gdignore ] || : > build/.gdignore
OUT_ABS=$(cd "$OUT" && pwd)

# import everything first (a fresh checkout has no .godot/), then export
"$GODOT" --headless --import > /dev/null 2>&1 || true
"$GODOT" --headless --export-release "Web" "$OUT_ABS/index.html" 2>&1 | grep -E "ERROR|error" | head -20 || true
[ -f "$OUT_ABS/index.pck" ] || { echo "the web export failed"; exit 1; }

printf 'built %s: ' "$OUT"
du -sh "$OUT_ABS" | cut -f1
