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

# L'Info.plist (icône, identifiant du bundle) est versionné. S'il manque, on le
# restaure depuis git ; hors dépôt git (archive téléchargée, dossier copié), on le
# régénère. Auparavant le script s'arrêtait là et l'app ne pouvait pas être compilée.
if [ ! -f "$APP/Contents/Info.plist" ]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
       && git checkout -- "$APP/Contents/Info.plist" 2>/dev/null; then
        echo "▸ Info.plist restauré depuis git."
    else
        echo "▸ Info.plist manquant, génération…"
        mkdir -p "$APP/Contents"
        cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>MacTuner</string>
    <key>CFBundleDisplayName</key>           <string>MacTuner</string>
    <key>CFBundleExecutable</key>            <string>MacTuner</string>
    <key>CFBundleIdentifier</key>            <string>local.rodolphe.mactuner</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>1.2.0</string>
    <key>CFBundleVersion</key>               <string>5</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>        <string>26.0</string>
    <key>LSApplicationCategoryType</key>     <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSHumanReadableCopyright</key>      <string>© Rodolphe Vandaele — MIT</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MacTuner utilise AppleScript pour demander une élévation de privilèges (mot de passe administrateur) et pour redémarrer le Mac à votre demande.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>MacTuner a besoin de privilèges administrateur pour appliquer les réglages système que vous choisissez (indexation Spotlight, Power Nap, son de démarrage, ventilation).</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>MacTuner analyse le Bureau pour repérer les installeurs et fichiers volumineux que vous pouvez supprimer.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>MacTuner analyse Documents pour repérer les doublons et fichiers volumineux que vous pouvez supprimer.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>MacTuner analyse Téléchargements pour repérer les installeurs oubliés que vous pouvez supprimer.</string>
</dict>
</plist>
PLIST
        printf 'APPL????' > "$APP/Contents/PkgInfo"
    fi
fi

# Garde-fou : un label launchd inexistant se « désactive » sans erreur et
# l'application l'annonce désactivé. On refuse de compiler dans ce cas.
echo "▸ Vérification des services du catalogue…"
python3 tools/verify-labels.py || { echo "✗ Catalogue incohérent, compilation annulée."; exit 1; }

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
# Sans signature valide, macOS refuse de lancer le bundle sur Apple Silicon :
# on ne masque plus l'erreur, on l'affiche et on s'arrête.
codesign --force --deep --sign - "$APP" || { echo "✗ Signature échouée."; exit 1; }

echo "▸ Lancement…"
pkill -x MacTuner 2>/dev/null || true
open "$APP"
echo "✓ MacTuner lancé."
