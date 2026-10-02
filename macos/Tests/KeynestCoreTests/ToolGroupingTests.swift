import Foundation
import XCTest
@testable import KeynestCore

final class ToolGroupingTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func group(_ name: String = "研究助手") -> ToolGroup {
        ToolGroup(name: name, notes: "用于多 API 工作流", createdAt: date, updatedAt: date)
    }

    private func entry(toolIDs: [UUID] = []) -> SecretEntry {
        SecretEntry(name: "OpenAI 正式", provider: "OpenAI", secret: "fixture-only-key",
                    createdAt: date, updatedAt: date, toolIDs: toolIDs,
                    environment: "正式", accountLabel: "团队账户")
    }

    func testToolValidationAndLimits() throws {
        var tool = group("  研究助手 \n")
        XCTAssertEqual(try tool.validated().name, "研究助手")
        for name in ["", " \n", String(repeating: "名", count: 81)] {
            tool.name = name
            XCTAssertThrowsError(try tool.validated())
        }
        tool = group(String(repeating: "名", count: 80))
        tool.notes = String(repeating: "注", count: 1000)
        XCTAssertNoThrow(try tool.validated())
        tool.notes.append("注")
        XCTAssertThrowsError(try tool.validated())
        tool = group(); tool.updatedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertThrowsError(try tool.validated())
    }

    func testEnvironmentAccountAndUniqueAssociationLimits() throws {
        let identifiers = (0..<20).map { _ in UUID() }
        var value = entry(toolIDs: identifiers + [identifiers[0], identifiers[1]])
        value.environment = "  开发 \n"; value.accountLabel = "  工作账户 "
        let normalized = try value.validated()
        XCTAssertEqual(normalized.toolIDs, identifiers)
        XCTAssertEqual(normalized.environment, "开发")
        XCTAssertEqual(normalized.accountLabel, "工作账户")
        value.toolIDs = identifiers + [UUID()]
        XCTAssertThrowsError(try value.validated())
        value = entry(); value.environment = String(repeating: "e", count: 41)
        XCTAssertThrowsError(try value.validated())
        value = entry(); value.accountLabel = String(repeating: "a", count: 121)
        XCTAssertThrowsError(try value.validated())
        value.environment = String(repeating: "e", count: 40)
        value.accountLabel = String(repeating: "a", count: 120)
        XCTAssertNoThrow(try value.validated())
    }

    func testDocumentRejectsMissingAssociationsAndDuplicateToolIDs() throws {
        let tool = group()
        let credential = entry(toolIDs: [tool.id])
        XCTAssertThrowsError(try VaultDocument(entries: [credential]).validated())
        XCTAssertThrowsError(try VaultDocument(entries: [credential], tools: [tool, tool]).validated())
        let valid = try VaultDocument(entries: [credential], tools: [tool]).validated()
        XCTAssertEqual(valid.entries, [credential])
        XCTAssertEqual(valid.tools, [tool])
    }

    func testOneCredentialCanBelongToMultipleToolsAndShareAProvider() throws {
        let first = group("研究助手"), second = group("内容工作台")
        let shared = entry(toolIDs: [first.id, second.id])
        var development = entry(toolIDs: [first.id])
        development.environment = "开发"; development.accountLabel = "测试账户"
        let document = try VaultDocument(entries: [shared, development], tools: [first, second]).validated()
        let reopened = try JSONDecoder().decode(VaultDocument.self, from: JSONEncoder().encode(document)).validated()
        XCTAssertEqual(reopened.entries, document.entries)
        XCTAssertEqual(reopened.tools, document.tools)
        XCTAssertEqual(reopened.entries[0].provider, reopened.entries[1].provider)
        XCTAssertNotEqual(reopened.entries[0].environment, reopened.entries[1].environment)
    }

    func testMergingToolCollisionRemapsOnlyIncomingAssociationsAndIsIdempotent() throws {
        let currentTool = group()
        var incomingTool = currentTool
        incomingTool.notes = "备份中的不同用途，不能按同名合并"
        let credential = entry(toolIDs: [currentTool.id])
        let existing = VaultDocument(entries: [credential], tools: [currentTool])
        let incoming = VaultDocument(entries: [credential], tools: [incomingTool])
        let merged = try existing.merging(incoming)
        XCTAssertEqual(merged.tools.count, 2)
        XCTAssertEqual(merged.tools[0], currentTool)
        XCTAssertNotEqual(merged.tools[1].id, currentTool.id)
        XCTAssertEqual(merged.tools[1].notes, incomingTool.notes)
        XCTAssertEqual(merged.entries.count, 2)
        XCTAssertEqual(merged.entries[0], credential)
        XCTAssertEqual(merged.entries[1].toolIDs, [merged.tools[1].id])
        XCTAssertNotEqual(merged.entries[1].id, credential.id)
        let repeated = try merged.merging(incoming)
        XCTAssertEqual(repeated.tools, merged.tools)
        XCTAssertEqual(repeated.entries, merged.entries)
        XCTAssertEqual(existing.tools, [currentTool])
        XCTAssertEqual(incoming.entries, [credential])
    }

    func testMergingKeepsDistinctSameNameToolsEvenWhenOtherContentIsIdentical() throws {
        let first = group()
        var second = first; second.id = UUID()
        let original = entry(toolIDs: [first.id])
        let incoming = entry(toolIDs: [second.id])
        let merged = try VaultDocument(entries: [original], tools: [first])
            .merging(VaultDocument(entries: [incoming], tools: [second]))
        XCTAssertEqual(merged.tools, [first, second])
        XCTAssertEqual(merged.entries, [original, incoming])
    }

    func testMergingSameToolAndEntryDoesNotDuplicateEither() throws {
        let tool = group()
        let credential = entry(toolIDs: [tool.id])
        let original = VaultDocument(entries: [credential], tools: [tool])
        let merged = try original.merging(original)
        XCTAssertEqual(merged.tools, original.tools)
        XCTAssertEqual(merged.entries, original.entries)
    }

    func testMergingEntryMetadataConflictIsStableAcrossRepeatedImports() throws {
        let original = entry()
        var incoming = original
        incoming.environment = "测试"; incoming.accountLabel = "另一个账户"
        let backup = VaultDocument(entries: [incoming])
        let merged = try VaultDocument(entries: [original]).merging(backup)
        XCTAssertEqual(merged.entries.count, 2)
        XCTAssertEqual(merged.entries[0], original)
        XCTAssertEqual(merged.entries[1].environment, incoming.environment)
        XCTAssertEqual(merged.entries[1].accountLabel, incoming.accountLabel)
        XCTAssertEqual(try merged.merging(backup).entries, merged.entries)
    }

    func testRemovingToolPreservesAllCredentialsAndOtherAssociations() throws {
        let first = group("研究助手"), second = group("内容工作台")
        let shared = entry(toolIDs: [first.id, second.id]), onlyFirst = entry(toolIDs: [first.id])
        let ungrouped = entry()
        let original = VaultDocument(entries: [shared, onlyFirst, ungrouped], tools: [first, second])
        let removed = try original.removingTool(id: first.id)
        var expectedShared = shared; expectedShared.toolIDs = [second.id]
        var expectedFirst = onlyFirst; expectedFirst.toolIDs = []
        XCTAssertEqual(removed.entries, [expectedShared, expectedFirst, ungrouped])
        XCTAssertEqual(removed.tools, [second])
        XCTAssertEqual(original.entries, [shared, onlyFirst, ungrouped])
        XCTAssertEqual(original.tools, [first, second])
        XCTAssertEqual(try removed.removingTool(id: first.id).entries, removed.entries)
    }

    func testToolCapacityAppliesAfterExactDeduplication() throws {
        let tools = (0..<100).map { group("工具 \($0)") }
        let document = VaultDocument(tools: tools)
        XCTAssertNoThrow(try document.validated())
        XCTAssertEqual(try document.merging(VaultDocument(tools: [tools[0]])).tools, tools)
        XCTAssertThrowsError(try document.merging(VaultDocument(tools: [group("额外工具")])))
        XCTAssertThrowsError(try VaultDocument(tools: tools + [group("额外工具")]).validated())
        XCTAssertEqual(document.tools, tools)
    }
}
