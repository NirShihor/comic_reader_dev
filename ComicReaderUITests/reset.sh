#!/bin/bash
# RESET_BUNDLE = folder containing comic.json (folder is copied under Documents/Comics/<comic.json id>)
APP=/private/tmp/claude-501/-Users-nirshihor-coding-comic-generator/21251934-5e50-4b1d-a040-2340fed23196/scratchpad/dd/Build/Products/Debug-iphonesimulator/ComicReader.app
BUNDLE="${RESET_BUNDLE:-/Users/nirshihor/coding/comic-generator/server/projects/comic-9832e1ed/export/la_biblioteca}"
ID=$(python3 -c "import json;print(json.load(open('$BUNDLE/comic.json'))['id'])")
xcrun simctl terminate booted com.comicreader.app 2>/dev/null; xcrun simctl uninstall booted com.comicreader.app 2>/dev/null
xcrun simctl install booted "$APP" && xcrun simctl launch booted com.comicreader.app >/dev/null && sleep 2 && xcrun simctl terminate booted com.comicreader.app
C=$(xcrun simctl get_app_container booted com.comicreader.app data)
mkdir -p "$C/Documents/Comics" && cp -R "$BUNDLE" "$C/Documents/Comics/$ID" && echo "reset ok ($ID)"
