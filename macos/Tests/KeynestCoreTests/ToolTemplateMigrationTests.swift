import Foundation
import XCTest
import CryptoKit
@testable import KeynestCore

final class ToolTemplateMigrationTests: XCTestCase {
    private let password = "template-migration-fixture-password"
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func tool(templateID: String? = nil) -> ToolGroup {
        ToolGroup(name: "工作工具", notes: "保留用户填写的备注", templateID: templateID,
                  createdAt: timestamp, updatedAt: timestamp)
    }

    private func credential(toolID: UUID) -> SecretEntry {
        SecretEntry(name: "工作密钥", category: .skill, provider: "OpenAI", secret: "fixture-only-template-secret",
                    baseURL: "https://api.example.test/v1", website: "https://console.example.test",
                    tags: ["工作"], notes: "私有用途", isFavorite: true,
                    createdAt: timestamp, updatedAt: timestamp, toolIDs: [toolID],
                    environment: "生产", accountLabel: "work@example.test")
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    /// Authenticated historical fixtures exercise payload validation independently
    /// of encrypt(), which correctly always writes the latest payload version.
    private func encryptedPayload(_ payload: [String: Any], session: VaultSession) throws -> Data {
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: VaultCodec.encrypt(VaultDocument(), session: session)) as? [String: Any])
        let nonce = AES.GCM.Nonce()
        let header = Data("Keynest|format=keynest-vault|version=1|cipher=aes-256-gcm|kdf=pbkdf2-sha256|iterations=600000|salt=\(session.salt.base64EncodedString())".utf8)
        let box = try AES.GCM.seal(JSONSerialization.data(withJSONObject: payload), using: session.key,
                                   nonce: nonce, authenticating: header)
        envelope["nonce"] = Data(nonce).base64EncodedString()
        envelope["ciphertext"] = box.ciphertext.base64EncodedString()
        envelope["tag"] = box.tag.base64EncodedString()
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    func testVersionTwoUpgradesToCurrentAndPreservesPasswordAndBiometricAccess() throws {
        let originalTool = tool()
        let original = VaultDocument(entries: [credential(toolID: originalTool.id)], tools: [originalTool])
        var payload = try object(original); payload["version"] = 2
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        let legacy = try encryptedPayload(payload, session: session)

        let passwordOpened = try VaultCodec.decrypt(legacy, password: password)
        let biometricOpened = try VaultCodec.decrypt(legacy, biometricUnlockData: token)
        for opened in [passwordOpened, biometricOpened] {
            XCTAssertEqual(opened.sourceVersion, 2)
            XCTAssertTrue(opened.requiresUpgrade)
            XCTAssertEqual(opened.document.version, 4)
            XCTAssertEqual(opened.document.entries, original.entries)
            XCTAssertEqual(opened.document.tools, original.tools)
            XCTAssertNil(opened.document.tools.first?.templateID)
        }

        let upgraded = try VaultCodec.encrypt(passwordOpened.document, session: passwordOpened.session)
        XCTAssertNotEqual(upgraded, legacy)
        let passwordReopened = try VaultCodec.decrypt(upgraded, password: password)
        let biometricReopened = try VaultCodec.decrypt(upgraded, biometricUnlockData: token)
        for reopened in [passwordReopened, biometricReopened] {
            XCTAssertEqual(reopened.sourceVersion, 4)
            XCTAssertFalse(reopened.requiresUpgrade)
            XCTAssertEqual(reopened.document.entries, original.entries)
            XCTAssertEqual(reopened.document.tools, original.tools)
        }
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: upgraded) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 1)
        let kdf = try XCTUnwrap(envelope["kdf"] as? [String: Any])
        XCTAssertEqual(kdf["salt"] as? String, session.salt.base64EncodedString())
        XCTAssertEqual(try VaultCodec.decrypt(legacy, biometricUnlockData: token).sourceVersion, 2)
    }

    func testEncryptedTemplateAssociationSurvivesBackupMergeAndIDConflict() throws {
        let incomingTool = tool(templateID: "continue")
        let incoming = VaultDocument(entries: [credential(toolID: incomingTool.id)], tools: [incomingTool])
        let session = try VaultCodec.createSession(password: password)
        let backup = try VaultCodec.encrypt(incoming, session: session)
        let text = String(decoding: backup, as: UTF8.self)
        for privateValue in ["templateID", "continue", incomingTool.name, incomingTool.notes, incoming.entries[0].secret] {
            XCTAssertFalse(text.contains(privateValue))
        }
        let restored = try VaultCodec.decrypt(backup, password: password)
        XCTAssertEqual(restored.sourceVersion, 4)
        XCTAssertFalse(restored.requiresUpgrade)
        XCTAssertEqual(restored.document.tools, incoming.tools)
        XCTAssertEqual(restored.document.entries, incoming.entries)

        // The only difference is the template association. Neither tool may be
        // discarded and the incoming credential must follow its remapped tool.
        var localTool = incomingTool; localTool.templateID = "cursor"
        let local = VaultDocument(tools: [localTool])
        let merged = try local.merging(restored.document)
        XCTAssertEqual(merged.tools.count, 2)
        XCTAssertEqual(merged.tools.first { $0.id == localTool.id }, localTool)
        let importedTool = try XCTUnwrap(merged.tools.first { $0.templateID == "continue" })
        XCTAssertNotEqual(importedTool.id, incomingTool.id)
        XCTAssertEqual(importedTool.name, incomingTool.name)
        XCTAssertEqual(importedTool.notes, incomingTool.notes)
        XCTAssertEqual(merged.entries.count, 1)
        XCTAssertEqual(merged.entries.first?.toolIDs, [importedTool.id])
        XCTAssertEqual(merged.entries.first?.secret, incoming.entries.first?.secret)
        let repeated = try merged.merging(restored.document)
        XCTAssertEqual(repeated.tools, merged.tools)
        XCTAssertEqual(repeated.entries, merged.entries)
        let reopened = try VaultCodec.decrypt(VaultCodec.encrypt(merged, session: session), password: password)
        XCTAssertEqual(reopened.document.tools, merged.tools)
        XCTAssertEqual(reopened.document.entries, merged.entries)
        XCTAssertEqual(local.tools, [localTool])
    }

    func testUnknownButWellFormedTemplateIDIsRetainedForFallback() throws {
        let future = tool(templateID: "future-agent-v9")
        let original = VaultDocument(entries: [credential(toolID: future.id)], tools: [future])
        XCTAssertNil(ToolTemplate.match(templateID: "future-agent-v9"))
        XCTAssertNoThrow(try future.validated())
        let session = try VaultCodec.createSession(password: password)
        let reopened = try VaultCodec.decrypt(VaultCodec.encrypt(original, session: session), password: password)
        XCTAssertEqual(reopened.document.tools, original.tools)
        XCTAssertEqual(reopened.document.entries, original.entries)
        XCTAssertFalse(reopened.requiresUpgrade)
        let merged = try VaultDocument().merging(reopened.document)
        XCTAssertEqual(merged.tools.first?.templateID, "future-agent-v9")
        XCTAssertNil(ToolTemplate.match(templateID: try XCTUnwrap(merged.tools.first?.templateID)))
    }

    func testDirectToolDecodingDefaultsOnlyAbsentTemplateID() throws {
        let original = tool()
        let absent = try object(original)
        XCTAssertFalse(absent.keys.contains("templateID"))
        XCTAssertEqual(try JSONDecoder().decode(ToolGroup.self, from: JSONSerialization.data(withJSONObject: absent)), original)
        let known = tool(templateID: "continue")
        XCTAssertEqual(try JSONDecoder().decode(ToolGroup.self, from: JSONEncoder().encode(known)), known)
        let invalidValues: [Any] = [NSNull(), 12, true, ["continue"], ["id": "continue"]]
        for malformed in invalidValues {
            var payload = absent; payload["templateID"] = malformed
            XCTAssertThrowsError(try JSONDecoder().decode(ToolGroup.self, from: JSONSerialization.data(withJSONObject: payload)))
        }
    }

    func testAuthenticatedCurrentVersionRejectsNullWrongTypeAndMalformedTemplateIDs() throws {
        let original = tool(templateID: "continue")
        let valid = try object(VaultDocument(tools: [original]))
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        let invalidValues: [Any] = [NSNull(), 12, true, ["continue"], ["id": "continue"], "", " ", "../continue", "bad_id", "中文", String(repeating: "a", count: 81)]
        for value in invalidValues {
            var payload = valid
            var tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
            tools[0]["templateID"] = value; payload["tools"] = tools
            let malformed = try encryptedPayload(payload, session: session)
            XCTAssertThrowsError(try VaultCodec.decrypt(malformed, biometricUnlockData: token)) {
                XCTAssertEqual($0 as? VaultError, .invalidFormat)
            }
        }
        // Include the password entry point without repeating PBKDF2 per fixture.
        var nullPayload = valid
        var tools = try XCTUnwrap(nullPayload["tools"] as? [[String: Any]])
        tools[0]["templateID"] = NSNull(); nullPayload["tools"] = tools
        XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(nullPayload, session: session), password: password)) {
            XCTAssertEqual($0 as? VaultError, .invalidFormat)
        }
    }

    func testVersionTwoCannotSmuggleVersionThreeTemplateMetadata() throws {
        let original = tool(templateID: "continue")
        var payload = try object(VaultDocument(tools: [original])); payload["version"] = 2
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        let invalid = try encryptedPayload(payload, session: session)
        XCTAssertThrowsError(try VaultCodec.decrypt(invalid, password: password)) {
            XCTAssertEqual($0 as? VaultError, .invalidFormat)
        }
        XCTAssertThrowsError(try VaultCodec.decrypt(invalid, biometricUnlockData: token)) {
            XCTAssertEqual($0 as? VaultError, .invalidFormat)
        }
        var tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        tools[0].removeValue(forKey: "templateID"); payload["tools"] = tools
        let valid = try VaultCodec.decrypt(encryptedPayload(payload, session: session), biometricUnlockData: token)
        XCTAssertEqual(valid.sourceVersion, 2)
        XCTAssertTrue(valid.requiresUpgrade)
        XCTAssertNil(valid.document.tools.first?.templateID)
    }
}
