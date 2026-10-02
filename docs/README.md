# Keynest 文档 / Documentation

[返回首页](../README.md) · [English home](../README.en.md)

## 使用 / Using Keynest

| 文档 / Document | 内容 / Contents |
| --- | --- |
| [中文使用说明](../macos/README.md) | 首页、多个账号与环境、工具关联、Touch ID、备份、升级和构建 |
| [English user guide](guide.en.md) | Home, multiple accounts, tools, Touch ID, backups, compatibility and builds |
| [发布与下载 / Releases](https://github.com/kody1126/Keynest/releases) | 安装包、校验文件与版本说明 / Packages, checksums and release notes |
| [服务商目录 / Provider catalog](../research/api-catalog-0.7.md) | 61 个预设与官方 API 来源 / 61 presets and official API sources |
| [工具模板 / Tool templates](../research/skill-agent-templates-0.7.md) | 25 个 Skill、Agent 与工具模板 / 25 Skill, Agent and tool templates |

目录及技术记录目前主要使用中文。The catalogs and technical records are currently primarily in Chinese.

## 安全与开发 / Security and development

- [安全政策 / Security policy](../SECURITY.md)
- [0.8.1 安全检查与边界 / Security review and limitations](../research/security-review-0.8.1.md)
- [原生验证记录 / Native verification record](../macos/verification.md)
- [贡献与测试 / Contributions and tests](../CONTRIBUTING.md)
- [第三方素材声明 / Third-party asset notices](../THIRD_PARTY_NOTICES.md)
- [App 图标方案 / App icon library](../macos/Resources/design/README.md)

## 早期实验 / Early experiment

根目录的 `src/`、`public/` 和 `test/` 保留早期 0.1 Web 实验，原生 App 不依赖它。需要 Node.js 22+，在仓库根目录执行 `npm start` 或 `npm test`。它默认使用 `.data/vault.json`，加密格式与原生 `.keynest` 备份不互通；请勿混用数据或备份。

The root `src/`, `public/` and `test/` directories contain the early 0.1 Web experiment. The native app does not depend on it. With Node.js 22+, run `npm start` or `npm test` from the repository root. Its default vault is `.data/vault.json`; its encrypted format is incompatible with native `.keynest` backups. Keep the two sets of data and backups separate.
