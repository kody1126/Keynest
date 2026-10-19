# Product screenshots

The Chinese and English READMEs use the same eight original PNG window captures, taken on 2026-10-20 from the regular **Keynest 0.11.1** application. They show the interface in the public download, not the unverified 0.12 source candidate. Images are linked to their full-resolution originals in both READMEs.

| File | What it shows |
| --- | --- |
| `keyring.png` | Home with five brand charms: OpenAI, Claude, DeepSeek, Gemini and Cloudflare |
| `home.png` | Compact provider cards, multiple keys, search, filters and copy actions; keyring collapsed |
| `key-details.png` | Two OpenAI credentials distinguished by account and environment, with masked secret and linked tools |
| `providers.png` | The 61-provider picker, showing model presets and use-case categories |
| `tool-templates.png` | Client and coding-tool templates, with brand icons and credential requirements |
| `agent-templates.png` | Agent and workflow templates, including OpenClaw, Dify, n8n and LangGraph |
| `keyring-customize.png` | Charm order and the specific credential copied by each charm |
| `home-layout.png` | The released Home layout editor, including complete cards and save/cancel/default controls |

## Capture boundaries

- The capture session used a temporary copy of the regular 0.11.1 app executable and its bundled artwork. Only the temporary copy's bundle identity and test-data-directory setting were changed to isolate the session; production views and rendering code were unchanged.
- An isolated temporary vault was generated from the repository's public fictional fixtures. Display names were changed to ordinary project/account labels. All credential values remained invalid sample values, concealed in the UI. No existing vault, real account, credential file or biometric enrollment was read or used.
- Touch ID enrollment and all quota requests were left off. No provider API was contacted, and no biometric-success or balance result was fabricated.
- Images were captured through the native window screenshot API, with no generated UI, painted-over labels or composited feature elements. The regular app naturally has no development-vault banner.
- Capture-only app copies and vaults are not release assets and must never be committed. Public downloads still contain only `Keynest.app`.
- Brand artwork is the artwork already bundled with Keynest; see [third-party notices](../../THIRD_PARTY_NOTICES.md).

For future refreshes, use the current public app with an explicitly isolated test directory. Keep credentials concealed, capture only the relevant window, inspect every image, and update both READMEs together. Do not present candidate-only features as available in the current download. Development fixtures and their setup remain documented in the [developer guide](../../macos/README.md#独立演示版).

## Historical captures

The older `home.jpg`, `home-layout.jpg` and `tool-templates.jpg` are retained for historical verification records. They are no longer embedded in either product README.

## Presentation references

The gallery structure was reviewed against [Ice](https://github.com/jordanbaird/Ice), [MonitorControl](https://github.com/MonitorControl/MonitorControl), [Stats](https://github.com/exelban/stats), and [AltTab](https://github.com/lwouis/alt-tab-macos): a prominent product view, task-specific screenshots, and compact paired detail views. All screenshots here are of Keynest itself.
