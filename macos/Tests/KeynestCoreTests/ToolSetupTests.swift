import Foundation
import XCTest
@testable import KeynestCore

final class ToolSetupTests: XCTestCase {
    private func credential(toolIDs: [UUID] = []) -> SecretEntry {
        SecretEntry(name: "工作项目 · 已修改名称", category: .other, provider: "OpenAI",
                    secret: "fixture-only-original-secret", baseURL: "https://relay.example.test/v1",
                    website: "https://console.example.test/keys", tags: ["工作", "手动分类"],
                    notes: "用户自己的备注与轮换安排", isFavorite: true, quotaProvider: .openrouter,
                    quota: QuotaSnapshot(kind: "key_limit", metrics: [QuotaMetric(label: "余额", value: "9.50", currency: "USD")],
                                         note: "保留缓存", fetchedAt: Date(timeIntervalSince1970: 1_700_000_050)),
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
                    toolIDs: toolIDs, environment: "生产", accountLabel: "work@example.test")
    }

    private func snapshot(_ document: VaultDocument) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    private func assertFailureLeavesSourceUnchanged(_ source: VaultDocument, template: String = "continue",
                                                   name: String = "新工具", selections: [ToolCredentialSelection],
                                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let before = try snapshot(source)
        XCTAssertThrowsError(try source.addingTool(templateID: template, name: name, selections: selections), file: file, line: line)
        XCTAssertEqual(try snapshot(source), before, file: file, line: line)
    }

    func testReuseLinksOneEntityAndPreservesEveryCustomizedField() throws {
        let oldTool = ToolGroup(name: "已有工具", notes: "原有备注")
        let entry = credential(toolIDs: [oldTool.id])
        let source = VaultDocument(entries: [entry], tools: [oldTool])
        let before = try snapshot(source)

        let result = try source.addingTool(templateID: "continue", name: "  我的 Continue  ", selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: entry.id,
                                    secret: "must-not-replace-the-secret", baseURL: "https://must-not-replace.example.test")
        ])

        XCTAssertEqual(result.tool.name, "我的 Continue")
        XCTAssertEqual(result.tool.templateID, "continue")
        XCTAssertEqual(result.document.tools, [oldTool, result.tool])
        XCTAssertEqual(result.document.entries.count, 1)
        var linked = try XCTUnwrap(result.document.entries.first)
        XCTAssertEqual(linked.toolIDs, [oldTool.id, result.tool.id])
        XCTAssertLessThan(entry.updatedAt, linked.updatedAt)
        linked.toolIDs = entry.toolIDs; linked.updatedAt = entry.updatedAt
        XCTAssertEqual(linked, entry)
        XCTAssertEqual(try snapshot(source), before)
    }

    func testSameExistingCredentialAcrossTwoRolesIsNeitherCopiedNorLinkedTwice() throws {
        let entry = credential()
        let result = try VaultDocument(entries: [entry]).addingTool(templateID: "continue", name: "共享用途", selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: entry.id),
            ToolCredentialSelection(slotID: "embedding", providerID: "openai", existingEntryID: entry.id)
        ])
        XCTAssertEqual(result.document.entries.count, 1)
        XCTAssertEqual(result.document.entries.first?.id, entry.id)
        XCTAssertEqual(result.document.entries.first?.secret, entry.secret)
        XCTAssertEqual(result.document.entries.first?.toolIDs, [result.tool.id])
    }

    func testOptionalSlotsOffDoNotCreateBlankCredentials() throws {
        let result = try VaultDocument().addingTool(templateID: "n8n", name: "内容流程", selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", secret: "fixture-only-model",
                                    baseURL: "https://api.example.test/v1")
        ])
        XCTAssertEqual(result.document.tools.count, 1)
        XCTAssertEqual(result.document.entries.count, 1)
        XCTAssertEqual(result.document.entries.first?.provider, try XCTUnwrap(ProviderPreset.match(provider: "openai")).name)
        XCTAssertEqual(result.document.entries.first?.secret, "fixture-only-model")
        XCTAssertEqual(result.document.entries.first?.toolIDs, [result.tool.id])
        XCTAssertFalse(result.document.entries.contains { $0.provider == "Firecrawl" || $0.provider == "Resend" })
    }

    func testNewAgentCredentialsAreSavedTogetherWithoutEnablingQuota() throws {
        let result = try VaultDocument().addingTool(templateID: "voice-assistant", name: "语音助手", selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", secret: "fixture-only-model",
                                    baseURL: "https://models.example.test/v1"),
            ToolCredentialSelection(slotID: "speech", providerID: "elevenlabs", secret: "fixture-only-speech",
                                    baseURL: "https://speech.example.test/v1"),
            ToolCredentialSelection(slotID: "transcription", providerID: "deepgram", secret: "fixture-only-transcription",
                                    baseURL: "https://transcription.example.test/v1")
        ])
        XCTAssertEqual(result.document.tools, [result.tool])
        XCTAssertEqual(result.tool.templateID, "voice-assistant")
        XCTAssertEqual(result.document.entries.count, 3)
        XCTAssertEqual(Set(result.document.entries.map(\.id)).count, 3)
        XCTAssertEqual(result.document.entries.map(\.secret), ["fixture-only-model", "fixture-only-speech", "fixture-only-transcription"])
        XCTAssertEqual(result.document.entries.map(\.baseURL), ["https://models.example.test/v1", "https://speech.example.test/v1", "https://transcription.example.test/v1"])
        for entry in result.document.entries {
            XCTAssertEqual(entry.toolIDs, [result.tool.id])
            XCTAssertEqual(entry.category, try XCTUnwrap(ProviderPreset.match(provider: entry.provider)).suggestedCategory)
            XCTAssertEqual(entry.quotaProvider, .none)
            XCTAssertNil(entry.quota)
            XCTAssertFalse(entry.website.isEmpty)
        }
    }

    func testSkillRecipeCreatesSkillCategoryWithoutChangingProviderDetails() throws {
        let preset = try XCTUnwrap(ProviderPreset.match(provider: "tavily"))
        let result = try VaultDocument().addingTool(templateID: "web-search-skill", name: "搜索能力", selections: [
            ToolCredentialSelection(slotID: "search", providerID: preset.id, secret: "fixture-only-search", baseURL: preset.baseURL)
        ])
        let entry = try XCTUnwrap(result.document.entries.first)
        XCTAssertEqual(entry.category, .skill)
        XCTAssertEqual(entry.provider, preset.name)
        XCTAssertEqual(entry.website, preset.website)
        XCTAssertEqual(entry.baseURL, preset.baseURL)
        XCTAssertEqual(entry.tags, ["Skill"])
        XCTAssertEqual(entry.quotaProvider, .none)
        XCTAssertEqual(entry.toolIDs, [result.tool.id])
    }

    func testMixedExistingAndNewCredentialsPreserveUnrelatedEntriesAndTools() throws {
        let oldTool = ToolGroup(name: "已有流程")
        let existing = credential(toolIDs: [oldTool.id])
        let unrelated = SecretEntry(name: "无关密钥", provider: "自建服务", secret: "fixture-only-unrelated")
        let source = VaultDocument(entries: [existing, unrelated], tools: [oldTool])
        let result = try source.addingTool(templateID: "n8n", name: "工作流", selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: existing.id),
            ToolCredentialSelection(slotID: "email", providerID: "resend", secret: "fixture-only-mail",
                                    baseURL: "https://mail.example.test")
        ])
        XCTAssertEqual(result.document.entries.count, 3)
        XCTAssertEqual(result.document.entries.filter { $0.id == existing.id }.count, 1)
        XCTAssertEqual(result.document.entries.first { $0.id == unrelated.id }, unrelated)
        XCTAssertEqual(result.document.tools, [oldTool, result.tool])
        let created = try XCTUnwrap(result.document.entries.first { $0.secret == "fixture-only-mail" })
        XCTAssertEqual(created.provider, "Resend")
        XCTAssertEqual(created.toolIDs, [result.tool.id])
        XCTAssertEqual(created.quotaProvider, .none)
        XCTAssertEqual(source.entries, [existing, unrelated])
        XCTAssertEqual(source.tools, [oldTool])
    }

    func testMissingRequiredRoleRejectsTheWholeSetup() throws {
        let source = VaultDocument(entries: [credential()])
        try assertFailureLeavesSourceUnchanged(source, selections: [])
        try assertFailureLeavesSourceUnchanged(source, template: "voice-assistant", selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", secret: "fixture-only-model")
        ])
        try assertFailureLeavesSourceUnchanged(source, selections: [
            ToolCredentialSelection(slotID: "embedding", providerID: "openai", secret: "fixture-only-embedding")
        ])
    }

    func testDuplicateAndUnknownSlotsAreRejectedBeforeAnyCreation() throws {
        let source = VaultDocument()
        let model = ToolCredentialSelection(slotID: "model", providerID: "openai", secret: "fixture-only-model")
        try assertFailureLeavesSourceUnchanged(source, selections: [model, model])
        try assertFailureLeavesSourceUnchanged(source, selections: [model,
            ToolCredentialSelection(slotID: "unexpected", providerID: "openai", secret: "fixture-only-other")
        ])
    }

    func testWrongProviderCannotSatisfyASlotOrRelabelAnExistingCredential() throws {
        let entry = credential()
        let source = VaultDocument(entries: [entry])
        try assertFailureLeavesSourceUnchanged(source, selections: [
            ToolCredentialSelection(slotID: "model", providerID: "resend", secret: "fixture-only-wrong-provider")
        ])
        try assertFailureLeavesSourceUnchanged(source, selections: [
            ToolCredentialSelection(slotID: "model", providerID: "anthropic", existingEntryID: entry.id)
        ])
        var custom = entry; custom.provider = "OpenAI 私有网关"
        try assertFailureLeavesSourceUnchanged(VaultDocument(entries: [custom]), selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: custom.id)
        ])
    }

    func testStaleExistingIDDoesNotCreateAReplacementSecret() throws {
        let source = VaultDocument(entries: [credential()])
        try assertFailureLeavesSourceUnchanged(source, selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: UUID(),
                                    secret: "must-not-become-a-new-entry")
        ])
    }

    func testLaterInvalidSecretOrURLLeavesEarlierValidReuseUntouched() throws {
        let entry = credential()
        let source = VaultDocument(entries: [entry])
        let model = ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: entry.id)
        for selection in [
            ToolCredentialSelection(slotID: "embedding", providerID: "openai", secret: " \n\t"),
            ToolCredentialSelection(slotID: "embedding", providerID: "openai", secret: "fixture-only-embedding",
                                    baseURL: "https://api.example.test/v1?api_key=must-not-enter-address")
        ] {
            try assertFailureLeavesSourceUnchanged(source, selections: [model, selection])
        }
        XCTAssertEqual(source.entries.first, entry)
    }

    func testLaterStaleSelectionDoesNotRetainAnEarlierNewSecret() throws {
        try assertFailureLeavesSourceUnchanged(VaultDocument(), template: "voice-assistant", selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", secret: "fixture-only-earlier-valid"),
            ToolCredentialSelection(slotID: "speech", providerID: "elevenlabs", existingEntryID: UUID())
        ])
    }

    func testTwentiethToolLinkSucceedsAndTwentyFirstFailsAtomically() throws {
        let oldTools = (0..<19).map { ToolGroup(name: "现有工具 \($0)") }
        let entry = credential(toolIDs: oldTools.map(\.id))
        let result = try VaultDocument(entries: [entry], tools: oldTools).addingTool(
            templateID: "continue", name: "第 20 个工具", selections: [
                ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: entry.id)
            ])
        XCTAssertEqual(result.document.entries.first?.toolIDs.count, 20)
        XCTAssertEqual(result.document.tools.count, 20)
        try assertFailureLeavesSourceUnchanged(result.document, name: "超过上限", selections: [
            ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: entry.id),
            ToolCredentialSelection(slotID: "embedding", providerID: "openai", secret: "fixture-only-new")
        ])
        XCTAssertEqual(result.document.entries.count, 1)
    }

    func testUnknownTemplateInvalidNameAndInvalidSourceFailWithoutChanges() throws {
        let entry = credential()
        let selection = ToolCredentialSelection(slotID: "model", providerID: "openai", existingEntryID: entry.id)
        let source = VaultDocument(entries: [entry])
        try assertFailureLeavesSourceUnchanged(source, template: "does-not-exist", selections: [selection])
        try assertFailureLeavesSourceUnchanged(source, name: " \n ", selections: [selection])
        try assertFailureLeavesSourceUnchanged(source, name: String(repeating: "长", count: 81), selections: [selection])
        var dangling = entry; dangling.toolIDs = [UUID()]
        try assertFailureLeavesSourceUnchanged(VaultDocument(entries: [dangling]), selections: [selection])
    }
}
