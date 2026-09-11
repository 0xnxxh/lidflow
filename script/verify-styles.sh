#!/usr/bin/env bash
# Build an isolated, offscreen harness; does not replace or re-sign the running app.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TASK_TMP="$(mktemp -d /tmp/lidflow-stylecheck.XXXXXX)"
trap 'rm -rf "$TASK_TMP"' EXIT
xcrun swiftc -emit-library -emit-module -module-name FoldCore Sources/FoldCore/*.swift -o "$TASK_TMP/libFoldCore.dylib" -emit-module-path "$TASK_TMP/FoldCore.swiftmodule"
python3 - "$TASK_TMP" <<'PY'
import sys
from pathlib import Path
s=Path('Sources/LidFlow/Renderer.swift').read_text().replace('let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal")!', 'let shaderURL = URL(fileURLWithPath: CommandLine.arguments[1])')
Path(sys.argv[1],'Renderer.swift').write_text(s)
PY
xcrun swiftc -O -I "$TASK_TMP" -L "$TASK_TMP" -lFoldCore -Xlinker -rpath -Xlinker "$TASK_TMP" "$TASK_TMP/Renderer.swift" Sources/LidFlow/RenderMetrics.swift Sources/LidFlow/RenderVerification.swift research/verify-styles.swift -o "$TASK_TMP/check"
"$TASK_TMP/check" "$ROOT/Sources/LidFlow/Shaders.metal" "$ROOT/artifacts/styles"
