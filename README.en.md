# Keynest

[简体中文](README.md) | **[English](README.en.md)**

A native macOS app for collecting and managing API keys. Unlock your vault, find a provider on Home, and copy the key you need. Account labels, environments, and API hosts help distinguish multiple keys from the same provider. You can also organize keys by the tools that use them, and share one key across multiple tools.

The current release is **0.8.1, a security update to the experimental native Mac app**. It uses SwiftUI and AppKit, with no Node.js, browser, or cloud account required. The distributed build targets Apple Silicon Macs running macOS 14 or later. The app currently has a Chinese interface.

## Open the app

Download a macOS package from [GitHub Releases](https://github.com/kody1126/Keynest/releases), or build from source below. Install it at `~/Applications/Keynest.app`. Open it in Finder, or run:

```sh
open "$HOME/Applications/Keynest.app"
```

The current disk image is `Keynest-0.8.1-arm64.dmg` ([download v0.8.1](https://github.com/kody1126/Keynest/releases/tag/v0.8.1)). It contains both `Keynest.app` and the separate `Keynest Demo.app`. Install both into `~/Applications` before opening them. The apps use local ad-hoc signatures; they are not signed with an Apple Developer ID or notarized by Apple.

On first launch, set a master password of at least **12 characters**. On Home, choose a provider, paste your key, and select **Save to Home (保存到首页)**. Presets fill in the name and a common API address; project-specific addresses must be entered as indicated. Expand the optional fields to add an account label or environment. **Full Editor… (完整编辑…)** also lets you add tags, notes, and tool associations. Subsequent unlocks open Home by default. There is no master-password recovery.

On a Mac that supports Touch ID, select **Enable Touch ID after unlocking (解锁后启用 Touch ID)**, or enable it in Settings after unlocking. Future launches can use the system fingerprint prompt, while the master password remains available as a fallback. Cancel fingerprint verification to switch to password entry. Touch ID must be enabled again after changing enrolled fingerprints, changing the master password, or moving to another Mac. Its unlock material stays on this Mac and is not included in exported encrypted backups.

## Try the demo vault

Open `~/Applications/Keynest Demo.app` and enter the test password **`Keynest-Demo-2026`**. No username is needed. This is a local demonstration vault, not a real account with any model provider.

A new demo vault contains **34 fictional keys and 10 tools**, including key combinations for Cline, OpenClaw, n8n, and LangGraph, plus Skill and Agent service examples. You can try adding, editing, linking, searching, revealing, and copying keys, as well as Touch ID. Quota requests, backup import/export, and password changes are disabled in the demo. Catalog upgrades preserve existing edits and do not restore previously deleted samples. The test password stays the same.

Demo data is stored separately from the regular vault in `~/Library/Application Support/Keynest Demo/`. **The demo password is public. Never put real credentials in this vault.** Website links can still be opened manually in a browser, so the demo is not a completely offline mode. See the [demo guide](macos/README.md#独立演示版) for details.

## Everyday use

- **Copy from Home:** Provider cards have a separate Copy button for each key. A card shows up to two keys directly; use **View All (查看全部)** to explicitly choose from additional keys. Account labels, environments, and API hostnames help distinguish personal accounts, team accounts, and custom gateways.
- **Home filters and search:** Filter by **All / Models / Skills & Services / Favorites (全部 / 模型 / Skill 与服务 / 常用)**. Home searches provider names and aliases, key names, account labels, environments, tags, and associated tool names. It does not search secrets, URLs, or notes. The management view retains broader metadata search, including URLs and notes.
- **Quick Add:** Choose a provider on Home and paste a key. If you already have keys for that provider, optional fields expand automatically and the default name receives a distinct number, making it easier to add an account label or purpose. The full editor remains available. You can also add another key from the bottom of a provider card.
- **25 tool templates:** Templates cover Cursor, Cline, OpenClaw, Dify, n8n, LangGraph, and others, plus Skills for search, crawling, browsers, Cloudflare, GitHub, Notion, email, maps, and weather. Choose a tool, reuse existing keys or enter new ones, and save all associations together. Optional capabilities are disabled by default.
- **Organize by tool:** The management view includes All Keys, Favorites, Ungrouped, My Tools, and categories. A tool can use multiple keys, and a key can belong to multiple tools. Removing a tool removes its associations without deleting the keys.
- **Separate accounts and environments:** Each key can have an account label and environment, and the list supports environment filtering. Keys created inside a tool are automatically associated with it; existing keys can also be linked.
- **61 provider presets:** Presets are grouped by Models & Inference, Images & Audio, Search & Crawling, Development & Data, Messaging & Collaboration, and Agent Tools—not by country. Each provides an official API website, a default request address where appropriate, and setup hints. Project-specific addresses are left blank for you to supply. All **76 brand icons—61 provider icons and 15 tool icons—are bundled locally**, with no network loading required.
- **Official API website links:** Known providers have a separate **API Website (API 官网)** link on Home cards, in Quick Add, in the full editor, and in details. The API address remains a separate endpoint field. Existing custom source websites are preserved.
- **View and edit:** Each key's menu on Home can copy its API address, toggle its favorite status, open its details, or edit it. The management list and detail pane also support copying keys. Neither search mode reads the secret field.
- **Hide and lock:** Keys are hidden by default. A revealed key hides again after 20 seconds, when you switch entries, or when the window loses focus. The vault locks after 10 minutes of inactivity or when the system sleeps.
- **Copying:** A key or API address is written only to the local clipboard. Cross-device clipboard sharing is disabled for that copy, and the content is marked as sensitive and transient. Keynest clears its own copied content after 30 seconds; if you copy something else in the meantime, the newer clipboard contents are preserved.
- **Backups:** Export an encrypted `.keynest` backup from the toolbar menu. Importing into an existing vault merges entries without overwriting existing records. A new vault can also be restored from a backup.

Common shortcuts: `⌘1` opens Home, `⌘2` opens All Keys in the management view, `⌘F` focuses Home search, `⌘N` adds a key, `⇧⌘N` adds a tool, and `⇧⌘L` locks the vault. `⇧⌘C` copies the selected key and `⌘E` edits it; these require a selected record in the management view. Home does not select a key automatically. See the [macOS guide](macos/README.md) for complete usage and build instructions.

You can choose another preset while editing. Keys, notes, tags, and custom names or addresses are preserved; only empty fields or values that still match the previous preset's defaults are replaced. Returning to the picker and then canceling brings you back to your draft. Switching to a different preset disables the previous quota-query setting and clears its snapshot. Choosing a preset does not send your key anywhere.

A category is suggested automatically only when you first choose a preset for a completely blank draft that still has the default category. Editing an existing entry or switching presets later does not recategorize it.

## Optional quota queries

Expand **Advanced Options (高级选项)** while editing an entry and explicitly choose a quota service. You can then refresh it manually from **Quota (额度查询)** in the detail pane. Quota queries are disabled by default. There is no real-time synchronization across all providers and no background polling.

| Service | Supported query |
| --- | --- |
| DeepSeek | Official API account balance, with currencies shown separately |
| SiliconFlow | Total account balance on the China service |
| OpenRouter | Limits and usage for the current key, not the total account balance |

You can still store keys for other models and tools normally. Quota data is a snapshot taken at query time and may lag behind upstream billing. An unset key limit does not mean an unlimited balance. Multiple keys may also share one account balance.

The regular app queries only the selected service's fixed official HTTPS endpoint. It does not guess which provider owns a key or try sending it to multiple platforms. If an API address is supplied, its origin must match the quota service; otherwise the key is not sent. Official API and source websites are handed to the default browser only when you click their links.

## Data and security

The native app stores its vault at:

```text
~/Library/Application Support/Keynest/vault.keynest
```

Names, keys, tags, notes, and quota snapshots are encrypted together with **AES-256-GCM**. The encryption key is derived from the master password using **PBKDF2-HMAC-SHA256**, with **600,000 iterations** and a **32-byte random salt**. Each write uses a fresh random nonce. MD5 is not used. The regular app does not persist your chosen master password. It does not initiate cloud synchronization, automatically read credentials from other tools, or modify CLI, MCP, or Skills configuration.

Touch ID protects access to the vault through Secure Enclave access control tied to the currently enrolled fingerprints. Only a hardware-bound private-key representation and encrypted, wrapped unlock material are stored locally; failed authentication cannot decrypt the vault. See the [Touch ID implementation and verification notes](research/touch-id-0.6.md).

Version 0.8.1 retains payload version 3 from 0.7 and can read versions 1 and 2. The demo catalog revision remains 7. This update does not change the encryption format or repopulate demo data. The upgrade protection introduced in 0.7 still applies: before the first save of an older format, Keynest preserves the original encrypted bytes as `vault-before-0.7.keynest` in the same directory. Existing 0.5 upgrade backups are also retained. Versions 0.6 and earlier cannot read payload version 3; downgrading requires a pre-upgrade backup and the password used at that time. See [upgrades and compatibility](macos/README.md#升级与兼容性).

Version 0.8.1 fixes imports committing after cancellation, clipboard ownership races, hard-link file permission handling, malformed URLs, a crash involving certain slices of unlock data, and inconsistencies between in-memory state and encrypted files after disk synchronization failures. Inactivity locking now uses a monotonic clock, and both apps enable Hardened Runtime. Existing passwords remain usable; newly created or changed passwords also have a maximum UTF-8 size of 16 KiB. See the [security review and fixes](research/security-review-0.8.1.md).

**This is an experimental app without an independent security audit.** Encryption at rest cannot protect against malware that already controls your Mac, reading memory while the vault is unlocked, screenshots, or third-party clipboard history. System backup software may still back up encrypted files. See the [macOS security boundaries](macos/README.md#安全边界) for the mechanisms and limitations.

## App icon styles

The current selection is **C2, “Translucent Ice Blue”**: the keyring shape from option C with the light ice-blue palette explored in option F. [View the current icon](macos/Resources/design/options-c-palette/C2.png).

All **12 styles**, their generation scripts, PNG and ICNS files, and small-size previews are retained for further adjustments:

- [A–D: four shape directions](macos/Resources/design/options/Keynest-icon-options.png)
- [E–H: light AI-key designs](macos/Resources/design/options-light-ai/Keynest-light-ai-options.png)
- [C1–C4: light keyring palettes](macos/Resources/design/options-c-palette/Keynest-C-palette-options.png)

The build reads [AppIcon.selection](macos/Resources/AppIcon.selection) to choose a style. Change its identifier and rebuild to switch icons without deleting the other candidates. See the [icon library](macos/Resources/design/README.md) for the full index and instructions.

## Development and references

- [Native app build, backup, and development guide](macos/README.md)
- [macOS design references](research/macos-design-references.md)
- [Existing projects and quota API research](research/2026-09-22-landscape.md)
- [0.5 product direction and tradeoffs](research/product-direction-0.5.md)
- [0.7 API presets and official sources](research/api-catalog-0.7.md)
- [Skill / Agent tool templates and sources](research/skill-agent-templates-0.7.md)
- [0.8 Home and Quick Add](research/home-usability-0.8.md)
- [0.8.1 security review and fixes](research/security-review-0.8.1.md)
- [Native app verification record](macos/verification.md)

The native source is in `macos/`, with no third-party Swift Package dependencies. You can check, build, and package it with the macOS Command Line Tools; a full Xcode installation is not required:

```sh
git clone https://github.com/kody1126/Keynest.git
cd Keynest/macos
bash scripts/run-checks.sh
bash scripts/run-app-checks.sh
zsh scripts/build-app.sh
zsh scripts/build-demo-app.sh
zsh scripts/package-app.sh
zsh scripts/install-apps.sh
```

Intermediate app bundles live only in `macos/dist/apps.noindex/`. Do not run them directly from the build directory or disk image. The installer places both apps in `~/Applications`. Before replacing an app, it checks its identity and signature, archives the old app in a verified ZIP under `.build/app-backups/`, and attempts rollback if installation fails. Installation does not launch either app, access a vault, or change system indexing settings.

The packaging script builds both apps, creates the DMG, verifies the disk image, and writes a SHA-256 checksum file. The [verification record](macos/verification.md) is the reference for the scope of the 0.8.1 checks, builds, and hands-on app verification.

## Archived web experiment

The Node.js / web implementation at the repository root is retained as the early **0.1 technical experiment**. Its data location, encryption format, and features differ from those of the native app. The native app is the main entry point.

To revisit the web experiment, use Node.js 22 or later, run `npm start` from the repository root, and open the local URL printed in the terminal. By default, it saves data to `.data/vault.json` inside the project. Set `API_VAULT_DATA_DIR` to use another directory. Run its tests with `npm test`.

The native app does not automatically import, overwrite, or delete the web experiment's `.data` directory. Their encrypted backup formats are incompatible; keep their backups separately.

## License and contributions

Original project code is available under the [MIT License](LICENSE). Third-party brand artwork retains its own licenses and trademark rights; the project license grants no additional rights to those assets. See [third-party notices](THIRD_PARTY_NOTICES.md).

Report usage problems through [Issues](https://github.com/kody1126/Keynest/issues), or follow the [contribution guide](CONTRIBUTING.md) to submit changes. Report vulnerabilities privately using the [security policy](SECURITY.md); never submit real credentials or vaults.

Future project updates are committed and pushed to GitHub after verification, with both READMEs maintained together. See [AGENTS.md](AGENTS.md) for the collaboration rules. This is not a background upload mechanism: personal vaults, test runtime data and build outputs stay out of the source repository.
