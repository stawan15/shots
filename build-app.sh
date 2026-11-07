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

echo "building $APP_NAME $VERSION..."
swift build -c release --product ShotsApp

echo "assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/ShotsApp "$BUNDLE/Contents/MacOS/$APP_NAME"

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
