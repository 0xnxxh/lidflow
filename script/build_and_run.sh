#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_BUNDLE="$ROOT_DIR/dist/LidFlow.app"
case "$MODE" in run|--build|--verify|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--build|--verify|--debug|--logs|--telemetry]" >&2; exit 2;; esac
PREVIOUS_ID="$((codesign -d -r- "$APP_BUNDLE" 2>&1 || true) | sed -n 's/^# designated => //p')"
if pgrep -x LidFlow >/dev/null; then pkill -x LidFlow; fi
swift build
BIN_DIR="$(swift build --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$ROOT_DIR/artifacts"
cp "$BIN_DIR/LidFlow" "$APP_BUNDLE/Contents/MacOS/LidFlow"
# SwiftPM resource bundles must accompany the GUI bundle.
for RESOURCE in "$BIN_DIR"/*.bundle; do
    [ -d "$RESOURCE" ] || continue
    cp -R "$RESOURCE" "$APP_BUNDLE/Contents/Resources/"
done
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LidFlow</string>
<key>CFBundleIdentifier</key><string>app.lidflow.local</string>
<key>CFBundleName</key><string>LidFlow</string>
<key>CFBundleDisplayName</key><string>LidFlow</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Set LIDFLOW_SIGN_IDENTITY to a valid development identity when available.
# Do not weaken the designated requirement or edit TCC to retain permissions.
codesign --force --deep --sign "${LIDFLOW_SIGN_IDENTITY:--}" "$APP_BUNDLE"
CURRENT_ID="$(codesign -d -r- "$APP_BUNDLE" 2>&1 | sed -n 's/^# designated => //p')"
if [ -n "$PREVIOUS_ID" ] && [ "$PREVIOUS_ID" != "$CURRENT_ID" ]; then
    echo "LidFlow signing identity changed. An old Screen Recording entry may need removal and re-addition in System Settings." >&2
fi
if [ "$MODE" = "--build" ]; then exit 0; fi
if [ "$MODE" = "--debug" ]; then lldb -- "$APP_BUNDLE/Contents/MacOS/LidFlow"; exit; fi
LAUNCH_ARGS=(--diagnostics "$ROOT_DIR/artifacts/runtime.json")
if [ "$MODE" = "--verify" ]; then
    # Each run gets a unique result; never accept an earlier run's report.
    VERIFY_REPORT="$ROOT_DIR/artifacts/render-check-$(date +%s)-$$.json"
    LAUNCH_ARGS+=(--render-check "$VERIFY_REPORT")
fi
/usr/bin/open -n "$APP_BUNDLE" --args "${LAUNCH_ARGS[@]}"
case "$MODE" in
 --verify)
   python3 - "$VERIFY_REPORT" "$ROOT_DIR/artifacts/render-check.json" <<'PYTEST'
import json, sys, time, shutil
from pathlib import Path
report=Path(sys.argv[1]); deadline=time.monotonic()+30
while not report.exists() and time.monotonic()<deadline:
    time.sleep(0.1)
if not report.exists():
    raise SystemExit("Timed out waiting for this launch's Metal verification")
with report.open() as source:
    result = json.load(source)
assert result["passed"], result
shutil.copyfile(report,sys.argv[2])
print("Metal render verification passed")
PYTEST
   ;;
 --logs) /usr/bin/log stream --info --style compact --predicate 'process == "LidFlow"' ;;
 --telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.lidflow.local"' ;;
esac
