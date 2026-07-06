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
    magick -size 1024x1024 "$SVG_PATH" "$BASE_PNG"
elif command -v convert &>/dev/null; then
    convert -size 1024x1024 "$SVG_PATH" "$BASE_PNG"
else
    echo "ERROR: ImageMagick not found. Install it with: brew install imagemagick"
    exit 1
fi

# Step 2: Create iconset with all required sizes
echo "  [2/3] Generating iconset..."
mkdir -p "$ICONSET"

declare -A SIZES=(
    ["icon_16x16.png"]=16
    ["icon_16x16@2x.png"]=32
    ["icon_32x32.png"]=32
    ["icon_32x32@2x.png"]=64
    ["icon_128x128.png"]=128
    ["icon_128x128@2x.png"]=256
    ["icon_256x256.png"]=256
    ["icon_256x256@2x.png"]=512
    ["icon_512x512.png"]=512
)

for name in "${!SIZES[@]}"; do
    dim="${SIZES[$name]}"
    sips -z "$dim" "$dim" "$BASE_PNG" --out "$ICONSET/$name" &>/dev/null
done

# 512x512@2x is just the 1024 base image
cp "$BASE_PNG" "$ICONSET/icon_512x512@2x.png"

# Step 3: Package into .icns
echo "  [3/3] Packaging .icns..."
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"

echo "==> Done: $ICNS_OUT ($(du -h "$ICNS_OUT" | cut -f1))"
