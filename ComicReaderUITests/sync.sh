#!/bin/bash
# Wait for the runner to write `ready` (its container id changes every run), then touch `go`.
touch /private/tmp/comigo-demo/runstart
for i in $(seq 1 2400); do
  R=$(find ~/Library/Developer/CoreSimulator/Devices/B8D6920D-3578-43E5-8C9B-6BAC89B3EEE0/data/Containers/Data/Application -path "*Documents/demo/ready" -newer /private/tmp/comigo-demo/runstart 2>/dev/null | head -1)
  [ -n "$R" ] && break; sleep 0.2
done
D=$(dirname "$R"); echo "$D" > /private/tmp/comigo-demo/dir
if [ "$1" = "record" ]; then
  xcrun simctl io booted recordVideo --codec h264 --force /private/tmp/comigo-demo/raw.mp4 & echo $! > /private/tmp/comigo-demo/recpid; sleep 1.5
fi
touch "$D/go"
if [ "$1" = "record" ]; then
  for i in $(seq 1 1200); do [ -f "$D/done" ] && break; sleep 0.1; done; sleep 5
  kill -INT $(cat /private/tmp/comigo-demo/recpid); sleep 2
fi
