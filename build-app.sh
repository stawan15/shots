#!/bin/bash
# Build Shots.app: a menu-bar app bundle around the ShotsApp executable.
#
# Version comes from the git tag when there is one (v1.1.0 -> 1.1.0), otherwise
# from VERSION below, so a release build and a local build agree.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Shots"
DIST="dist"
BUNDLE="$DIST/$APP_NAME.app"
# Version lives in Sources/ShotsCore/Version.swift so the CLI and app agree.
VERSION="${VERSION:-$(grep -o 'current = "[^"]*"' Sources/ShotsCore/Version.swift | cut -d'"' -f2)}"
BUNDLE_ID="com.teveus.shots"

echo "building $APP_NAME $VERSION (universal)..."
# The CLI ships inside the bundle too: `shots update` installs from this DMG, so it
# needs a copy of the tool to copy out.
if swift build -c release --product shots --arch arm64 --arch x86_64 2>/dev/null; then
  CLI=".build/out/Products/Release/shots"
else
  swift build -c release --product shots
  CLI=".build/release/shots"
fi
# Universal so the same DMG runs on Apple silicon and Intel.
if swift build -c release --product ShotsApp --arch arm64 --arch x86_64 2>/dev/null; then
  BIN=".build/out/Products/Release/ShotsApp"
else
  echo "note: universal build unavailable, falling back to the host architecture"
  swift build -c release --product ShotsApp
  BIN=".build/release/ShotsApp"
fi

echo "assembling $BUNDLE"
rm -rf "$BUNDLE"
# The CLI goes in Resources/bin, not MacOS: the volume is case-insensitive, so
# Contents/MacOS/shots would collide with Contents/MacOS/Shots and silently win.
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/bin"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$CLI" "$BUNDLE/Contents/Resources/bin/shots"
lipoinfo=$(lipo -info "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true)
[ -n "$lipoinfo" ] && echo "  $lipoinfo"

if [ -f assets/Shots.icns ]; then
  cp assets/Shots.icns "$BUNDLE/Contents/Resources/Shots.icns"
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>Shots</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>MIT licensed. https://github.com/stawan15/shots</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. There is no Developer ID here, so this is what makes the app
# runnable on Apple silicon after the user clears the quarantine flag once.
if codesign --force --sign - --timestamp=none "$BUNDLE" 2>/dev/null; then
  echo "ad-hoc signed"
else
  echo "note: codesign unavailable, leaving unsigned"
fi

echo "built $BUNDLE"
echo
echo "run it with:   open $BUNDLE"
echo "install it:    cp -R $BUNDLE /Applications/"
