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
bash scripts/run-biometric-checks.sh --file-only

# Legacy Web app, from repository root; Node.js 22+
cd ..
npm test
```

原生核心使用系统框架，没有第三方 Swift 包依赖。构建、安装与数据兼容说明见 [macOS README](macos/README.md)。品牌资源有各自授权边界，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。

The native core uses system frameworks without third-party Swift packages. See the [macOS README](macos/README.md) for building, installation and data compatibility, and [third-party notices](THIRD_PARTY_NOTICES.md) for brand assets.

## 安全问题 / Security reports

请按 [安全政策](SECURITY.md) 私下报告漏洞；不要在公开 Issue、PR 或日志中粘贴真实密钥或密钥库。

Follow the [security policy](SECURITY.md) to report vulnerabilities privately. Never paste real credentials or vault files into public issues, pull requests or logs.
