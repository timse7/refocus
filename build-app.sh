#!/bin/zsh
# Builds Refocus.app (Apple silicon) into ./build and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64
APP=build/Refocus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/Refocus" "$APP/Contents/MacOS/Refocus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
