#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/version.sh"
SPARKLE_DIR="$("$ROOT_DIR/script/ensure_sparkle.sh")"
DMG="$ROOT_DIR/dist/LidFlow-v$APP_VERSION.dmg"
[[ -f "$DMG" ]] || { echo "Missing DMG; run script/release_check.sh" >&2; exit 1; }
TASK_TMP="$(mktemp -d "$ROOT_DIR/dist/appcast-stage.XXXXXX")"
trap 'rm -rf "$TASK_TMP"' EXIT
cp "$DMG" "$TASK_TMP/"
KEY_ARGS=(--account 0xnxxh.lidflow)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then KEY_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"); fi
"$SPARKLE_DIR/bin/generate_appcast" "${KEY_ARGS[@]}" \
  --download-url-prefix "https://github.com/0xnxxh/lidflow/releases/download/v$APP_VERSION/" "$TASK_TMP" >&2
cp "$TASK_TMP/appcast.xml" "$ROOT_DIR/dist/appcast.xml"
echo "$ROOT_DIR/dist/appcast.xml"
