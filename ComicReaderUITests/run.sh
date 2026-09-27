#!/bin/bash
S=/private/tmp/claude-501/-Users-nirshihor-coding-comic-generator/21251934-5e50-4b1d-a040-2340fed23196/scratchpad
cd /Users/nirshihor/coding/comic-reader
for attempt in 1 2 3; do
  /private/tmp/comigo-demo/reset.sh >/dev/null && xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --batteryState charged --wifiBars 3 --cellularBars 4
  rm -f /private/tmp/comigo-demo/raw.mp4 /private/tmp/comigo-demo/cfr.mp4
  /private/tmp/comigo-demo/sync.sh record & 
  xcodebuild test -scheme ComicReader -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath $S/dd -only-testing:ComicReaderUITests/DemoRecording/testDemoScript 2>&1 | grep -E "error:|failed \(|passed \(|missing:" | head -3
  wait
  cd /private/tmp/comigo-demo && ffmpeg -y -loglevel error -i raw.mp4 -vf fps=30 -an -c:v libx264 -preset fast -crf 16 -pix_fmt yuv420p cfr.mp4
  echo "attempt $attempt:"; python3 ${VERIFY:-verify.py} "$(cat dir)" && { echo "verified on attempt $attempt"; [ -n "$TAKE" ] && mkdir -p takes/$TAKE && cp raw.mp4 cfr.mp4 takes/$TAKE/ && cp "$(cat dir)/events.json" takes/$TAKE/ && echo "$(pwd)/takes/$TAKE" > takes/$TAKE/dir; exit 0; }
  cd /Users/nirshihor/coding/comic-reader
done
echo "no clean run in 3 attempts"; exit 1
