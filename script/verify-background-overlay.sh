#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TASK_TMP="$(mktemp -d /tmp/lidflow-backgroundcheck.XXXXXX)"
trap 'rm -rf "$TASK_TMP"' EXIT
APP="$TASK_TMP/BackgroundCheck.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" artifacts/automatic-follow
xcrun swiftc -emit-library -emit-module -module-name FoldCore Sources/FoldCore/*.swift -o "$TASK_TMP/libFoldCore.dylib" -emit-module-path "$TASK_TMP/FoldCore.swiftmodule"
python3 - "$TASK_TMP" <<'PY'
import sys
from pathlib import Path
s=Path('Sources/LidFlow/Renderer.swift').read_text().replace('Bundle.module.url(', 'Bundle.main.url(')
Path(sys.argv[1],'Renderer.swift').write_text(s)
PY
xcrun swiftc -O -I "$TASK_TMP" -L "$TASK_TMP" -lFoldCore -Xlinker -rpath -Xlinker "$TASK_TMP" "$TASK_TMP/Renderer.swift" Sources/LidFlow/RenderMetrics.swift Sources/LidFlow/DisplayPacedView.swift Sources/LidFlow/OverlayController.swift research/background-overlay.swift -o "$APP/Contents/MacOS/BackgroundCheck"
cp Sources/LidFlow/Shaders.metal "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>BackgroundCheck</string><key>CFBundleIdentifier</key><string>app.lidflow.backgroundcheck</string><key>CFBundleName</key><string>LidFlow Background Check</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PLIST
codesign --force --sign - "$APP"
REPORT="$ROOT/artifacts/automatic-follow/overlay-$(date +%s).json"
open -g -n "$APP" --args "$REPORT"
python3 - "$REPORT" <<'PY'
import json,sys,time
from pathlib import Path
p=Path(sys.argv[1]);deadline=time.monotonic()+25
while not p.exists() and time.monotonic()<deadline:time.sleep(.1)
if not p.exists():raise SystemExit('Background overlay timed out')
r=json.loads(p.read_text());print(json.dumps(r,indent=2));assert r['passed'],r
PY
