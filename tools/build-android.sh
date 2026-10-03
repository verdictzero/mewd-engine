#!/bin/sh
# =====================================================================
# MEWD — the Godot build for Android, as an APK (arm64: an Anbernic
# RG557, a phone), signed and ready to side-load
# =====================================================================
#
#   tools/build-android.sh [out.apk]      (default build/android/mewd.apk)
#
# export_presets.cfg's "Android" preset: the Mobile renderer on Vulkan,
# landscape either way round, immersive, the network permission for a
# match. Needs Godot 4.7 on the path (or $GODOT) with its Android export
# templates installed, the Android SDK's build tools (the editor setting
# export/android/android_sdk_path, or $ANDROID_HOME) and Java for
# signing. Signed with the keystore in $MEWD_KEYSTORE (alias
# $MEWD_KEY_ALIAS, password $MEWD_KEY_PASS) when one is given, else as a
# debug build with the editor's debug key.
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-build/android/mewd.apk}"
GODOT="${GODOT:-godot}"
mkdir -p build "$(dirname "$OUT")"
[ -f build/.gdignore ] || : > build/.gdignore
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
"$GODOT" --headless --import > /dev/null 2>&1 || true
# THE ISLANDS, BAKED (tools/bake_island.gd), unless they are already, for
# this code: the APK carries them, so the handheld reads its world off
# disk instead of spending minutes making it
# ONE ISLAND TO A PROCESS, and a crashed one tried again (twice at most):
# a fresh bake of every island in one process segfaulted on CI (exit
# 139) once there were four of them, and took the whole build with it
for key in $(grep -o '"key": "[^"]*"' godot/scripts/level/islands.gd | cut -d'"' -f4); do
  tries=0
  until "$GODOT" --headless --script res://tools/bake_island.gd -- --map="$key" --if-missing; do
    tries=$((tries + 1))
    [ "$tries" -lt 3 ] || { echo "bake of $key failed $tries times" >&2; exit 1; }
    echo "bake of $key failed (try $tries), again" >&2
  done
done
if [ -n "${MEWD_KEYSTORE:-}" ]; then
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$MEWD_KEYSTORE"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${MEWD_KEY_ALIAS:-mewd}"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${MEWD_KEY_PASS:-}"
  MODE=--export-release
else
  MODE=--export-debug
fi
"$GODOT" --headless $MODE "Android" "$OUT_ABS" 2>&1 | grep -E "ERROR|error|rror:" | grep -v "Global uniform\|Shader compilation failed" | head -20 || true
[ -f "$OUT_ABS" ] || { echo "the Android export failed"; exit 1; }
printf 'built %s: ' "$OUT"
du -h "$OUT_ABS" | cut -f1
