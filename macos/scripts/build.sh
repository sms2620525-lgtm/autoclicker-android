#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build dist build/TapBench.app/Contents/MacOS build/TapBench.app/Contents/Resources
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
xcrun swiftc -swift-version 5 Sources/RunSchedule.swift Tests/ScheduleTests.swift -o build/schedule-tests
build/schedule-tests | tee dist/schedule-tests.txt
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK_PATH" -target "${arch}-apple-macos13.0" \
    -framework SwiftUI -framework AppKit -framework ApplicationServices -framework Carbon \
    Sources/*.swift -o "build/TapBench-${arch}"
done
lipo -create build/TapBench-arm64 build/TapBench-x86_64 -output build/TapBench.app/Contents/MacOS/TapBench
cp Info.plist build/TapBench.app/Contents/Info.plist
plutil -lint build/TapBench.app/Contents/Info.plist
xcrun swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/TapBench.app/Contents/Resources/AppIcon.icns
codesign --force --sign - --timestamp=none build/TapBench.app
codesign --verify --deep --strict --verbose=2 build/TapBench.app
lipo build/TapBench.app/Contents/MacOS/TapBench -verify_arch arm64 x86_64
mkdir -p build/dmg
ditto build/TapBench.app build/dmg/TapBench.app
ln -sfn /Applications build/dmg/Applications
cp README.md build/dmg/READ-ME.txt
hdiutil create -volname TapBench -srcfolder build/dmg -ov -format UDZO "dist/TapBench-${APP_VERSION}-universal.dmg"
hdiutil verify "dist/TapBench-${APP_VERSION}-universal.dmg"
ditto -c -k --keepParent build/TapBench.app "dist/TapBench-${APP_VERSION}-universal.zip"
(cd dist && shasum -a 256 "TapBench-${APP_VERSION}-universal.dmg" "TapBench-${APP_VERSION}-universal.zip" > SHA256SUMS.txt)
{
  sw_vers
  file build/TapBench.app/Contents/MacOS/TapBench
  codesign -dv build/TapBench.app 2>&1
  echo 'Packaging and logic tests verified. Actual received CPS requires Accessibility permission and a browser test on the user Mac.'
} > dist/build-verification.txt
