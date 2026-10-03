#!/bin/sh
# =====================================================================
# MEWD — the Android APK on a clean machine (.github/workflows/android.yml)
# =====================================================================
#
#   tools/ci-android.sh [out.apk]
#
# What a fresh runner needs before tools/build-android.sh can run: Godot
# 4.7's Android export templates (fetched once — the archive holds every
# platform's, only Android's are kept), the editor's settings pointing at
# the Android SDK ($ANDROID_HOME, or $ANDROID_SDK_ROOT) and Java
# ($JAVA_HOME), and a key to sign with: the keystore in $MEWD_KEYSTORE_B64
# (base64; alias $MEWD_KEY_ALIAS, password $MEWD_KEY_PASS) if there is
# one — the same key every build, so an install updates in place — else a
# new one made here, which signs a release build all the same but a
# different one each time (uninstall before installing the next).
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$SDK" ] || { echo "no Android SDK: set ANDROID_HOME"; exit 1; }
JAVA="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/godot"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
T="$DATA/export_templates/4.7.stable"

# the templates
if [ ! -f "$T/android_release.apk" ]; then
  mkdir -p "$T"
  curl -sSL -o /tmp/tpl.tpz https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_export_templates.tpz
  unzip -o -j /tmp/tpl.tpz templates/android_release.apk templates/android_debug.apk templates/version.txt -d "$T"
  rm /tmp/tpl.tpz
fi

# a key
WORK="${RUNNER_TEMP:-/tmp}/mewd-android"
mkdir -p "$WORK"
KS="$WORK/mewd.keystore"
if [ -n "${MEWD_KEYSTORE_B64:-}" ]; then
  printf '%s' "$MEWD_KEYSTORE_B64" | base64 -d > "$KS"
else
  rm -f "$KS"
  MEWD_KEY_ALIAS=mewd
  MEWD_KEY_PASS=mewd-$(date +%s)
  keytool -genkeypair -keystore "$KS" -alias "$MEWD_KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$MEWD_KEY_PASS" -keypass "$MEWD_KEY_PASS" -dname "CN=MEWD, O=MEWD, C=US" > /dev/null 2>&1
fi
DKS="$WORK/debug.keystore"
[ -f "$DKS" ] || keytool -genkeypair -keystore "$DKS" -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=Android Debug, O=Android, C=US" > /dev/null 2>&1

# the editor's settings: made by starting the editor once, then pointed
# at the SDK, Java and the debug key
[ -f "$CONF/editor_settings-4.7.tres" ] || "$GODOT" --headless --editor --quit > /dev/null 2>&1 || true
python3 - "$CONF/editor_settings-4.7.tres" "$SDK" "$JAVA" "$DKS" <<'PY'
import re, sys
p, sdk, java, dks = sys.argv[1:]
s = open(p).read()
vals = {"export/android/android_sdk_path": sdk, "export/android/java_sdk_path": java,
        "export/android/debug_keystore": dks, "export/android/debug_keystore_user": "androiddebugkey",
        "export/android/debug_keystore_pass": "android"}
for k in vals:
    s = re.sub(r"^" + re.escape(k) + r" = .*\n", "", s, flags=re.M)
i = s.index("[resource]") + len("[resource]\n")
s = s[:i] + "".join('%s = "%s"\n' % (k, v) for k, v in vals.items()) + s[i:]
open(p, "w").write(s)
PY

MEWD_KEYSTORE="$KS" MEWD_KEY_ALIAS="${MEWD_KEY_ALIAS:-mewd}" MEWD_KEY_PASS="${MEWD_KEY_PASS:-}" \
  sh tools/build-android.sh "${1:-build/android/mewd.apk}"
