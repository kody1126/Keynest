<p align="center">
  <img src="macos/Resources/design/options-c-palette/C2-256.png" width="112" alt="Keynest icon">
</p>
<h1 align="center">Keynest</h1>
<p align="center"><strong>Keep your API keys together on your Mac.</strong></p>
<p align="center">Local encryption · Touch ID · Find a provider, copy a key</p>

<p align="center">
  <a href="https://github.com/kody1126/Keynest/releases/tag/v0.11.1"><img src="https://img.shields.io/badge/preview-v0.11.1-5b9bd5" alt="Preview v0.11.1"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-333333" alt="macOS 14 or later">
  <a href="https://github.com/kody1126/Keynest/actions/workflows/checks.yml"><img src="https://github.com/kody1126/Keynest/actions/workflows/checks.yml/badge.svg?branch=main" alt="Build and tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/code-MIT-38956e" alt="Code license: MIT"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/kody1126/Keynest/releases/download/v0.11.1/Keynest-0.11.1-arm64-r1.dmg">Download for macOS</a></strong>
  · <a href="README.md">简体中文</a>
  · <a href="docs/guide.en.md">User guide</a>
  · <a href="https://github.com/kody1126/Keynest/issues">Report an issue</a>
</p>

<p align="center">Apple Silicon · Chinese interface · Free and open source</p>

<p align="center">
  <a href="docs/images/keyring.png"><img src="docs/images/keyring.png" width="1000" alt="Keynest Home with a three-dimensional keyring above provider cards"></a>
</p>
<p align="center"><sub>Keynest 0.11.1 · Your most-used keys, close at hand.</sub></p>

One model provider can mean several keys. One Agent can need access to search, a browser, and a database. Keynest keeps these credentials in one local vault: save them once, then find the provider on Home and copy the key you need.

<p align="center">
  <a href="#open-home-find-a-provider-copy-a-key">Home</a> ·
  <a href="#keep-personal-team-and-development-keys-separate">Multiple keys</a> ·
  <a href="#choose-from-61-providers">Providers</a> ·
  <a href="#organize-keys-around-your-tools-skills-and-agents">Tools &amp; Skills</a> ·
  <a href="#make-the-keyring-and-home-your-own">Customization</a>
</p>

## Open Home, find a provider, copy a key

Search by provider, key name, account, or environment, filter your favorites, and copy directly from a card. Cards fit their content in a compact layout. Collapse the keyring when you want more room for provider cards.

<p align="center">
  <a href="docs/images/home.png"><img src="docs/images/home.png" width="1000" alt="Home showing compact provider cards, search, filters, and a Copy button for each key"></a>
</p>

## Keep personal, team, and development keys separate

Save several keys for the same provider and distinguish them by name, account, environment, and API address. Link a key to the tools that use it, so you can find the right credential without keeping duplicate copies.

<p align="center">
  <a href="docs/images/key-details.png"><img src="docs/images/key-details.png" width="1000" alt="Key details showing account, environment, API address, and associated tools"></a>
</p>

## Choose from 61 providers

OpenAI, Claude, Gemini, DeepSeek, Cloudflare, GitHub, and more are ready to select, with brand icons and official API links. Choose the provider, paste your own key, and save. Custom providers are supported too.

<p align="center">
  <a href="docs/images/providers.png"><img src="docs/images/providers.png" width="800" alt="Provider picker with model and service presets, brand icons, and categories for different uses"></a>
</p>

## Organize keys around your tools, Skills, and Agents

Start with 25 templates for tools such as Cursor, Cline, Dify, and n8n. Reuse a saved key across several tools or add a missing credential when you need it. Keynest organizes these relationships; it does not automatically change external tools' configuration.

<table>
  <tr>
    <td width="50%" align="center"><a href="docs/images/tool-templates.png"><img src="docs/images/tool-templates.png" width="100%" alt="Tool template picker with coding assistants and their provider requirements"></a></td>
    <td width="50%" align="center"><a href="docs/images/agent-templates.png"><img src="docs/images/agent-templates.png" width="100%" alt="Agent and workflow templates for organizing related API credentials"></a></td>
  </tr>
  <tr>
    <td align="center">Coding tools and assistants</td>
    <td align="center">Agents, Skills, and workflows</td>
  </tr>
</table>

[Browse the provider catalog](research/api-catalog-0.7.md) · [Explore the tool templates](research/skill-agent-templates-0.7.md)

## Make the keyring and Home your own

Choose up to eight charms and decide which key each one copies. When a provider has multiple keys, select the intended account and environment in **Customize (定制)**; afterward, clicking its charm copies that key directly. You can reorder the charms, reset their position, or collapse the keyring.

Use **Edit Layout (编辑布局)** to drag complete provider cards into your preferred order, or adjust them with the previous and next buttons. Save when you are happy, cancel your changes, or restore the default order.

<table>
  <tr>
    <td width="50%" align="center"><a href="docs/images/keyring-customize.png"><img src="docs/images/keyring-customize.png" width="100%" alt="Keyring customization showing charm selection and the key assigned to each provider"></a></td>
    <td width="50%" align="center"><a href="docs/images/home-layout.png"><img src="docs/images/home-layout.png" width="100%" alt="Home layout editor with complete provider cards and controls to save, cancel, or restore the default order"></a></td>
  </tr>
  <tr>
    <td align="center">Choose your charms and their keys</td>
    <td align="center">Arrange your provider cards</td>
  </tr>
</table>

The keyring renders locally and receives only display information such as provider names, artwork, and colors; it does not hold secret values. Charm bindings and Home order are encrypted with the vault and included in encrypted backups. It respects Reduce Motion and Reduce Transparency.

<p align="center">
  <sub>All screenshots show the Keynest 0.11.1 interface.</sub>
</p>

## Download and get started

**[Download Keynest 0.11.1 · Apple Silicon](https://github.com/kody1126/Keynest/releases/download/v0.11.1/Keynest-0.11.1-arm64-r1.dmg)** · [Release notes and SHA-256 checksums](https://github.com/kody1126/Keynest/releases/tag/v0.11.1)

The public download includes only `Keynest.app`. See the [release notes](https://github.com/kody1126/Keynest/releases/tag/v0.11.1) for packaging revision details.

Requires **macOS 14 or later**. A package is available for Apple Silicon. You can try building from source on an Intel Mac, but that configuration has not been verified.

1. Open the DMG, copy `Keynest.app` to your personal `~/Applications` folder, and launch the installed app.
2. Set a master password of at least 12 characters. Enable Touch ID if your Mac supports it.
3. Choose a provider on Home, paste your API key, and save. Next time, use **Copy (复制)** on its card or click a charm with a selected key to copy it directly.

> [!IMPORTANT]
> This is a preview release with a local ad-hoc signature. It is not signed with an Apple Developer ID or notarized, so macOS may block the first launch. Download from this repository or build from source; see [Apple’s first-launch guidance](https://support.apple.com/en-us/102445). Your master password cannot be recovered; keep it safe and export encrypted backups regularly.

## Local storage, clear security boundaries

The entire vault is encrypted with **AES-256-GCM**. Its encryption key is derived from your master password using **PBKDF2-HMAC-SHA256 with 600,000 iterations and a random salt**. Touch ID unlock is protected by Apple's Secure Enclave.

- No cloud account is required, and Keynest does not initiate vault uploads or synchronization.
- Supported Macs can unlock with Touch ID, with your master password available as a fallback.
- Export encrypted backups locally, or merge entries from a backup into your existing vault.
- The vault locks after 10 minutes of inactivity or when your Mac sleeps.
- Universal Clipboard synchronization is disabled for each copy. Keynest clears it after 60 seconds without replacing anything you copy afterward; third-party clipboard tools may still retain a copy.
- Quota queries must be enabled explicitly and refreshed manually. They currently support selected balance or usage information from DeepSeek, SiliconFlow, and OpenRouter. **There is no real-time quota synchronization across all providers.**

This project has not undergone an independent security audit. Encryption at rest cannot guarantee the safety of unlocked memory, the screen, or the clipboard if malware already controls your Mac.

[Security mechanisms and limits](docs/guide.en.md#data-and-security) · [0.8.1 review record](research/security-review-0.8.1.md) · [Report a vulnerability privately](SECURITY.md)

## Build from source

> **Source preview:** `main` contains the 0.12.0 candidate with live card reordering and refined Blender charms. Final native UI verification is pending; the downloadable release and screenshots above remain 0.11.1. [Verification record](macos/verification.md) · [3D asset previews and source files](macos/Resources/KeychainArt/README.md)

The native app uses SwiftUI and AppKit, with SceneKit rendering the Home keyring locally. There are no third-party Swift Package dependencies. You need macOS and Apple's Command Line Tools; Node.js, a full Xcode installation, and Blender are not required. Blender is used only to regenerate the bundled [3D assets](macos/Resources/KeychainArt/README.md) during development.

```sh
git clone https://github.com/kody1126/Keynest.git
cd Keynest/macos
zsh scripts/build-app.sh
zsh scripts/install-apps.sh
```

The default steps build and install only the regular app. The installer verifies and backs up an existing app without modifying your vault. Build outputs are placed in `macos/dist/apps.noindex/`; run the installed copy.

[Full build and packaging instructions](docs/guide.en.md#development-and-references) · [Testing and contributing](CONTRIBUTING.md) · [More documentation](docs/README.md)

## Contribute

Feedback, bug reports, and pull requests are welcome. Read the [contribution guide](CONTRIBUTING.md) first, and keep real keys and vaults out of public issues, screenshots, and logs. Submit security issues through [private vulnerability reporting](https://github.com/kody1126/Keynest/security/advisories/new).

## License

Original Keynest code is available under the [MIT License](LICENSE). Third-party brand icons retain their own licenses and trademark rights. Some assets from official websites have no separate open-source license and are not covered by this project's MIT license. See the [third-party notices](THIRD_PARTY_NOTICES.md).
