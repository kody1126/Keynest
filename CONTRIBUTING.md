# 贡献 / Contributing

感谢参与 Keynest。当前主产品是 `macos/` 原生 App；根目录 Web 是独立的早期实验。

Thank you for contributing. The native app in `macos/` is the main product; the root Web app is a separate early experiment.

## 提交修改 / Submitting changes

- 先说明需要解决的问题，保持修改范围清晰。同步维护 [中文 README](README.md) 与 [English README](README.en.md)。
- Describe the problem and keep changes focused. Update both READMEs when public behavior or setup changes.
- 测试只能使用临时库与虚构凭据；不要提交密钥、加密库、Touch ID 文件、构建缓存或本机 App。
- Use temporary vaults and fictitious credentials only. Never commit secrets, encrypted vaults, biometric files, build caches or local app bundles.
- 运行与修改相关的检查，提交 PR 时注明结果。不要为了通过测试而删掉安全限制或忽略失败。
- Run the relevant checks and include results in your PR. Do not remove security controls or ignore failures to make tests pass.

```sh
# macOS + Apple Command Line Tools
cd macos
bash scripts/run-checks.sh
bash scripts/run-app-checks.sh
bash scripts/run-keychain-checks.sh
bash scripts/run-keychain-drag-checks.sh
bash scripts/run-keychain-catalog-checks.sh
bash scripts/run-keychain-asset-checks.sh
bash scripts/run-biometric-checks.sh --file-only

# Legacy Web app, from repository root; Node.js 22+
cd ..
npm test
```

原生核心使用系统框架，没有第三方 Swift 包依赖。构建、安装与数据兼容说明见 [macOS README](macos/README.md)。品牌资源有各自授权边界，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。

The native core uses system frameworks without third-party Swift packages. See the [macOS README](macos/README.md) for building, installation and data compatibility, and [third-party notices](THIRD_PARTY_NOTICES.md) for brand assets.

钥匙串检查无需窗口：运动与资源检查不创建渲染器，平台目录检查只用内存虚构条目。渲染效果、点击取用和真实窗口生命周期仍需在独立 Demo 中人工检查。配置保存在加密载荷版本 4 内；修改配置结构时请覆盖旧版兼容、加密备份、合并与锁定清理。

Keyring checks do not require windows: motion and resource checks do not create a renderer, and catalog checks use fictional in-memory entries. Verify rendering, key-panel interactions, and real window lifecycle behavior separately in the Demo. Configuration lives in encrypted payload version 4; schema changes need coverage for older payloads, encrypted backups, merging, and clearing state on lock.

安装与常规源码构建不需要 Blender。仅在重建立体资源时使用它，步骤与来源见 [KeychainArt](macos/Resources/KeychainArt/README.md)。品牌挂件是上游图标的派生资源，须保留对应授权说明，不可统一标为原创 MIT 图形。

Blender is not needed to install the app or make a normal source build. Use it only when regenerating 3D artwork, following the [KeychainArt notes](macos/Resources/KeychainArt/README.md). Brand charms derive from upstream icons; preserve their license records instead of labeling every mesh as original MIT artwork.

## 安全问题 / Security reports

请按 [安全政策](SECURITY.md) 私下报告漏洞；不要在公开 Issue、PR 或日志中粘贴真实密钥或密钥库。

Follow the [security policy](SECURITY.md) to report vulnerabilities privately. Never paste real credentials or vault files into public issues, pull requests or logs.
