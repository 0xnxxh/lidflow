#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$ROOT_DIR/Resources/Icon"
ICON_PNG="$ICON_DIR/AppIcon.png"
ICON_ICNS="$ROOT_DIR/Resources/AppIcon.icns"
TASK_TMP="$(mktemp -d /tmp/lidflow-icon.XXXXXX)"
trap 'rm -rf "$TASK_TMP"' EXIT
ICONSET="$TASK_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
xcrun swiftc "$ROOT_DIR/Sources/LidFlow/BrandIcon.swift" "$ICON_DIR/draw-icon.swift" -o "$TASK_TMP/draw-icon"
"$TASK_TMP/draw-icon" "$ICON_PNG" >&2
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  /usr/bin/sips -z "$retina" "$retina" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$ICON_ICNS"
echo "$ICON_ICNS"
