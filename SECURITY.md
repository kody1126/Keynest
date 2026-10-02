# 安全政策 / Security policy

Keynest 当前为实验版，尚未经过独立安全审计。请使用最新版本，并保留自己妥善保管的加密备份。本仓库不提供安全保证或固定响应时限。

Keynest is experimental and has not undergone an independent security audit. Use the latest version and keep encrypted backups under your own control. This repository provides no security guarantee or fixed response-time commitment.

## 私下报告 / Private reporting

请使用 GitHub 的 [Report a vulnerability](https://github.com/kody1126/Keynest/security/advisories/new)。说明受影响版本、复现步骤与预期影响，使用虚构凭据。不要发送真实 API Key、主密码、密钥库或 Touch ID 文件。

Use GitHub's [Report a vulnerability](https://github.com/kody1126/Keynest/security/advisories/new). Include the affected version, reproduction steps and expected impact using fictitious credentials. Do not send real API keys, master passwords, vaults or biometric enrollment files.

如果无法使用私密报告入口，请勿把漏洞细节或敏感资料改发到公开 Issue；先通过仓库维护者的 GitHub 个人资料中提供的联系渠道沟通。

If private reporting is unavailable, do not post vulnerability details or sensitive material in a public issue. First contact the maintainer through a contact method listed on their GitHub profile.

## 边界 / Scope

- 原生 App 和历史 Web 实验的加密格式、数据目录和运行环境不同。
- The native app and legacy Web experiment use different encrypted formats, data directories and runtimes.
- 静态加密不能保证本机已被恶意软件控制时，解锁内存、屏幕或剪贴板仍安全。
- Encryption at rest cannot guarantee protection of unlocked memory, the screen or clipboard on a compromised machine.
- 本机 ad-hoc 签名与 Hardened Runtime 不等于 App Sandbox、Developer ID 签名或 Apple 公证。
- Local ad-hoc signing and Hardened Runtime are not App Sandbox isolation, Developer ID signing or Apple notarization.

[0.8.1 检查与边界 / Review and limitations](research/security-review-0.8.1.md)
