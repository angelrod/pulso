#!/bin/sh
# Builds Pulso.app from the SwiftPM executable: Info.plist, icons, ad-hoc signature.
# Usage: native/scripts/bundle.sh [output dir]   (default: native/.build/app)
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
out=${1:-.build/app}
# A local build never carries a released version number (docs/RELEASING.md).
version=${PULSO_VERSION:-"2.0.0-dev.$(date +%Y%m%d%H%M)"}
# Only a release build checks for updates by itself; local builds check when asked.
auto_checks=${PULSO_AUTO_UPDATE_CHECKS:-false}
public_key=$(cat scripts/sparkle-public-key.txt)

swift build -c release --product Pulso
app="$out/Pulso.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp .build/release/Pulso "$app/Contents/MacOS/Pulso"
# Sparkle ships as a framework next to the executable (rpath @executable_path/../Frameworks).
if [ -d .build/release/Sparkle.framework ]; then
  cp -R .build/release/Sparkle.framework "$app/Contents/Frameworks/"
fi
cp ../resources/icon.icns ../resources/tray*.png "$app/Contents/Resources/"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.angelrod.pulso</string>
  <key>CFBundleName</key><string>Pulso</string>
  <key>CFBundleDisplayName</key><string>Pulso</string>
  <key>CFBundleExecutable</key><string>Pulso</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Miguel Angel Rod</string>
  <key>SUFeedURL</key><string>https://github.com/angelrod/pulso/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$public_key</string>
  <key>SUEnableAutomaticChecks</key><$auto_checks/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built $app ($version)"
