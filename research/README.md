# 开发验证工具

本目录保留仍有用途的本地诊断与验证程序，不参与应用运行。

- `verify-styles.swift`、`benchmark-render.swift`、`background-overlay.swift`：由 `script/` 中对应入口编译运行。
- `probe-lid.swift`、`probe-lid-events.swift`、`inspect-angle-elements.swift`、`measure-lid-read.swift`：只读传感器探测与采样。
- `verify-background-sensor.swift`、`replay-lid-motion.swift`：后台读取与角度重建诊断。
- `extract-frames.swift`：本地视频关键帧检查。

开发前的视觉调研已移到 `docs/archive/`，不代表当前功能状态。`research/assets/`、`artifacts/` 与 `dist/` 都是本地产物，不提交。
