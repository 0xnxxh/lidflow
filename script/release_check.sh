#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
./script/test_publish_release.sh
swift test --scratch-path "$ROOT_DIR/.build/lidflow"
./script/build_and_run.sh --release-build
./script/package_dmg.sh
./script/generate_appcast.sh
python3 ./script/verify_release.py
