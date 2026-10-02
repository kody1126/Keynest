import Foundation
import XCTest
@testable import KeynestCore

final class ProviderPresetTests: XCTestCase {
    func testStableIdentifiersAndCommonUseOrder() {
        XCTAssertEqual(Array(ProviderPreset.all.prefix(12).map(\.id)), [
            "openai", "anthropic", "google", "deepseek", "qwen", "kimi",
            "doubao", "glm", "minimax", "xai", "siliconflow", "openrouter"
        ])
        XCTAssertEqual(Set(ProviderPreset.all.map(\.id)).count, ProviderPreset.all.count)
        XCTAssertEqual(ProviderPreset.all.count, 61)
    }

    func testEveryPresetRemainsOfflineByDefault() {
        for preset in ProviderPreset.all {
            XCTAssertEqual(preset.quotaProvider, .none, preset.id)
            XCTAssertNil(preset.quotaProvider.endpoint, preset.id)
            XCTAssertEqual(preset.iconFilename, "\(preset.id).png")
        }
    }

    func testAllPresetValuesFitExistingEntrySchema() throws {
        for preset in ProviderPreset.all {
            let entry = SecretEntry(name: "示例", provider: preset.name, secret: "fixture-only",
                                    baseURL: preset.baseURL, website: preset.website,
                                    quotaProvider: preset.quotaProvider)
            XCTAssertEqual(try entry.validated(), entry, preset.id)
            for value in [preset.baseURL, preset.website] where !value.isEmpty {
                let url = try XCTUnwrap(URLComponents(string: value))
                XCTAssertEqual(url.scheme, "https", preset.id)
                XCTAssertNil(url.query, preset.id)
                XCTAssertNil(url.fragment, preset.id)
                XCTAssertNil(url.user, preset.id)
                XCTAssertNil(url.password, preset.id)
            }
        }
    }

    func testEveryPresetHasALocalBrandPNGAndANativeFallback() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let iconDirectory = packageRoot.appendingPathComponent("Resources/ProviderIcons")
        XCTAssertEqual(ProviderPreset.all.filter(\.hasBundledIcon).count, ProviderPreset.all.count)
        for preset in ProviderPreset.all {
            XCTAssertFalse(preset.fallbackSymbol.isEmpty, preset.id)
            guard preset.hasBundledIcon else { continue }
            let data = try Data(contentsOf: iconDirectory.appendingPathComponent(preset.iconFilename))
            XCTAssertTrue(data.count > 24, preset.id)
            XCTAssertEqual(data.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]), preset.id)
        }
    }

    func testOfficialOriginsAndRegionalEndpoints() {
        let expected = [
            "openai": "https://api.openai.com/v1",
            "anthropic": "https://api.anthropic.com",
            "google": "https://generativelanguage.googleapis.com/v1beta",
            "xai": "https://api.x.ai/v1",
            "deepseek": "https://api.deepseek.com",
            "qwen": "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "doubao": "https://ark.cn-beijing.volces.com/api/v3",
            "kimi": "https://api.moonshot.cn/v1",
            "glm": "https://open.bigmodel.cn/api/paas/v4",
            "minimax": "https://api.minimax.cn/v1",
            "siliconflow": "https://api.siliconflow.cn/v1",
            "openrouter": "https://openrouter.ai/api/v1"
        ]
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: ProviderPreset.all.prefix(12).map { ($0.id, $0.baseURL) }), expected)
    }

    func testWebsitesArePublicAPIEntrancesSeparateFromRequestEndpoints() {
        let expected = [
            "openai": "https://openai.com/api/",
            "anthropic": "https://claude.com/platform/api",
            "google": "https://ai.google.dev/gemini-api",
            "deepseek": "https://api-docs.deepseek.com",
            "qwen": "https://www.aliyun.com/product/bailian",
            "kimi": "https://platform.kimi.com",
            "doubao": "https://www.volcengine.com/product/ark",
            "glm": "https://bigmodel.cn",
            "minimax": "https://platform.minimax.cn",
            "xai": "https://x.ai/api",
            "siliconflow": "https://siliconflow.cn",
            "openrouter": "https://openrouter.ai"
        ]
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: ProviderPreset.all.prefix(12).map { ($0.id, $0.website) }), expected)
        for preset in ProviderPreset.all {
            XCTAssertNotEqual(preset.website, preset.baseURL, preset.id)
            XCTAssertFalse(preset.website.contains("api-keys"), preset.id)
            XCTAssertFalse(preset.website.contains("/settings/"), preset.id)
            XCTAssertFalse(preset.website.contains("/login"), preset.id)
        }
    }

    func testKnownSavedProviderNamesAndAliasesMatchExactly() {
        for preset in ProviderPreset.all {
            for name in [preset.id, preset.name] + preset.aliases {
                XCTAssertEqual(ProviderPreset.match(provider: name)?.id, preset.id, name)
            }
        }
        XCTAssertEqual(ProviderPreset.match(provider: "  ＯＰＥＮＡＩ \n")?.id, "openai")
        XCTAssertEqual(ProviderPreset.match(provider: "Claude / Anthropic")?.id, "anthropic")
        XCTAssertEqual(ProviderPreset.match(provider: "deep-seek")?.id, "deepseek")
        XCTAssertEqual(ProviderPreset.match(provider: "硅基流动")?.id, "siliconflow")
    }

    func testMatchingDoesNotGuessCustomGatewaysOrCredentials() {
        for value in ["", "  ", "---", "OpenAI-compatible proxy", "My Claude gateway",
                      "https://api.openai.com/v1", "api.openai.com.evil.example",
                      "sk-openai-fixture-only", "sk-ant-fixture-only", "AI", "Open"] {
            XCTAssertNil(ProviderPreset.match(provider: value), value)
        }
    }

    func testSearchIncludesNamesAndAliases() throws {
        let openai = try XCTUnwrap(ProviderPreset.match(provider: "OpenAI"))
        let qwen = try XCTUnwrap(ProviderPreset.match(provider: "Qwen"))
        XCTAssertTrue(openai.matches(search: "ChatGPT"))
        XCTAssertTrue(openai.matches(search: "open ai"))
        XCTAssertTrue(openai.matches(search: "ＣＨＡＴＧＰＴ"))
        XCTAssertTrue(qwen.matches(search: "百炼"))
        XCTAssertTrue(qwen.matches(search: "QWEN 百炼"))
        XCTAssertFalse(qwen.matches(search: "Qwen Claude"))
        XCTAssertTrue(ProviderPreset.all.allSatisfy { $0.matches(search: " \n") })
        XCTAssertFalse(openai.matches(search: "---"))
    }

    func testSearchDoesNotIncludeCountryMetadata() {
        for query in ["中国", "美国", "China", "United States"] {
            XCTAssertTrue(ProviderPreset.all.allSatisfy { !$0.matches(search: query) }, query)
        }
    }

    func testFunctionalGroupsAreCompleteAndPreserveStoredCategories() {
        let counts: [ProviderPresetGroup: Int] = [.languageModels: 18, .media: 8, .search: 9, .agentTools: 6, .development: 13, .communication: 7]
        XCTAssertEqual(counts.count, ProviderPresetGroup.allCases.count)
        for group in ProviderPresetGroup.allCases {
            XCTAssertEqual(ProviderPreset.all.filter { $0.group == group }.count, counts[group])
            XCTAssertFalse(group.title.isEmpty)
            XCTAssertFalse(group.symbol.isEmpty)
        }
        for preset in ProviderPreset.all {
            XCTAssertFalse(preset.summary.isEmpty, preset.id)
            XCTAssertFalse(preset.usageHint.isEmpty, preset.id)
            let expected: EntryCategory = preset.group == .agentTools ? .skill : [.languageModels, .media].contains(preset.group) ? .ai : .service
            XCTAssertEqual(preset.suggestedCategory, expected, preset.id)
        }
    }

    func testProjectAndUnverifiedPublicEndpointsRemainBlank() throws {
        let supabase = try XCTUnwrap(ProviderPreset.match(provider: "supabase"))
        XCTAssertEqual(supabase.baseURL, "")
        XCTAssertTrue(supabase.usageHint.contains("每个项目"))
        XCTAssertTrue(supabase.usageHint.contains("/rest/v1"))
        let serper = try XCTUnwrap(ProviderPreset.match(provider: "serper"))
        XCTAssertEqual(serper.baseURL, "")
        XCTAssertTrue(serper.usageHint.contains("Playground"))
        for preset in ProviderPreset.all {
            XCTAssertFalse(preset.baseURL.contains("<"), preset.id)
            XCTAssertFalse(preset.baseURL.contains("{"), preset.id)
        }
    }

    func testNewCommonServiceEndpointsAndPurposeSearch() throws {
        let endpoints = [
            "together": "https://api.together.ai/v1", "fal": "https://queue.fal.run",
            "firecrawl": "https://api.firecrawl.dev/v2", "github": "https://api.github.com",
            "cloudflare": "https://api.cloudflare.com/client/v4", "resend": "https://api.resend.com",
            "jina": "https://r.jina.ai", "cartesia": "https://api.cartesia.ai",
            "amap": "https://restapi.amap.com/v3", "openweather": "https://api.openweathermap.org/data/2.5"
        ]
        for (id, endpoint) in endpoints {
            XCTAssertEqual(ProviderPreset.match(provider: id)?.baseURL, endpoint, id)
        }
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "elevenlabs")).matches(search: "语音"))
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "tavily")).matches(search: "搜索"))
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "github")).matches(search: "开发"))
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "resend")).matches(search: "邮件"))
        XCTAssertFalse(try XCTUnwrap(ProviderPreset.match(provider: "github")).matches(search: "邮件"))
    }

    func testMatchingDoesNotModifyAnExistingCustomEntry() throws {
        let entry = SecretEntry(name: "个人网关", provider: "OpenAI", secret: "fixture-only",
                                baseURL: "https://gateway.example/v1", website: "https://gateway.example")
        _ = ProviderPreset.match(provider: entry.provider)
        let decoded = try JSONDecoder().decode(SecretEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(decoded.baseURL, "https://gateway.example/v1")
        XCTAssertEqual(decoded.website, "https://gateway.example")
        XCTAssertEqual(decoded.quotaProvider, .none)
    }

    func testAgentServicesPreserveIndependentCredentialsAndProjectAddresses() throws {
        let agentIDs: Set<String> = ["browserbase", "browserless", "context7", "composio", "mem0", "zep"]
        XCTAssertEqual(Set(ProviderPreset.all.filter { $0.group == .agentTools }.map(\.id)), agentIDs)
        XCTAssertEqual(ProviderPresetGroup.agentTools.title, "Agent 工具")
        for id in agentIDs {
            let preset = try XCTUnwrap(ProviderPreset.match(provider: id))
            XCTAssertEqual(preset.suggestedCategory, .skill)
            XCTAssertTrue(preset.matches(search: "Agent"))
            XCTAssertEqual(preset.quotaProvider, .none)
        }
        for id in ["qdrant", "pinecone", "weaviate"] {
            let preset = try XCTUnwrap(ProviderPreset.match(provider: id))
            XCTAssertEqual(preset.baseURL, "", "Project-specific hosts must not be guessed")
            XCTAssertFalse(preset.usageHint.isEmpty)
        }
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "browserbase")).usageHint.contains("Project ID"))
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "langfuse")).usageHint.contains("Public Key + Secret Key"))
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "composio")).usageHint.contains("各自授权"))
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "browserless")).usageHint.contains("勿把密钥存进地址"))
    }

    func testCurrentAgentAPIEndpointsAndLegacyNamesRemainDiscoverable() throws {
        let expected = [
            "perplexity": "https://api.perplexity.ai", "apify": "https://api.apify.com/v2",
            "browserbase": "https://api.browserbase.com/v1", "browserless": "https://production-sfo.browserless.io",
            "parallel": "https://api.parallel.ai", "context7": "https://context7.com/api",
            "composio": "https://backend.composio.dev/api/v3", "mem0": "https://api.mem0.ai",
            "langsmith": "https://api.smith.langchain.com", "langfuse": "https://cloud.langfuse.com/api/public",
            "zep": "https://api.getzep.com"
        ]
        for (id, endpoint) in expected {
            XCTAssertEqual(ProviderPreset.match(provider: id)?.baseURL, endpoint)
        }
        let perplexity = try XCTUnwrap(ProviderPreset.match(provider: "Sonar"))
        XCTAssertEqual(perplexity.id, "perplexity")
        XCTAssertTrue(perplexity.usageHint.contains("Agent API"))
        XCTAssertEqual(perplexity.group, .search)
        XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: "parallel")).usageHint.contains("/v1/search"))
    }
}
