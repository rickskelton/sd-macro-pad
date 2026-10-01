#!/bin/bash
# Builds "SD Macro Pad.app" and the sdpad command-line tool into the project folder.
#
#   scripts/build-app.sh              build, sign with Developer ID if a certificate is in the keychain
#   scripts/build-app.sh --notarize   also notarise with Apple and staple the ticket
#
# The first "Developer ID Application" certificate in the keychain is used unless SIGN_ID is set.
# Notarising needs a notarytool keychain profile (xcrun notarytool store-credentials <name>):
#   NOTARY_PROFILE=<name> scripts/build-app.sh --notarize
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
VERSION="1.0"
APP="SD Macro Pad.app"

[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SDPadApp" "$APP/Contents/MacOS/SD Macro Pad"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SD Macro Pad</string>
    <key>CFBundleDisplayName</key><string>SD Macro Pad</string>
    <key>CFBundleIdentifier</key><string>com.rickskelton.sdmacropad</string>
    <key>CFBundleExecutable</key><string>SD Macro Pad</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Rick Skelton</string>
</dict>
</plist>
PLIST
cp "$BIN/sdpad" ./sdpad

if [ -n "$SIGN_ID" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" ./sdpad
    codesign --verify --deep --strict "$APP"
    echo "Signed with $SIGN_ID"
else
    codesign --force --sign - "$APP"
    echo "No Developer ID certificate found; signed ad hoc (runs on this Mac only)."
fi

if [ "${1:-}" = "--notarize" ]; then
    [ -n "$NOTARY_PROFILE" ] || { echo "Set NOTARY_PROFILE to a notarytool keychain profile name."; exit 1; }
    ZIP="$(mktemp -d)/SD Macro Pad.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    rm -f "SD Macro Pad $VERSION.zip"
    ditto -c -k --keepParent "$APP" "SD Macro Pad $VERSION.zip"
    echo "Notarised. Share: SD Macro Pad $VERSION.zip"
fi
echo "Built $APP and ./sdpad"
