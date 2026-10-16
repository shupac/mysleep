#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift test --package-path native
xcodebuild -quiet -project native/mysleep.xcodeproj -scheme MySleepWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath native/.build-watch CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project native/mysleep.xcodeproj -scheme MySleep \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath native/.build-ios CODE_SIGNING_ALLOWED=NO build
python3 scripts/verify-app-bundle.py native/.build-ios/Build/Products/Debug-iphonesimulator/MySleep.app
# Run the fixture UI suite separately with a booted iPhone simulator:
# xcodebuild -project native/mysleep.xcodeproj -scheme MySleep \
#   -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
#   -derivedDataPath native/.build-ios CODE_SIGNING_ALLOWED=NO test
