#!/bin/bash
# generate_icon.sh — Regenerate AppIcon.icns from PearblossomLogo.svg
#
# Prerequisites: ImageMagick (`magick` or `convert`)
#   brew install imagemagick
#
# Usage: ./Scripts/generate_icon.sh
# Output: Sources/Pearblossom/Resources/AppIcon.icns

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SVG_PATH="$PROJECT_DIR/Sources/Pearblossom/Resources/PearblossomLogo.svg"
ICNS_OUT="$PROJECT_DIR/Sources/Pearblossom/Resources/AppIcon.icns"
TMP_DIR="$(mktemp -d)"
BASE_PNG="$TMP_DIR/icon_1024.png"
ICONSET="$TMP_DIR/AppIcon.iconset"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "==> Generating AppIcon.icns from $SVG_PATH"

# Step 1: Render SVG to 1024x1024 PNG
echo "  [1/3] Rendering SVG to 1024×1024 PNG..."
if command -v magick &>/dev/null; then
    magick -density 144 -background none "$SVG_PATH" -resize 1024x1024 "$BASE_PNG"
elif command -v convert &>/dev/null; then
    convert -density 144 -background none "$SVG_PATH" -resize 1024x1024 "$BASE_PNG"
else
    echo "ERROR: ImageMagick not found. Install it with: brew install imagemagick"
    exit 1
fi

# Step 2: Create iconset with all required sizes
echo "  [2/3] Generating iconset..."
mkdir -p "$ICONSET"

sips -z 16 16   "$BASE_PNG" --out "$ICONSET/icon_16x16.png"       &>/dev/null
sips -z 32 32   "$BASE_PNG" --out "$ICONSET/icon_16x16@2x.png"    &>/dev/null
sips -z 32 32   "$BASE_PNG" --out "$ICONSET/icon_32x32.png"       &>/dev/null
sips -z 64 64   "$BASE_PNG" --out "$ICONSET/icon_32x32@2x.png"    &>/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET/icon_128x128.png"     &>/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET/icon_128x128@2x.png"  &>/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET/icon_256x256.png"     &>/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET/icon_256x256@2x.png"  &>/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET/icon_512x512.png"     &>/dev/null

# 512x512@2x is just the 1024 base image
cp "$BASE_PNG" "$ICONSET/icon_512x512@2x.png"

# Step 3: Package into .icns
echo "  [3/3] Packaging .icns..."
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"

echo "==> Done: $ICNS_OUT ($(du -h "$ICNS_OUT" | cut -f1))"
