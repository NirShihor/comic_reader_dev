#!/bin/bash
# Records DemoRecording.testDemoScript on the booted iPhone 17 Pro simulator.
# Usage: ./ComicReaderUITests/record-demo.sh <export folder of the comic> <out dir>
# Produces <out dir>/raw.mp4 (video only, VFR) and <out dir>/events.json (tap times).
set -e
EXPORT="$1"; OUT="$2"; DD="${DD:-/tmp/comigo-dd}"; DEV="${DEV:-iPhone 17 Pro}"
mkdir -p "$OUT"; cd "$(dirname "$0")/.."
xcrun simctl boot "$DEV" 2>/dev/null || true
xcodebuild -scheme ComicReader -destination "platform=iOS Simulator,name=$DEV" -derivedDataPath "$DD" build-for-testing -quiet
APP="$DD/Build/Products/Debug-iphonesimulator/ComicReader.app"
xcrun simctl terminate booted com.comicreader.app 2>/dev/null || true; xcrun simctl uninstall booted com.comicreader.app 2>/dev/null || true
xcrun simctl install booted "$APP"; xcrun simctl launch booted com.comicreader.app >/dev/null; sleep 2; xcrun simctl terminate booted com.comicreader.app
C=$(xcrun simctl get_app_container booted com.comicreader.app data)
mkdir -p "$C/Documents/Comics"; cp -R "$EXPORT" "$C/Documents/Comics/$(python3 -c "import json,sys;print(json.load(open('$EXPORT/comic.json'))['id'])")"
xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --batteryState charged --wifiBars 3 --cellularBars 4
touch "$OUT/.runstart"
( for i in $(seq 1 2400); do
    R=$(find ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application -path "*Documents/demo/ready" -newer "$OUT/.runstart" 2>/dev/null | head -1)
    [ -n "$R" ] && break; sleep 0.2; done
  D=$(dirname "$R")
  xcrun simctl io booted recordVideo --codec h264 --force "$OUT/raw.mp4" & P=$!; sleep 1.5; touch "$D/go"
  for i in $(seq 1 1200); do [ -f "$D/done" ] && break; sleep 0.1; done; sleep 0.4; kill -INT $P; wait $P; cp "$D/events.json" "$OUT/" ) &
xcodebuild -scheme ComicReader -destination "platform=iOS Simulator,name=$DEV" -derivedDataPath "$DD" test-without-building -only-testing:ComicReaderUITests/DemoRecording/testDemoScript -quiet
wait; echo "raw video: $OUT/raw.mp4  events: $OUT/events.json"
