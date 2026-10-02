import Foundation

/// Browse categories only; these do not change the saved vault schema.
public enum ProviderPresetGroup: String, CaseIterable, Identifiable, Sendable {
    case languageModels, media, search, agentTools, development, communication
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .languageModels: return "模型与推理"
        case .media: return "图像与语音"
        case .search: return "搜索与采集"
        case .agentTools: return "Agent 工具"
        case .development: return "开发与数据"
        case .communication: return "消息与协作"
        }
    }
    public var symbol: String {
        switch self {
        case .languageModels: return "sparkles"
        case .media: return "photo.on.rectangle.angled"
        case .search: return "magnifyingglass"
        case .agentTools: return "puzzlepiece.extension"
        case .development: return "terminal"
        case .communication: return "bubble.left.and.bubble.right"
        }
    }
    public var suggestedCategory: EntryCategory {
        switch self {
        case .languageModels, .media: return .ai
        case .agentTools: return .skill
        case .search, .development, .communication: return .service
        }
    }
}

/// Offline form defaults, never credential detection or permission to send a key.
public struct ProviderPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let website: String
    public let baseURL: String
    public let group: ProviderPresetGroup
    public let summary: String
    public let usageHint: String
    public let hasBundledIcon: Bool
    private let symbolOverride: String?
    public let quotaProvider: QuotaProvider = .none

    public var suggestedCategory: EntryCategory { group.suggestedCategory }
    public var fallbackSymbol: String { symbolOverride ?? group.symbol }
    public var iconFilename: String { "\(id).png" }

    private init(id: String, name: String, aliases: [String], website: String,
                 baseURL: String, group: ProviderPresetGroup, summary: String,
                 usageHint: String, hasBundledIcon: Bool = true, symbol: String? = nil) {
        self.id = id; self.name = name; self.aliases = aliases
        self.website = website; self.baseURL = baseURL; self.group = group
        self.summary = summary; self.usageHint = usageHint
        self.hasBundledIcon = hasBundledIcon; self.symbolOverride = symbol
    }

    /// Sources and scope notes: research/api-catalog-0.6.md and api-catalog-0.7.md.
    /// Empty base URLs deliberately require a project or console-specific value.
    public static let all: [ProviderPreset] = [
        .init(id: "openai", name: "ChatGPT / OpenAI", aliases: ["OpenAI", "ChatGPT", "Chat GPT", "Open AI"],
              website: "https://openai.com/api/", baseURL: "https://api.openai.com/v1",
              group: .languageModels, summary: "通用对话、推理与多模态",
              usageHint: "普通 API 密钥与 ChatGPT 订阅分开；地址可按自己的网关修改。", hasBundledIcon: true),
        .init(id: "anthropic", name: "Claude / Anthropic", aliases: ["Claude", "Anthropic", "Anthropic Claude", "克劳德"],
              website: "https://claude.com/platform/api", baseURL: "https://api.anthropic.com",
              group: .languageModels, summary: "对话、代码与 Agent",
              usageHint: "使用 Claude API 密钥；请求还需 anthropic-version 版本头。", hasBundledIcon: true),
        .init(id: "google", name: "Gemini / Google", aliases: ["Gemini", "Google Gemini", "Google", "Google AI Studio", "谷歌"],
              website: "https://ai.google.dev/gemini-api", baseURL: "https://generativelanguage.googleapis.com/v1beta",
              group: .languageModels, summary: "多模态理解与生成",
              usageHint: "这里是原生 Gemini API；OpenAI 兼容接口使用另一条路径。", hasBundledIcon: true),
        .init(id: "deepseek", name: "DeepSeek", aliases: ["Deep Seek", "深度求索"],
              website: "https://api-docs.deepseek.com", baseURL: "https://api.deepseek.com",
              group: .languageModels, summary: "推理与代码模型",
              usageHint: "默认普通 API 地址；订阅或第三方网关请核对自己的地址。", hasBundledIcon: true),
        .init(id: "qwen", name: "通义千问 / Qwen", aliases: ["Qwen", "通义千问", "通义", "阿里云百炼", "百炼", "DashScope", "Qwen 通义千问"],
              website: "https://www.aliyun.com/product/bailian", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
              group: .languageModels, summary: "通义模型与百炼服务",
              usageHint: "默认北京地域的兼容接口；其他地域、工作空间或 Coding Plan 请改为对应地址。", hasBundledIcon: true),
        .init(id: "kimi", name: "Kimi / Moonshot", aliases: ["Kimi", "Moonshot", "Moonshot AI", "月之暗面"],
              website: "https://platform.kimi.com", baseURL: "https://api.moonshot.cn/v1",
              group: .languageModels, summary: "长文本、推理与 Agent",
              usageHint: "默认 Moonshot 常规模型接口；不同站点与订阅计划请核对地址。", hasBundledIcon: true),
        .init(id: "doubao", name: "豆包 / Doubao", aliases: ["Doubao", "豆包", "火山方舟", "Volcengine", "ByteDance", "字节跳动"],
              website: "https://www.volcengine.com/product/ark", baseURL: "https://ark.cn-beijing.volces.com/api/v3",
              group: .languageModels, summary: "火山方舟模型服务",
              usageHint: "默认北京地域的方舟 API；Coding Plan 使用不同地址。", hasBundledIcon: true),
        .init(id: "glm", name: "智谱 / GLM", aliases: ["GLM", "智谱", "智谱 AI", "Zhipu", "ZhipuAI", "BigModel", "ChatGLM"],
              website: "https://bigmodel.cn", baseURL: "https://open.bigmodel.cn/api/paas/v4",
              group: .languageModels, summary: "GLM 对话与代码模型",
              usageHint: "默认常规 API；Coding Plan 与其他站点需使用对应地址。", hasBundledIcon: true),
        .init(id: "minimax", name: "MiniMax", aliases: ["Mini Max", "稀宇科技"],
              website: "https://platform.minimax.cn", baseURL: "https://api.minimax.cn/v1",
              group: .languageModels, summary: "文本、语音与多模态",
              usageHint: "默认常规文本 API；语音接口和订阅密钥请按官方文档核对。", hasBundledIcon: true),
        .init(id: "xai", name: "Grok / xAI", aliases: ["Grok", "xAI", "xAI Grok"],
              website: "https://x.ai/api", baseURL: "https://api.x.ai/v1",
              group: .languageModels, summary: "Grok 模型与工具调用",
              usageHint: "默认 xAI API；模型与计费权限取决于自己的 API 账户。", hasBundledIcon: true),
        .init(id: "siliconflow", name: "硅基流动 / SiliconFlow", aliases: ["SiliconFlow", "Silicon Flow", "SiliconCloud", "硅基流动"],
              website: "https://siliconflow.cn", baseURL: "https://api.siliconflow.cn/v1",
              group: .languageModels, summary: "多模型推理平台",
              usageHint: "默认硅基流动站点；其他地域和第三方中转请使用自己的地址。", hasBundledIcon: true),
        .init(id: "openrouter", name: "OpenRouter", aliases: ["Open Router"],
              website: "https://openrouter.ai", baseURL: "https://openrouter.ai/api/v1",
              group: .languageModels, summary: "统一入口调用多模型",
              usageHint: "模型名通常包含提供方前缀；预设不会选择或调用模型。", hasBundledIcon: true),
        .init(id: "mistral", name: "Mistral AI", aliases: ["Mistral", "Le Chat"],
              website: "https://docs.mistral.ai/api", baseURL: "https://api.mistral.ai/v1",
              group: .languageModels, summary: "语言、代码与文档理解",
              usageHint: "这是 Mistral API；Le Chat 订阅不等同 API 额度。"),
        .init(id: "groq", name: "Groq", aliases: ["GroqCloud"],
              website: "https://console.groq.com/docs/overview", baseURL: "https://api.groq.com/openai/v1",
              group: .languageModels, summary: "快速语言模型推理",
              usageHint: "使用 Groq 的 OpenAI 兼容接口；可用模型以自己的账户为准。"),
        .init(id: "together", name: "Together AI", aliases: ["Together", "TogetherAI"],
              website: "https://docs.together.ai/docs/inference/openai-compatibility", baseURL: "https://api.together.ai/v1",
              group: .languageModels, summary: "开源模型推理与微调",
              usageHint: "默认共享推理接口；专属端点需按项目配置。"),
        .init(id: "cohere", name: "Cohere", aliases: ["Command", "Cohere Command"],
              website: "https://docs.cohere.com/reference/chat", baseURL: "https://api.cohere.com/v2",
              group: .languageModels, summary: "企业文本、向量与重排",
              usageHint: "默认 v2 API；不同功能的请求路径和模型参数请参照文档。"),
        .init(id: "deepinfra", name: "DeepInfra", aliases: ["Deep Infra"],
              website: "https://docs.deepinfra.com/chat/overview", baseURL: "https://api.deepinfra.com/v1/openai",
              group: .languageModels, summary: "多模型托管推理",
              usageHint: "默认 OpenAI 兼容接口；原生推理 API 使用不同路径。"),
        .init(id: "huggingface", name: "Hugging Face", aliases: ["HuggingFace", "HF", "Inference Providers"],
              website: "https://huggingface.co/docs/inference-providers/index", baseURL: "https://router.huggingface.co/v1",
              group: .languageModels, summary: "多提供方模型推理",
              usageHint: "默认路由器的聊天兼容接口；其他任务和专属端点需核对地址。"),
        .init(id: "replicate", name: "Replicate", aliases: [],
              website: "https://replicate.com/docs/reference/http", baseURL: "https://api.replicate.com/v1",
              group: .media, summary: "图像、视频与开源模型",
              usageHint: "模型或部署 ID 位于请求路径或请求体；预设不会运行模型。", symbol: "photo.stack"),
        .init(id: "fal", name: "fal.ai", aliases: ["fal", "FAL"],
              website: "https://fal.ai/docs/documentation/model-apis/inference/queue", baseURL: "https://queue.fal.run",
              group: .media, summary: "图像、视频与音频生成",
              usageHint: "默认异步队列；需在地址后加模型路径，认证使用 Authorization: Key。", symbol: "photo.badge.bolt"),
        .init(id: "stability", name: "Stability AI", aliases: ["Stability", "Stable Diffusion", "SD"],
              website: "https://platform.stability.ai/docs/api-reference", baseURL: "https://api.stability.ai/v2beta",
              group: .media, summary: "图像生成与编辑",
              usageHint: "默认 Stable Image v2beta；不同图像操作使用不同路径。", symbol: "photo.artframe"),
        .init(id: "runway", name: "Runway", aliases: ["RunwayML", "Runway ML"],
              website: "https://docs.dev.runwayml.com/guides/using-the-api/", baseURL: "https://api.dev.runwayml.com/v1",
              group: .media, summary: "视频和图像生成",
              usageHint: "请求需带 X-Runway-Version；API 账户与网页创作订阅请分开核对。", symbol: "video"),
        .init(id: "elevenlabs", name: "ElevenLabs", aliases: ["Eleven Labs", "11labs"],
              website: "https://elevenlabs.io/docs/api-reference/text-to-speech/convert", baseURL: "https://api.elevenlabs.io/v1",
              group: .media, summary: "语音合成与声音工具",
              usageHint: "语音合成需 voice_id；通常使用 xi-api-key 请求头。", symbol: "waveform"),
        .init(id: "deepgram", name: "Deepgram", aliases: ["Deep Gram"],
              website: "https://developers.deepgram.com/reference/speech-to-text/listen-pre-recorded", baseURL: "https://api.deepgram.com/v1",
              group: .media, summary: "语音识别与语音 AI",
              usageHint: "默认 HTTP API；实时语音使用 WebSocket，专属端点请另填。", symbol: "mic"),
        .init(id: "assemblyai", name: "AssemblyAI", aliases: ["Assembly AI"],
              website: "https://www.assemblyai.com/docs", baseURL: "https://api.assemblyai.com/v2",
              group: .media, summary: "转录、说话人和音频理解",
              usageHint: "默认预录音频 API；实时转录与其他数据地域使用不同地址。", symbol: "text.bubble"),
        .init(id: "cartesia", name: "Cartesia", aliases: [],
              website: "https://docs.cartesia.ai/api-reference/tts/bytes", baseURL: "https://api.cartesia.ai",
              group: .media, summary: "低延迟语音合成",
              usageHint: "请求需 Cartesia-Version、voice ID 和相应模型参数。", symbol: "waveform.circle"),
        .init(id: "tavily", name: "Tavily", aliases: [],
              website: "https://docs.tavily.com/documentation/api-reference/endpoint/search", baseURL: "https://api.tavily.com",
              group: .search, summary: "面向 Agent 的搜索与提取",
              usageHint: "搜索使用 /search，其他网页操作使用各自路径。"),
        .init(id: "exa", name: "Exa", aliases: ["Exa AI"],
              website: "https://exa.ai/docs/reference/search", baseURL: "https://api.exa.ai",
              group: .search, summary: "语义搜索与网页内容",
              usageHint: "搜索使用 /search；请求头与参数以官方文档为准。"),
        .init(id: "brave", name: "Brave Search", aliases: ["Brave", "Brave Search API"],
              website: "https://api-dashboard.search.brave.com/app/documentation/web-search", baseURL: "https://api.search.brave.com/res/v1",
              group: .search, summary: "网页、新闻与图片搜索",
              usageHint: "网页搜索路径为 /web/search；使用 X-Subscription-Token。"),
        .init(id: "firecrawl", name: "Firecrawl", aliases: ["Fire Crawl"],
              website: "https://docs.firecrawl.dev/api-reference/endpoint/scrape", baseURL: "https://api.firecrawl.dev/v2",
              group: .search, summary: "网页抓取与结构化提取",
              usageHint: "默认 v2 API；抓取、爬取和提取使用不同路径。"),
        .init(id: "jina", name: "Jina Reader", aliases: ["Jina", "Jina AI", "Reader"],
              website: "https://jina.ai/reader/", baseURL: "https://r.jina.ai",
              group: .search, summary: "网页转为模型可读文本",
              usageHint: "Reader 把目标网址接在 r.jina.ai/ 后；搜索及 Embeddings 使用其他地址。", symbol: "doc.text.magnifyingglass"),
        .init(id: "serper", name: "Serper", aliases: ["Google Serper", "Serper.dev"],
              website: "https://serper.dev/", baseURL: "",
              group: .search, summary: "搜索结果与网页数据",
              usageHint: "请从官方控制台的 Playground 复制请求地址；公开页面未列完整端点，预设留空。"),
        .init(id: "github", name: "GitHub", aliases: ["Git Hub", "GitHub REST"],
              website: "https://docs.github.com/en/rest", baseURL: "https://api.github.com",
              group: .development, summary: "代码仓库与开发协作",
              usageHint: "默认 GitHub.com REST API；Enterprise 实例需要自己的地址。", symbol: "chevron.left.forwardslash.chevron.right"),
        .init(id: "supabase", name: "Supabase", aliases: ["Supabase Data API"],
              website: "https://supabase.com/docs/guides/api", baseURL: "",
              group: .development, summary: "项目数据库与后端服务",
              usageHint: "每个项目地址不同：从项目 Data API 设置复制含 /rest/v1 的完整 URL。", symbol: "externaldrive"),
        .init(id: "cloudflare", name: "Cloudflare", aliases: ["Cloud Flare"],
              website: "https://developers.cloudflare.com/api/", baseURL: "https://api.cloudflare.com/client/v4",
              group: .development, summary: "DNS、站点与云资源管理",
              usageHint: "这是 Cloudflare 管理 API；Workers、R2 与自建服务另有项目地址。", symbol: "cloud"),
        .init(id: "sentry", name: "Sentry", aliases: [],
              website: "https://docs.sentry.io/api/", baseURL: "https://sentry.io/api/0",
              group: .development, summary: "错误监控与项目管理",
              usageHint: "这是管理 API，非 SDK DSN；特定地域或自建 Sentry 请修改主机。", symbol: "ladybug"),
        .init(id: "stripe", name: "Stripe", aliases: [],
              website: "https://docs.stripe.com/api", baseURL: "https://api.stripe.com/v1",
              group: .development, summary: "支付、账单与订阅",
              usageHint: "请用环境字段区分测试和正式密钥；不同 API 版本需按项目配置。", symbol: "creditcard"),
        .init(id: "mapbox", name: "Mapbox", aliases: ["Map Box"],
              website: "https://docs.mapbox.com/api/overview/", baseURL: "https://api.mapbox.com",
              group: .development, summary: "地图、地理编码与路线",
              usageHint: "地图和路线各有版本路径；不要把 access_token 放入保存的地址。", symbol: "map"),
        .init(id: "amap", name: "高德地图 / AMap", aliases: ["AMap", "高德", "高德地图"],
              website: "https://lbs.amap.com/api/webservice/summary", baseURL: "https://restapi.amap.com/v3",
              group: .development, summary: "地点、地理编码与路线",
              usageHint: "默认 Web 服务 v3；部分路线 API 使用 v5，密钥类型需选 Web 服务。", symbol: "location"),
        .init(id: "openweather", name: "OpenWeather", aliases: ["Open Weather", "OpenWeatherMap", "天气"],
              website: "https://openweathermap.org/api", baseURL: "https://api.openweathermap.org/data/2.5",
              group: .development, summary: "实时天气与天气预报",
              usageHint: "默认当前天气 API；One Call 3.0 具有不同路径及订阅要求。", symbol: "cloud.sun"),
        .init(id: "resend", name: "Resend", aliases: [],
              website: "https://resend.com/docs/api-reference/introduction", baseURL: "https://api.resend.com",
              group: .communication, summary: "事务邮件与邮件发送",
              usageHint: "按自己的域名和发送权限创建 API 密钥；预设不会发送邮件。", symbol: "envelope"),
        .init(id: "sendgrid", name: "SendGrid", aliases: ["Twilio SendGrid", "Send Grid"],
              website: "https://www.twilio.com/docs/sendgrid/api-reference/how-to-use-the-sendgrid-v3-api/requests", baseURL: "https://api.sendgrid.com/v3",
              group: .communication, summary: "邮件发送与营销集成",
              usageHint: "默认全局 Web API v3；特定数据地域的子账户使用不同地址。", symbol: "envelope.badge"),
        .init(id: "notion", name: "Notion", aliases: [],
              website: "https://developers.notion.com/reference/intro", baseURL: "https://api.notion.com/v1",
              group: .communication, summary: "文档、数据库与自动化",
              usageHint: "集成 Token 需关联页面权限，并带 Notion-Version 请求头。", symbol: "doc.richtext"),
        .init(id: "slack", name: "Slack", aliases: [],
              website: "https://docs.slack.dev/apis/web-api/", baseURL: "https://slack.com/api",
              group: .communication, summary: "工作区消息与机器人",
              usageHint: "保存对应工作区的 Bot 或 User Token；Webhook 地址不是此 API。", symbol: "bubble.left.and.bubble.right"),
        .init(id: "feishu", name: "飞书 / Feishu", aliases: ["Feishu", "飞书", "飞书开放平台"],
              website: "https://open.feishu.cn/document/", baseURL: "https://open.feishu.cn/open-apis",
              group: .communication, summary: "机器人、文档与团队协作",
              usageHint: "App Secret 与 tenant_access_token 不同；应用凭证通常需先换取访问令牌。", symbol: "paperplane"),
        .init(id: "dingtalk", name: "钉钉 / DingTalk", aliases: ["DingTalk", "钉钉"],
              website: "https://open.dingtalk.com/document/", baseURL: "https://api.dingtalk.com/v1.0",
              group: .communication, summary: "工作通知与企业自动化",
              usageHint: "默认新版服务端 API；旧接口和机器人 Webhook 使用不同地址。", symbol: "bolt.horizontal"),
        .init(id: "twilio", name: "Twilio", aliases: [],
              website: "https://www.twilio.com/docs/iam/api", baseURL: "https://api.twilio.com/2010-04-01",
              group: .communication, summary: "短信、通话与消息集成",
              usageHint: "通常需 API Key SID 与 Secret 配对；SID 可填账号标签，其他产品有独立域名。", symbol: "phone"),
        .init(id: "perplexity", name: "Perplexity", aliases: ["Perplexity AI", "Sonar", "Perplexity Sonar", "Perplexity Agent API"],
              website: "https://docs.perplexity.ai/docs/getting-started/quickstart", baseURL: "https://api.perplexity.ai",
              group: .search, summary: "联网搜索、引用与研究回答",
              usageHint: "使用独立的 Perplexity API Key；旧 Sonar 调用请按官方迁移指南改用 Agent API。"),
        .init(id: "apify", name: "Apify", aliases: ["Apify Actors"],
              website: "https://docs.apify.com/api/v2", baseURL: "https://api.apify.com/v2",
              group: .search, summary: "网页采集与 Actor 自动化",
              usageHint: "使用 API Token；运行采集器还需 Actor ID，建议使用 Bearer 请求头，勿把 token 写入地址。"),
        .init(id: "browserbase", name: "Browserbase", aliases: ["Browser Base", "Stagehand"],
              website: "https://docs.browserbase.com/reference/api/create-a-session", baseURL: "https://api.browserbase.com/v1",
              group: .agentTools, summary: "Agent 云端浏览器与会话",
              usageHint: "使用 X-BB-API-Key；浏览器会话的 Project ID 可记在账号标签，浏览器连接地址由会话返回。"),
        .init(id: "browserless", name: "Browserless", aliases: ["Browserless.io", "BrowserQL"],
              website: "https://docs.browserless.io/overview/connection-urls", baseURL: "https://production-sfo.browserless.io",
              group: .agentTools, summary: "浏览器自动化、截图与网页提取",
              usageHint: "默认共享云 REST 主机；私有部署或其他地域请修改。调用时才附加 token，勿把密钥存进地址。"),
        .init(id: "parallel", name: "Parallel", aliases: ["Parallel AI", "Parallel Web Systems"],
              website: "https://docs.parallel.ai/search/search-quickstart", baseURL: "https://api.parallel.ai",
              group: .search, summary: "Agent 网页搜索与研究任务",
              usageHint: "使用 x-api-key；新搜索接口为 /v1/search，研究任务等功能使用各自的 API 路径。"),
        .init(id: "context7", name: "Context7", aliases: ["Context 7", "Upstash Context7"],
              website: "https://context7.com/docs/api-guide", baseURL: "https://context7.com/api",
              group: .agentTools, summary: "编程 Agent 的文档与代码上下文",
              usageHint: "REST 使用 Bearer API Key；搜索、库解析和上下文接口版本不同，MCP 服务另有连接地址。"),
        .init(id: "composio", name: "Composio", aliases: ["Composio Tool Router"],
              website: "https://docs.composio.dev/reference/v3", baseURL: "https://backend.composio.dev/api/v3",
              group: .agentTools, summary: "Agent 工具连接与第三方集成",
              usageHint: "这里保存 Composio 项目 API Key；连接其他服务仍需各自授权，Tool Router 等新接口可能使用 v3.1。"),
        .init(id: "mem0", name: "Mem0", aliases: ["Mem 0", "Mem0 Platform"],
              website: "https://docs.mem0.ai/api-reference/memory/add-memories", baseURL: "https://api.mem0.ai",
              group: .agentTools, summary: "Agent 长期记忆与用户上下文",
              usageHint: "这是托管平台，认证为 Authorization: Token；还需用户或 Agent 标识，自托管实例请填写自己的地址。"),
        .init(id: "langsmith", name: "LangSmith", aliases: ["Lang Smith", "LangChain LangSmith"],
              website: "https://docs.langchain.com/langsmith/create-account-api-key", baseURL: "https://api.smith.langchain.com",
              group: .development, summary: "LLM 追踪、评估与 Agent 调试",
              usageHint: "使用 LangSmith API Key；工作区、项目及地域需匹配，欧洲地域或自托管部署请修改地址。"),
        .init(id: "langfuse", name: "Langfuse", aliases: ["Lang Fuse"],
              website: "https://langfuse.com/docs/api-and-data-platform/features/public-api", baseURL: "https://cloud.langfuse.com/api/public",
              group: .development, summary: "模型调用追踪与评估分析",
              usageHint: "Public API 使用 Public Key + Secret Key 的 Basic Auth；公钥可放账号标签，私钥放密钥栏，按项目地域修改地址。"),
        .init(id: "qdrant", name: "Qdrant", aliases: ["Qdrant Cloud"],
              website: "https://qdrant.tech/documentation/quickstart/", baseURL: "",
              group: .development, summary: "知识库与 Agent 向量检索",
              usageHint: "请填自己的集群 URL 和数据库 API Key；集群密钥与 Qdrant Cloud 管理密钥不同，不能互换。"),
        .init(id: "pinecone", name: "Pinecone", aliases: ["Pinecone Database"],
              website: "https://docs.pinecone.io/guides/manage-data/target-an-index", baseURL: "",
              group: .development, summary: "知识库检索与向量数据库",
              usageHint: "请从控制台填入索引专属 HTTPS host；使用项目 API Key，向量请求不能直接使用管理域名 api.pinecone.io。"),
        .init(id: "weaviate", name: "Weaviate", aliases: ["Weaviate Cloud"],
              website: "https://docs.weaviate.io/cloud/manage-clusters/connect", baseURL: "",
              group: .development, summary: "向量搜索与检索增强生成",
              usageHint: "请填集群 REST endpoint 与对应 API Key；调用外部嵌入模型时，可能还需另存该模型提供商的密钥。"),
        .init(id: "zep", name: "Zep", aliases: ["Zep Cloud", "GetZep"],
              website: "https://help.getzep.com/v3/install-sdks", baseURL: "https://api.getzep.com",
              group: .agentTools, summary: "Agent 记忆图谱与会话上下文",
              usageHint: "这里是 Zep Cloud API Key；云端 SDK 与旧版 Community Edition 不同，路径按当前 SDK 文档填写。")
    ]

    /// Match only an explicitly known provider name or alias. Custom gateways
    /// containing a brand name must not be represented as that official provider.
    public static func match(provider: String) -> ProviderPreset? {
        let value = normalized(provider)
        guard !value.isEmpty else { return nil }
        return aliasLookup[value]
    }

    private static let aliasLookup: [String: ProviderPreset] = {
        var result: [String: ProviderPreset] = [:]
        for preset in all {
            for alias in [preset.id, preset.name] + preset.aliases {
                let key = normalized(alias)
                if result[key] == nil { result[key] = preset }
            }
        }
        return result
    }()

    /// Supports names, aliases and whitespace-separated terms.
    /// Empty search includes every preset; punctuation alone is not a match.
    public func matches(search: String) -> Bool {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let terms = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .map(Self.normalized).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return false }
        let fields = ([id, name, summary, group.title] + aliases).map(Self.normalized)
        return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
