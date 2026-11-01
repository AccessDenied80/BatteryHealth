#!/bin/bash
# Збирає build/BatteryHealth.app (universal: arm64 + x86_64), а з --dmg ще й build/BatteryHealth-<версія>.dmg.
# Використання: scripts/build-app.sh [--dmg]
set -euo pipefail
cd "$(dirname "$0")/.."

MAKE_DMG=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg) MAKE_DMG=1; shift ;;
        *) echo "Невідомий аргумент: $1" >&2; exit 64 ;;
    esac
done

# Окремі збірки під кожну архітектуру: мультиархітектурний swift build потребує Xcode.
BINS=()
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx13.0" --product BatteryHealth
    BINS+=(".build/$ARCH-apple-macosx/release/BatteryHealth")
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP=build/BatteryHealth.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/BatteryHealth"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
[[ -f LICENSE ]] && cp LICENSE "$APP/Contents/Resources/"

# Ad-hoc підпис: без сертифіката Apple Developer інший немає.
codesign --force -s - "$APP"

echo "Готово: $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/BatteryHealth"))"

if [[ $MAKE_DMG == 1 ]]; then
    DMG="build/BatteryHealth-$VERSION.dmg"
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -quiet -volname "BatteryHealth $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
    echo "Готово: $DMG ($(du -h "$DMG" | cut -f1))"
fi
