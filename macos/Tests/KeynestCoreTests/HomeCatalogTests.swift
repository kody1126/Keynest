import Foundation
import XCTest
@testable import KeynestCore

final class HomeCatalogTests: XCTestCase {
    private func entry(_ number: Int, provider: String, category: EntryCategory = .ai,
                       favorite: Bool = false, updatedAt: TimeInterval = 100) -> SecretEntry {
        SecretEntry(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
                    name: "密钥 \(number)", category: category, provider: provider,
                    secret: "fixture-only-secret-\(number)", isFavorite: favorite,
                    createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    private func ids(_ groups: [HomeProviderGroup]) -> Set<UUID> {
        Set(groups.flatMap(\.entries).map(\.id))
    }

    func testKnownAliasesShareCanonicalGroupWithoutLosingMultipleKeysOrMetadata() throws {
        var first = entry(1, provider: "OpenAI")
        first.accountLabel = "个人账户"; first.environment = "开发"
        var second = entry(2, provider: "ＣＨＡＴＧＰＴ", favorite: true)
        second.accountLabel = "工作账户"; second.environment = "生产"
        let third = entry(3, provider: " Chat GPT ")
        let source = [first, second, third]
        let groups = HomeCatalog.groups(entries: source)
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.id, "openai")
        XCTAssertEqual(group.preset?.id, "openai")
        XCTAssertEqual(group.name, ProviderPreset.match(provider: "openai")?.name)
        XCTAssertEqual(group.entries.count, 3)
        XCTAssertEqual(group.entries.map(\.id), [second.id, first.id, third.id])
        for original in source {
            XCTAssertEqual(group.entries.first { $0.id == original.id }, original)
        }
        XCTAssertEqual(source, [first, second, third])
    }

    func testCustomNamesMergeOnlyCaseAndOuterWhitespaceVariants() throws {
        let source = [
            entry(1, provider: "  Acme Cloud  "), entry(2, provider: "acme cloud"),
            entry(3, provider: "Acme-Cloud"), entry(4, provider: "AcmeCloud"),
            entry(5, provider: "Acme  Cloud"), entry(6, provider: "Acmé Cloud"),
            entry(7, provider: "My OpenAI proxy"), entry(8, provider: "OpenAI")
        ]
        let groups = HomeCatalog.groups(entries: source)
        XCTAssertEqual(groups.count, 7)
        let acme = try XCTUnwrap(groups.first { $0.id == "custom:acme cloud" })
        XCTAssertEqual(ids([acme]), Set([source[0].id, source[1].id]))
        XCTAssertEqual(acme.name, "Acme Cloud")
        XCTAssertNil(acme.preset)
        XCTAssertEqual(groups.first { $0.id == "openai" }?.entries.map(\.id), [source[7].id])
        let proxy = try XCTUnwrap(groups.first { $0.entries.contains { $0.id == source[6].id } })
        XCTAssertNil(proxy.preset)
        XCTAssertEqual(proxy.entries.count, 1)
        XCTAssertEqual(HomeCatalog.groups(entries: Array(source.reversed())), groups)
    }

    func testBlankProvidersAreSeparateGroupsNamedAfterTheirEntries() throws {
        var first = entry(1, provider: "")
        var second = entry(2, provider: " \n\t ")
        first.name = "未注明平台 A"; second.name = "未注明平台 B"
        let groups = HomeCatalog.groups(entries: [first, second])
        XCTAssertEqual(groups.count, 2)
        for original in [first, second] {
            let group = try XCTUnwrap(groups.first { $0.id == "entry:\(original.id.uuidString)" })
            XCTAssertNil(group.preset)
            XCTAssertEqual(group.name, original.name)
            XCTAssertEqual(group.entries, [original])
        }
    }

    func testEmptyOrWhitespaceSearchIncludesAllRecordsAndEmptyInputIsEmpty() {
        let source = [entry(1, provider: "OpenAI"), entry(2, provider: "Resend", category: .service),
                      entry(3, provider: "自己的服务", category: .other)]
        let all = HomeCatalog.groups(entries: source)
        XCTAssertEqual(ids(all), Set(source.map(\.id)))
        XCTAssertEqual(HomeCatalog.groups(entries: source, query: " \n\t　"), all)
        XCTAssertEqual(HomeCatalog.groups(entries: []), [])
        XCTAssertEqual(HomeCatalog.groups(entries: [], query: "anything", scope: .favorites), [])
    }

    func testModelAndServiceScopesUseKnownProviderPurposeThenUnknownEntryCategory() {
        let source = [
            entry(1, provider: "OpenAI", category: .skill),
            entry(2, provider: "ElevenLabs", category: .service),
            entry(3, provider: "Tavily", category: .ai),
            entry(4, provider: "Context7", category: .ai),
            entry(5, provider: "自建推理平台", category: .ai),
            entry(6, provider: "自建工作流", category: .skill),
            entry(7, provider: "Resend", category: .other)
        ]
        let models = ids(HomeCatalog.groups(entries: source, scope: .models))
        let services = ids(HomeCatalog.groups(entries: source, scope: .services))
        XCTAssertEqual(models, Set([source[0].id, source[1].id, source[4].id]))
        XCTAssertEqual(services, Set([source[2].id, source[3].id, source[5].id, source[6].id]))
        XCTAssertTrue(models.isDisjoint(with: services))
        XCTAssertEqual(models.union(services), Set(source.map(\.id)))
    }

    func testFavoritesScopeIncludesOnlyFavoriteEntriesWithinSharedProvider() throws {
        let first = entry(1, provider: "OpenAI", favorite: true)
        let hidden = entry(2, provider: "ChatGPT")
        let service = entry(3, provider: "Resend", favorite: true)
        let groups = HomeCatalog.groups(entries: [hidden, service, first], scope: .favorites)
        XCTAssertEqual(ids(groups), Set([first.id, service.id]))
        XCTAssertEqual(groups.map(\.id), ["openai", "resend"])
        XCTAssertEqual(try XCTUnwrap(groups.first).entries, [first])
        XCTAssertEqual(HomeCatalog.groups(entries: [hidden], scope: .favorites), [])
    }

    func testSearchANDMatchesSafeMetadataToolsAndCanonicalAliases() {
        let tool = ToolGroup(name: "写作助手")
        var matching = entry(1, provider: "OpenAI")
        matching.name = "公司凭据"; matching.accountLabel = "Alice@example.test"
        matching.environment = "生产"; matching.tags = ["内容", "每日"]
        matching.toolIDs = [tool.id]
        let other = entry(2, provider: "OpenAI")
        let source = [matching, other]
        for query in ["公司", "alice@", "生产", "内容 每日", "写作助手", "ChatGPT",
                      "ChatGPT 公司 ALICE 生产 内容 写作"] {
            let groups = HomeCatalog.groups(entries: source, tools: [tool], query: query)
            if query == "ChatGPT" {
                XCTAssertEqual(ids(groups), Set(source.map(\.id)))
            } else {
                XCTAssertEqual(ids(groups), Set([matching.id]), query)
            }
        }
        XCTAssertEqual(HomeCatalog.groups(entries: source, tools: [tool], query: "公司 缺失词"), [])
        XCTAssertEqual(HomeCatalog.groups(entries: source, query: "写作助手"), [])
        XCTAssertEqual(HomeCatalog.groups(entries: source, tools: [tool], query: "写作助手", scope: .services), [])
    }

    func testFilteringBeforeGroupingNeverAddsNonmatchingAccountsOrTools() throws {
        let workTool = ToolGroup(name: "工作助手")
        let privateTool = ToolGroup(name: "个人助手")
        var work = entry(1, provider: "OpenAI")
        work.accountLabel = "工作"; work.environment = "生产"; work.toolIDs = [workTool.id]
        var personal = entry(2, provider: "ChatGPT")
        personal.accountLabel = "个人"; personal.environment = "开发"; personal.toolIDs = [privateTool.id]
        let source = [work, personal]
        let tools = [workTool, privateTool]
        let allPlatform = HomeCatalog.groups(entries: source, tools: tools, query: "openai")
        XCTAssertEqual(allPlatform.count, 1)
        XCTAssertEqual(try XCTUnwrap(allPlatform.first).entries.count, 2)
        XCTAssertEqual(ids(HomeCatalog.groups(entries: source, tools: tools, query: "openai 工作")), Set([work.id]))
        XCTAssertEqual(ids(HomeCatalog.groups(entries: source, tools: tools, query: "ChatGPT 开发")), Set([personal.id]))
        XCTAssertEqual(HomeCatalog.groups(entries: source, tools: tools, query: "工作 个人助手"), [])
        XCTAssertEqual(source, [work, personal])
    }

    func testSearchNeverReadsSecretURLsNotesOrQuotaAndDoesNotGuessASecretProvider() {
        let tool = ToolGroup(name: "普通工具", notes: "tool-note-sensitive-marker")
        var value = entry(1, provider: "OpenAI")
        value.secret = "credential-material-sensitive-marker"
        value.baseURL = "https://url-sensitive-marker.example.test/v1"
        value.website = "https://website-sensitive-marker.example.test"
        value.notes = "entry-note-sensitive-marker"; value.toolIDs = [tool.id]
        value.quota = QuotaSnapshot(kind: "balance", metrics: [QuotaMetric(label: "quota-sensitive-marker", value: "123")],
                                   note: "quota-note-sensitive-marker")
        for query in ["credential-material-sensitive-marker", "sensitive-marker", "url-sensitive-marker",
                      "website-sensitive-marker", "entry-note-sensitive-marker", "tool-note-sensitive-marker",
                      "quota-sensitive-marker", "quota-note-sensitive-marker", "OpenAI credential-material",
                      value.id.uuidString, tool.id.uuidString] {
            XCTAssertEqual(HomeCatalog.groups(entries: [value], tools: [tool], query: query), [], query)
        }
        var unlabelled = entry(2, provider: "")
        unlabelled.secret = "OpenAI ChatGPT sk-fixture-only"
        XCTAssertEqual(HomeCatalog.groups(entries: [unlabelled], query: "OpenAI"), [])
        XCTAssertNil(HomeCatalog.groups(entries: [unlabelled]).first?.preset)
    }

    func testSearchFoldsCaseWidthAndDiacriticsAcrossMultipleTokens() {
        var value = entry(1, provider: "OpenAI")
        value.name = "Café 项目"; value.accountLabel = "ÉLODIE"; value.environment = "ＰＲＯＤ"
        let groups = HomeCatalog.groups(entries: [value], query: "ＣＨＡＴＧＰＴ cafe ELODIE prod")
        XCTAssertEqual(ids(groups), Set([value.id]))
        XCTAssertEqual(HomeCatalog.groups(entries: [value], query: "café staging"), [])
    }

    func testGroupsSortModelsThenFavoritesThenNameWithStableIDTies() {
        let source = [
            entry(1, provider: "Zeta", category: .ai, favorite: true),
            entry(2, provider: "Alpha", category: .ai),
            entry(3, provider: "Omega", category: .service, favorite: true),
            entry(4, provider: "Aardvark", category: .service),
            entry(5, provider: "Café", category: .service),
            entry(6, provider: "Cafe", category: .service)
        ]
        let groups = HomeCatalog.groups(entries: source)
        XCTAssertEqual(groups.map(\.id), ["custom:zeta", "custom:alpha", "custom:omega", "custom:aardvark", "custom:cafe", "custom:café"])
        XCTAssertEqual(HomeCatalog.groups(entries: Array(source.reversed())), groups)
        XCTAssertEqual(HomeCatalog.groups(entries: Array(source.dropFirst()) + [source[0]]), groups)
    }

    func testEntriesSortFavoriteThenNewestThenUUIDWithoutDiscardingEqualValues() throws {
        let first = entry(1, provider: "OpenAI", updatedAt: 100)
        let second = entry(2, provider: "OpenAI", updatedAt: 100)
        let newest = entry(3, provider: "OpenAI", updatedAt: 200)
        let favorite = entry(4, provider: "OpenAI", favorite: true, updatedAt: 1)
        let source = [second, first, favorite, newest]
        let groups = HomeCatalog.groups(entries: source)
        XCTAssertEqual(try XCTUnwrap(groups.first).entries.map(\.id), [favorite.id, newest.id, first.id, second.id])
        XCTAssertEqual(HomeCatalog.groups(entries: Array(source.reversed())), groups)
        XCTAssertEqual(ids(groups), Set(source.map(\.id)))
    }

    func testUnknownMixedCategoryProviderFiltersRecordsBeforeClassifyingGroups() throws {
        let model = entry(1, provider: "自建平台", category: .ai)
        let skill = entry(2, provider: "自建平台", category: .skill)
        let service = entry(3, provider: "AAA service", category: .service, favorite: true)
        let source = [service, skill, model]
        let all = HomeCatalog.groups(entries: source)
        XCTAssertEqual(all.first?.name, "自建平台")
        XCTAssertEqual(all.first?.entries.count, 2)
        XCTAssertEqual(ids(HomeCatalog.groups(entries: source, scope: .models)), Set([model.id]))
        let services = HomeCatalog.groups(entries: source, scope: .services)
        XCTAssertEqual(ids(services), Set([skill.id, service.id]))
        let custom = try XCTUnwrap(services.first { $0.name == "自建平台" })
        XCTAssertEqual(custom.entries, [skill])
    }

    func testScopesExposeStableIDsAndCurrentUIVocabulary() {
        XCTAssertEqual(HomeScope.allCases.map(\.id), ["all", "models", "services", "favorites"])
        XCTAssertEqual(HomeScope.allCases.map(\.title), ["全部", "模型", "Skill 与服务", "常用"])
    }

    func testExplicitOrderMovesOnlyListedGroupsAndKeepsRemainingDefaultOrder() {
        let source = [entry(1, provider: "OpenAI"), entry(2, provider: "Claude"),
                      entry(3, provider: "Resend"), entry(4, provider: "Private service")]
        let groups = HomeCatalog.groups(entries: source)
        let order = ["resend", "custom:private service"]
        let ordered = HomeCatalog.ordered(groups, by: order)
        XCTAssertEqual(ordered.map(\.id), order + groups.filter { !order.contains($0.id) }.map(\.id))
        XCTAssertEqual(ids(ordered), Set(source.map(\.id)))
        for group in groups { XCTAssertEqual(ordered.first { $0.id == group.id }, group) }
        XCTAssertEqual(HomeCatalog.ordered(groups, by: nil), groups)
        XCTAssertEqual(HomeCatalog.ordered(groups, by: []), groups)
    }

    func testOrderingFilteredGroupsNeverRestoresHiddenCredentialsOrMissingProviders() {
        var first = entry(1, provider: "OpenAI"); first.accountLabel = "private"
        var second = entry(2, provider: "OpenAI"); second.accountLabel = "work"
        let other = entry(3, provider: "Resend")
        let groups = HomeCatalog.groups(entries: [first, second, other], query: "work")
        let ordered = HomeCatalog.ordered(groups, by: ["resend", "custom:deleted", "openai"])
        XCTAssertEqual(ordered.map(\.id), ["openai"])
        XCTAssertEqual(ids(ordered), [second.id])
        XCTAssertEqual(HomeCatalog.ordered([], by: ["openai"]), [])
    }

    func testOrderingDefensivelyHandlesDuplicateAndUnknownHintsWithoutDuplicatingGroups() {
        let groups = HomeCatalog.groups(entries: [entry(1, provider: "OpenAI"), entry(2, provider: "Resend")])
        let ordered = HomeCatalog.ordered(groups, by: ["unknown", "resend", "resend", "openai"])
        XCTAssertEqual(ordered.map(\.id), ["resend", "openai"])
        XCTAssertEqual(ordered.count, groups.count)
    }
}
