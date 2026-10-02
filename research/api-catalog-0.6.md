# Keynest 0.6 · 常用 API 本地目录

核对日期：2026-09-29。共 47 个预设：模型与推理 18、图像与语音 8、搜索与采集 6、开发与数据 8、消息与协作 7。按用途浏览，不按国家划分。

目录是收藏表单的本地模板，不是可用账户、API 测试器、模型版本清单或计费承诺。选择模板只填入名称、官方 API 入口、地址和用途提示；不发送密钥、不调用模型、不启用额度查询。模型名、权限、区域、余额和价格由平台持续调整，使用时以自己的 API 项目和官方文档为准。

## 地址与凭据的边界

- `website` 是官方 API 产品页或开发文档，用户手动打开；`baseURL` 是可编辑的请求地址。二者分开保存。
- Supabase 地址由项目决定，因此留空。Serper 的公开页面本轮未提供可核验端点，亦留空并提示从官方 Playground 复制；没有根据第三方教程猜填。
- “官方默认地址”不代表适用于所有地域、专属部署、Coding Plan 或 SDK。用途提示注明这些差别；不在地址里嵌入密钥、访问令牌或查询参数。
- 飞书、钉钉和 Twilio 等平台可能需要多项凭据或令牌交换。Keynest 只收藏输入的秘密，不自动获取、刷新或交换令牌。
- 原有 12 个平台 ID、名称、默认地址及品牌 PNG 保持兼容。新增 35 项使用离线 SF Symbols 功能图标，没有 CDN、抓取 favicon 或运行时图标下载。

## 官方来源与表单默认值

以下为官方页面内容归纳及本项目据此选择的默认值。不是已完成鉴权请求的结果；本轮未使用任何真实 API 密钥。GLM 的原始 Markdown 直读失败，其旧值另由官方 API 搜索结果交叉确认；Serper 的端点未核验，明确留空。

### 模型与推理

| ID / 平台 | 官方 API 入口 | 请求地址默认值 | 官方证据与适用范围 |
| --- | --- | --- | --- |
| `openai` · ChatGPT / OpenAI | [API 官网](https://openai.com/api/) | `https://api.openai.com/v1` | [文档](https://developers.openai.com/api/docs/quickstart)：请求示例使用 /v1/responses；普通 API 与 ChatGPT 订阅分开。 |
| `anthropic` · Claude / Anthropic | [API 官网](https://claude.com/platform/api) | `https://api.anthropic.com` | [文档](https://platform.claude.com/docs/en/api/overview)：API overview 给出 REST origin；请求另有版本头。 |
| `google` · Gemini / Google | [API 官网](https://ai.google.dev/gemini-api) | `https://generativelanguage.googleapis.com/v1beta` | [文档](https://ai.google.dev/api)：原生 generateContent 示例使用 v1beta；不是兼容接口。 |
| `deepseek` · DeepSeek | [API 官网](https://api-docs.deepseek.com) | `https://api.deepseek.com` | [文档](https://api-docs.deepseek.com/guides/harness)：First API Call 表列出 OpenAI 兼容 base_url。 |
| `qwen` · 通义千问 / Qwen | [API 官网](https://www.aliyun.com/product/bailian) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | [文档](https://help.aliyun.com/en/model-studio/base-url)：官方区分地域、工作空间和 Coding Plan；这里只预填北京共享兼容地址。 |
| `kimi` · Kimi / Moonshot | [API 官网](https://platform.kimi.com) | `https://api.moonshot.cn/v1` | [文档](https://platform.kimi.com/docs/api/balance)：官方余额示例使用 api.moonshot.cn/v1。这里不实现 Kimi 余额请求。 |
| `doubao` · 豆包 / Doubao | [API 官网](https://www.volcengine.com/product/ark) | `https://ark.cn-beijing.volces.com/api/v3` | [文档](https://docs.volcengine.com/docs/ark/base-url-and-authentication?lang=en)：官方数据面地址与 Coding Plan 分开。 |
| `glm` · 智谱 / GLM | [API 官网](https://bigmodel.cn) | `https://open.bigmodel.cn/api/paas/v4` | [文档](https://docs.bigmodel.cn/cn/guide/develop/openai/introduction.md)：保留 0.4 核对的标准接口；本轮官方 API 搜索结果仍显示 /api/paas/v4。Markdown 直读暂失败。 |
| `minimax` · MiniMax | [API 官网](https://platform.minimax.cn) | `https://api.minimax.cn/v1` | [文档](https://platform.minimax.cn/docs/api-reference/text-openai-api)：OpenAI SDK 文档明确 OPENAI_BASE_URL；其他能力/订阅需另核对。 |
| `xai` · Grok / xAI | [API 官网](https://x.ai/api) | `https://api.x.ai/v1` | [文档](https://docs.x.ai/overview)：官方示例使用 /v1/responses 和相同 SDK base_url。 |
| `siliconflow` · 硅基流动 / SiliconFlow | [API 官网](https://siliconflow.cn) | `https://api.siliconflow.cn/v1` | [文档](https://docs.siliconflow.cn/docs/userguide/quickstart)：Quickstart 给出兼容 base_url。 |
| `openrouter` · OpenRouter | [API 官网](https://openrouter.ai) | `https://openrouter.ai/api/v1` | [文档](https://openrouter.ai/docs/quickstart)：Quickstart 示例使用 /api/v1/chat/completions。 |
| `mistral` · Mistral AI | [API 官网](https://docs.mistral.ai/api) | `https://api.mistral.ai/v1` | [文档](https://docs.mistral.ai/api)：Chat Completion 示例使用 api.mistral.ai/v1。 |
| `groq` · Groq | [API 官网](https://console.groq.com/docs/overview) | `https://api.groq.com/openai/v1` | [文档](https://console.groq.com/docs/openai)：OpenAI Compatibility 给出 /openai/v1。 |
| `together` · Together AI | [API 官网](https://docs.together.ai/docs/inference/openai-compatibility) | `https://api.together.ai/v1` | [文档](https://docs.together.ai/docs/inference/openai-compatibility)：当前官方示例使用 api.together.ai/v1，不沿用旧 .xyz 主机。 |
| `cohere` · Cohere | [API 官网](https://docs.cohere.com/reference/chat) | `https://api.cohere.com/v2` | [文档](https://docs.cohere.com/reference/chat)：Chat reference 为 /v2/chat；官方音频 quickstart 同样确认 api.cohere.com/v2 主机与版本。 |
| `deepinfra` · DeepInfra | [API 官网](https://docs.deepinfra.com/chat/overview) | `https://api.deepinfra.com/v1/openai` | [文档](https://docs.deepinfra.com/chat/overview)：Chat overview 给出 /v1/openai；原生推理路径另有定义。 |
| `huggingface` · Hugging Face | [API 官网](https://huggingface.co/docs/inference-providers/index) | `https://router.huggingface.co/v1` | [文档](https://huggingface.co/docs/inference-providers/index)：聊天兼容路由为 router.huggingface.co/v1；其他任务不共用这个路径。 |

### 图像与语音

| ID / 平台 | 官方 API 入口 | 请求地址默认值 | 官方证据与适用范围 |
| --- | --- | --- | --- |
| `replicate` · Replicate | [API 官网](https://replicate.com/docs/reference/http) | `https://api.replicate.com/v1` | [文档](https://replicate.com/docs/reference/http)：HTTP API 示例使用 /v1/predictions；模型和部署另有路径。 |
| `fal` · fal.ai | [API 官网](https://fal.ai/docs/documentation/model-apis/inference/queue) | `https://queue.fal.run` | [文档](https://fal.ai/docs/documentation/model-apis/inference/queue)：队列 curl 明确 queue.fal.run；同步、流式端点不同。 |
| `stability` · Stability AI | [API 官网](https://platform.stability.ai/docs/api-reference) | `https://api.stability.ai/v2beta` | [文档](https://platform.stability.ai/docs/api-reference)：Stable Image 示例使用 /v2beta/stable-image。 |
| `runway` · Runway | [API 官网](https://docs.dev.runwayml.com/guides/using-the-api/) | `https://api.dev.runwayml.com/v1` | [文档](https://docs.dev.runwayml.com/guides/using-the-api/)：示例使用 api.dev.runwayml.com/v1；仍需版本头。 |
| `elevenlabs` · ElevenLabs | [API 官网](https://elevenlabs.io/docs/api-reference/text-to-speech/convert) | `https://api.elevenlabs.io/v1` | [文档](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)：语音接口为 /v1/text-to-speech/:voice_id。 |
| `deepgram` · Deepgram | [API 官网](https://developers.deepgram.com/reference/speech-to-text/listen-pre-recorded) | `https://api.deepgram.com/v1` | [文档](https://developers.deepgram.com/reference/speech-to-text/listen-pre-recorded)：预录语音识别为 /v1/listen；实时转录另走 WebSocket。 |
| `assemblyai` · AssemblyAI | [API 官网](https://www.assemblyai.com/docs) | `https://api.assemblyai.com/v2` | [文档](https://www.assemblyai.com/docs/guides/timestamped-transcripts)：转录示例使用 api.assemblyai.com/v2/transcript。 |
| `cartesia` · Cartesia | [API 官网](https://docs.cartesia.ai/api-reference/tts/bytes) | `https://api.cartesia.ai` | [文档](https://docs.cartesia.ai/api-reference/tts/bytes)：TTS Bytes 的主机为 api.cartesia.ai，路径 /tts/bytes。 |

### 搜索与采集

| ID / 平台 | 官方 API 入口 | 请求地址默认值 | 官方证据与适用范围 |
| --- | --- | --- | --- |
| `tavily` · Tavily | [API 官网](https://docs.tavily.com/documentation/api-reference/endpoint/search) | `https://api.tavily.com` | [文档](https://docs.tavily.com/documentation/api-reference/endpoint/search)：搜索 curl 使用 api.tavily.com/search。 |
| `exa` · Exa | [API 官网](https://exa.ai/docs/reference/search) | `https://api.exa.ai` | [文档](https://exa.ai/docs/reference/search)：Search reference 给出 api.exa.ai/search。 |
| `brave` · Brave Search | [API 官网](https://api-dashboard.search.brave.com/app/documentation/web-search) | `https://api.search.brave.com/res/v1` | [文档](https://api-dashboard.search.brave.com/app/documentation/web-search)：Web Search 示例使用 /res/v1/web/search。 |
| `firecrawl` · Firecrawl | [API 官网](https://docs.firecrawl.dev/api-reference/endpoint/scrape) | `https://api.firecrawl.dev/v2` | [文档](https://docs.firecrawl.dev/api-reference/endpoint/scrape)：当前 Scrape 示例使用 /v2/scrape。 |
| `jina` · Jina Reader | [API 官网](https://jina.ai/reader/) | `https://r.jina.ai` | [文档](https://jina.ai/reader/)：Reader 是 r.jina.ai URL 前缀；搜索及向量接口是其他地址。 |
| `serper` · Serper | [API 官网](https://serper.dev/) | **留空** | [文档](https://serper.dev/)：官方公开主页确认产品；Playground 为动态界面，本轮未取得公开端点证据，因此地址留空。 |

### 开发与数据

| ID / 平台 | 官方 API 入口 | 请求地址默认值 | 官方证据与适用范围 |
| --- | --- | --- | --- |
| `github` · GitHub | [API 官网](https://docs.github.com/en/rest) | `https://api.github.com` | [文档](https://docs.github.com/en/rest/using-the-rest-api/getting-started-with-the-rest-api)：官方教程明确 GitHub.com REST base URL；Enterprise 可用不同主机。 |
| `supabase` · Supabase | [API 官网](https://supabase.com/docs/guides/api) | **留空** | [文档](https://supabase.com/docs/guides/api)：每个项目具有独立 project_ref 子域；不把模板域名当成可用地址。 |
| `cloudflare` · Cloudflare | [API 官网](https://developers.cloudflare.com/api/) | `https://api.cloudflare.com/client/v4` | [文档](https://developers.cloudflare.com/fundamentals/api/how-to/make-api-calls/)：官方明确 v4 HTTPS 稳定基地址；不是 Workers/R2 的项目地址。 |
| `sentry` · Sentry | [API 官网](https://docs.sentry.io/api/) | `https://sentry.io/api/0` | [文档](https://docs.sentry.io/api/requests/)：请求必须使用 /api/0 前缀；地域和自建实例可改主机。 |
| `stripe` · Stripe | [API 官网](https://docs.stripe.com/api) | `https://api.stripe.com/v1` | [文档](https://docs.stripe.com/api)：文档给出 api.stripe.com；v1 操作示例确认版本路径，测试/正式密钥必须分辨。 |
| `mapbox` · Mapbox | [API 官网](https://docs.mapbox.com/api/overview/) | `https://api.mapbox.com` | [文档](https://docs.mapbox.com/api/overview/)：官方明确统一主机；产品各有路径和版本。 |
| `amap` · 高德地图 / AMap | [API 官网](https://lbs.amap.com/api/webservice/summary) | `https://restapi.amap.com/v3` | [文档](https://lbs.amap.com/api/webservice/guide/api/search/)：POI 文档给出 /v3/place/text；部分路线服务为 v5。 |
| `openweather` · OpenWeather | [API 官网](https://openweathermap.org/api) | `https://api.openweathermap.org/data/2.5` | [文档](https://openweathermap.org/current)：Current Weather 给出 /data/2.5/weather；One Call 不同。 |

### 消息与协作

| ID / 平台 | 官方 API 入口 | 请求地址默认值 | 官方证据与适用范围 |
| --- | --- | --- | --- |
| `resend` · Resend | [API 官网](https://resend.com/docs/api-reference/introduction) | `https://api.resend.com` | [文档](https://resend.com/docs/api-reference/introduction)：Introduction 明确 HTTPS base URL。 |
| `sendgrid` · SendGrid | [API 官网](https://www.twilio.com/docs/sendgrid/api-reference/how-to-use-the-sendgrid-v3-api/requests) | `https://api.sendgrid.com/v3` | [文档](https://www.twilio.com/docs/sendgrid/api-reference/how-to-use-the-sendgrid-v3-api/requests)：官方给出全局与 EU 两套 v3 主机；只预填全局。 |
| `notion` · Notion | [API 官网](https://developers.notion.com/reference/intro) | `https://api.notion.com/v1` | [文档](https://developers.notion.com/reference/intro)：Introduction 展示 api.notion.com/v1，并要求相应版本头。 |
| `slack` · Slack | [API 官网](https://docs.slack.dev/apis/web-api/) | `https://slack.com/api` | [文档](https://docs.slack.dev/apis/web-api/)：Web API 方法形如 slack.com/api/METHOD_FAMILY.method。 |
| `feishu` · 飞书 / Feishu | [API 官网](https://open.feishu.cn/document/) | `https://open.feishu.cn/open-apis` | [文档](https://open.feishu.cn/document/hire-v1/get-candidates/import-external-system-information/import-external-interview-info/update)：服务端示例使用 /open-apis；App Secret 与 tenant_access_token 不能混用。 |
| `dingtalk` · 钉钉 / DingTalk | [API 官网](https://open.dingtalk.com/document/) | `https://api.dingtalk.com/v1.0` | [文档](https://help.aliyun.com/zh/pds/drive-and-photo-service-dev/user-guide/access-process-for-dingtalk-app)：阿里云官方钉钉应用示例使用 api.dingtalk.com/v1.0；旧 oapi 与 Webhook 分开。 |
| `twilio` · Twilio | [API 官网](https://www.twilio.com/docs/iam/api) | `https://api.twilio.com/2010-04-01` | [文档](https://www.twilio.com/docs/iam/api)：官方 basics 给出 /2010-04-01；认证须 SID 与 Secret 配对。 |

补充端点证据：[Cohere v2 主机](https://docs.cohere.com/docs/audio-transcription-quickstart)、[Stripe v1 请求示例](https://docs.stripe.com/api/charges/create)、[GLM 官方 API 示例](https://docs.bigmodel.cn/api-reference/%E5%8A%A9%E7%90%86-api/%E5%8A%A9%E6%89%8B%E5%88%97%E8%A1%A8)。这些链接用于确认主机/路径，不推荐其中已经弃用的具体操作。

## 实现规则与验证范围

- `ProviderPresetGroup` 只用于浏览。持久化的 `EntryCategory` 仍是 `.ai/.skill/.service/.other`，不新增数据库类别。
- 只有内容全空、仍使用默认 `.ai` 的新草稿采用建议类别：模型和媒体为 AI，其余为开发服务。已填写内容或已自行选类别的草稿保持原类别。
- 换预设仅更新空字段和仍等于上一个预设默认值的名称/网址；保留秘密、备注、标签、工具关联、账号、环境、星标、ID 和时间。换到不同平台时清除旧额度配置与快照；重新选择同一平台保留用户已明确设置的额度选项。
- 名称和已知别名仅作精确平台识别，不从秘密格式或含品牌名的中转地址推断官方服务。目录搜索支持名称、别名、用途和功能分组，不搜索密钥。
- 原 12 个品牌图标的来源、许可证和校验值在 [ProviderIcons/SOURCES.md](../macos/Resources/ProviderIcons/SOURCES.md)。新功能图标使用系统 SF Symbols，不冒充品牌标志。
- 本轮测试覆盖目录完整性、别名无冲突、HTTPS/无令牌地址、离线图标、项目地址留空、用途搜索、分类建议边界以及换预设时用户数据和额度行为。最终运行数字及 App 实机验证由 [verification.md](../macos/verification.md) 记录。
