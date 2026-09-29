#!/bin/sh
# =====================================================================
# MEWD — assemble the deployable site into public/
# =====================================================================
#
#   tools/build-site.sh [outdir]
#
# There is no build step in the sense of compiling anything: every
# texture, sprite and level is generated in the page at start-up. This
# is a COPY, and the only reason it exists is that the repository holds
# things the site does not need — the untouched Freedoom frames the
# apron is painted onto, the source PNGs for art already baked into
# js/art-data.js, the tools, the README. Publishing the repo wholesale
# would ship about a megabyte of source nobody downloads.
#
# It is a script rather than a list in a CI file so that the two CI
# files and a person checking the deploy locally all assemble exactly
# the same site.
set -eu

OUT="${1:-public}"
cd "$(dirname "$0")/.."

rm -rf "$OUT"
mkdir -p "$OUT/assets"

cp index.html "$OUT/"
# The two files a phone reads before the game: what to call it and what
# to draw on the home screen.
cp manifest.webmanifest icon.png "$OUT/"
cp -r css js vendor "$OUT/"

# The wood, the people, the sky, the gun and the van: art that came from
# outside, is loaded at run time rather than generated, and stays as files.
# Everything else the page needs it draws for itself — the fire included,
# since js/fireart.js took that job back off the golf project's strips.
#
# assets/cars is gone. It held the four-view sheet the drawn fleet is
# painted from, and the car park is one modelled van now, so nothing the
# page loads reads it — it has moved to art/vehicles-atlas.png, beside
# the other source art, and waits there for the responders' riot van and
# APC. Half a megabyte nobody downloads until they turn up.
# and the music: the user's three tracks, played in a loop by js/music.js
# assets/sky is not in this list: the sky is baked in the page now
# (js/skyart.js) and the photograph in there is kept, not shipped.
# and the texture pack and its skies (js/texpack.js): pictures the user
# handed over, loaded when a map wears one or the editor opens
cp -r assets/forest assets/people assets/models assets/fonts assets/music assets/sfx assets/textures assets/skies assets/logo "$OUT/assets/"
# none of the Godot port's own files
# (and the pictures its importer pulled out of the models, the page
# reading the .glb files whole), its import sidecars (x.png.import), its
# .gdignore markers, and the fonts it bundles for a page with no system
# fonts (GODOT.txt)
find "$OUT/assets/models" -type f ! -name '*.glb' -delete
find "$OUT" \( -name '*.import' -o -name '.gdignore' \) -delete
rm -rf "$OUT/assets/fonts/dejavu"

# THE PACKING LIST, for the DOWNLOAD in the pause menu. The page has no
# way to ask a static host what is on it, so the site carries a list of
# itself: every file just copied, sorted, as a JSON array of paths
# relative to the site root. js/pack.js fetches this and zips what it
# names. It is written last, and leaves itself out — an archive of the
# game does not need the list the archive was made from.
#
# The same file is kept at the top of the repository so a checkout
# served straight off the disk packs too, and the smoke test rebuilds
# the site and fails if the two have drifted apart.
( cd "$OUT" && find . -type f ! -name files.json | sed 's|^\./||' | LC_ALL=C sort |
  awk 'BEGIN { printf "[" } { printf "%s\n  \"%s\"", (NR > 1 ? "," : ""), $0 } END { printf "\n]\n" }'
) > "$OUT/files.json"

printf 'built %s: ' "$OUT"
find "$OUT" -type f | wc -l | tr -d ' '
printf ' files, '
du -sh "$OUT" | cut -f1
