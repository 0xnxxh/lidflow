#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_DIR="$("$ROOT_DIR/script/ensure_sparkle.sh")"
PUBLIC_KEY="$ROOT_DIR/Config/sparkle_public_ed_key.txt"
[[ ! -e "$PUBLIC_KEY" ]] || { echo "Public key already exists; refusing to replace the update identity" >&2; exit 1; }
mkdir -p "$ROOT_DIR/Config"
"$SPARKLE_DIR/bin/generate_keys" --account 0xnxxh.lidflow >/dev/null
"$SPARKLE_DIR/bin/generate_keys" --account 0xnxxh.lidflow -p > "$PUBLIC_KEY"
echo "Sparkle private key retained in login Keychain (account 0xnxxh.lidflow); public key saved."
