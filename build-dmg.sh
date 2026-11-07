#!/bin/bash
# Build a distributable DMG from the app bundle.
#
# The DMG is laid out so the user sees Shots.app next to an Applications shortcut
# and can just drag it across. There is no Developer ID on this machine, so the
# image is not notarized: the README explains the one-time Gatekeeper step.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Shots"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"
# Version lives in Sources/ShotsCore/Version.swift so the CLI and app agree.
VERSION="${VERSION:-$(grep -o 'current = "[^"]*"' Sources/ShotsCore/Version.swift | cut -d'"' -f2)}"
STAGE="$(mktemp -d)"

trap 'rm -rf "$STAGE"' EXIT

if [ ! -d "$APP" ]; then
  echo "no $APP — running build-app.sh first"
  VERSION="$VERSION" ./build-app.sh
fi

echo "staging $APP_NAME $VERSION"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A short readme inside the image, since the Gatekeeper step is not obvious.
cat > "$STAGE/Read Me.txt" <<TXT
Shots $VERSION
============

Drag Shots.app onto the Applications folder.

Shots is a menu-bar app and has no Dock icon. After launching, look for the photo
icon in the menu bar — click it to review and file your screenshots, right-click
it to quit.

First launch
------------
This build is not notarized by Apple. If macOS says the app "cannot be opened
because the developer cannot be verified", do one of:

  * Right-click Shots.app in Applications and choose Open, then Open again.
  * Or run:  xattr -dr com.apple.quarantine /Applications/Shots.app

The app needs no network access and makes no network calls.

Homepage: https://github.com/stawan15/shots
License: MIT
TXT

rm -f "$DMG"
echo "creating $DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -fs HFS+ \
  "$DMG" >/dev/null

if codesign --force --sign - "$DMG" 2>/dev/null; then
  echo "ad-hoc signed dmg"
fi

echo
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
echo "verify with: hdiutil verify $DMG"
