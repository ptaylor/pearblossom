#!/bin/zsh
# Builds a release Pearblossom.app and installs it to ~/Applications (or $1).
set -euo pipefail
repo="${0:A:h:h}"
dest="${1:-$HOME/Applications}"
app="$dest/Pearblossom.app"

cd "$repo"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Pearblossom" "$app/Contents/MacOS/"
cp Sources/Pearblossom/Resources/AppIcon.icns "$app/Contents/Resources/"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Pearblossom</string>
    <key>CFBundleDisplayName</key><string>Pearblossom</string>
    <key>CFBundleIdentifier</key><string>com.pearblossom</string>
    <key>CFBundleExecutable</key><string>Pearblossom</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for an app you built and run on this Mac.
codesign --force --deep --sign - "$app"
echo "Installed $app"
