#!/bin/sh
# Builds resources/icon.icns from resources/icon.png with macOS's own sips and iconutil.
cd "$(dirname "$0")/.." || exit 2
set -e
set_dir=$(mktemp -d)/icon.iconset
mkdir -p "$set_dir"
for size in 16 32 128 256 512; do
  sips -z $size $size resources/icon.png --out "$set_dir/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double resources/icon.png --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o resources/icon.icns
echo "Wrote resources/icon.icns"
