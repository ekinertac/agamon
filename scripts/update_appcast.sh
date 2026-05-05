#!/usr/bin/env bash
# Prepends a new release entry to appcast.xml.
# Usage: update_appcast.sh VERSION BUILD DOWNLOAD_URL FILE_SIZE ED_SIGNATURE [APPCAST_PATH]
#
# VERSION       — e.g. "0.3.2"  (CFBundleShortVersionString)
# BUILD         — e.g. "5"      (CFBundleVersion, integer)
# DOWNLOAD_URL  — full URL to the release ZIP on GitHub Releases
# FILE_SIZE     — byte size of the ZIP
# ED_SIGNATURE  — base64 EdDSA signature from Sparkle's sign_update tool
# APPCAST_PATH  — defaults to "appcast.xml" relative to cwd
set -euo pipefail

VERSION="$1"
BUILD="$2"
URL="$3"
SIZE="$4"
SIG="$5"
APPCAST="${6:-appcast.xml}"
DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

ITEM_FILE=$(mktemp /tmp/sparkle_item.XXXXXX)
trap 'rm -f "$ITEM_FILE"' EXIT

cat > "$ITEM_FILE" <<ITEM
    <item>
      <title>Version $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$URL"
        sparkle:edSignature="$SIG"
        length="$SIZE"
        type="application/octet-stream" />
    </item>
ITEM

python3 - "$APPCAST" "$ITEM_FILE" <<'PYEOF'
import sys
appcast_path, item_path = sys.argv[1], sys.argv[2]
with open(appcast_path) as f:
    content = f.read()
with open(item_path) as f:
    item = f.read().rstrip('\n')
# Insert before first existing <item>, or before </channel> if none yet.
if '<item>' in content:
    content = content.replace('<item>', item + '\n    <item>', 1)
else:
    content = content.replace('  </channel>', item + '\n  </channel>')
with open(appcast_path, 'w') as f:
    f.write(content)
PYEOF

echo "Updated $APPCAST with version $VERSION (build $BUILD)"
