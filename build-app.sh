#!/bin/bash
# Build Shots.app: a menu-bar app bundle around the ShotsApp executable.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Shots"
DIST="dist"
BUNDLE="$DIST/$APP_NAME.app"
VERSION="1.0.0"

echo "building..."
swift build -c release

echo "assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/ShotsApp "$BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>com.teveus.shots</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for local use, and required for launchd/notarization-free
# distribution on Apple silicon.
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || \
  echo "note: ad-hoc signing skipped (codesign not available)"

echo "built $BUNDLE"
echo
echo "run it with:   open $BUNDLE"
echo "install it:    cp -R $BUNDLE /Applications/"
