#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TASK_TMP="$(mktemp -d /tmp/lidflow-renderbench.XXXXXX)"
trap 'rm -rf "$TASK_TMP"' EXIT
xcrun swiftc -emit-library -emit-module -module-name FoldCore Sources/FoldCore/*.swift -o "$TASK_TMP/libFoldCore.dylib" -emit-module-path "$TASK_TMP/FoldCore.swiftmodule"
python3 - "$TASK_TMP" <<'PY'
import sys
from pathlib import Path
folder=Path(sys.argv[1])
s=Path('Sources/LidFlow/Renderer.swift').read_text()
s=s.replace('let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal")!', 'let shaderURL = URL(fileURLWithPath: CommandLine.arguments[1])')
(folder/'Renderer.swift').write_text(s)
PY
xcrun swiftc -O -I "$TASK_TMP" -L "$TASK_TMP" -lFoldCore -Xlinker -rpath -Xlinker "$TASK_TMP" "$TASK_TMP/Renderer.swift" Sources/LidFlow/RenderMetrics.swift Sources/LidFlow/DisplayPacedView.swift research/benchmark-render.swift -o "$TASK_TMP/bench"
"$TASK_TMP/bench" "$ROOT/Sources/LidFlow/Shaders.metal"
