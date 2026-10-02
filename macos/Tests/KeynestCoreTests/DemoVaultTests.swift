import Foundation
import XCTest
@testable import KeynestCore

final class DemoVaultTests: XCTestCase {
    func testDemoProfileHasAnExplicitSeparateNameAndPublicPassword() {
        XCTAssertEqual(DemoVault.directoryName, "Keynest Demo")
        XCTAssertNotEqual(DemoVault.directoryName, "Keynest")
        XCTAssertFalse(DemoVault.directoryName.contains("/"))
        XCTAssertEqual(DemoVault.password, "Keynest-Demo-2026")
        XCTAssertTrue(DemoVault.password.count >= 12)
        XCTAssertEqual(DemoVault.catalogRevision, 7)
    }

    func testEverySampleIsClearlyFictionalAndQuotaIsDisabled() {
        let entries = DemoVault.document().entries
        XCTAssertEqual(entries.count, 34)
        for (index, entry) in entries.enumerated() {
            XCTAssertEqual(entry.secret, String(format: "demo-only-not-a-real-key-%03d", index + 1))
            XCTAssertTrue(entry.name.contains("演示"))
            XCTAssertTrue(entry.tags.contains("演示"))
            XCTAssertTrue(entry.notes.contains("虚构"))
            XCTAssertTrue(entry.notes.contains("密钥无效"))
            XCTAssertTrue(entry.notes.contains("请勿"))
            XCTAssertEqual(entry.quotaProvider, .none)
            XCTAssertNil(entry.quota)
            XCTAssertThrowsError(try QuotaClient.request(for: entry)) {
                XCTAssertEqual($0 as? QuotaError, .unsupportedProvider)
            }
        }
    }

    func testModelSamplesUseTheCurrentLocalPresetMetadata() throws {
        let entries = DemoVault.document().entries
        for id in ["openai", "anthropic", "google", "deepseek", "kimi"] {
            let preset = try XCTUnwrap(ProviderPreset.all.first { $0.id == id })
            let entry = try XCTUnwrap(entries.first { $0.provider == preset.name })
            XCTAssertEqual(entry.category, .ai)
            XCTAssertEqual(entry.website, preset.website)
            XCTAssertEqual(entry.baseURL, preset.baseURL)
        }
    }

    func testCustomExamplesUseReservedTestDomainsAndUsefulCategories() throws {
        let entries = DemoVault.document().entries
        for category in [EntryCategory.skill, .service] {
            let entry = try XCTUnwrap(entries.first { $0.category == category })
            XCTAssertNil(ProviderPreset.match(provider: entry.provider))
            for address in [entry.website, entry.baseURL] {
                let components = try XCTUnwrap(URLComponents(string: address))
                XCTAssertEqual(components.scheme, "https")
                XCTAssertTrue(components.host?.hasSuffix(".example.test") == true)
                XCTAssertNil(components.user)
                XCTAssertNil(components.password)
                XCTAssertNil(components.query)
            }
        }
        XCTAssertEqual(Set(entries.map(\.category)), Set([.ai, .skill, .service]))
        XCTAssertTrue(entries.contains { $0.isFavorite })
        XCTAssertTrue(entries.contains { !$0.isFavorite })
    }

    func testTheFixtureIsValidDeterministicAndIndependentOnEveryCall() throws {
        let first = DemoVault.document()
        let second = DemoVault.document()
        XCTAssertEqual(first.entries, second.entries)
        XCTAssertEqual(first.tools, second.tools)
        XCTAssertEqual(Set(first.entries.map(\.id)).count, first.entries.count)
        XCTAssertEqual(try first.validated().entries, first.entries)
        for (index, entry) in first.entries.enumerated() {
            let suffix = String(format: "%012d", index + 1)
            XCTAssertEqual(entry.id.uuidString, "D3A00000-0000-4000-8000-\(suffix)")
        }
        var edited = first
        edited.entries[0].secret = "demo-only-edited-fixture"
        edited.entries[0].notes = "A local edit must not modify the bundled seed."
        XCTAssertEqual(DemoVault.document().entries, second.entries)
        XCTAssertNotEqual(edited.entries, second.entries)
    }

    func testDemoPasswordEncryptsAndReopensTheSamplesWithoutPlaintext() throws {
        let original = DemoVault.document()
        let session = try VaultCodec.createSession(password: DemoVault.password)
        let data = try VaultCodec.encrypt(original, session: session)
        let encoded = String(decoding: data, as: UTF8.self)
        for entry in original.entries {
            XCTAssertFalse(encoded.contains(entry.secret))
            XCTAssertFalse(encoded.contains(entry.name))
        }
        let reopened = try VaultCodec.decrypt(data, password: DemoVault.password)
        XCTAssertEqual(reopened.document.entries, original.entries)
        XCTAssertEqual(reopened.document.tools, original.tools)
    }

    func testToolScenariosIncludeSharedCredentialsAndSameProviderEnvironments() throws {
        let document = try DemoVault.document().validated()
        XCTAssertEqual(document.tools.count, 10)
        XCTAssertTrue(document.entries.contains { $0.toolIDs.count > 1 })
        XCTAssertTrue(document.tools.allSatisfy { tool in document.entries.contains { $0.toolIDs.contains(tool.id) } })
        let openai = document.entries.filter { $0.provider == "ChatGPT / OpenAI" }
        XCTAssertEqual(openai.count, 2)
        XCTAssertEqual(Set(openai.map(\.environment)), Set(["正式", "开发"]))
        XCTAssertEqual(Set(openai.map(\.accountLabel)).count, 2)
        XCTAssertNotEqual(openai[0].secret, openai[1].secret)
    }

    private func legacyFixture() -> VaultDocument {
        let entries = DemoVault.document().entries.prefix(7).map { original -> SecretEntry in
            var entry = original
            entry.toolIDs = []; entry.environment = ""; entry.accountLabel = ""
            return entry
        }
        var legacy = VaultDocument(entries: entries)
        legacy.version = 1
        return legacy
    }

    private func catalog05Fixture() -> VaultDocument {
        let old = catalog06Fixture()
        return VaultDocument(entries: Array(old.entries.prefix(9)), tools: Array(old.tools.prefix(3)))
    }

    private func catalog06Fixture() -> VaultDocument {
        let latest = DemoVault.document()
        let tools = Array(latest.tools.prefix(6))
        let toolIDs = Set(tools.map(\.id))
        let entries = latest.entries.prefix(24).map { entry -> SecretEntry in
            var original = entry
            original.toolIDs = original.toolIDs.filter { toolIDs.contains($0) }
            return original
        }
        return VaultDocument(entries: entries, tools: tools)
    }

    func testEnrichmentUpgradesUntouchedLegacyFixturesAndIsIdempotent() throws {
        let original = legacyFixture()
        let enriched = try DemoVault.enriching(original)
        let seed = catalog05Fixture()
        XCTAssertEqual(enriched.entries, seed.entries)
        XCTAssertEqual(enriched.tools, seed.tools)
        let repeated = try DemoVault.enriching(enriched)
        XCTAssertEqual(repeated.entries, enriched.entries)
        XCTAssertEqual(repeated.tools, enriched.tools)
        XCTAssertEqual(original.entries.count, 7)
        XCTAssertEqual(original.tools, [])
        XCTAssertTrue(original.entries.allSatisfy { $0.toolIDs.isEmpty && $0.environment.isEmpty && $0.accountLabel.isEmpty })
    }

    func testEnrichmentPreservesEveryEditedExistingSample() throws {
        var edited = DemoVault.document()
        for index in edited.entries.indices {
            edited.entries[index].name = "用户自定义 \(index)"
            edited.entries[index].notes = "用户自己的备注"
            edited.entries[index].accountLabel = "用户账户"
            edited.entries[index].environment = "用户环境"
            edited.entries[index].toolIDs = []
        }
        for index in edited.tools.indices { edited.tools[index].notes = "用户修改的工具说明" }
        let enriched = try DemoVault.enriching(edited)
        XCTAssertEqual(enriched.entries, edited.entries)
        XCTAssertEqual(enriched.tools, edited.tools)
    }

    func testAnyLegacyFieldEditPreventsWholeEntryReplacement() throws {
        let changes: [(inout SecretEntry) -> Void] = [
            { $0.name = "用户名称" }, { $0.provider = "用户平台" },
            { $0.secret = "user-fixture-secret" }, { $0.category = .other },
            { $0.baseURL = "https://custom.example.test/v1" },
            { $0.website = "https://custom.example.test" }, { $0.tags = ["用户标签"] },
            { $0.notes = "用户备注" }, { $0.isFavorite.toggle() },
            { $0.createdAt = $0.createdAt.addingTimeInterval(1) },
            { $0.updatedAt = $0.updatedAt.addingTimeInterval(1) },
            { $0.environment = "自定义" }, { $0.accountLabel = "自定义" }
        ]
        for change in changes {
            var original = legacyFixture()
            change(&original.entries[0])
            let enriched = try DemoVault.enriching(original)
            XCTAssertEqual(enriched.entries.first { $0.id == original.entries[0].id }, original.entries[0])
        }
        var linked = legacyFixture()
        let custom = ToolGroup(name: "用户已有工具")
        linked.tools = [custom]; linked.entries[0].toolIDs = [custom.id]
        let enriched = try DemoVault.enriching(linked)
        XCTAssertEqual(enriched.entries[0], linked.entries[0])
        XCTAssertEqual(enriched.tools.first { $0.id == custom.id }, custom)
    }

    func testEnrichmentKeepsIDConflictsAndSkipsTheirSampleAssociations() throws {
        let seed = DemoVault.document()
        var original = legacyFixture()
        var conflictingTool = seed.tools[0]; conflictingTool.name = "我的同 ID 工具"
        original.tools = [conflictingTool]
        var conflictingEntry = seed.entries[7]
        conflictingEntry.name = "我的同 ID 密钥"; conflictingEntry.toolIDs = []
        original.entries.append(conflictingEntry)
        original.entries.remove(at: 1) // A deleted old Claude sample must not return.
        let enriched = try DemoVault.enriching(original)
        XCTAssertEqual(enriched.tools.first { $0.id == conflictingTool.id }, conflictingTool)
        XCTAssertEqual(enriched.entries.first { $0.id == conflictingEntry.id }, conflictingEntry)
        XCTAssertNil(enriched.entries.first { $0.id == seed.entries[1].id })
        XCTAssertTrue(enriched.entries.allSatisfy { !$0.toolIDs.contains(conflictingTool.id) })
        XCTAssertTrue(enriched.entries.allSatisfy { $0.quotaProvider == .none && $0.quota == nil })
        XCTAssertNoThrow(try enriched.validated())
        let repeated = try DemoVault.enriching(enriched)
        XCTAssertEqual(repeated.entries, enriched.entries)
        XCTAssertEqual(repeated.tools, enriched.tools)
    }

    func testNewExamplesCoverModelsAndEveryRequestedAPICapability() throws {
        let latest = DemoVault.document()
        let expectedIDs = ["qwen", "openrouter", "tavily", "brave", "firecrawl", "jina", "replicate",
                           "fal", "elevenlabs", "cartesia", "amap", "openweather", "github", "cloudflare", "resend"]
        for (index, id) in expectedIDs.enumerated() {
            let preset = try XCTUnwrap(ProviderPreset.match(provider: id))
            let entry = latest.entries[index + 9]
            XCTAssertEqual(entry.provider, preset.name)
            XCTAssertEqual(entry.website, preset.website)
            XCTAssertEqual(entry.baseURL, preset.baseURL)
            XCTAssertFalse(entry.toolIDs.isEmpty)
            XCTAssertFalse(entry.environment.isEmpty)
            XCTAssertFalse(entry.accountLabel.isEmpty)
        }
        let tags = Set(latest.entries.flatMap(\.tags))
        for capability in ["AI 模型", "搜索", "网页采集", "图像", "语音", "地图", "天气", "开发", "消息"] {
            XCTAssertTrue(tags.contains(capability))
        }
        XCTAssertEqual(latest.tools.prefix(6).map(\.name), ["研究助手", "内容工作台", "个人自动化", "语音助手", "旅行助手", "开发运维"])
    }

    func testCatalogMigrationFrom05AddsOnlyTheNewRevisionAndIsIdempotent() throws {
        let old = catalog05Fixture()
        let latest = DemoVault.document()
        let upgraded = try DemoVault.upgradingCatalog(old, fromRevision: 5)
        XCTAssertEqual(upgraded.entries, latest.entries)
        XCTAssertEqual(upgraded.tools, latest.tools)
        let oldToolIDs = Set(old.tools.map(\.id))
        let originalFields = upgraded.entries.prefix(9).map { entry -> SecretEntry in
            var original = entry
            original.toolIDs = original.toolIDs.filter { oldToolIDs.contains($0) }
            return original
        }
        XCTAssertEqual(originalFields, old.entries)
        XCTAssertEqual(Array(upgraded.tools.prefix(3)), old.tools)
        let repeated = try DemoVault.upgradingCatalog(upgraded, fromRevision: 5)
        XCTAssertEqual(repeated.entries, upgraded.entries)
        XCTAssertEqual(repeated.tools, upgraded.tools)
        XCTAssertEqual(old.entries.count, 9)
        XCTAssertEqual(old.tools.count, 3)
    }

    func testCatalogRevisionWorksForCurrentPayloadWithoutAFormatUpgrade() throws {
        let old = catalog05Fixture()
        let session = try VaultCodec.createSession(password: DemoVault.password)
        let reopened = try VaultCodec.decrypt(VaultCodec.encrypt(old, session: session), password: DemoVault.password)
        XCTAssertFalse(reopened.requiresUpgrade)
        XCTAssertEqual(reopened.document.version, 3)
        let upgraded = try DemoVault.upgradingCatalog(reopened.document, fromRevision: 5)
        XCTAssertEqual(upgraded.entries.count, 34)
        XCTAssertEqual(upgraded.version, 3)
    }

    func testCatalogMigrationFrom05PreservesAllUserChangesAndCustomRecords() throws {
        var original = catalog05Fixture()
        for index in original.entries.indices {
            original.entries[index].name = "用户收藏 \(index)"
            original.entries[index].secret = "user-edited-fixture-\(index)"
            original.entries[index].notes = "用户备注"
            original.entries[index].provider = "用户自定义提供商"
            original.entries[index].baseURL = "https://custom.example.test/v1"
            original.entries[index].website = "https://custom.example.test"
            original.entries[index].tags = ["用户标签"]
            original.entries[index].category = .other
            original.entries[index].isFavorite.toggle()
            original.entries[index].environment = "沙盒"
            original.entries[index].accountLabel = "自己的账户"
            original.entries[index].createdAt = original.entries[index].createdAt.addingTimeInterval(100)
            original.entries[index].updatedAt = original.entries[index].updatedAt.addingTimeInterval(200)
            original.entries[index].toolIDs = []
        }
        for index in original.tools.indices {
            original.tools[index].name = "用户工具 \(index)"
            original.tools[index].notes = "用户的工具说明"
        }
        let customTool = ToolGroup(name: "自己的工具")
        original.tools.append(customTool)
        let customEntry = SecretEntry(name: "自己的收藏", secret: "fictional-user-key", toolIDs: [customTool.id])
        original.entries.append(customEntry)
        let upgraded = try DemoVault.upgradingCatalog(original, fromRevision: 5)
        for entry in original.entries { XCTAssertEqual(upgraded.entries.first { $0.id == entry.id }, entry) }
        for tool in original.tools { XCTAssertEqual(upgraded.tools.first { $0.id == tool.id }, tool) }
        let oldToolIDs = Set(original.tools.map(\.id))
        XCTAssertTrue(upgraded.entries.dropFirst(original.entries.count).allSatisfy { Set($0.toolIDs).isDisjoint(with: oldToolIDs) })
    }

    func testCatalogMigrationDoesNotResurrectDeleted05SamplesOrTools() throws {
        var original = catalog05Fixture()
        let deletedEntries = Set([original.entries[0].id, original.entries[7].id, original.entries[8].id])
        original.entries.removeAll { deletedEntries.contains($0.id) }
        let deletedTool = original.tools[0].id
        original = try original.removingTool(id: deletedTool)
        let upgraded = try DemoVault.upgradingCatalog(original, fromRevision: 5)
        XCTAssertTrue(upgraded.entries.allSatisfy { !deletedEntries.contains($0.id) })
        XCTAssertNil(upgraded.tools.first { $0.id == deletedTool })
        XCTAssertTrue(upgraded.entries.allSatisfy { !$0.toolIDs.contains(deletedTool) })
        XCTAssertEqual(Array(upgraded.entries.prefix(original.entries.count)), original.entries)
        XCTAssertNoThrow(try upgraded.validated())

        let empty = try DemoVault.upgradingCatalog(VaultDocument(), fromRevision: 5)
        XCTAssertEqual(empty.entries.count, 25)
        XCTAssertEqual(empty.tools.count, 7)
        XCTAssertTrue(empty.entries.allSatisfy { Set($0.toolIDs).isSubset(of: Set(empty.tools.map(\.id))) })
    }

    func testCatalogMigrationKeepsNewIDConflictsAndRejectsTheirAssociations() throws {
        let seed = DemoVault.document()
        var original = catalog05Fixture()
        var conflictingTool = seed.tools[3]
        conflictingTool.notes = "这个 ID 已被我的工具使用"
        original.tools.append(conflictingTool)
        var conflictingEntry = seed.entries[9]
        conflictingEntry.name = "这个 ID 已被我的收藏使用"
        conflictingEntry.secret = "user-id-conflict-fixture"
        conflictingEntry.toolIDs = [conflictingTool.id]
        original.entries.append(conflictingEntry)
        let upgraded = try DemoVault.upgradingCatalog(original, fromRevision: 5)
        XCTAssertEqual(upgraded.tools.first { $0.id == conflictingTool.id }, conflictingTool)
        XCTAssertEqual(upgraded.entries.first { $0.id == conflictingEntry.id }, conflictingEntry)
        XCTAssertTrue(upgraded.entries.filter { $0.id != conflictingEntry.id }.allSatisfy { !$0.toolIDs.contains(conflictingTool.id) })
        let repeated = try DemoVault.upgradingCatalog(upgraded, fromRevision: 5)
        XCTAssertEqual(repeated.entries, upgraded.entries)
        XCTAssertEqual(repeated.tools, upgraded.tools)
    }

    func testCurrentOrFutureRevisionNeverAddsDeletedExamplesAgain() throws {
        var original = DemoVault.document()
        original.entries.remove(at: 24)
        original = try original.removingTool(id: original.tools[9].id)
        for revision in [DemoVault.catalogRevision, DemoVault.catalogRevision + 1] {
            let unchanged = try DemoVault.upgradingCatalog(original, fromRevision: revision)
            XCTAssertEqual(unchanged.entries, original.entries)
            XCTAssertEqual(unchanged.tools, original.tools)
        }
    }

    func testCatalogUpgradeReadsLegacyV1FieldsAndChainsBothMigrations() throws {
        let old = legacyFixture()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        payload["version"] = 1
        payload.removeValue(forKey: "tools")
        var entries = try XCTUnwrap(payload["entries"] as? [[String: Any]])
        for index in entries.indices {
            for key in ["toolIDs", "environment", "accountLabel"] { entries[index].removeValue(forKey: key) }
        }
        payload["entries"] = entries
        let decoded = try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.entries, old.entries)
        let upgraded = try DemoVault.upgradingCatalog(decoded, fromRevision: 4)
        XCTAssertEqual(upgraded.entries, DemoVault.document().entries)
        XCTAssertEqual(upgraded.tools, DemoVault.document().tools)
        XCTAssertEqual(upgraded.version, 3)
    }

    func testCatalogUpgradeFrom04RetainsEditedAndDeletedLegacyEntries() throws {
        var old = legacyFixture()
        let deletedID = old.entries.remove(at: 1).id
        old.entries[0].notes = "我修改过旧演示"
        let edited = old.entries[0]
        let upgraded = try DemoVault.upgradingCatalog(old, fromRevision: 4)
        XCTAssertNil(upgraded.entries.first { $0.id == deletedID })
        XCTAssertEqual(upgraded.entries.first { $0.id == edited.id }, edited)
        XCTAssertEqual(upgraded.entries.count, 33)
        XCTAssertEqual(upgraded.tools.count, 10)
        XCTAssertTrue(upgraded.entries.allSatisfy { $0.quotaProvider == .none && $0.quota == nil })
        XCTAssertNoThrow(try upgraded.validated())
    }

    func test07AddsBrandedToolsAndSkillAgentExamplesWithNoQuotaRequests() throws {
        let latest = DemoVault.document()
        XCTAssertEqual(latest.tools.suffix(4).compactMap(\.templateID), ["cline", "openclaw", "n8n", "langgraph"])
        XCTAssertTrue(latest.tools.prefix(6).allSatisfy { $0.templateID == nil })
        for tool in latest.tools.suffix(4) {
            XCTAssertNotEqual(ToolTemplate.match(templateID: try XCTUnwrap(tool.templateID)), nil)
            XCTAssertTrue(latest.entries.contains { $0.toolIDs.contains(tool.id) })
        }
        let ids = ["context7", "browserbase", "apify", "composio", "mem0", "langsmith", "qdrant", "perplexity", "notion", "github"]
        for (index, id) in ids.enumerated() {
            let entry = latest.entries[index + 24]
            let preset = try XCTUnwrap(ProviderPreset.match(provider: id))
            XCTAssertEqual(entry.provider, preset.name)
            XCTAssertEqual(entry.baseURL, preset.baseURL)
            XCTAssertEqual(entry.website, preset.website)
            XCTAssertEqual(entry.quotaProvider, .none)
            XCTAssertNil(entry.quota)
            XCTAssertFalse(entry.toolIDs.isEmpty)
        }
        XCTAssertEqual(latest.entries.suffix(10).filter { $0.category == .skill }.count, 5)
        XCTAssertTrue(latest.entries.suffix(10).contains { $0.tags.contains("Agent 工具") })
    }

    func test06To07MigrationReusesOnlyPristineModelFixturesAndIsIdempotent() throws {
        let old = catalog06Fixture()
        let upgraded = try DemoVault.upgradingCatalog(old, fromRevision: 6)
        let expected = DemoVault.document()
        XCTAssertEqual(upgraded.entries, expected.entries)
        XCTAssertEqual(upgraded.tools, expected.tools)
        let reusableNumbers = Set([1, 2, 11])
        for index in old.entries.indices {
            var observed = upgraded.entries[index]
            if reusableNumbers.contains(index + 1) {
                XCTAssertTrue(observed.toolIDs.count > old.entries[index].toolIDs.count)
                observed.toolIDs = old.entries[index].toolIDs
            }
            XCTAssertEqual(observed, old.entries[index])
        }
        let repeated = try DemoVault.upgradingCatalog(upgraded, fromRevision: 6)
        XCTAssertEqual(repeated.entries, upgraded.entries)
        XCTAssertEqual(repeated.tools, upgraded.tools)
        XCTAssertEqual(old.entries.count, 24)
        XCTAssertEqual(old.tools.count, 6)
    }

    func test06To07MigrationPreservesAllEditedOldRecordsAndTools() throws {
        var edited = catalog06Fixture()
        for index in edited.entries.indices {
            edited.entries[index].notes = "用户改过的备注 \(index)"
            edited.entries[index].environment = "用户环境"
            edited.entries[index].accountLabel = "用户账户"
        }
        for index in edited.tools.indices { edited.tools[index].name = "用户工具 \(index)" }
        let upgraded = try DemoVault.upgradingCatalog(edited, fromRevision: 6)
        XCTAssertEqual(Array(upgraded.entries.prefix(24)), edited.entries)
        XCTAssertEqual(Array(upgraded.tools.prefix(6)), edited.tools)
        XCTAssertEqual(upgraded.entries.count, 34)
        XCTAssertEqual(upgraded.tools.count, 10)
    }

    func testAnyModelFixtureEditPrevents07AssociationChanges() throws {
        let changes: [(inout SecretEntry) -> Void] = [
            { $0.name = "用户名称" }, { $0.provider = "用户平台" },
            { $0.secret = "user-edited-fixture" }, { $0.category = .other },
            { $0.baseURL = "https://custom.example.test/v1" },
            { $0.website = "https://custom.example.test" }, { $0.tags = ["用户标签"] },
            { $0.notes = "用户备注" }, { $0.isFavorite.toggle() },
            { $0.createdAt = $0.createdAt.addingTimeInterval(1) },
            { $0.updatedAt = $0.updatedAt.addingTimeInterval(1) },
            { $0.environment = "自定义" }, { $0.accountLabel = "自定义" },
            { $0.toolIDs = [] }, { $0.quotaProvider = .openrouter }
        ]
        for index in [0, 1, 10] {
            for change in changes {
                var old = catalog06Fixture()
                change(&old.entries[index])
                let upgraded = try DemoVault.upgradingCatalog(old, fromRevision: 6)
                XCTAssertEqual(upgraded.entries.first { $0.id == old.entries[index].id }, old.entries[index])
            }
        }
    }

    func test06To07DoesNotResurrectDeletedPriorExamplesOrTools() throws {
        var old = catalog06Fixture()
        let deletedIDs = Set([old.entries[0].id, old.entries[1].id, old.entries[10].id, old.entries[23].id])
        old.entries.removeAll { deletedIDs.contains($0.id) }
        let deletedTool = old.tools[5].id
        old = try old.removingTool(id: deletedTool)
        let upgraded = try DemoVault.upgradingCatalog(old, fromRevision: 6)
        XCTAssertTrue(upgraded.entries.allSatisfy { !deletedIDs.contains($0.id) })
        XCTAssertNil(upgraded.tools.first { $0.id == deletedTool })
        XCTAssertEqual(Array(upgraded.entries.prefix(old.entries.count)), old.entries)
        let empty = try DemoVault.upgradingCatalog(VaultDocument(), fromRevision: 6)
        XCTAssertEqual(empty.entries.count, 10)
        XCTAssertEqual(empty.tools.count, 4)
        XCTAssertEqual(Set(empty.entries.map(\.id)), Set(DemoVault.document().entries.suffix(10).map(\.id)))
        XCTAssertNoThrow(try empty.validated())
    }

    func test07IDConflictsKeepUserValuesAndDoNotGainForeignLinks() throws {
        let seed = DemoVault.document()
        var old = catalog06Fixture()
        var conflictTool = seed.tools[6]
        conflictTool.templateID = "openclaw"
        conflictTool.notes = "我自己的工具"
        old.tools.append(conflictTool)
        var conflictEntry = seed.entries[24]
        conflictEntry.secret = "user-conflict-fixture"
        conflictEntry.toolIDs = [old.tools[0].id]
        old.entries.append(conflictEntry)
        let upgraded = try DemoVault.upgradingCatalog(old, fromRevision: 6)
        XCTAssertEqual(upgraded.tools.first { $0.id == conflictTool.id }, conflictTool)
        XCTAssertEqual(upgraded.entries.first { $0.id == conflictEntry.id }, conflictEntry)
        XCTAssertTrue(upgraded.entries.allSatisfy { !$0.toolIDs.contains(conflictTool.id) })
        XCTAssertEqual(upgraded.entries[10], old.entries[10])
        let repeated = try DemoVault.upgradingCatalog(upgraded, fromRevision: 6)
        XCTAssertEqual(repeated.entries, upgraded.entries)
        XCTAssertEqual(repeated.tools, upgraded.tools)
    }

    func test06PayloadV2WithoutTemplateFieldsUpgradesCatalogSafely() throws {
        let old = catalog06Fixture()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        payload["version"] = 2
        var tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        for index in tools.indices { tools[index].removeValue(forKey: "templateID") }
        payload["tools"] = tools
        let decoded = try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.entries, old.entries)
        XCTAssertEqual(decoded.tools, old.tools)
        let upgraded = try DemoVault.upgradingCatalog(decoded, fromRevision: 6)
        XCTAssertEqual(upgraded.entries, DemoVault.document().entries)
        XCTAssertEqual(upgraded.tools, DemoVault.document().tools)
        XCTAssertEqual(upgraded.version, 3)
    }
}
