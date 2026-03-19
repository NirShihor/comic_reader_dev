#!/bin/bash

# Comic Import Script
# Usage: ./import-comic.sh <path-to-export-folder>
# Example: ./import-comic.sh /path/to/comic-generator/server/projects/comic-xxx/export/my_comic

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_COMICS_DIR="$SCRIPT_DIR/ComicReader/BundledComics"

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: No export path provided${NC}"
    echo ""
    echo "Usage: ./import-comic.sh <path-to-export-folder>"
    echo "Example: ./import-comic.sh ~/Desktop/coding/comic-generator/server/projects/comic-xxx/export/my_comic"
    exit 1
fi

# Remove trailing slash if present
EXPORT_PATH="${1%/}"

# Verify the export path exists
if [ ! -d "$EXPORT_PATH" ]; then
    echo -e "${RED}Error: Export folder not found: $EXPORT_PATH${NC}"
    exit 1
fi

# Verify comic.json exists
if [ ! -f "$EXPORT_PATH/comic.json" ]; then
    echo -e "${RED}Error: comic.json not found in export folder${NC}"
    exit 1
fi

# Get comic folder name
COMIC_NAME=$(basename "$EXPORT_PATH")

echo -e "${YELLOW}Importing comic: $COMIC_NAME${NC}"

# Check if comic already exists
if [ -d "$BUNDLED_COMICS_DIR/$COMIC_NAME" ]; then
    echo -e "${YELLOW}Comic already exists. Replacing...${NC}"
    rm -rf "$BUNDLED_COMICS_DIR/$COMIC_NAME"
fi

# Copy the comic
cp -R "$EXPORT_PATH" "$BUNDLED_COMICS_DIR/"

# Verify the copy
if [ -d "$BUNDLED_COMICS_DIR/$COMIC_NAME" ]; then
    # Count files
    IMAGE_COUNT=$(find "$BUNDLED_COMICS_DIR/$COMIC_NAME/images" -type f -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    SENTENCE_AUDIO_COUNT=$(find "$BUNDLED_COMICS_DIR/$COMIC_NAME/audio" -maxdepth 1 -type f -name "*.mp3" 2>/dev/null | wc -l | tr -d ' ')
    WORD_AUDIO_COUNT=$(find "$BUNDLED_COMICS_DIR/$COMIC_NAME/audio/words" -type f -name "*.mp3" 2>/dev/null | wc -l | tr -d ' ')

    echo -e "${GREEN}Successfully imported: $COMIC_NAME${NC}"
    echo "  - Images: $IMAGE_COUNT"
    echo "  - Sentence audio: $SENTENCE_AUDIO_COUNT"
    echo "  - Word audio: $WORD_AUDIO_COUNT"
    echo ""
    echo -e "${YELLOW}Rebuild the app in Xcode (Cmd+R) to see changes.${NC}"
else
    echo -e "${RED}Error: Failed to copy comic${NC}"
    exit 1
fi
