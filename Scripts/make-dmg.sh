#!/bin/bash
# Builds the disk image to hand to other people: dist/Spindle-<version>.dmg, holding the app
# for both Apple silicon and Intel Macs, a shortcut to Applications to drag it onto, and a
# note on getting past macOS's warning the first time.
# Run from anywhere:  Scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=build/release
xcodegen generate >/dev/null
xcodebuild -project Spindle.xcodeproj -scheme Spindle -configuration Release -derivedDataPath "$BUILD" \
    -destination "generic/platform=macOS" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build 2>&1 \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="$BUILD/Build/Products/Release/Spindle.app"
[ -d "$APP" ] || { echo "The build did not produce $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

# A damaged signature is the difference between "could not verify", which the user can get
# past, and "is damaged", which they cannot.
codesign --verify --deep --strict "$APP"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Spindle.app"
ln -s /Applications "$STAGING/Applications"
textutil -convert rtf "Support/How to Install Spindle.html" -output "$STAGING/How to Install Spindle.rtf"

mkdir -p dist
DMG="dist/Spindle-$VERSION.dmg"
hdiutil create -volname "Spindle" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify -quiet "$DMG"

echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' ')) for $(lipo -archs "$APP/Contents/MacOS/Spindle")"
