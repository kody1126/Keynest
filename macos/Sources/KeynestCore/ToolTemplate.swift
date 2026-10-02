import Foundation

public enum ToolTemplateKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case client, agent, skill
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .client: return "客户端"
        case .agent: return "Agent 与工作流"
        case .skill: return "Skill"
        }
    }
}

/// One credential role. providerIDs are alternatives, not a list of keys to create.
/// Required means required by this API-key recipe, not by every mode of the tool.
public struct ToolCredentialSlot: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let providerIDs: [String]
    public let defaultProviderID: String
    public let isOptional: Bool
    /// Only populated when all alternatives use the same documented variable.
    /// Descriptive only: Keynest does not read or write process environments.
    public let environmentVariable: String?

    fileprivate init(_ id: String, _ title: String, _ providerIDs: [String],
                     default defaultProviderID: String, optional: Bool = false, env: String? = nil) {
        self.id = id; self.title = title; self.providerIDs = providerIDs
        self.defaultProviderID = defaultProviderID; self.isOptional = optional
        self.environmentVariable = env
    }
}

/// Offline suggestions for organizing credentials. No installation, account
/// login, environment edits, workflow execution or network requests are implied.
public struct ToolTemplate: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let kind: ToolTemplateKind
    public let summary: String
    public let notes: String
    /// Empty for generic combinations, which have no independent product website.
    public let website: String
    /// A real product's bundled ToolIcons brand ID; nil for generic combinations.
    public let logoID: String?
    /// Existing ProviderIcons used together for an unbranded functional recipe.
    public let providerLogoIDs: [String]
    public let credentialSlots: [ToolCredentialSlot]
    public var iconFilename: String? { logoID.map { "\($0).png" } }

    private init(_ id: String, _ name: String, aliases: [String] = [], kind: ToolTemplateKind,
                 summary: String, notes: String, website: String, logoID: String? = nil,
                 providerLogoIDs: [String] = [], slots: [ToolCredentialSlot]) {
        self.id = id; self.name = name; self.aliases = aliases; self.kind = kind
        self.summary = summary; self.website = website; self.logoID = logoID
        self.providerLogoIDs = providerLogoIDs; self.credentialSlots = slots
        self.notes = notes + "\n在 Keynest 保存并关联凭据；实际调用在对应工具中配置。"
    }

    /// Official configuration references and recipe scope: research/skill-agent-templates-0.7.md.
    public static let all: [ToolTemplate] = [
        .init("cursor", "Cursor", kind: .client,
              summary: "整理编辑器自带密钥模式的模型 API",
              notes: "适用于 Cursor 的自带模型密钥配置，不代表 Cursor 订阅或 CLI 登录。部分编辑器能力使用其内置服务；模型仍需在 Cursor 中选择。",
              website: "https://docs.cursor.com/settings/api-keys", logoID: "cursor",
              slots: [.init("model", "模型 API", ["anthropic", "openai", "google"], default: "anthropic")]),
        .init("cline", "Cline", kind: .client,
              summary: "为编码助手准备一个模型提供商",
              notes: "适用于直接填写模型 API Key 的模式。Cline 账户、本地模型和其他认证方式不属于这个凭据模板。",
              website: "https://docs.cline.bot/provider-config/openrouter", logoID: "cline",
              slots: [.init("model", "模型 API", ["openrouter", "anthropic", "openai"], default: "openrouter")]),
        .init("roo-code", "Roo Code", aliases: ["RooCode"], kind: .client,
              summary: "按 API 提供商组织编码代理密钥",
              notes: "保存 Roo Code 设置中的模型提供商密钥；模型和可选自定义地址仍在 Roo Code 中配置。",
              website: "https://roocodeinc.github.io/Roo-Code/providers/anthropic/", logoID: "roo-code",
              slots: [.init("model", "模型 API", ["anthropic", "openrouter", "openai", "google", "deepseek"], default: "anthropic")]),
        .init("continue", "Continue", kind: .client,
              summary: "把聊天模型与可选向量化密钥放在一起",
              notes: "API Key 可供聊天、编辑等模型角色使用。使用云端向量化时再关联第二个槽位，也可复用同一 OpenAI 密钥；本地模型不需要在这里虚构密钥。",
              website: "https://docs.continue.dev/reference", logoID: "continue",
              slots: [.init("model", "聊天模型 API", ["anthropic", "openai", "google", "openrouter"], default: "anthropic"),
                      .init("embedding", "云端向量化 API", ["openai"], default: "openai", optional: true)]),
        .init("opencode", "OpenCode", aliases: ["Open Code"], kind: .client,
              summary: "收藏通过 connect 配置的模型密钥",
              notes: "对应手动输入提供商 API Key 的配置路径。OpenCode 的其他订阅、OAuth 与本地模型方式不需要套用这个模板。",
              website: "https://opencode.ai/docs/providers", logoID: "opencode",
              slots: [.init("model", "模型 API", ["anthropic", "openai", "google", "openrouter"], default: "anthropic")]),
        .init("claude-code", "Claude Code", aliases: ["ClaudeCode"], kind: .client,
              summary: "保存 Anthropic API 计费模式的密钥",
              notes: "仅适用于 ANTHROPIC_API_KEY 模式，API 用量与 Claude 订阅分开。使用 Claude 订阅登录时，不需要新增 API 密钥，更不要填写登录密码或会话令牌。",
              website: "https://code.claude.com/docs/en/authentication", logoID: "claude-code",
              slots: [.init("model", "Anthropic API Key", ["anthropic"], default: "anthropic", env: "ANTHROPIC_API_KEY")]),
        .init("openclaw", "OpenClaw", aliases: ["Open Claw"], kind: .agent,
              summary: "整理模型凭据与可选联网搜索",
              notes: "模型槽适用于提供商 API Key 模式，搜索槽仅在启用 Brave 搜索时使用。频道账号、Gateway 令牌与 OAuth 登录不在本模板内。",
              website: "https://docs.openclaw.ai/concepts/model-providers", logoID: "openclaw",
              slots: [.init("model", "模型 API", ["anthropic", "openai", "google", "openrouter"], default: "anthropic"),
                      .init("search", "Brave 联网搜索", ["brave"], default: "brave", optional: true, env: "BRAVE_API_KEY")]),
        .init("dify", "Dify", kind: .agent,
              summary: "集中保管应用模型与知识库向量化凭据",
              notes: "对应工作区的自定义模型提供商。云端知识库向量化是可选配置，可复用已有 OpenAI 密钥；Dify 系统供应商、登录和应用发布 API Key 是不同配置。",
              website: "https://docs.dify.ai/zh-hans/guides/model-configuration/readme", logoID: "dify",
              slots: [.init("model", "应用模型 API", ["openai", "anthropic", "google"], default: "openai"),
                      .init("embedding", "知识库向量化 API", ["openai", "cohere"], default: "openai", optional: true)]),
        .init("n8n", "n8n", kind: .agent,
              summary: "为内容整理工作流组合模型、采集和邮件",
              notes: "这是内容自动化的凭据组合示例，不是 n8n 的安装要求。按实际节点启用采集或邮件槽；额外节点、URL、发件域名和组织参数需在 n8n 中配置。",
              website: "https://docs.n8n.io/integrations/builtin/credentials/openai", logoID: "n8n",
              slots: [.init("model", "内容模型 API", ["openai"], default: "openai"),
                      .init("crawl", "网页采集 API", ["firecrawl"], default: "firecrawl", optional: true),
                      .init("email", "邮件通知 API", ["resend"], default: "resend", optional: true)]),
        .init("flowise", "Flowise", aliases: ["FlowiseAI"], kind: .agent,
              summary: "整理可视化 AI 流程的模型与向量库密钥",
              notes: "保存流程节点使用的第三方 API 凭据。托管向量库需填写自己的集群或索引地址；这些凭据不同于保护 Flowise 自身流程接口的 API Key。",
              website: "https://docs.flowiseai.com/integrations/langchain/vector-stores/qdrant", logoID: "flowise",
              slots: [.init("model", "模型 API", ["openai"], default: "openai"),
                      .init("vector-store", "托管向量库 API", ["qdrant", "pinecone"], default: "qdrant", optional: true)]),
        .init("langgraph", "LangGraph", aliases: ["Lang Graph"], kind: .agent,
              summary: "整理图式 Agent 的模型与可选追踪凭据",
              notes: "对应自己编写的模型调用配置；LangGraph 框架本身不需要购买专属 API 密钥。只有启用 LangSmith 追踪时才添加追踪槽。",
              website: "https://docs.langchain.com/oss/python/langgraph/quickstart", logoID: "langgraph",
              slots: [.init("model", "模型 API", ["anthropic", "openai", "google"], default: "anthropic"),
                      .init("tracing", "LangSmith 追踪", ["langsmith"], default: "langsmith", optional: true, env: "LANGSMITH_API_KEY")]),
        .init("crewai", "CrewAI", aliases: ["Crew AI"], kind: .agent,
              summary: "为多代理项目保管所选模型 API",
              notes: "为 CrewAI 项目中的 LLM 配置保存一个提供商密钥。不同代理可复用同一条收藏；工具调用需要的其他凭据可稍后关联，不代表框架必须使用付费云模型。",
              website: "https://docs.crewai.com/en/concepts/llms", logoID: "crewai",
              slots: [.init("model", "模型 API", ["openai", "anthropic", "google"], default: "openai")]),
        .init("open-webui", "Open WebUI", aliases: ["OpenWebUI"], kind: .client,
              summary: "收藏聊天界面的 OpenAI 兼容服务凭据",
              notes: "对应外部 OpenAI 兼容连接。模型名称和连接地址需在 Open WebUI 中配置；连接本地免密模型时无需在这里创建假密钥。",
              website: "https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-openai-compatible/", logoID: "open-webui",
              slots: [.init("model", "兼容模型 API", ["openai", "openrouter", "deepseek", "groq"], default: "openai")]),
        .init("anythingllm", "AnythingLLM", aliases: ["Anything LLM"], kind: .client,
              summary: "集中保存工作区云端模型 API",
              notes: "对应 AnythingLLM 的 OpenAI 云端模型配置，可供工作区与 Agent 复用。内置或本地模型不一定需要 API Key；其他知识库组件可在创建后继续关联。",
              website: "https://docs.anythingllm.com/setup/llm-configuration/cloud/openai", logoID: "anythingllm",
              slots: [.init("model", "OpenAI 模型 API", ["openai"], default: "openai")]),
        .init("cherry-studio", "Cherry Studio", aliases: ["CherryStudio", "樱桃工作室"], kind: .client,
              summary: "整理桌面模型服务与可选 Tavily 搜索",
              notes: "按 Cherry Studio 中选用的模型提供商关联密钥。Tavily 仅用于启用其联网搜索的场景；模型、地址与搜索参数仍在客户端中设置。",
              website: "https://docs.cherry-ai.com/cherry-studio-wen-dang/en-us/cherry-studio/preview/settings/providers", logoID: "cherry-studio",
              slots: [.init("model", "模型 API", ["openai", "doubao", "deepseek"], default: "openai"),
                      .init("search", "Tavily 联网搜索", ["tavily"], default: "tavily", optional: true)]),
        .init("web-search-skill", "联网搜索 Skill", aliases: ["Web Search"], kind: .skill,
              summary: "为搜索能力选择一家网页搜索服务",
              notes: "通用功能组合，不是已安装的 Skill。选择 Tavily、Brave 或 Exa 中的一家；不同服务的参数和调用方式不同，需在自己的 Skill 中实现。",
              website: "", providerLogoIDs: ["tavily", "brave", "exa"],
              slots: [.init("search", "网页搜索 API", ["tavily", "brave", "exa"], default: "tavily")]),
        .init("web-crawl-skill", "网页采集 Skill", aliases: ["Web Crawl", "Scrape"], kind: .skill,
              summary: "集中保存网页采集或正文提取的 API",
              notes: "通用功能组合，不是某家提供商发布的 Skill。选择自己使用的采集服务；抓取、正文提取与 Actor 服务的能力和请求方式各不相同。",
              website: "", providerLogoIDs: ["firecrawl", "jina", "apify"],
              slots: [.init("crawl", "网页采集 API", ["firecrawl", "jina", "apify"], default: "firecrawl")]),
        .init("voice-assistant", "语音助手", aliases: ["Voice Assistant"], kind: .agent,
              summary: "把对话、语音合成与可选转录凭据放在一起",
              notes: "通用功能组合；默认模型负责对话、语音服务负责合成。需要音频输入时再添加转录槽。仍需自行选择模型、声音和音频格式并搭建调用流程。",
              website: "", providerLogoIDs: ["openai", "elevenlabs", "deepgram"],
              slots: [.init("model", "对话模型 API", ["openai", "anthropic", "google"], default: "openai"),
                      .init("speech", "语音合成 API", ["elevenlabs", "cartesia", "openai"], default: "elevenlabs"),
                      .init("transcription", "语音识别 API", ["deepgram", "assemblyai", "openai"], default: "deepgram", optional: true)]),
        .init("knowledge-agent", "知识库 Agent", aliases: ["RAG", "Knowledge Agent"], kind: .agent,
              summary: "整理知识库模型、向量化与可选托管向量库",
              notes: "通用知识库组合：OpenAI 密钥可用于对话与向量化。采用托管向量库时选择 Qdrant 或 Pinecone，并填写自己的集群或索引地址；本地向量库可跳过该槽。",
              website: "", providerLogoIDs: ["openai", "qdrant", "pinecone"],
              slots: [.init("model", "模型与向量化 API", ["openai"], default: "openai"),
                      .init("vector-store", "托管向量库 API", ["qdrant", "pinecone"], default: "qdrant", optional: true)]),
        .init("cloudflare-skill", "Cloudflare 运维 Skill", aliases: ["DNS", "Workers"], kind: .skill,
              summary: "整理 DNS 或 Workers 操作用的 API Token",
              notes: "通用运维能力组合。使用与目标 DNS 区域或 Workers 账户对应的 API Token 权限；Account ID、Zone ID 是需另行配置的标识，不是 API 密钥。",
              website: "", providerLogoIDs: ["cloudflare"],
              slots: [.init("cloud", "Cloudflare API Token", ["cloudflare"], default: "cloudflare")]),
        .init("github-skill", "GitHub 仓库 Skill", aliases: ["GitHub PAT", "Repository"], kind: .skill,
              summary: "为仓库检索或维护能力保存访问令牌",
              notes: "通用仓库能力组合，使用 GitHub Personal Access Token。按实际仓库和操作配置 token 权限；仓库名称与组织名称属于调用配置。",
              website: "", providerLogoIDs: ["github"],
              slots: [.init("repository", "GitHub 访问令牌", ["github"], default: "github")]),
        .init("notion-skill", "Notion 笔记 Skill", aliases: ["Notion Integration"], kind: .skill,
              summary: "为笔记与知识整理保存集成令牌",
              notes: "通用笔记能力组合，使用 Notion 内部集成令牌；集成还需要获得相应页面的访问权限。页面或数据源 ID 与集成令牌分开配置。",
              website: "", providerLogoIDs: ["notion"],
              slots: [.init("notes", "Notion 集成令牌", ["notion"], default: "notion")]),
        .init("email-skill", "邮件通知 Skill", aliases: ["Email", "Notification"], kind: .skill,
              summary: "为通知能力选择一家邮件 API 服务",
              notes: "通用邮件能力组合，选择 Resend 或 SendGrid。API Key 与邮箱登录密码不同；实际发送还需在对应服务配置发件身份和域名。",
              website: "", providerLogoIDs: ["resend", "sendgrid"],
              slots: [.init("email", "邮件发送 API", ["resend", "sendgrid"], default: "resend")]),
        .init("map-weather-skill", "地图天气 Skill", aliases: ["Maps", "Weather", "旅行"], kind: .skill,
              summary: "组合位置检索与可选天气查询凭据",
              notes: "通用位置能力组合；高德应选择 Web 服务 Key，Mapbox 使用适合所需接口的 Access Token。两个地图服务的请求格式不同，天气槽按需关联。",
              website: "", providerLogoIDs: ["amap", "mapbox", "openweather"],
              slots: [.init("maps", "地图 API", ["amap", "mapbox"], default: "amap"),
                      .init("weather", "天气 API", ["openweather"], default: "openweather", optional: true)]),
        .init("browser-skill", "浏览器自动化 Skill", aliases: ["Browser Automation"], kind: .skill,
              summary: "保存托管浏览器服务的访问凭据",
              notes: "通用浏览器能力组合。Browserbase 除 API Key 外还需另填 Project ID；Browserless 使用对应区域或部署的服务地址与 token。服务间调用方式不同。",
              website: "", providerLogoIDs: ["browserbase", "browserless"],
              slots: [.init("browser", "浏览器服务 API", ["browserbase", "browserless"], default: "browserbase")])
    ]

    /// Stable catalog lookup only. Never infer a template from a key or URL.
    public static func match(templateID: String) -> ToolTemplate? {
        all.first { $0.id == templateID }
    }

    public func matches(search: String) -> Bool {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let terms = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .map(Self.normalized).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return false }
        let fields = ([id, name, kind.title, summary] + aliases + credentialSlots.map(\.title)
                      + credentialSlots.flatMap(\.providerIDs)).map(Self.normalized)
        return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
