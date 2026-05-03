#!/usr/bin/env bash
# Converts icon.png (project root) into packaging/AppIcon.icns.
# Requires Xcode command-line tools (sips + iconutil, both ship with macOS).
# Usage: ./scripts/generate_icon.sh
set -euo pipefail

SRC="${1:-icon.png}"
OUT="packaging/AppIcon.icns"
ICONSET=$(mktemp -d)/AppIcon.iconset

if [[ ! -f "$SRC" ]]; then
    echo "Error: $SRC not found. Save the app icon as icon.png in the project root." >&2
    exit 1
fi

mkdir -p "$ICONSET"

sizes=(16 32 64 128 256 512 1024)
for size in "${sizes[@]}"; do
    sips -z "$size" "$size" "$SRC" --out "$ICONSET/icon_${size}x${size}.png"       >/dev/null 2>&1
    half=$((size / 2))
    if [[ $half -gt 0 ]]; then
        sips -z "$size" "$size" "$SRC" --out "$ICONSET/icon_${half}x${half}@2x.png" >/dev/null 2>&1
    fi
done

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$(dirname "$ICONSET")"
echo "Created $OUT"
