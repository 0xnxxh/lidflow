#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SPARKLE_DIR="$ROOT_DIR/.build/lidflow/artifacts/sparkle/Sparkle"
if [[ ! -x "$SPARKLE_DIR/bin/sign_update" ]]; then
  swift package --scratch-path "$ROOT_DIR/.build/lidflow" resolve >&2
fi
[[ -x "$SPARKLE_DIR/bin/sign_update" ]] || { echo "Sparkle tools missing after package resolution" >&2; exit 1; }
echo "$SPARKLE_DIR"
