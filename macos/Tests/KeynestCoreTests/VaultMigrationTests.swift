import Foundation
import XCTest
import CryptoKit
import Darwin
@testable import KeynestCore

final class VaultMigrationTests: XCTestCase {
    private let password = "migration-fixture-password"
    private let backupName = "vault-before-0.10.keynest"

    private func credential() -> SecretEntry {
        SecretEntry(name: "旧版密钥", provider: "自定义平台", secret: "fixture-only-legacy-secret",
                    baseURL: "https://api.example.test/v1", website: "https://example.test",
                    tags: ["旧版"], notes: "旧版备注", isFavorite: true,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_100))
    }

    private func object(_ document: VaultDocument) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    }

    private func legacyPayload() throws -> [String: Any] {
        var payload = try object(VaultDocument(entries: [credential()]))
        payload["version"] = 1; payload.removeValue(forKey: "tools")
        var entries = try XCTUnwrap(payload["entries"] as? [[String: Any]])
        for field in ["toolIDs", "environment", "accountLabel"] { entries[0].removeValue(forKey: field) }
        payload["entries"] = entries
        return payload
    }

    private func encryptedPayload(_ payload: [String: Any], session: VaultSession) throws -> Data {
        let base = try VaultCodec.encrypt(VaultDocument(), session: session)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
        let nonce = AES.GCM.Nonce()
        let header = Data("Keynest|format=keynest-vault|version=1|cipher=aes-256-gcm|kdf=pbkdf2-sha256|iterations=600000|salt=\(session.salt.base64EncodedString())".utf8)
        let box = try AES.GCM.seal(JSONSerialization.data(withJSONObject: payload),
                                   using: session.key, nonce: nonce, authenticating: header)
        envelope["nonce"] = Data(nonce).base64EncodedString()
        envelope["ciphertext"] = box.ciphertext.base64EncodedString()
        envelope["tag"] = box.tag.base64EncodedString()
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    private func storage() throws -> VaultStorage {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keynest-migration-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try VaultStorage(directory: directory)
    }

    func testLegacyEncryptedPayloadDefaultsNewFieldsAndMarksUpgrade() throws {
        let session = try VaultCodec.createSession(password: password)
        let original = try encryptedPayload(legacyPayload(), session: session)
        let reopened = try VaultCodec.decrypt(original, password: password)
        XCTAssertTrue(reopened.requiresUpgrade)
        XCTAssertEqual(reopened.document.version, 4)
        XCTAssertEqual(reopened.document.tools, [])
        let entry = try XCTUnwrap(reopened.document.entries.first)
        XCTAssertEqual(entry.name, "旧版密钥")
        XCTAssertEqual(entry.website, "https://example.test")
        XCTAssertEqual(entry.secret, "fixture-only-legacy-secret")
        XCTAssertEqual(entry.toolIDs, [])
        XCTAssertEqual(entry.environment, "")
        XCTAssertEqual(entry.accountLabel, "")
        let upgraded = try VaultCodec.encrypt(reopened.document, session: reopened.session)
        XCTAssertFalse(try VaultCodec.decrypt(upgraded, password: password).requiresUpgrade)
        XCTAssertEqual(try VaultCodec.decrypt(upgraded, password: password).document.entries, reopened.document.entries)
    }

    func testNewPayloadKeepsToolMetadataInsideEnvelopeVersionOne() throws {
        let tool = ToolGroup(name: "私人工具", notes: "工具私有备注")
        var entry = credential()
        entry.toolIDs = [tool.id]; entry.environment = "正式"; entry.accountLabel = "公司账户"
        let original = VaultDocument(entries: [entry], tools: [tool])
        let data = try VaultCodec.encrypt(original, session: VaultCodec.createSession(password: password))
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 1)
        XCTAssertEqual(envelope["cipher"] as? String, "aes-256-gcm")
        for value in [tool.name, tool.notes, entry.environment, entry.accountLabel] {
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(value))
        }
        let reopened = try VaultCodec.decrypt(data, password: password)
        XCTAssertFalse(reopened.requiresUpgrade)
        XCTAssertEqual(reopened.document.tools, original.tools)
        XCTAssertEqual(reopened.document.entries, original.entries)
    }

    func testLegacyCodableDefaultsOnlyAbsentFieldsAndEveryWriteUsesVersionFour() throws {
        let payload = try legacyPayload()
        let decoded = try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.tools, [])
        let rewritten = try object(decoded)
        XCTAssertEqual(rewritten["version"] as? Int, 4)
        XCTAssertEqual((rewritten["tools"] as? [Any])?.count, 0)
        let entries = try XCTUnwrap(rewritten["entries"] as? [[String: Any]])
        XCTAssertEqual(entries[0]["environment"] as? String, "")
        XCTAssertEqual(entries[0]["accountLabel"] as? String, "")
        XCTAssertEqual((entries[0]["toolIDs"] as? [String])?.count, 0)
        for field in ["toolIDs", "environment", "accountLabel"] {
            var malformed = payload
            var items = try XCTUnwrap(malformed["entries"] as? [[String: Any]])
            items[0][field] = NSNull(); malformed["entries"] = items
            XCTAssertThrowsError(try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: malformed)))
        }
        var nullTools = payload; nullTools["tools"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: nullTools)))
    }

    func testAuthenticatedNewSchemaRejectsUnknownMalformedAndDanglingFields() throws {
        let session = try VaultCodec.createSession(password: password)
        let tool = ToolGroup(name: "工具")
        var entry = credential(); entry.toolIDs = [tool.id]
        let valid = try object(VaultDocument(entries: [entry], tools: [tool]))
        var cases: [[String: Any]] = []
        var malformed = valid; malformed["version"] = 5; cases.append(malformed)
        malformed = valid; malformed["tools"] = NSNull(); cases.append(malformed)
        malformed = valid
        var tools = try XCTUnwrap(valid["tools"] as? [[String: Any]])
        tools[0]["unexpected"] = "must not disappear"; malformed["tools"] = tools; cases.append(malformed)
        for field in ["toolIDs", "environment", "accountLabel", "unrecognized"] {
            malformed = valid
            var entries = try XCTUnwrap(valid["entries"] as? [[String: Any]])
            entries[0][field] = 123; malformed["entries"] = entries; cases.append(malformed)
        }
        malformed = valid; malformed["tools"] = []; cases.append(malformed)
        for value in cases {
            XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(value, session: session), password: password)) {
                XCTAssertEqual($0 as? VaultError, .invalidFormat)
            }
        }
    }

    func testUpgradeBackupPreservesOriginalBytesPermissionsAndFirstCopy() throws {
        let store = try storage()
        let session = try VaultCodec.createSession(password: password)
        let legacy = try encryptedPayload(legacyPayload(), session: session)
        try store.write(legacy)
        let historicalBackups = ["vault-before-0.5.keynest", "vault-before-0.7.keynest"].map {
            store.directory.appendingPathComponent($0)
        }
        for old in historicalBackups { try legacy.write(to: old) }
        try store.preserveUpgradeBackup(store.read())
        let backup = store.directory.appendingPathComponent(backupName)
        XCTAssertEqual(try Data(contentsOf: backup), legacy)
        let permissions = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let upgraded = try VaultCodec.encrypt(VaultDocument(), session: session)
        try store.write(upgraded)
        try store.preserveUpgradeBackup(upgraded)
        XCTAssertEqual(try Data(contentsOf: backup), legacy)
        XCTAssertEqual(try store.read(), upgraded)
        for old in historicalBackups { XCTAssertEqual(try Data(contentsOf: old), legacy) }
        XCTAssertTrue(try VaultCodec.decrypt(Data(contentsOf: backup), password: password).requiresUpgrade)
    }

    func testUpgradeBackupRejectsSymbolicLinksAndKeepsVaultUntouched() throws {
        let store = try storage()
        let data = try VaultCodec.encrypt(VaultDocument(), session: VaultCodec.createSession(password: password))
        try store.write(data)
        let target = store.directory.appendingPathComponent("sentinel.txt")
        let sentinel = Data("do not replace this file".utf8)
        try sentinel.write(to: target)
        let backup = store.directory.appendingPathComponent(backupName)
        try FileManager.default.createSymbolicLink(at: backup, withDestinationURL: target)
        XCTAssertThrowsError(try store.preserveUpgradeBackup(data))
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertEqual(try store.read(), data)
    }

    func testUpgradeBackupRejectsHardLinksWithoutChangingOutsidePermissions() throws {
        let store = try storage()
        let session = try VaultCodec.createSession(password: password)
        let data = try VaultCodec.encrypt(VaultDocument(), session: session)
        try store.write(data)
        let outside = store.directory.appendingPathComponent("unrelated-fixture.keynest")
        let backup = store.directory.appendingPathComponent(backupName)
        try data.write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: outside.path)
        XCTAssertEqual(link(outside.path, backup.path), 0)
        XCTAssertThrowsError(try store.preserveUpgradeBackup(data))
        XCTAssertEqual(try Data(contentsOf: outside), data)
        XCTAssertEqual(try Data(contentsOf: backup), data)
        XCTAssertEqual(try store.read(), data)
        let mode = try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o644)
        try FileManager.default.removeItem(at: backup)
        try store.preserveUpgradeBackup(data)
        let backupMode = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(backupMode?.intValue, 0o600)
        XCTAssertEqual(try Data(contentsOf: backup), data)
    }

    func testUpgradeBackupRejectsIncompleteExistingFilesAndInvalidInput() throws {
        let store = try storage()
        let data = try VaultCodec.encrypt(VaultDocument(), session: VaultCodec.createSession(password: password))
        let backup = store.directory.appendingPathComponent(backupName)
        XCTAssertThrowsError(try store.preserveUpgradeBackup(Data("plaintext".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        let partial = Data("interrupted partial backup".utf8)
        try partial.write(to: backup)
        XCTAssertThrowsError(try store.preserveUpgradeBackup(data))
        XCTAssertEqual(try Data(contentsOf: backup), partial)
    }
}
