# 版本与发布

`VERSION` 是三段版本号，`BUILD_NUMBER` 是递增的正整数。首个发行版为 `1.0.0` / `2`，构建号 1 留给此前本机开发版。后续版本必须同时递增版本号与构建号，保持 `app.lidflow.local` Bundle ID 和 Sparkle 公钥，才能沿用设置与更新信任。

## 构建与检查

```sh
./script/release_check.sh
```

脚本运行发布流程测试、Swift 核心测试、release 优化构建、图标生成、嵌套代码签名、DMG 生成与校验、appcast 生成，以及使用应用内公钥独立验证 Ed25519 签名。产物位于 `dist/`，均不提交 Git。

Sparkle 2.9.3 由 SwiftPM 下载并校验二进制包；更新私钥使用登录钥匙串账号 `0xnxxh.lidflow`，仓库只包含 `Config/sparkle_public_ed_key.txt`。从新电脑发布前需安全迁移同一私钥，不能重新生成并替换已分发的公钥。可用 `SPARKLE_PRIVATE_KEY_FILE` 指定导出的私钥文件路径，文件不得提交或输出内容。普通源码构建只需仓库里的公钥。

默认应用签名为 ad-hoc，与更新包的 Ed25519 签名是两回事。可通过 `LIDFLOW_SIGN_IDENTITY` 使用有效身份签名；只有实际完成 Developer ID 签名、公证和 stapling 后，才能将发行说明改为已公证。当前流程不自动提交 Apple 公证。

## 发布

先更新版本、构建号与 `RELEASE_NOTES.md`，检查 README 的功能、下载说明是否与当前应用一致。复查待提交目录，运行检查后提交并推送 `main`。

```sh
CONFIRM_PUBLISH=1 ./script/publish_release.sh
```

发布入口需要干净且与 `origin/main` 同步的 `main` 分支。它校验 release 不存在、运行发布检查、创建并推送对应 tag，上传 DMG 与 appcast 为草稿，核对 GitHub 的 SHA-256 摘要，再公开 Release。失败时保留真实错误和未发布草稿，禁止覆盖已有版本。

更新地址固定为 `https://github.com/0xnxxh/lidflow/releases/latest/download/appcast.xml`。每个 appcast 中安装包地址指向对应版本的 GitHub Release。发布后从应用的“检查更新…”正常入口验证在线检查；首版不能证明所有后续版本的升级兼容性。

## 提交边界

提交源码、测试、构建/发布脚本、版本文件、公钥、应用图标、当前文档。`artifacts/`、`dist/`、`.build/`、私钥、证书、临时视频、第三方原始模板与低分辨率弃用素材不提交。

`docs/archive/` 是历史研究，不作为当前契约；`research/README.md` 说明仍有消费者的验证工具。
