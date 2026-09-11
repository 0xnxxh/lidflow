#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/version.sh"
APP="$ROOT_DIR/dist/LidFlow.app"
[[ -d "$APP" ]] || { echo "Build the release app first" >&2; exit 1; }
TASK_TMP="$(mktemp -d "$ROOT_DIR/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$TASK_TMP"' EXIT
mkdir -p "$TASK_TMP/volume"
ditto "$APP" "$TASK_TMP/volume/LidFlow.app"
ln -s /Applications "$TASK_TMP/volume/Applications"
DMG="$ROOT_DIR/dist/LidFlow-v$APP_VERSION.dmg"
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 27 ]]; then
  # macOS 27 hdiutil create can leave its write device attached.
  diskutil image create from --volumeName "LidFlow $APP_VERSION" --format UDZO "$TASK_TMP/volume" "$TASK_TMP/release.dmg" >/dev/null
  mv "$TASK_TMP/release.dmg" "$DMG"
else
  hdiutil create -volname "LidFlow $APP_VERSION" -srcfolder "$TASK_TMP/volume" -ov -format UDZO "$DMG" >/dev/null
fi
hdiutil verify "$DMG" >/dev/null
echo "$DMG"
