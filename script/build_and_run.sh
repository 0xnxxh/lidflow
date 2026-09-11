#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/version.sh"
APP_BUNDLE="$ROOT_DIR/dist/LidFlow.app"
case "$MODE" in run|--build|--release-build|--verify|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--build|--release-build|--verify|--debug|--logs|--telemetry]" >&2; exit 2;; esac
SPARKLE_DIR="$("$ROOT_DIR/script/ensure_sparkle.sh")"
PUBLIC_KEY_FILE="$ROOT_DIR/Config/sparkle_public_ed_key.txt"
[[ -s "$PUBLIC_KEY_FILE" ]] || { echo "Missing Sparkle public key; run script/generate_sparkle_keys.sh" >&2; exit 1; }
CONFIGURATION=debug
[[ "$MODE" != "--release-build" ]] || CONFIGURATION=release
PREVIOUS_ID="$((codesign -d -r- "$APP_BUNDLE" 2>&1 || true) | sed -n 's/^# designated => //p')"
swift build --scratch-path "$ROOT_DIR/.build/lidflow" -c "$CONFIGURATION"
BIN_DIR="$(swift build --scratch-path "$ROOT_DIR/.build/lidflow" -c "$CONFIGURATION" --show-bin-path)"
if pgrep -x LidFlow >/dev/null; then pkill -x LidFlow; fi
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$ROOT_DIR/artifacts"
"$ROOT_DIR/script/make_icon.sh" >/dev/null
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
ditto "$ROOT_DIR/Resources/Licenses" "$APP_BUNDLE/Contents/Resources/Licenses"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
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
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 - "$APP_BUNDLE/Contents/Info.plist" "$APP_VERSION" "$BUILD_NUMBER" "$PUBLIC_KEY_FILE" <<'PYPLIST'
import base64, pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
key = pathlib.Path(sys.argv[4]).read_text().strip()
assert len(base64.b64decode(key, validate=True)) == 32, 'Invalid Sparkle public key'
info = plistlib.loads(path.read_bytes())
info.update(CFBundleShortVersionString=sys.argv[2], CFBundleVersion=sys.argv[3],
    SUFeedURL='https://github.com/0xnxxh/lidflow/releases/latest/download/appcast.xml',
    SUPublicEDKey=key, SUEnableAutomaticChecks=True,
    SUAutomaticallyUpdate=False, SUEnableSystemProfiling=False,
    SUEnableDownloaderSystemProfiling=False)
path.write_bytes(plistlib.dumps(info))
PYPLIST
# Set LIDFLOW_SIGN_IDENTITY to a valid development identity when available.
# Do not weaken the designated requirement or edit TCC to retain permissions.
IDENTITY="${LIDFLOW_SIGN_IDENTITY:--}"
SIGN_OPTIONS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--options runtime --timestamp); fi
FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
for ITEM in "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
            "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
            "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app"; do
    codesign "${SIGN_OPTIONS[@]}" "$ITEM"
done
codesign "${SIGN_OPTIONS[@]}" "$FRAMEWORK"
codesign "${SIGN_OPTIONS[@]}" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
CURRENT_ID="$(codesign -d -r- "$APP_BUNDLE" 2>&1 | sed -n 's/^# designated => //p')"
if [ -n "$PREVIOUS_ID" ] && [ "$PREVIOUS_ID" != "$CURRENT_ID" ]; then
    echo "LidFlow signing identity changed. An old Screen Recording entry may need removal and re-addition in System Settings." >&2
fi
if [[ "$MODE" == "--build" || "$MODE" == "--release-build" ]]; then echo "$APP_BUNDLE"; exit 0; fi
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
