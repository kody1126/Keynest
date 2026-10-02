import XCTest
import Foundation
@testable import KeynestCore

final class PresetApplicationTests: XCTestCase {
    private func savedEntry(provider: String = "自建服务") -> SecretEntry {
        SecretEntry(
            name: "项目 A · 开发环境", category: .skill, provider: provider,
            secret: "test-only-user-secret", baseURL: "https://relay.example.test/v1",
            website: "https://console.example.test/keys", tags: ["开发", "项目 A"],
            notes: "手动记录的用途与轮换日期", isFavorite: true,
            quotaProvider: .deepseek,
            quota: QuotaSnapshot(kind: "balance", metrics: [QuotaMetric(label: "余额", value: "8.50", currency: "CNY")], fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_650_000_000),
            toolIDs: [UUID(uuidString: "D5D660D8-52F3-4A0A-B813-AE72DB59AB13")!],
            environment: "开发", accountLabel: "个人账号"
        )
    }

    private func assertUserContentPreserved(_ result: SecretEntry, from entry: SecretEntry, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.id, entry.id, file: file, line: line)
        XCTAssertEqual(result.secret, entry.secret, file: file, line: line)
        XCTAssertEqual(result.notes, entry.notes, file: file, line: line)
        XCTAssertEqual(result.tags, entry.tags, file: file, line: line)
        XCTAssertEqual(result.category, entry.category, file: file, line: line)
        XCTAssertEqual(result.isFavorite, entry.isFavorite, file: file, line: line)
        XCTAssertEqual(result.createdAt, entry.createdAt, file: file, line: line)
        XCTAssertEqual(result.updatedAt, entry.updatedAt, file: file, line: line)
        XCTAssertEqual(result.toolIDs, entry.toolIDs, file: file, line: line)
        XCTAssertEqual(result.environment, entry.environment, file: file, line: line)
        XCTAssertEqual(result.accountLabel, entry.accountLabel, file: file, line: line)
    }

    func testEveryPresetFillsAnEmptyDraftWithoutAuthorizingQuotaRequests() throws {
        XCTAssertFalse(ProviderPreset.all.isEmpty)
        let entry = SecretEntry(secret: "test-only-existing-secret")
        for preset in ProviderPreset.all {
            let result = preset.applying(to: entry)
            XCTAssertEqual(result.name, preset.name)
            XCTAssertEqual(result.provider, preset.name)
            XCTAssertEqual(result.baseURL, preset.baseURL)
            XCTAssertEqual(result.website, preset.website)
            XCTAssertEqual(result.secret, entry.secret)
            XCTAssertEqual(result.quotaProvider, .none)
            XCTAssertNil(result.quota)
            XCTAssertThrowsError(try QuotaClient.request(for: result)) {
                XCTAssertEqual($0 as? QuotaError, .unsupportedProvider)
            }
        }
    }

    func testSwitchingReplacesOnlyThePreviousPresetMetadata() throws {
        let first = try XCTUnwrap(ProviderPreset.all.first)
        let next = try XCTUnwrap(ProviderPreset.all.first { $0.id != first.id })
        var entry = savedEntry(provider: first.name)
        entry.name = first.name
        entry.website = first.website
        entry.baseURL = first.baseURL

        let result = next.applying(to: entry)

        XCTAssertEqual(result.name, next.name)
        XCTAssertEqual(result.provider, next.name)
        XCTAssertEqual(result.website, next.website)
        XCTAssertEqual(result.baseURL, next.baseURL)
        assertUserContentPreserved(result, from: entry)
        XCTAssertEqual(result.quotaProvider, .none)
        XCTAssertNil(result.quota)
    }

    func testCustomNameURLsAndContextSurviveEveryPresetSwitch() throws {
        let first = try XCTUnwrap(ProviderPreset.all.first)
        let original = savedEntry(provider: first.name)
        var draft = original

        for preset in ProviderPreset.all {
            draft = preset.applying(to: draft)
            XCTAssertEqual(draft.name, original.name)
            XCTAssertEqual(draft.baseURL, original.baseURL)
            XCTAssertEqual(draft.website, original.website)
            assertUserContentPreserved(draft, from: original)
        }
        XCTAssertEqual(original.provider, first.name)
        XCTAssertEqual(original.quotaProvider, .deepseek)
        XCTAssertEqual(original.quota?.metrics.first?.value, "8.50")
    }

    func testUnrecognizedProviderKeepsUserFieldsAndDisablesQuota() throws {
        let preset = try XCTUnwrap(ProviderPreset.all.first)
        let original = savedEntry()

        let result = preset.applying(to: original)

        XCTAssertEqual(result.provider, preset.name)
        XCTAssertEqual(result.name, original.name)
        XCTAssertEqual(result.baseURL, original.baseURL)
        XCTAssertEqual(result.website, original.website)
        assertUserContentPreserved(result, from: original)
        XCTAssertEqual(result.quotaProvider, .none)
        XCTAssertNil(result.quota)
    }

    func testPartiallyCustomizedFieldsAreHandledIndependently() throws {
        let first = try XCTUnwrap(ProviderPreset.all.first)
        let next = try XCTUnwrap(ProviderPreset.all.first { $0.id != first.id })
        var entry = savedEntry(provider: first.name)
        entry.name = " \n\t"
        entry.website = first.website

        let result = next.applying(to: entry)

        XCTAssertEqual(result.name, next.name)
        XCTAssertEqual(result.website, next.website)
        XCTAssertEqual(result.baseURL, entry.baseURL)
        assertUserContentPreserved(result, from: entry)

        entry.name = "用户自定义名称"
        entry.website = "https://custom.example.test"
        entry.baseURL = ""
        let other = next.applying(to: entry)
        XCTAssertEqual(other.name, entry.name)
        XCTAssertEqual(other.website, entry.website)
        XCTAssertEqual(other.baseURL, next.baseURL)
    }

    func testSwitchingClearsAllKindsOfPreviouslyEnabledQuota() throws {
        let first = try XCTUnwrap(ProviderPreset.all.first)
        let next = try XCTUnwrap(ProviderPreset.all.first { $0.id != first.id })
        for quotaProvider in QuotaProvider.allCases where quotaProvider != .none {
            var entry = savedEntry(provider: first.name)
            entry.quotaProvider = quotaProvider

            let result = next.applying(to: entry)

            XCTAssertEqual(result.quotaProvider, .none)
            XCTAssertNil(result.quota)
            XCTAssertEqual(result.secret, entry.secret)
            XCTAssertThrowsError(try QuotaClient.request(for: result)) {
                XCTAssertEqual($0 as? QuotaError, .unsupportedProvider)
            }
        }
    }

    func testOnlyPristineDefaultDraftReceivesCategorySuggestion() throws {
        for preset in ProviderPreset.all {
            let fresh = SecretEntry()
            XCTAssertEqual(preset.applying(to: fresh).category, preset.suggestedCategory, preset.id)
            for category in [EntryCategory.skill, .service, .other] {
                let customized = SecretEntry(category: category)
                XCTAssertEqual(preset.applying(to: customized).category, category, preset.id)
            }
            for entry in [SecretEntry(secret: "fixture-only"), SecretEntry(notes: "保留备注"),
                          SecretEntry(name: "我的收藏"), SecretEntry(environment: "正式"),
                          SecretEntry(accountLabel: "我的账号"), SecretEntry(tags: ["工作"])] {
                XCTAssertEqual(preset.applying(to: entry).category, entry.category, preset.id)
            }
        }
    }

    func testProjectSpecificPresetDoesNotEraseCustomAddress() throws {
        let preset = try XCTUnwrap(ProviderPreset.match(provider: "supabase"))
        let entry = savedEntry()
        let result = preset.applying(to: entry)
        XCTAssertEqual(result.baseURL, entry.baseURL)
        assertUserContentPreserved(result, from: entry)
        let empty = preset.applying(to: SecretEntry())
        XCTAssertEqual(empty.baseURL, "")
        XCTAssertEqual(empty.category, .service)
        XCTAssertEqual(empty.quotaProvider, .none)
    }

    func testReselectingTheSamePresetPreservesIntentionalSettings() throws {
        let preset = try XCTUnwrap(ProviderPreset.all.first)
        let original = savedEntry(provider: preset.name)

        let result = preset.applying(to: original)

        XCTAssertEqual(result, original)
    }

    func testAgentTemplateSuggestsSkillWithoutChangingSavedContext() throws {
        for preset in ProviderPreset.all where preset.group == .agentTools {
            let original = savedEntry()
            let result = preset.applying(to: original)
            assertUserContentPreserved(result, from: original)
            XCTAssertEqual(result.baseURL, original.baseURL)
            XCTAssertEqual(result.website, original.website)
            XCTAssertEqual(preset.applying(to: SecretEntry()).category, .skill)
            XCTAssertEqual(result.quotaProvider, .none)
            XCTAssertNil(result.quota)
        }
    }

    func testVectorDatabasePresetsNeverInventOrReplaceProjectHosts() throws {
        for id in ["qdrant", "pinecone", "weaviate"] {
            let preset = try XCTUnwrap(ProviderPreset.match(provider: id))
            let entry = savedEntry()
            XCTAssertEqual(preset.applying(to: SecretEntry()).baseURL, "")
            XCTAssertEqual(preset.applying(to: entry).baseURL, entry.baseURL)
            XCTAssertEqual(preset.applying(to: entry).secret, entry.secret)
        }
    }
}
