<p align="center">
  <img src="macos/Resources/design/options-c-palette/C2-256.png" width="112" alt="Keynest 图标">
</p>
<h1 align="center">Keynest</h1>
<p align="center"><strong>把散落在各个平台的 API 密钥，收进你的 Mac。</strong></p>
<p align="center">本地加密保存 · Touch ID 解锁 · 找到平台，直接复制</p>

<p align="center">
  <a href="https://github.com/kody1126/Keynest/releases/tag/v0.9.0"><img src="https://img.shields.io/badge/preview-v0.9.0-5b9bd5" alt="预览版 v0.9.0"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-333333" alt="macOS 14 或更新版本">
  <a href="https://github.com/kody1126/Keynest/actions/workflows/checks.yml"><img src="https://github.com/kody1126/Keynest/actions/workflows/checks.yml/badge.svg?branch=main" alt="构建与测试"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/code-MIT-38956e" alt="代码许可证 MIT"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/kody1126/Keynest/releases/download/v0.9.0/Keynest-0.9.0-arm64.dmg">下载 macOS 版</a></strong>
  · <a href="README.en.md">English</a>
  · <a href="macos/README.md">使用文档</a>
  · <a href="https://github.com/kody1126/Keynest/issues">反馈问题</a>
</p>

<p align="center">适用于 Apple Silicon · 当前界面为中文 · 免费开源</p>

<p align="center">
  <img src="docs/images/home.jpg" width="1000" alt="Keynest 首页：按平台展示密钥，以账号和环境区分同平台的多把密钥，并直接复制">
</p>
<p align="center"><sub>真实 App 截图，使用独立 Demo 的虚构数据。</sub></p>

## 少翻几个网站，多留一点时间

一个模型平台有几把 Key，一个 Agent 又要连接搜索、浏览器和数据库。Keynest 把这些凭据放在同一个本地密钥库里：保存一次，下次用的时候打开首页，找到平台，复制需要的那一把。

- **打开就能取用** — 首页卡片按内容高度紧凑排列，右上角搜索，支持常用筛选；无需先进入编辑表单。
- **一串可互动的钥匙** — 首页大展示区放着银白冰蓝的多链钥匙串，配有 OpenAI、Claude、Gemini 图标吊牌；可拖动回弹、复位或收起，并记住展开或收起的选择。
- **多把密钥，也分得清** — 用账号、环境和 API 地址区分个人、团队、开发与正式用途。
- **常见平台，选好再粘贴** — 内置 61 个服务商预设，覆盖 OpenAI、Claude、Gemini、DeepSeek、Cloudflare、GitHub 等，附品牌图标和官方 API 入口。
- **按工具整理一组密钥** — 25 个工具与 Skill 模板，覆盖 Cursor、Cline、Dify、n8n 等；一把密钥可供多个工具关联使用。
- **Touch ID 快速解锁** — 支持的 Mac 可使用系统指纹验证，主密码始终保留为备用。
- **带着备份，留在本地** — 导出加密备份，也能将备份中的条目合并进现有密钥库。

钥匙串仅作装饰，在本机渲染，不联网，也不读取或保存密钥；支持系统的「减少动态效果」设置。

<details>
<summary><strong>看看工具模板</strong></summary>

<p align="center">
  <img src="docs/images/tool-templates.jpg" width="720" alt="Keynest 工具模板选择器，展示 Cursor、Cline、Roo Code、Continue 等模板">
</p>

为工具复用已有密钥，或补上它需要的新密钥；Keynest 负责整理，不会自动修改这些工具的配置。[查看平台目录](research/api-catalog-0.7.md) · [查看工具模板](research/skill-agent-templates-0.7.md)

</details>

## 下载与开始使用

**[下载 Keynest 0.9.0 · Apple Silicon](https://github.com/kody1126/Keynest/releases/download/v0.9.0/Keynest-0.9.0-arm64.dmg)** · [发布说明与 SHA-256 校验文件](https://github.com/kody1126/Keynest/releases/tag/v0.9.0)

需要 **macOS 14 或更新版本**。当前提供 Apple Silicon 安装包；Intel Mac 可尝试从源码构建，但尚未验证。

1. 打开 DMG，将 `Keynest.app` 复制到个人的 `~/Applications` 文件夹，再打开安装后的 App。
2. 设置至少 12 个字符的主密码；支持 Touch ID 时可选择启用指纹解锁。
3. 在首页选择平台，粘贴自己的 API Key，保存。下次直接从平台卡片复制。

> [!IMPORTANT]
> 当前是预览版，采用本地 ad-hoc 签名，尚未使用 Apple Developer ID 签名或公证，首次打开可能被 macOS 拦截。请从本仓库下载，或从源码构建；首次打开可参考 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。主密码无法找回，请妥善保存并定期导出加密备份。

<details>
<summary><strong>想先试用？安装包里附有独立 Demo</strong></summary>

将 `Keynest Demo.app` 也复制到 `~/Applications` 后打开，输入公开密码 **`Keynest-Demo-2026`**，不需要用户名。内有 **34 把虚构密钥和 10 个工具**，可以体验搜索、复制、添加与关联。

Demo 与正式密钥库分开存储，不发起额度查询，也不支持导入导出或改密码。**不要在 Demo 中保存真实凭据。**

</details>

## 本地保存，安全边界说清楚

密钥库整体使用 **AES-256-GCM** 加密，主密码通过 **PBKDF2-HMAC-SHA256（600,000 次迭代、随机盐）**派生加密密钥。Touch ID 的解锁能力由 Apple Secure Enclave 保护。

- 不需要云端账户，不主动上传或同步密钥库。
- 闲置 10 分钟或系统休眠后自动锁定。
- 复制时禁用通用剪贴板同步；30 秒后清除本次复制内容，不覆盖后来复制的其他内容。第三方剪贴板工具仍可能保存副本。
- 额度查询需主动开启并手动刷新。目前支持 DeepSeek、硅基流动和 OpenRouter 的部分余额或用量信息，**不提供全平台实时额度同步**。

本项目尚未经过独立安全审计。磁盘加密不能保证电脑已被恶意软件控制时，解锁中的内存、屏幕或剪贴板仍然安全。

[安全机制与限制](macos/README.md#安全边界) · [0.8.1 检查记录](research/security-review-0.8.1.md) · [私下报告漏洞](SECURITY.md)

## 从源码构建

原生 App 使用 SwiftUI / AppKit，首页钥匙串使用 SceneKit 本地渲染，没有第三方 Swift Package 依赖。需要 macOS 和 Apple Command Line Tools；不需要 Node.js 或完整 Xcode。

```sh
git clone https://github.com/kody1126/Keynest.git
cd Keynest/macos
zsh scripts/build-app.sh
zsh scripts/build-demo-app.sh
zsh scripts/install-apps.sh
```

安装脚本会校验并备份已有 App，不会改动密钥库。构建产物位于 `macos/dist/apps.noindex/`；请运行安装后的副本。

[完整构建与打包说明](macos/README.md#从源码构建) · [测试与贡献指南](CONTRIBUTING.md) · [更多文档](docs/README.md)

## 参与这个项目

欢迎提交使用反馈、Bug 和 Pull Request。请先看 [贡献指南](CONTRIBUTING.md)；公开 Issue、截图和日志中不要包含真实密钥或密钥库。安全问题请通过 [私密漏洞报告入口](https://github.com/kody1126/Keynest/security/advisories/new) 提交。

## 许可证

Keynest 原创代码采用 [MIT License](LICENSE)。第三方品牌图标保留各自的许可及商标权利，部分官网素材未附独立开源授权，不在本项目 MIT 授权范围内。详见 [第三方声明](THIRD_PARTY_NOTICES.md)。
