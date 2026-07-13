#!/bin/bash
#
# build.sh — Compile, signe et lance MacTuner.
# Rassemble toutes les sources Swift + l'en-tête C du SMC.
#
set -euo pipefail
cd "$(dirname "$0")"

APP="MacTuner.app"
BIN="$APP/Contents/MacOS/MacTuner"
HEADER="smc_bridge.h"

echo "▸ Compilation (cible macOS 26.0 → compatible 26 et 27)…"
mkdir -p "$APP/Contents/MacOS"
# Cible 26.0 : le compilateur refuse toute API non disponible sur macOS 26.
# Toutes les sources Swift du projet (racine Sources + sous-dossiers).
swiftc -O -parse-as-library -target arm64-apple-macos26.0 -import-objc-header "$HEADER" \
    Sources/*.swift \
    Sources/Core/*.swift \
    Sources/Sensors/*.swift \
    Sources/Features/*.swift \
    Sources/UI/*.swift \
    Sources/Views/*.swift \
    Sources/App/*.swift \
    -o "$BIN"

echo "▸ Icône…"
if [ -f "logo.png" ] && [ ! -f "AppIcon.icns" ]; then
    ICONSET="AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s logo.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
        sips -z $((s*2)) $((s*2)) logo.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o AppIcon.icns && rm -rf "$ICONSET"
fi
[ -f "AppIcon.icns" ] && { mkdir -p "$APP/Contents/Resources"; cp AppIcon.icns "$APP/Contents/Resources/"; }

echo "▸ Signature ad-hoc…"
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "▸ Lancement…"
pkill -x MacTuner 2>/dev/null || true
open "$APP"
echo "✓ MacTuner lancé."
