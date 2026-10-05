# Keynest user guide

[Back to the project](../README.en.md) · [中文使用说明](../macos/README.md)

A native macOS app for collecting and managing API keys. Unlock your vault, find a provider on Home, and copy the key you need. Account labels, environments, and API hosts help distinguish multiple keys from the same provider. You can also organize keys by the tools that use them, and share one key across multiple tools.

The current release is **0.11.0 (build 13)**. Click a keyring charm to copy its selected key, and drag provider cards in place to arrange Home. The platform buttons beneath the 3D display are removed; provider cards and search remain available. This experimental native Mac app retains the security fixes from 0.8.1 and uses SwiftUI and AppKit, with no Node.js, browser, or cloud account required. The distributed build targets Apple Silicon Macs running macOS 14 or later. The app currently has a Chinese interface.

## Open the app

Download a macOS package from [GitHub Releases](https://github.com/kody1126/Keynest/releases), or build from source below. Install it at `~/Applications/Keynest.app`. Open it in Finder, or run:

```sh
open "$HOME/Applications/Keynest.app"
```

The current disk image is `Keynest-0.11.0-arm64.dmg` ([download v0.11.0](https://github.com/kody1126/Keynest/releases/tag/v0.11.0)). It contains both `Keynest.app` and the separate `Keynest Demo.app`. Install both into `~/Applications` before opening them. The apps use local ad-hoc signatures; they are not signed with an Apple Developer ID or notarized by Apple.

On first launch, set a master password of at least **12 characters**. On Home, choose a provider, paste your key, and select **Save to Home (保存到首页)**. Presets fill in the name and a common API address; project-specific addresses must be entered as indicated. Expand the optional fields to add an account label or environment. **Full Editor… (完整编辑…)** also lets you add tags, notes, and tool associations. Subsequent unlocks open Home by default. There is no master-password recovery.

On a Mac that supports Touch ID, select **Enable Touch ID after unlocking (解锁后启用 Touch ID)**, or enable it in Settings after unlocking. Future launches can use the system fingerprint prompt, while the master password remains available as a fallback. Cancel fingerprint verification to switch to password entry. Touch ID must be enabled again after changing enrolled fingerprints, changing the master password, or moving to another Mac. Its unlock material stays on this Mac and is not included in exported encrypted backups.

## Try the demo vault

Open `~/Applications/Keynest Demo.app` and enter the test password **`Keynest-Demo-2026`**. No username is needed. This is a local demonstration vault, not a real account with any model provider.

A new demo vault contains **34 fictional keys and 10 tools**, including key combinations for Cline, OpenClaw, n8n, and LangGraph, plus Skill and Agent service examples. You can try adding, editing, linking, searching, revealing, and copying keys, as well as Touch ID. Quota requests, backup import/export, and password changes are disabled in the demo. Catalog upgrades preserve existing edits and do not restore previously deleted samples. The test password stays the same.

Demo data is stored separately from the regular vault in `~/Library/Application Support/Keynest Demo/`. **The demo password is public. Never put real credentials in this vault.** Website links can still be opened manually in a browser, so the demo is not a completely offline mode. See the [demo guide](../macos/README.md#独立演示版) for details.

## Everyday use

- **Interactive keyring:** Only the lower arc of a metal clasp appears below the cropped top edge, with chains of staggered lengths that complement the light interface. The 61 independent enamel brand charms follow the logos' contours, with cutouts, depth, and soft highlights, modeled in Blender and rendered locally. Multicolor logos use a representative hue. Custom providers without artwork use glass keys in six colors: ice, lavender, mint, amber, rose, and graphite.
- **Click to copy:** A charm copies the key explicitly selected for it. With no explicit selection, a provider with exactly one key can copy directly; a provider with several keys opens **Customize (定制)** so you can choose by name, account, and environment. The picker also shows the API host and port, with a short ID to distinguish matching names. A previously selected key must still belong to that provider. If it was removed or moved, select again or use **Reset Invalid Binding (重置失效绑定)** and save; there is no automatic fallback. A provider with no keys and no previous binding opens Quick Add, which retains the official API website link.
- **Keyboard access:** The display has no platform buttons underneath. Focus the scene, use left/right arrows to select a charm, and press Space or Return to activate it. VoiceOver offers the same provider actions.
- **Choose your charms:** Click the metal clasp or **Customize (定制)** to select and reorder **0–8 charms** from the 61 presets and your saved custom providers. Save an empty selection to keep only the clasp. Cancel leaves your saved setup unchanged. **Restore Automatic Selection (恢复自动选择)** follows the first three providers in your saved Home order; an empty vault shows OpenAI, Claude, and Gemini. Save to apply this choice. Missing custom providers are marked unavailable in the editor and omitted from the scene until you remove or replace them.
- **Drag and reset:** A movement of 6 points or more counts as a drag, even if you move back to the starting point, so releasing it does not copy a key. **Reset (复位)** restores the initial pose; **Collapse / Expand (收起 / 展开)** remembers your preference. Reduce Motion disables inertial motion, and Reduce Transparency uses opaque materials. Continuous rendering stops when the scene settles, is collapsed, leaves Home, or locks.
- **Encrypted configuration:** Charm bindings, order, colors, custom-provider references, and Home card order are encrypted with the vault and included in backups, not saved as plaintext preferences. The SceneKit component receives only display metadata; it holds no secret values and makes no network requests. The app checks the current unlocked record before copying. A charm is not a provider connection-status indicator.
- **Copy from Home:** Provider cards fit their content in a compact layout, reducing empty space between cards. Each key has its own Copy button. A card still shows up to two keys directly; use **View All (查看全部)** to explicitly choose from additional keys. Account labels, environments, and API hostnames help distinguish personal accounts, team accounts, and custom gateways.
- **Arrange Home:** Choose **Edit Layout (编辑布局)** to drag cards in place, or use their previous/next buttons with the keyboard. Editing shows all providers and temporarily disables search and filters. **Done (完成)** saves the order; Cancel discards the draft. Restoring the default also requires Done. The order applies to provider cards, not keys inside a card; new, unlisted providers follow in default order.
- **Home filters and search:** Search stays at the top right, alongside the compact header. Filter by **All / Models / Skills & Services / Favorites (全部 / 模型 / Skill 与服务 / 常用)**. Home searches provider names and aliases, key names, account labels, environments, tags, and associated tool names. It does not search secrets, URLs, or notes. The management view retains broader metadata search, including URLs and notes.
- **Large catalogs:** Home initially shows up to 80 matching providers. Use **Show more providers (显示更多平台)** below the cards to expand the list. Search always covers the full vault; changing the query or scope returns to the top of the results.
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

Common shortcuts: `⌘1` opens Home, `⌘2` opens All Keys in the management view, `⌘F` focuses Home search, `⌘N` adds a key, `⇧⌘N` adds a tool, and `⇧⌘L` locks the vault. `⇧⌘C` copies the selected key and `⌘E` edits it; these require a selected record in the management view. Home does not select a key automatically. See the [macOS guide](../macos/README.md) for complete usage and build instructions.

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

Names, keys, tags, notes, quota snapshots, charm bindings, and Home order are encrypted together with **AES-256-GCM**. The encryption key is derived from the master password using **PBKDF2-HMAC-SHA256**, with **600,000 iterations** and a **32-byte random salt**. Each write uses a fresh random nonce. MD5 is not used. The regular app does not persist your chosen master password. It does not initiate cloud synchronization, automatically read credentials from other tools, or modify CLI, MCP, or Skills configuration.

Touch ID protects access to the vault through Secure Enclave access control tied to the currently enrolled fingerprints. Only a hardware-bound private-key representation and encrypted, wrapped unlock material are stored locally; failed authentication cannot decrypt the vault. See the [Touch ID implementation and verification notes](../research/touch-id-0.6.md).

Version 0.11.0 writes **payload version 5** and reads versions **1–4**, preserving records, associations, and existing charms. The new fields store optional credential bindings and Home order. Old vaults do not receive an invented key binding or manual order; explicitly saved empty lists remain distinct from automatic settings. The encrypted outer envelope remains version 1, with unchanged AES-256-GCM and password derivation. The demo catalog revision stays **7**, so this format upgrade does not repopulate deleted demo samples.

Before saving an older payload for the first time, Keynest preserves its original encrypted bytes as **`vault-before-0.11.keynest`** in the same directory, including when a password change triggers the first write. Existing 0.5, 0.7, and 0.10 upgrade backups are never overwritten. If preservation fails, the upgrade is not saved and the password session does not change. Version 0.10 and earlier cannot read payload version 5; downgrading requires the pre-upgrade backup and its password. The historical 0.7 tool-template identifiers and 0.10 charm configuration remain supported. See [upgrades and compatibility](../macos/README.md#升级与兼容性).

Restoring a backup also restores charm bindings and Home order. When merging, each explicitly saved local setting takes priority, including empty lists; an automatic setting can adopt the imported one. Conflicting record IDs and their imported references are remapped. A missing reference never binds to an unrelated local key merely because its ID matches.

Version 0.8.1 fixes imports committing after cancellation, clipboard ownership races, hard-link file permission handling, malformed URLs, a crash involving certain slices of unlock data, and inconsistencies between in-memory state and encrypted files after disk synchronization failures. Inactivity locking now uses a monotonic clock, and both apps enable Hardened Runtime. Existing passwords remain usable; newly created or changed passwords also have a maximum UTF-8 size of 16 KiB. See the [security review and fixes](../research/security-review-0.8.1.md).

**This is an experimental app without an independent security audit.** Encryption at rest cannot protect against malware that already controls your Mac, reading memory while the vault is unlocked, screenshots, or third-party clipboard history. System backup software may still back up encrypted files. See the [macOS security boundaries](../macos/README.md#安全边界) for the mechanisms and limitations.

## App icon styles

The current selection is **C2, “Translucent Ice Blue”**: the keyring shape from option C with the light ice-blue palette explored in option F. [View the current icon](../macos/Resources/design/options-c-palette/C2.png).

All **12 styles**, their generation scripts, PNG and ICNS files, and small-size previews are retained for further adjustments:

- [A–D: four shape directions](../macos/Resources/design/options/Keynest-icon-options.png)
- [E–H: light AI-key designs](../macos/Resources/design/options-light-ai/Keynest-light-ai-options.png)
- [C1–C4: light keyring palettes](../macos/Resources/design/options-c-palette/Keynest-C-palette-options.png)

The build reads [AppIcon.selection](../macos/Resources/AppIcon.selection) to choose a style. Change its identifier and rebuild to switch icons without deleting the other candidates. See the [icon library](../macos/Resources/design/README.md) for the full index and instructions.

## Development and references

- [Native app build, backup, and development guide](../macos/README.md)
- [macOS design references](../research/macos-design-references.md)
- [Existing projects and quota API research](../research/2026-09-22-landscape.md)
- [0.5 product direction and tradeoffs](../research/product-direction-0.5.md)
- [0.7 API presets and official sources](../research/api-catalog-0.7.md)
- [Skill / Agent tool templates and sources](../research/skill-agent-templates-0.7.md)
- [0.8 Home and Quick Add](../research/home-usability-0.8.md)
- [0.8.1 security review and fixes](../research/security-review-0.8.1.md)
- [Native app verification record](../macos/verification.md)

The native source is in `macos/`, using Apple's SwiftUI, AppKit, and SceneKit frameworks with no third-party Swift Package dependencies. You can check, build, and package it with the macOS Command Line Tools; a full Xcode installation is not required. Installing the app or making a normal source build does not require Blender. Developers use Blender only to regenerate the committed [3D assets](../macos/Resources/KeychainArt/README.md).

```sh
git clone https://github.com/kody1126/Keynest.git
cd Keynest/macos
bash scripts/run-checks.sh
bash scripts/run-app-checks.sh
bash scripts/run-keychain-checks.sh
bash scripts/run-keychain-drag-checks.sh
bash scripts/run-keychain-attachment-checks.sh
bash scripts/run-keychain-catalog-checks.sh
bash scripts/run-keychain-asset-checks.sh
zsh scripts/build-app.sh
zsh scripts/build-demo-app.sh
zsh scripts/package-app.sh
zsh scripts/install-apps.sh
```

Intermediate app bundles live only in `macos/dist/apps.noindex/`. Do not run them directly from the build directory or disk image. The installer places both apps in `~/Applications`. Before replacing an app, it checks its identity and signature, archives the old app in a verified ZIP under `.build/app-backups/`, and attempts rollback if installation fails. Installation does not launch either app, access a vault, or change system indexing settings.

The packaging script builds both apps, creates the DMG, verifies the disk image, and writes a SHA-256 checksum file. The [verification record](../macos/verification.md) is the reference for completed checks, builds, and hands-on app verification for each release.

The keyring checks run without windows: `run-keychain-checks.sh` exercises motion, click-versus-drag boundaries, and mesh validation without creating a renderer. `run-keychain-drag-checks.sh` checks off-center grips, chain links, and bounded rotation/extension by projecting solved poses back to the pointer. `run-keychain-catalog-checks.sh` uses fictional in-memory entries to check platform selection, ordering, automatic defaults, empty lists, and unavailable references. Visual quality and real window lifecycle behavior still require hands-on verification.

`run-keychain-attachment-checks.sh` checks real brand meshes and synthetic shapes to ensure both ends of each attachment rod sit inside solid geometry, rather than relying only on a bounding box. It opens no windows or vaults.

## Archived web experiment

The Node.js / web implementation at the repository root is retained as the early **0.1 technical experiment**. Its data location, encryption format, and features differ from those of the native app. The native app is the main entry point.

To revisit the web experiment, use Node.js 22 or later, run `npm start` from the repository root, and open the local URL printed in the terminal. By default, it saves data to `.data/vault.json` inside the project. Set `API_VAULT_DATA_DIR` to use another directory. Run its tests with `npm test`.

The native app does not automatically import, overwrite, or delete the web experiment's `.data` directory. Their encrypted backup formats are incompatible; keep their backups separately.

## License and contributions

Original project code is available under the [MIT License](../LICENSE). Third-party brand artwork retains its own licenses and trademark rights; the project license grants no additional rights to those assets. See [third-party notices](../THIRD_PARTY_NOTICES.md).

Report usage problems through [Issues](https://github.com/kody1126/Keynest/issues), or follow the [contribution guide](../CONTRIBUTING.md) to submit changes. Report vulnerabilities privately using the [security policy](../SECURITY.md); never submit real credentials or vaults.

Future project updates are committed and pushed to GitHub after verification, with both READMEs maintained together. See [AGENTS.md](../AGENTS.md) for the collaboration rules. This is not a background upload mechanism: personal vaults, test runtime data and build outputs stay out of the source repository.
