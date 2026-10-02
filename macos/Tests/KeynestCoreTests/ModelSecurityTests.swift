import XCTest
import CryptoKit
@testable import KeynestCore

final class ModelSecurityTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ url: String = "") -> SecretEntry {
        SecretEntry(name: "Offline audit fixture", secret: "fake-audit-key-never-use",
                    baseURL: url, createdAt: timestamp, updatedAt: timestamp)
    }

    func testURLFieldsRejectLiteralControlCharactersInsteadOfSavingInvisibleText() {
        for scalar in ["\n", "\r", "\t", "\0", "\u{000B}", "\u{001B}", "\u{007F}", "\u{0085}", "\u{2028}", "\u{2029}"] {
            let url = "https://example.test/before\(scalar)after"
            XCTAssertThrowsError(try entry(url).validated())
            var website = entry(); website.website = url
            XCTAssertThrowsError(try website.validated())
        }
    }

    func testURLFieldsRejectPortsOutsideTheNetworkPortRange() {
        for port in ["0", "65536", "999999999999"] {
            let url = "https://example.test:\(port)/v1"
            XCTAssertThrowsError(try entry(url).validated())
            var website = entry(); website.website = url
            XCTAssertThrowsError(try website.validated())
        }
    }

    func testURLValidationKeepsLocalEndpointsIPv6AndExplicitlyEscapedPaths() throws {
        for url in ["", "http://localhost:1/v1", "http://127.0.0.1:65535/v1",
                    "http://[::1]:8080/v1", "https://example.test:443/v1",
                    "https://example.test/a%20b", "https://example.test/a%0Ab"] {
            var input = entry("  \(url)\n"); input.website = "\t\(url)  "
            let value = try input.validated()
            XCTAssertEqual(value.baseURL, url)
            XCTAssertEqual(value.website, url)
        }
    }

    func testPreviouslyForbiddenImportedURLRejectsTheWholeMergeWithoutChangingOriginal() throws {
        let original = entry("https://example.test/v1")
        let current = VaultDocument(entries: [original])
        let validIncoming = entry("https://other.example.test/v1")
        for url in ["file:///private/tmp/fixture", "https://user:fake-secret@example.test/v1", "https://example.test/?key=fake-secret", "https://example.test/#fake-secret"] {
            XCTAssertThrowsError(try current.merging(VaultDocument(entries: [validIncoming, entry(url)])))
        }
        XCTAssertEqual(current.entries, [original])
        XCTAssertTrue(current.tools.isEmpty)
    }

    func testLegacyEncryptedURLsCanUnlockAndResaveWithoutLosingSecretsOrAssociations() throws {
        let password = "fake-audit-master-password"
        let session = try VaultCodec.createSession(password: password)
        let tool = ToolGroup(name: "Legacy fixture tool", createdAt: timestamp, updatedAt: timestamp)
        var legacyEntries = [entry("https://example.test/before\nafter"), entry("https://example.test:0/v1"),
                             entry("https://example.test:65536/v1"), entry("https://example.test:999999999999/v1"),
                             entry("https://example.test/a" + String(repeating: "\t", count: 1900) + "b")]
        for index in legacyEntries.indices {
            legacyEntries[index].toolIDs = [tool.id]
            legacyEntries[index].notes = "Original notes must remain intact"
            legacyEntries[index].website = "https://example.test/console\taccount"
        }
        let original = VaultDocument(entries: legacyEntries, tools: [tool])
        let ciphertext = try legacyCiphertext(original, session: session)
        let opened = try VaultCodec.decrypt(ciphertext, password: password)
        XCTAssertEqual(opened.document.tools, [tool])
        XCTAssertEqual(opened.document.entries.count, legacyEntries.count)
        for index in legacyEntries.indices {
            let value = opened.document.entries[index]
            XCTAssertEqual(value.id, legacyEntries[index].id)
            XCTAssertEqual(value.secret, legacyEntries[index].secret)
            XCTAssertEqual(value.notes, legacyEntries[index].notes)
            XCTAssertEqual(value.toolIDs, [tool.id])
            XCTAssertEqual(value.website, "https://example.test/console%09account")
            XCTAssertFalse(value.baseURL.contains("\n") || value.baseURL.contains("\t"))
        }
        XCTAssertEqual(opened.document.entries[0].baseURL, "https://example.test/before%0Aafter")
        XCTAssertEqual(opened.document.entries[1].baseURL, legacyEntries[1].baseURL)
        XCTAssertEqual(opened.document.entries[2].baseURL, legacyEntries[2].baseURL)
        XCTAssertEqual(opened.document.entries[3].baseURL, legacyEntries[3].baseURL)
        XCTAssertTrue(opened.document.entries[4].baseURL.count > 2048)
        XCTAssertNoThrow(try opened.document.entries[0].validated())
        for index in 1...4 { XCTAssertThrowsError(try opened.document.entries[index].validated()) }
        let savedAgain = try VaultCodec.encrypt(opened.document, session: opened.session)
        let reopened = try VaultCodec.decrypt(savedAgain, password: password)
        XCTAssertEqual(reopened.document.entries, opened.document.entries)
        XCTAssertEqual(reopened.document.tools, opened.document.tools)
        let imported = try VaultDocument().merging(opened.document)
        XCTAssertEqual(imported.entries, opened.document.entries)
        XCTAssertEqual(imported.tools, opened.document.tools)
    }

    private func legacyCiphertext(_ document: VaultDocument, session: VaultSession) throws -> Data {
        // Seal the unnormalized historical payload directly: using encrypt()
        // here would silently test the current writer instead of an old file.
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: VaultCodec.encrypt(VaultDocument(), session: session)) as? [String: Any])
        let header = Data("Keynest|format=keynest-vault|version=1|cipher=aes-256-gcm|kdf=pbkdf2-sha256|iterations=600000|salt=\(session.salt.base64EncodedString())".utf8)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(JSONEncoder().encode(document), using: session.key, nonce: nonce, authenticating: header)
        envelope["nonce"] = Data(nonce).base64EncodedString()
        envelope["ciphertext"] = sealed.ciphertext.base64EncodedString()
        envelope["tag"] = sealed.tag.base64EncodedString()
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    func testRepeatedImportPreservesAssociationsWhenConflictIDsAreAlreadyOccupied() throws {
        let currentTool = ToolGroup(name: "Original tool", notes: "Current notes", createdAt: timestamp, updatedAt: timestamp)
        var incomingTool = currentTool; incomingTool.notes = "Different backup notes"
        var currentEntry = entry(); currentEntry.toolIDs = [currentTool.id]
        var incomingEntry = currentEntry; incomingEntry.secret = "second-fake-audit-key"
        let current = VaultDocument(entries: [currentEntry], tools: [currentTool])
        let incoming = VaultDocument(entries: [incomingEntry], tools: [incomingTool])

        // A prior import can leave an edited conflict copy. A later import must
        // retain that copy and create/reuse another identity without losing links.
        var prior = try current.merging(incoming)
        prior.tools[1].notes = "User subsequently edited the imported tool"
        prior.entries[1].notes = "User subsequently edited the imported key"
        let merged = try prior.merging(incoming)
        XCTAssertEqual(merged.tools.count, 3)
        XCTAssertEqual(merged.entries.count, 3)
        XCTAssertEqual(Array(merged.tools.prefix(2)), prior.tools)
        XCTAssertEqual(Array(merged.entries.prefix(2)), prior.entries)
        XCTAssertEqual(merged.entries[2].secret, incomingEntry.secret)
        XCTAssertEqual(merged.entries[2].toolIDs, [merged.tools[2].id])
        XCTAssertEqual(merged.tools[2].notes, incomingTool.notes)
        let repeated = try merged.merging(incoming)
        XCTAssertEqual(repeated.tools, merged.tools)
        XCTAssertEqual(repeated.entries, merged.entries)
    }
}
