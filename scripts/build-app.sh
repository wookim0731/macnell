#!/bin/bash
# Macnell.app 빌드: ./scripts/build-app.sh  (설치까지: ./scripts/build-app.sh install)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Macnell.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Macnell "$APP/Contents/MacOS/Macnell"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: Resources/AppIcon.png (from scripts/make-icon.swift) → AppIcon.icns
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
    sips -z $px $px Resources/AppIcon.png --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null
echo "✓ $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x Macnell 2>/dev/null || true
    rm -rf /Applications/Macnell.app
    cp -R "$APP" /Applications/
    echo "✓ /Applications/Macnell.app"
    open /Applications/Macnell.app
fi
