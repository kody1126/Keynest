# 第三方声明 / Third-party notices

根目录 [MIT LICENSE](LICENSE) 适用于 Keynest 的原创代码与原创文档。它不重新授权第三方图标、商标或上游许可文本。服务和产品图标仅用于在目录中识别相应服务，不表示合作、推荐或获得品牌授权。

The root [MIT LICENSE](LICENSE) covers Keynest's original code and original documentation. It does not relicense third-party artwork, trademarks or upstream license texts. Service and product icons identify entries in the catalog and do not imply affiliation, endorsement or permission from the brand owner.

## 资源与许可证 / Assets and licenses

| Collection | Source records | Applicable notice |
| --- | --- | --- |
| Original provider icons | [Original sources](macos/Resources/ProviderIcons/SOURCES.md) | [LobeHub MIT](macos/Resources/ProviderIcons/LICENSE); OpenRouter is separately identified in the source record |
| Additional provider icons | [0.7 sources](macos/Resources/ProviderIcons/SOURCES-0.7.md) | [LobeHub MIT](macos/Resources/ProviderIcons/LICENSE-LOBEHUB-0.7.txt), [Simple Icons CC0](macos/Resources/ProviderIcons/LICENSE-SIMPLEICONS.md), or vendor notices below, as indicated per file |
| Tool icons | [Tool sources](macos/Resources/ToolIcons/SOURCES.md) | [LobeHub MIT](macos/Resources/ToolIcons/LICENSE-LOBEHUB.txt), [Flowise Apache-2.0 portion](macos/Resources/ToolIcons/LICENSE-FLOWISE.md), or vendor notices below, as indicated per file |

官网图标中没有单独开源授权声明的资源：

Vendor-sourced artwork for which no separate open-source grant is asserted:

- Provider icons: `cartesia`, `serper`, `amap`, `openweather`, `sendgrid`, `slack`, `dingtalk`, `twilio`, `apify`, `browserbase`, `parallel`, `context7`, `composio`, `mem0`, `pinecone`, `weaviate`, `zep`, `feishu`. See [provider vendor notice](macos/Resources/ProviderIcons/LICENSE-VENDOR-ASSETS.md).
- Tool icons: `continue`, `anythingllm`. See [tool vendor notice](macos/Resources/ToolIcons/LICENSE-VENDOR-ASSETS.md).
- The original `openrouter` icon follows its [official brand source record](macos/Resources/ProviderIcons/SOURCES.md); it is not relabeled as LobeHub MIT artwork.

这些资源不在项目 MIT 授权范围内。来源记录或公开可下载性本身不构成额外的开源授权；重新分发者应遵守各品牌的适用条款及商标权利，不应假定整套品牌资源都可按 MIT 任意再利用。

These assets are outside the project's MIT grant. Attribution or public download availability does not itself create an additional open-source license. Redistributors must respect the applicable brand terms and trademark rights and must not assume the entire artwork collection can be freely reused under MIT.

Flowise 图标来自公开 UI 目录，不包含企业版代码；保留原仓库许可证，其中也说明企业版内容的独立许可。处理过程包括等比缩放、透明画布排版和必要的 SVG 转 PNG；源 URL、固定提交和校验和详见 [资源清单](macos/scripts/brand-icon-manifest.json)。

The Flowise icon comes from the public UI directory; no enterprise code is included. Its upstream license text is retained, including the separate terms for enterprise content. Processing consists of proportional resizing, transparent-canvas placement and SVG-to-PNG conversion where needed. Source URLs, pinned revisions and checksums are recorded in the [asset manifest](macos/scripts/brand-icon-manifest.json).

## 系统框架 / System frameworks

原生 App 调用 Apple 系统框架（SwiftUI、AppKit、CryptoKit、Security、CommonCrypto），不在本仓库分发这些框架。历史 Web 实验使用 Node.js 内置模块，没有第三方运行依赖。

The native app uses Apple system frameworks (SwiftUI, AppKit, CryptoKit, Security and CommonCrypto); these frameworks are not redistributed in this repository. The legacy Web experiment uses Node.js built-in modules without third-party runtime dependencies.
