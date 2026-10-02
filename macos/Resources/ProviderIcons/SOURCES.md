# Provider preset and icon sources

**Current 0.7 coverage: 61 actual provider brand PNGs.** See [SOURCES-0.7.md](SOURCES-0.7.md) for all added sources, licenses and checks. The 12 original PNGs below remain byte-for-byte unchanged; later sections describe the historical 0.4/0.6 catalogue.

Verified on 2026-09-23. These assets are bundled with Keynest and loaded locally. The app does not contact an icon CDN, inspect a credential to choose a provider, or enable quota synchronization when applying a preset. Existing entries keep their free-form provider and URL fields.

## Public API websites

Version 0.4 removes country categories and country search terms. The catalog uses a single common-use order: ChatGPT, Claude, Gemini, DeepSeek, Qwen, Kimi, Doubao, GLM, MiniMax, Grok, SiliconFlow and OpenRouter. Provider IDs, names, aliases and icons stay compatible with version 0.3.

The `website` field points to a public API product or developer-platform entrance. It is independent of `baseURL`, which is the actual API request endpoint. Presets no longer point directly to key-management or login pages. Existing saved website values are not migrated.

| Preset | Stored API website | Verification on 2026-09-23 |
| --- | --- | --- |
| ChatGPT / OpenAI | [OpenAI API Platform](https://openai.com/api/) | Public API product page with models, API capabilities and a separate Start building link. |
| Claude / Anthropic | [Claude Platform](https://claude.com/platform/api) | Public developer-platform product page; the Console is a separate link. |
| Gemini / Google | [Gemini API](https://ai.google.dev/gemini-api) | Official public API developer entrance; redirects to `/gemini-api/docs`. |
| DeepSeek | [DeepSeek API](https://api-docs.deepseek.com) | Public official API home with a first-request guide, pricing and separate platform access. Selected instead of the platform login experience. |
| 通义千问 / Qwen | [Alibaba Cloud Model Studio](https://www.aliyun.com/product/bailian) | Public 百炼 product page describing model inference and API access; the console is a separate link. The site may select its `cn.aliyun.com` locale. |
| Kimi / Moonshot | [Kimi API Open Platform](https://platform.kimi.com) | Public model-service landing page with model information, API pricing and a Start building link. |
| 豆包 / Doubao | [Volcengine Ark](https://www.volcengine.com/product/ark) | Official Ark product URL, served as a JavaScript application. This replaces the Beijing API-key console route. |
| 智谱 / GLM | [BigModel Platform](https://bigmodel.cn) | Official BigModel platform root, served as a JavaScript application. This replaces the specific key-management route. |
| MiniMax | [MiniMax Open Platform](https://platform.minimax.cn) | Public platform entrance; currently redirects to the model/API documentation overview. |
| Grok / xAI | [Grok API](https://x.ai/api) | Public API product page describing Grok models, API keys and pricing. |
| 硅基流动 / SiliconFlow | [SiliconFlow](https://siliconflow.cn) | Public product site explicitly describing ready-to-use model APIs; model catalog, pricing and docs are accessible from the page. |
| OpenRouter | [OpenRouter](https://openrouter.ai) | Public API platform landing page with model catalog and developer documentation. |

## API request defaults

These are editable form defaults for ordinary API access. ChatGPT, Claude, Gemini and other consumer subscriptions are distinct from API access. Regional keys and Coding/Token Plan keys can require different endpoints. Selecting a brand alone cannot determine the user's region or billing plan.

| Preset | Base URL | Official endpoint evidence |
| --- | --- | --- |
| ChatGPT / OpenAI | `https://api.openai.com/v1` | [OpenAI quickstart](https://developers.openai.com/api/docs/quickstart) shows `/v1/responses`. |
| Claude / Anthropic | `https://api.anthropic.com` | [Claude API overview](https://platform.claude.com/docs/en/api/overview) identifies the REST origin. |
| Gemini / Google | `https://generativelanguage.googleapis.com/v1beta` | [Native API reference](https://ai.google.dev/api). Uses the native Gemini path, not the separate OpenAI compatibility path. |
| DeepSeek | `https://api.deepseek.com` | [First API call](https://api-docs.deepseek.com/) gives this OpenAI-compatible base URL. |
| 通义千问 / Qwen | `https://dashscope.aliyuncs.com/compatible-mode/v1` | [Model Studio base URLs](https://help.aliyun.com/en/model-studio/base-url): Beijing shared endpoint for ordinary model access; workspace-specific endpoints are also available. |
| Kimi / Moonshot | `https://api.moonshot.cn/v1` | [Kimi balance API](https://platform.kimi.com/docs/api/balance) shows the mainland API origin/path. |
| 豆包 / Doubao | `https://ark.cn-beijing.volces.com/api/v3` | [Ark Chat API](https://docs.volcengine.com/docs/ark/chat-api?lang=zh&redirect=1) shows the Beijing endpoint. This is not the separate Coding Plan endpoint. |
| 智谱 / GLM | `https://open.bigmodel.cn/api/paas/v4` | [Official OpenAI compatibility guide (Markdown)](https://docs.bigmodel.cn/cn/guide/develop/openai/introduction.md), discovered from the [official docs index](https://docs.bigmodel.cn/llms.txt), gives the mainland base URL. This is not the Coding Plan endpoint. |
| MiniMax | `https://api.minimax.cn/v1` | [Current official OpenAI SDK guide](https://platform.minimax.cn/docs/api-reference/text-openai-api) uses this base URL. [API overview](https://platform.minimax.cn/docs/api-reference/api-overview) distinguishes ordinary keys from subscription keys. Old `platform.minimaxi.com` documentation redirects to `platform.minimax.cn`. |
| Grok / xAI | `https://api.x.ai/v1` | [Grok API overview](https://docs.x.ai/overview) shows the base URL. |
| 硅基流动 / SiliconFlow | `https://api.siliconflow.cn/v1` | [Official quickstart](https://docs.siliconflow.cn/docs/userguide/quickstart) gives the China endpoint. |
| OpenRouter | `https://openrouter.ai/api/v1` | [Official quickstart](https://openrouter.ai/docs/quickstart) shows the endpoint. |

## Brand assets

Eleven assets come from [LobeHub's open-source icon repository](https://github.com/lobehub/lobe-icons), pinned to commit [`2e76c48721e91b9aaa40803a0fa2eb8aca7399c4`](https://github.com/lobehub/lobe-icons/tree/2e76c48721e91b9aaa40803a0fa2eb8aca7399c4). The exact upstream MIT license is preserved in `LICENSE`; brand names and marks remain those of their owners. No third-party runtime dependency was added.

| Local filename | Original repository path | Processing |
| --- | --- | --- |
| `openai.png` | `packages/static-png/light/openai.png` | Unmodified upstream PNG, 640 × 640. |
| `anthropic.png` | `packages/static-png/light/claude-color.png` | Unmodified upstream PNG, 640 × 640. |
| `google.png` | `packages/static-png/light/gemini-color.png` | Unmodified upstream PNG, 640 × 640. |
| `xai.png` | `packages/static-png/light/grok.png` | Unmodified upstream PNG, 640 × 640. |
| `deepseek.png` | `packages/static-png/light/deepseek-color.png` | Unmodified upstream PNG, 640 × 640. |
| `qwen.png` | `packages/static-png/light/qwen-color.png` | Unmodified upstream PNG, 640 × 640. |
| `doubao.png` | `packages/static-png/light/doubao-color.png` | Unmodified upstream PNG, 640 × 640. |
| `kimi.png` | `packages/static-avatar/avatars/kimi.webp` | Losslessly converted decoded pixels to PNG, 1280 × 1280. This upstream black background preserves contrast for the white K and blue dot. |
| `glm.png` | `packages/static-png/light/zhipu-color.png` | Unmodified upstream PNG, 640 × 640. |
| `minimax.png` | `packages/static-png/light/minimax-color.png` | Unmodified upstream PNG, 640 × 640. |
| `siliconflow.png` | `packages/static-png/light/siliconcloud-color.png` | Unmodified upstream PNG, 640 × 640. |

`openrouter.png` comes directly from [OpenRouter's official brand asset page](https://openrouter.ai/brand), using the unmodified [Grape glyph PNG for light backgrounds](https://openrouter.ai/brand/logos/transparent/glyph/png/glyph-grape@2x.png), 2048 × 1460. Its terms are the brand page's usage guidance, not the LobeHub MIT license: preserve the mark's proportions and colors. OpenRouter [announced its new geometric OR mark on 2026-07-13](https://openrouter.ai/blog/announcements/brand-refresh/), replacing the earlier routing-arrow logo. The initial LobeHub Volt-colored version was replaced with this official Grape variant for contrast in the app's light icon wells.

All final PNGs were decoded and visually inspected. Their checksums are recorded in `SHA256SUMS`. Kimi conversion was a one-time build-time operation; the app only reads the PNG.

## Version 0.6 catalog expansion

On 2026-09-29 the catalog expanded to 47 presets in five functional groups. The original 12 PNGs and their provenance above remain unchanged. The 35 added presets use native offline SF Symbols, with category or capability symbols rather than fabricated brand logos. Only presets marked `hasBundledIcon` load PNGs; missing assets fall back to a local system symbol. No network icon lookup was added. Current endpoint evidence and scope notes are in [research/api-catalog-0.6.md](../../../research/api-catalog-0.6.md).
