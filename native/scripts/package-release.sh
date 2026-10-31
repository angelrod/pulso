#!/bin/sh
# Packages a release: the app (auto-update on), a dmg, a zip signed for Sparkle, appcast.xml.
# Usage: native/scripts/package-release.sh <version> [out dir]   (default out: native/.build/release-out)
# The EdDSA key comes from SPARKLE_PRIVATE_KEY if set, else from the login Keychain (account "pulso").
set -e
cd "$(dirname "$0")/.."
version=${1:?usage: package-release.sh <version> [out dir]}
out=${2:-.build/release-out}
repo="https://github.com/angelrod/pulso"
rm -rf "$out" && mkdir -p "$out"

PULSO_VERSION="$version" PULSO_AUTO_UPDATE_CHECKS=true sh scripts/bundle.sh "$out/stage"
app="$out/stage/Pulso.app"

# The zip is what Sparkle downloads; ditto keeps the bundle's symlinks and signature intact.
zip="$out/Pulso-$version.zip"
ditto -c -k --keepParent "$app" "$zip"

# The dmg is for first installs: the app beside a link to /Applications.
ln -s /Applications "$out/stage/Applications"
dmg="$out/Pulso-$version.dmg"
hdiutil create -volname "Pulso $version" -srcfolder "$out/stage" -ov -format UDZO "$dmg" >/dev/null
rm "$out/stage/Applications"

sign_update=$(find .build/artifacts -name sign_update -type f | head -1)
if [ -n "$SPARKLE_PRIVATE_KEY" ]; then
  attrs=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$zip")
else
  attrs=$("$sign_update" --account pulso "$zip")
fi
case "$attrs" in
  *sparkle:edSignature=*) ;;
  *) echo "Signing the update failed: $attrs" >&2; exit 1 ;;
esac

cat > "$out/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Pulso</title>
    <item>
      <title>Pulso $version</title>
      <link>$repo/releases/tag/v$version</link>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <enclosure url="$repo/releases/download/v$version/Pulso-$version.zip" type="application/octet-stream" $attrs/>
    </item>
  </channel>
</rss>
XML
rm -rf "$out/stage"
echo "Packaged $version in $out:"
ls -1 "$out"
