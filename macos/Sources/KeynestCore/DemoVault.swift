import Foundation

/// Public, fictional samples for the separately identified Keynest Demo app.
/// This password is intentionally documented and must never protect real keys.
public enum DemoVault {
    public static let password = "Keynest-Demo-2026"
    public static let directoryName = "Keynest Demo"
    /// Separate from VaultDocument.version: adding examples never changes encryption.
    public static let catalogRevision = 7

    public static func document() -> VaultDocument {
        adding07(to: catalog06Document())
    }

    private static func catalog06Document() -> VaultDocument {
        var result = catalog05Document()
        result.tools.append(contentsOf: additional06Tools())
        result.entries.append(contentsOf: additional06Entries())
        return result
    }

    /// Run once per catalog revision, then persist the revision only after the
    /// encrypted save succeeds. A v2 Demo without a marker starts at revision 5;
    /// a v1 Demo starts at 4. Passing the current/future revision is a no-op.
    public static func upgradingCatalog(_ existing: VaultDocument, fromRevision: Int) throws -> VaultDocument {
        guard fromRevision < catalogRevision else { return try existing.validated() }
        var result = try fromRevision < 5 ? enriching(existing) : existing.validated()
        if fromRevision < 6 { result = adding06(to: result) }
        result = adding07(to: result)
        return try result.validated()
    }

    private static func adding06(to existing: VaultDocument) -> VaultDocument {
        var result = existing
        let previousTools = catalog05Document().tools
        let newTools = additional06Tools()

        // Old missing tools may have been deleted. Only this revision's new IDs
        // can be inserted. A same-ID tool edit never receives new sample links.
        for candidate in newTools where !result.tools.contains(where: { $0.id == candidate.id }) {
            result.tools.append(candidate)
        }
        let availableTools = Set((previousTools + newTools).filter { candidate in
            result.tools.contains(candidate)
        }.map(\.id))
        for candidate in additional06Entries() where !result.entries.contains(where: { $0.id == candidate.id }) {
            var addition = candidate
            addition.toolIDs = candidate.toolIDs.filter { availableTools.contains($0) }
            result.entries.append(addition)
        }
        return result
    }

    private static func adding07(to existing: VaultDocument) -> VaultDocument {
        var result = existing
        let newTools = additional07Tools()
        for candidate in newTools where !result.tools.contains(where: { $0.id == candidate.id }) {
            result.tools.append(candidate)
        }
        let availableTools = Set(newTools.filter { result.tools.contains($0) }.map(\.id))
        for candidate in additional07Entries() where !result.entries.contains(where: { $0.id == candidate.id }) {
            var addition = candidate
            addition.toolIDs = candidate.toolIDs.filter { availableTools.contains($0) }
            result.entries.append(addition)
        }

        // Only exact, unchanged 0.6 fixtures may gain these new associations.
        // A changed credential, URL, field, timestamp or old link stays untouched.
        // Deleted entries are never restored; matching a provider is insufficient.
        let baseline = catalog06Document().entries
        let links: [(Int, [Int])] = [(1, [9]), (2, [8, 10]), (11, [7])]
        for (number, toolNumbers) in links {
            let fixture = baseline[number - 1]
            guard let index = result.entries.firstIndex(where: { $0.id == fixture.id }),
                  result.entries[index] == fixture else { continue }
            result.entries[index].toolIDs.append(contentsOf: toolNumbers.map { toolID(number: $0) }
                .filter { availableTools.contains($0) })
        }
        return result
    }

    private static func catalog05Document() -> VaultDocument {
        let tools = [
            tool(number: 1, name: "研究助手", notes: "为资料检索、推理和长文整理组合使用多个 API。"),
            tool(number: 2, name: "内容工作台", notes: "按工具查找生成、润色和多模态处理所需的 API。"),
            tool(number: 3, name: "个人自动化", notes: "区分开发与正式环境；同一个密钥也能供多个工具使用。")
        ]
        var entries = legacyDocument().entries
        let associations = [[0, 1], [0], [1], [0, 2], [0], [0], [2]]
        for index in entries.indices {
            entries[index].toolIDs = associations[index].map { tools[$0].id }
            entries[index].environment = index == 6 ? "开发" : "正式"
            entries[index].accountLabel = index == 1 ? "团队演示账户" : "个人演示账户"
        }
        entries.append(entry(number: 8, name: "OpenAI · 开发环境演示", category: .ai,
                             provider: entries[0].provider, baseURL: entries[0].baseURL,
                             website: entries[0].website, tags: ["演示", "AI 模型", "开发环境"],
                             toolIDs: [tools[2].id], environment: "开发", accountLabel: "测试项目"))
        entries.append(entry(number: 9, name: "DeepSeek · 测试账户演示", category: .ai,
                             provider: entries[3].provider, baseURL: entries[3].baseURL,
                             website: entries[3].website, tags: ["演示", "AI 模型", "测试环境"],
                             toolIDs: [tools[0].id, tools[2].id], environment: "测试", accountLabel: "团队测试账户"))
        return VaultDocument(entries: entries, tools: tools)
    }

    /// Add the 0.5 scenarios without overwriting edited samples. Call this only
    /// during a Demo payload-v1 upgrade, so later user deletions stay deleted.
    public static func enriching(_ existing: VaultDocument) throws -> VaultDocument {
        let original = try existing.validated()
        let seed = catalog05Document()
        let legacy = Dictionary(uniqueKeysWithValues: legacyDocument().entries.map { ($0.id, $0) })
        var result = original
        var availableTools = Set<UUID>()
        for tool in seed.tools {
            if let current = result.tools.first(where: { $0.id == tool.id }) {
                if current == tool { availableTools.insert(tool.id) }
            } else {
                result.tools.append(tool); availableTools.insert(tool.id)
            }
        }
        for candidate in seed.entries {
            if let index = result.entries.firstIndex(where: { $0.id == candidate.id }) {
                // A match includes every original field, including its timestamps,
                // notes, URLs and credential. Any edit makes the sample user-owned.
                guard legacy[candidate.id] == result.entries[index] else { continue }
                result.entries[index].toolIDs = candidate.toolIDs.filter { availableTools.contains($0) }
                result.entries[index].environment = candidate.environment
                result.entries[index].accountLabel = candidate.accountLabel
            } else if legacy[candidate.id] == nil {
                // Deleted old samples are not recreated. Only new sample IDs qualify.
                var addition = candidate
                addition.toolIDs = candidate.toolIDs.filter { availableTools.contains($0) }
                result.entries.append(addition)
            }
        }
        return try result.validated()
    }

    private static func additional06Tools() -> [ToolGroup] {
        [
            tool(number: 4, name: "语音助手", notes: "用语言模型理解需求，再组合语音合成与低延迟音频服务。"),
            tool(number: 5, name: "旅行助手", notes: "结合地图、天气与网页搜索，为行程工具整理所需 API。"),
            tool(number: 6, name: "开发运维", notes: "集中管理代码仓库、云服务与邮件通知；按环境区分使用。")
        ]
    }

    private static func additional06Entries() -> [SecretEntry] {
        // Freeze the exact 0.6 metadata for matching; future provider defaults
        // must not change historical fixture identity or user-edit detection.
        let providers: [String: (name: String, website: String, baseURL: String)] = [
            "qwen": ("通义千问 / Qwen", "https://www.aliyun.com/product/bailian", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
            "openrouter": ("OpenRouter", "https://openrouter.ai", "https://openrouter.ai/api/v1"),
            "tavily": ("Tavily", "https://docs.tavily.com/documentation/api-reference/endpoint/search", "https://api.tavily.com"),
            "brave": ("Brave Search", "https://api-dashboard.search.brave.com/app/documentation/web-search", "https://api.search.brave.com/res/v1"),
            "firecrawl": ("Firecrawl", "https://docs.firecrawl.dev/api-reference/endpoint/scrape", "https://api.firecrawl.dev/v2"),
            "jina": ("Jina Reader", "https://jina.ai/reader/", "https://r.jina.ai"),
            "replicate": ("Replicate", "https://replicate.com/docs/reference/http", "https://api.replicate.com/v1"),
            "fal": ("fal.ai", "https://fal.ai/docs/documentation/model-apis/inference/queue", "https://queue.fal.run"),
            "elevenlabs": ("ElevenLabs", "https://elevenlabs.io/docs/api-reference/text-to-speech/convert", "https://api.elevenlabs.io/v1"),
            "cartesia": ("Cartesia", "https://docs.cartesia.ai/api-reference/tts/bytes", "https://api.cartesia.ai"),
            "amap": ("高德地图 / AMap", "https://lbs.amap.com/api/webservice/summary", "https://restapi.amap.com/v3"),
            "openweather": ("OpenWeather", "https://openweathermap.org/api", "https://api.openweathermap.org/data/2.5"),
            "github": ("GitHub", "https://docs.github.com/en/rest", "https://api.github.com"),
            "cloudflare": ("Cloudflare", "https://developers.cloudflare.com/api/", "https://api.cloudflare.com/client/v4"),
            "resend": ("Resend", "https://resend.com/docs/api-reference/introduction", "https://api.resend.com")
        ]
        let samples: [(String, String, EntryCategory, [String], [Int], String, String)] = [
            ("qwen", "通义千问 · 多语言演示", .ai, ["AI 模型", "多语言"], [1, 4], "正式", "个人演示账户"),
            ("openrouter", "OpenRouter · 多模型演示", .ai, ["AI 模型", "模型聚合"], [1, 2], "测试", "模型评测项目"),
            ("tavily", "Tavily · 联网搜索演示", .service, ["搜索", "研究"], [1], "正式", "研究项目"),
            ("brave", "Brave Search · 网页搜索演示", .service, ["搜索", "旅行"], [1, 5], "正式", "个人演示账户"),
            ("firecrawl", "Firecrawl · 网页采集演示", .service, ["网页采集", "研究"], [1, 3], "开发", "采集测试项目"),
            ("jina", "Jina · 网页阅读演示", .service, ["网页采集", "文本提取"], [1], "正式", "研究项目"),
            ("replicate", "Replicate · 图像生成演示", .ai, ["图像", "模型托管"], [2], "测试", "创作测试项目"),
            ("fal", "fal · 图像工作流演示", .ai, ["图像", "创作"], [2, 3], "开发", "内容工具项目"),
            ("elevenlabs", "ElevenLabs · 配音演示", .ai, ["语音", "配音"], [2, 4], "正式", "音频项目"),
            ("cartesia", "Cartesia · 实时语音演示", .ai, ["语音", "实时"], [4], "开发", "语音助手项目"),
            ("amap", "高德地图 · 行程地图演示", .service, ["地图", "旅行"], [5], "正式", "旅行工具项目"),
            ("openweather", "OpenWeather · 天气演示", .service, ["天气", "旅行"], [5, 3], "正式", "个人演示账户"),
            ("github", "GitHub · 仓库服务演示", .service, ["开发", "代码仓库"], [6, 3], "开发", "开发工具项目"),
            ("cloudflare", "Cloudflare · 云服务演示", .service, ["开发", "云服务"], [6], "测试", "基础设施测试项目"),
            ("resend", "Resend · 邮件通知演示", .service, ["消息", "邮件"], [6, 3], "开发", "通知测试项目")
        ]
        return samples.enumerated().map { index, sample in
            // IDs are a checked-in catalog contract, verified by DemoVaultTests.
            guard let preset = providers[sample.0] else {
                preconditionFailure("Missing historical Demo provider: \(sample.0)")
            }
            return entry(number: index + 10, name: sample.1, category: sample.2,
                         provider: preset.name, baseURL: preset.baseURL, website: preset.website,
                         tags: ["演示"] + sample.3,
                         toolIDs: sample.4.map { toolID(number: $0) },
                         environment: sample.5, accountLabel: sample.6)
        }
    }

    private static func additional07Tools() -> [ToolGroup] {
        [
            tool(number: 7, name: "Cline 编程助手", notes: "组合模型、文档检索与仓库能力；样例凭据均为虚构。", templateID: "cline"),
            tool(number: 8, name: "OpenClaw 个人 Agent", notes: "组合模型、浏览器、长期记忆与联网研究能力；样例凭据均为虚构。", templateID: "openclaw"),
            tool(number: 9, name: "n8n 内容自动化", notes: "组合模型、内容采集与笔记归档能力；样例凭据均为虚构。", templateID: "n8n"),
            tool(number: 10, name: "LangGraph 知识 Agent", notes: "组合模型、工具连接、长期记忆、追踪与向量检索；样例凭据均为虚构。", templateID: "langgraph")
        ]
    }

    private static func additional07Entries() -> [SecretEntry] {
        let samples: [(String, String, EntryCategory, [String], [Int])] = [
            ("context7", "Context7 · 文档 Skill 演示", .skill, ["Skill", "文档检索"], [7]),
            ("browserbase", "Browserbase · 浏览器 Agent 演示", .service, ["Agent 工具", "浏览器"], [8]),
            ("apify", "Apify · 网页采集 Skill 演示", .skill, ["Skill", "采集"], [9]),
            ("composio", "Composio · 工具连接演示", .service, ["Agent 工具", "集成"], [10]),
            ("mem0", "Mem0 · 长期记忆演示", .service, ["Agent 工具", "记忆"], [8, 10]),
            ("langsmith", "LangSmith · Agent 追踪演示", .service, ["Agent 工具", "追踪"], [10]),
            ("qdrant", "Qdrant · 知识检索演示", .service, ["Agent 工具", "向量库"], [10]),
            ("perplexity", "Perplexity · 研究 Skill 演示", .skill, ["Skill", "联网研究"], [8]),
            ("notion", "Notion · 笔记 Skill 演示", .skill, ["Skill", "笔记"], [9]),
            ("github", "GitHub · 仓库 Skill 演示", .skill, ["Skill", "代码仓库"], [7])
        ]
        return samples.enumerated().map { index, sample in
            guard let preset = ProviderPreset.match(provider: sample.0) else {
                preconditionFailure("Missing bundled Demo provider preset: \(sample.0)")
            }
            return entry(number: index + 25, name: sample.1, category: sample.2,
                         provider: preset.name, baseURL: preset.baseURL, website: preset.website,
                         tags: ["演示"] + sample.3, toolIDs: sample.4.map { toolID(number: $0) },
                         environment: "开发", accountLabel: "虚构 Agent 项目")
        }
    }

    private static func legacyDocument() -> VaultDocument {
        // Freeze the exact 0.4 seed metadata for safe migration matching, even if
        // the provider catalog's editable defaults change in a future release.
        let providers = [
            ("OpenAI · 演示", "ChatGPT / OpenAI", "https://api.openai.com/v1", "https://openai.com/api/"),
            ("Claude · 演示", "Claude / Anthropic", "https://api.anthropic.com", "https://claude.com/platform/api"),
            ("Gemini · 演示", "Gemini / Google", "https://generativelanguage.googleapis.com/v1beta", "https://ai.google.dev/gemini-api"),
            ("DeepSeek · 演示", "DeepSeek", "https://api.deepseek.com", "https://api-docs.deepseek.com"),
            ("Kimi · 演示", "Kimi / Moonshot", "https://api.moonshot.cn/v1", "https://platform.kimi.com")
        ]
        var entries = providers.enumerated().map { index, item in
            return entry(number: index + 1, name: item.0, category: .ai,
                         provider: item.1, baseURL: item.2,
                         website: item.3, tags: ["演示", "AI 模型"],
                         isFavorite: index == 0)
        }
        entries.append(entry(number: 6, name: "资料搜索 Skill · 演示", category: .skill,
                             provider: "自定义搜索 Skill", baseURL: "https://search.example.test/v1",
                             website: "https://search.example.test", tags: ["演示", "搜索", "Skill"],
                             isFavorite: true))
        entries.append(entry(number: 7, name: "开发服务 · 演示", category: .service,
                             provider: "示例开发服务", baseURL: "https://api.example.test/v1",
                             website: "https://developer.example.test", tags: ["演示", "开发环境"]))
        return VaultDocument(entries: entries)
    }

    private static func tool(number: Int, name: String, notes: String, templateID: String? = nil) -> ToolGroup {
        let date = Date(timeIntervalSince1970: 1_790_121_600 + Double(number))
        return ToolGroup(id: toolID(number: number),
                         name: name, notes: notes, templateID: templateID, createdAt: date, updatedAt: date)
    }

    private static func toolID(number: Int) -> UUID {
        let suffix = String(format: "%012d", number)
        return UUID(uuidString: "D3A10000-0000-4000-8000-\(suffix)")!
    }

    private static func entry(number: Int, name: String, category: EntryCategory,
                              provider: String, baseURL: String, website: String,
                              tags: [String], isFavorite: Bool = false, toolIDs: [UUID] = [],
                              environment: String = "", accountLabel: String = "") -> SecretEntry {
        let suffix = String(format: "%012d", number)
        // The format above has exactly twelve decimal digits for all fixtures.
        let id = UUID(uuidString: "D3A00000-0000-4000-8000-\(suffix)")!
        let date = Date(timeIntervalSince1970: 1_790_121_600 + Double(number))
        return SecretEntry(
            id: id, name: name, category: category, provider: provider,
            secret: String(format: "demo-only-not-a-real-key-%03d", number),
            baseURL: baseURL, website: website, tags: tags,
            notes: "这是虚构的演示收藏，密钥无效，不属于任何真实账户。请勿在演示库保存真实密钥。额度查询已禁用；点击来源网站会打开默认浏览器。",
            isFavorite: isFavorite, quotaProvider: .none, quota: nil,
            createdAt: date, updatedAt: date, toolIDs: toolIDs,
            environment: environment, accountLabel: accountLabel
        )
    }
}
