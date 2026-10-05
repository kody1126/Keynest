import XCTest
import Foundation
import CryptoKit
import CommonCrypto
import Darwin
@testable import KeynestCore

final class VaultCoreTests: XCTestCase {
    private let password = "test-only-master-password-32"
    private let fixtureEntry = SecretEntry(
        name: "Private sample skill", category: .skill, provider: "Custom Developer",
        secret: "sk-fake-tests-only-never-real", baseURL: "https://api.example.com/v1",
        website: "https://example.com/console", tags: ["development"],
        notes: "Private fixture notes", isFavorite: true,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keynest-core-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func envelope(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encoded(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    func testEncryptedRoundTripReopenPermissionsAndNoPlaintext() throws {
        let storage = try VaultStorage(directory: temporaryDirectory().appendingPathComponent("vault"))
        XCTAssertFalse(storage.exists)
        let session = try VaultCodec.createSession(password: password)
        let document = VaultDocument(entries: [fixtureEntry])
        let encrypted = try VaultCodec.encrypt(document, session: session)
        try storage.write(encrypted)
        XCTAssertTrue(storage.exists)
        let raw = try storage.read()
        let text = try XCTUnwrap(String(data: raw, encoding: .utf8))
        for value in [fixtureEntry.secret, fixtureEntry.name, fixtureEntry.provider, fixtureEntry.notes, password] {
            XCTAssertFalse(text.contains(value), "Encrypted file exposed fixture metadata")
        }
        let reopenedStorage = try VaultStorage(directory: storage.directory)
        let reopened = try VaultCodec.decrypt(reopenedStorage.read(), password: password)
        XCTAssertEqual(reopened.document.entries, [fixtureEntry])
        XCTAssertEqual(reopened.document.version, 5)
        let permissions = try FileManager.default.attributesOfItem(atPath: storage.fileURL.path)[.posixPermissions] as? NSNumber
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: storage.directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: storage.directory.path), ["vault.keynest"])
    }

    func testFreshNonceForEverySaveAndFreshSaltForEverySession() throws {
        let firstSession = try VaultCodec.createSession(password: password)
        let secondSession = try VaultCodec.createSession(password: password)
        XCTAssertNotEqual(firstSession.salt, secondSession.salt)
        let document = VaultDocument(entries: [fixtureEntry])
        let first = try VaultCodec.encrypt(document, session: firstSession)
        let second = try VaultCodec.encrypt(document, session: firstSession)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(try envelope(first)["nonce"] as? String, try envelope(second)["nonce"] as? String)
        XCTAssertEqual(try VaultCodec.decrypt(second, password: password).document.entries, [fixtureEntry])
    }

    func testWrongPasswordAndTamperLeaveExistingFileUntouched() throws {
        let storage = try VaultStorage(directory: temporaryDirectory())
        let session = try VaultCodec.createSession(password: password)
        let original = try VaultCodec.encrypt(VaultDocument(entries: [fixtureEntry]), session: session)
        try storage.write(original)
        XCTAssertThrowsError(try VaultCodec.decrypt(storage.read(), password: "wrong-test-password-32")) { error in
            XCTAssertEqual(error as? VaultError, .authenticationFailed)
        }
        var changed = try envelope(original)
        let tagString = try XCTUnwrap(changed["tag"] as? String)
        var tag = try XCTUnwrap(Data(base64Encoded: tagString))
        tag[0] ^= 1
        changed["tag"] = tag.base64EncodedString()
        XCTAssertThrowsError(try VaultCodec.decrypt(encoded(changed), password: password)) { error in
            XCTAssertEqual(error as? VaultError, .authenticationFailed)
        }
        XCTAssertEqual(try storage.read(), original)
        XCTAssertEqual(try VaultCodec.decrypt(storage.read(), password: password).document.entries, [fixtureEntry])
    }

    func testEnvelopeSchemaAndKDFParametersCannotBeChanged() throws {
        let session = try VaultCodec.createSession(password: password)
        let original = try envelope(VaultCodec.encrypt(VaultDocument(), session: session))
        var invalid: [[String: Any]] = []
        var version = original; version["version"] = 2; invalid.append(version)
        var format = original; format["format"] = "unrelated-vault"; invalid.append(format)
        var cipher = original; cipher["cipher"] = "aes-256-cbc"; invalid.append(cipher)
        var unknown = original; unknown["secret"] = "unexpected plaintext field"; invalid.append(unknown)
        var missing = original; missing.removeValue(forKey: "nonce"); invalid.append(missing)
        var shortNonce = original; shortNonce["nonce"] = Data([0]).base64EncodedString(); invalid.append(shortNonce)
        var noncanonical = original; noncanonical["tag"] = "not base64!"; invalid.append(noncanonical)
        var weakKDF = original
        var kdf = try XCTUnwrap(weakKDF["kdf"] as? [String: Any])
        kdf["iterations"] = 1; weakKDF["kdf"] = kdf; invalid.append(weakKDF)
        for value in invalid {
            XCTAssertThrowsError(try VaultCodec.decrypt(encoded(value), password: password)) { error in
                XCTAssertEqual(error as? VaultError, .invalidFormat)
            }
        }
    }

    func testSaltIsAuthenticated() throws {
        let session = try VaultCodec.createSession(password: password)
        var modified = try envelope(VaultCodec.encrypt(VaultDocument(), session: session))
        var kdf = try XCTUnwrap(modified["kdf"] as? [String: Any])
        var salt = session.salt
        salt[0] ^= 1
        kdf["salt"] = salt.base64EncodedString(); modified["kdf"] = kdf
        XCTAssertThrowsError(try VaultCodec.decrypt(encoded(modified), password: password)) { error in
            XCTAssertEqual(error as? VaultError, .authenticationFailed)
        }
    }

    func testMalformedWritesAndOversizedFilesNeverReplacePreviousData() throws {
        let storage = try VaultStorage(directory: temporaryDirectory())
        let session = try VaultCodec.createSession(password: password)
        let original = try VaultCodec.encrypt(VaultDocument(entries: [fixtureEntry]), session: session)
        try storage.write(original)
        for malformed in [Data(), Data("not a vault".utf8), Data("{\"version\":1}".utf8), Data(repeating: 0, count: VaultCodec.maximumFileSize + 1)] {
            XCTAssertThrowsError(try storage.write(malformed))
            XCTAssertEqual(try storage.read(), original)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: storage.directory.path), ["vault.keynest"])
    }

    func testDirectorySyncFailureReturnsCommittedResultAndNewDecryptableCiphertext() throws {
        let directory = try temporaryDirectory()
        let storage = try VaultStorage(directory: directory)
        let session = try VaultCodec.createSession(password: password)
        let original = try VaultCodec.encrypt(VaultDocument(entries: [fixtureEntry]), session: session)
        var changedEntry = fixtureEntry
        changedEntry.notes = "This committed update must not be lost after a directory sync failure"
        let replacement = try VaultCodec.encrypt(VaultDocument(entries: [changedEntry]), session: session)
        for syncError in [EIO, EINVAL, ENOTSUP] {
            try storage.write(original)
            let failingSync = try VaultStorage(directory: directory, directorySync: { _ in
                errno = syncError
                return -1
            })
            // This must return, not throw: rename already committed the update.
            let outcome = try failingSync.write(replacement)
            XCTAssertEqual(outcome, .durabilityUncertain)
            XCTAssertEqual(try storage.read(), replacement)
            XCTAssertEqual(try VaultCodec.decrypt(storage.read(), password: password).document.entries, [changedEntry])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["vault.keynest"])
            let mode = try FileManager.default.attributesOfItem(atPath: storage.fileURL.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(mode?.intValue, 0o600)
        }
    }

    func testPreCommitFailureStillThrowsAndPreservesOldCiphertextWithSyncInjection() throws {
        let directory = try temporaryDirectory()
        let storage = try VaultStorage(directory: directory, directorySync: { _ in
            errno = EIO
            return -1
        })
        let original = try VaultCodec.encrypt(VaultDocument(entries: [fixtureEntry]),
                                              session: VaultCodec.createSession(password: password))
        XCTAssertEqual(try storage.write(original), .durabilityUncertain)
        XCTAssertThrowsError(try storage.write(Data("not an encrypted vault".utf8))) {
            XCTAssertEqual($0 as? VaultError, .invalidFormat)
        }
        XCTAssertEqual(try storage.read(), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["vault.keynest"])
        let successfulSync = try VaultStorage(directory: directory, directorySync: { _ in 0 })
        XCTAssertEqual(try successfulSync.write(original), .durable)
        XCTAssertEqual(try storage.read(), original)
    }

    func testOversizedPlaintextCannotBeEncrypted() throws {
        let session = try VaultCodec.createSession(password: password)
        let largeEntry = SecretEntry(name: "Large test", secret: String(repeating: "x", count: 8192), notes: String(repeating: "y", count: 4000))
        let entries = (0..<400).map { _ -> SecretEntry in
            var entry = largeEntry; entry.id = UUID(); return entry
        }
        XCTAssertThrowsError(try VaultCodec.encrypt(VaultDocument(entries: entries), session: session)) { error in
            XCTAssertEqual(error as? VaultError, .fileTooLarge)
        }
    }

    func testInvalidPasswordsAndEntryFieldsAreRejected() throws {
        XCTAssertThrowsError(try VaultCodec.validatePassword("short"))
        XCTAssertThrowsError(try VaultCodec.validatePassword(String(repeating: "a", count: 1025)))
        XCTAssertNoThrow(try VaultCodec.validatePassword(String(repeating: "a", count: 12)))
        XCTAssertNoThrow(try VaultCodec.validatePassword(String(repeating: "a", count: 1024)))
        XCTAssertNoThrow(try fixtureEntry.validated())
        for value in ["", "   ", "sk-test\nkey", "sk-test\rkey", "sk-test\0key", String(repeating: "a", count: 8193)] {
            var entry = fixtureEntry; entry.secret = value
            XCTAssertThrowsError(try entry.validated())
        }
        var entry = fixtureEntry; entry.name = "  "; XCTAssertThrowsError(try entry.validated())
        entry = fixtureEntry; entry.provider = String(repeating: "p", count: 121); XCTAssertThrowsError(try entry.validated())
        entry = fixtureEntry; entry.tags = Array(repeating: "tag", count: 13); XCTAssertThrowsError(try entry.validated())
        entry = fixtureEntry; entry.tags = [String(repeating: "t", count: 41)]; XCTAssertThrowsError(try entry.validated())
        entry = fixtureEntry; entry.notes = String(repeating: "n", count: 4001); XCTAssertThrowsError(try entry.validated())
    }

    func testNewPasswordByteLimitRejectsOversizedGraphemesButAllowsItsBoundary() throws {
        let boundary = String(repeating: "x", count: 12) + String(repeating: "\u{0301}", count: 8_186)
        XCTAssertEqual(boundary.count, 12)
        XCTAssertEqual(boundary.utf8.count, 16 * 1024)
        XCTAssertNoThrow(try VaultCodec.createSession(password: boundary))
        let oversized = boundary + "\u{0301}"
        XCTAssertEqual(oversized.count, 12)
        XCTAssertThrowsError(try VaultCodec.createSession(password: oversized)) {
            XCTAssertEqual($0 as? VaultError, .invalidField("新主密码的 UTF-8 编码不能超过 16 KiB。"))
        }
    }

    func testLegacyPasswordBeyondNewByteLimitStillDecryptsUsingItsExactUTF8Bytes() throws {
        // Construct the previous release's PBKDF2 input path independently.
        // Embedded NUL and combining scalars must not be truncated or normalized.
        let legacyPassword = "legacy-fixture\0-key" + String(repeating: "\u{0301}", count: 16_384)
        XCTAssertTrue(legacyPassword.utf8.count > 16 * 1024)
        XCTAssertTrue((12...1024).contains(legacyPassword.count))
        var passwordBytes = Array(legacyPassword.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        defer {
            _ = passwordBytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            _ = derived.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }
        let salt = Data(repeating: 0x47, count: 32)
        let byteCount = passwordBytes.count
        let status = passwordBytes.withUnsafeBytes { bytes in
            salt.withUnsafeBytes { saltBytes in
                derived.withUnsafeMutableBytes { key in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                        bytes.baseAddress!.assumingMemoryBound(to: Int8.self), byteCount,
                                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000,
                                        key.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        XCTAssertEqual(status, Int32(kCCSuccess))
        let legacySession = VaultSession(key: SymmetricKey(data: derived), salt: salt)
        let fixture = try VaultCodec.encrypt(VaultDocument(entries: [fixtureEntry]), session: legacySession)
        let reopened = try VaultCodec.decrypt(fixture, password: legacyPassword)
        XCTAssertEqual(reopened.document.entries, [fixtureEntry])
        XCTAssertEqual(reopened.session.key, legacySession.key)
        XCTAssertThrowsError(try VaultCodec.decrypt(fixture, password: legacyPassword + "\u{0301}")) {
            XCTAssertEqual($0 as? VaultError, .authenticationFailed)
        }
        XCTAssertThrowsError(try VaultCodec.createSession(password: legacyPassword))
    }

    func testEntryURLsAreBookmarksWithoutEmbeddedCredentials() throws {
        for value in ["ftp://example.com", "https://name:password@example.com", "https://example.com/?token=test", "https://example.com/#token", "not a URL", "https://"] {
            var entry = fixtureEntry; entry.baseURL = value
            XCTAssertThrowsError(try entry.validated())
            entry = fixtureEntry; entry.website = value
            XCTAssertThrowsError(try entry.validated())
        }
        var local = fixtureEntry; local.baseURL = "http://127.0.0.1:8080/v1"
        XCTAssertNoThrow(try local.validated())
        var normalized = fixtureEntry; normalized.name = "  Sample  "; normalized.tags = [" test ", "test", "", "other"]
        XCTAssertEqual(try normalized.validated().name, "Sample")
        XCTAssertEqual(try normalized.validated().tags, ["test", "other"])
    }

    func testDuplicateIdentifiersAndUnknownDocumentVersionsAreRejected() throws {
        let session = try VaultCodec.createSession(password: password)
        XCTAssertThrowsError(try VaultCodec.encrypt(VaultDocument(entries: [fixtureEntry, fixtureEntry]), session: session))
        var document = VaultDocument(); document.version = 99
        XCTAssertThrowsError(try VaultCodec.encrypt(document, session: session))
    }

    func testSymbolicLinkDestinationsCannotBeReadOrReplaced() throws {
        let root = try temporaryDirectory()
        let outside = root.appendingPathComponent("outside.txt")
        let sentinel = Data("Do not overwrite this fixture".utf8)
        try sentinel.write(to: outside)
        let storage = try VaultStorage(directory: root.appendingPathComponent("vault"))
        try FileManager.default.createSymbolicLink(at: storage.fileURL, withDestinationURL: outside)
        XCTAssertTrue(storage.exists)
        XCTAssertThrowsError(try storage.read())
        let encrypted = try VaultCodec.encrypt(VaultDocument(), session: VaultCodec.createSession(password: password))
        XCTAssertThrowsError(try storage.write(encrypted))
        XCTAssertEqual(try Data(contentsOf: outside), sentinel)
        let directoryLink = root.appendingPathComponent("linked-directory")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: storage.directory)
        XCTAssertThrowsError(try VaultStorage(directory: directoryLink))
    }

    func testHardLinkedVaultCannotChangeOutsideFilePermissionsOrReplaceItsAlias() throws {
        let root = try temporaryDirectory()
        let storage = try VaultStorage(directory: root.appendingPathComponent("vault"))
        let session = try VaultCodec.createSession(password: password)
        let original = try VaultCodec.encrypt(VaultDocument(entries: [fixtureEntry]), session: session)
        let replacement = try VaultCodec.encrypt(VaultDocument(), session: session)
        let outside = root.appendingPathComponent("outside-fixture.keynest")
        try original.write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: outside.path)
        XCTAssertEqual(link(outside.path, storage.fileURL.path), 0)

        XCTAssertTrue(storage.exists)
        XCTAssertThrowsError(try VaultStorage(directory: storage.directory))
        XCTAssertThrowsError(try storage.read())
        XCTAssertThrowsError(try storage.write(replacement))
        XCTAssertEqual(try Data(contentsOf: outside), original)
        XCTAssertEqual(try Data(contentsOf: storage.fileURL), original)
        let mode = try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o644)

        // Removing the rejected alias permits a normal independent vault write;
        // it must not modify the other link's data or permissions afterward.
        try FileManager.default.removeItem(at: storage.fileURL)
        try storage.write(replacement)
        XCTAssertEqual(try storage.read(), replacement)
        XCTAssertEqual(try Data(contentsOf: outside), original)
        let remainingMode = try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(remainingMode?.intValue, 0o644)
    }

    func testAuthenticatedButMalformedPayloadIsRejected() throws {
        let session = try VaultCodec.createSession(password: password)
        let valid = try VaultCodec.encrypt(VaultDocument(entries: [fixtureEntry]), session: session)
        var encryptedEnvelope = try envelope(valid)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(VaultDocument(entries: [fixtureEntry]))) as? [String: Any])
        payload["unknownSensitiveField"] = "must not be silently accepted"
        let plaintext = try JSONSerialization.data(withJSONObject: payload)
        let nonce = AES.GCM.Nonce()
        let header = Data("Keynest|format=keynest-vault|version=1|cipher=aes-256-gcm|kdf=pbkdf2-sha256|iterations=600000|salt=\(session.salt.base64EncodedString())".utf8)
        let box = try AES.GCM.seal(plaintext, using: session.key, nonce: nonce, authenticating: header)
        encryptedEnvelope["nonce"] = Data(nonce).base64EncodedString()
        encryptedEnvelope["ciphertext"] = box.ciphertext.base64EncodedString()
        encryptedEnvelope["tag"] = box.tag.base64EncodedString()
        XCTAssertThrowsError(try VaultCodec.decrypt(encoded(encryptedEnvelope), password: password)) { error in
            XCTAssertEqual(error as? VaultError, .invalidFormat)
        }
    }

    func testMergingExactDuplicateRetainsOneOriginalEntry() throws {
        let existing = VaultDocument(entries: [fixtureEntry])
        let merged = try existing.merging(VaultDocument(entries: [fixtureEntry]))
        XCTAssertEqual(merged.entries, [fixtureEntry])
        XCTAssertEqual(existing.entries, [fixtureEntry])
    }

    func testMergingMetadataOnlyChangesRetainsBothVersions() throws {
        var incomingEntry = fixtureEntry
        incomingEntry.notes = "Different notes from the backup"
        incomingEntry.tags = ["backup-tag"]
        incomingEntry.website = "https://example.com/another-console"
        let existing = VaultDocument(entries: [fixtureEntry])
        let merged = try existing.merging(VaultDocument(entries: [incomingEntry]))
        XCTAssertEqual(merged.entries.count, 2)
        XCTAssertEqual(merged.entries[0], fixtureEntry)
        XCTAssertNotEqual(merged.entries[1].id, fixtureEntry.id)
        var restoredOriginalID = merged.entries[1]
        restoredOriginalID.id = fixtureEntry.id
        XCTAssertEqual(restoredOriginalID, incomingEntry)
        XCTAssertEqual(existing.entries, [fixtureEntry])
    }

    func testMergingIdentifierCollisionCreatesCopyAndPreservesUnrelatedIDs() throws {
        var conflicting = fixtureEntry
        conflicting.secret = "sk-another-test-only-secret"
        var unrelated = fixtureEntry
        unrelated.id = UUID()
        unrelated.name = "An unrelated entry"
        let incoming = VaultDocument(entries: [conflicting, unrelated])
        let merged = try VaultDocument(entries: [fixtureEntry]).merging(incoming)
        XCTAssertEqual(merged.entries.count, 3)
        XCTAssertEqual(merged.entries[0], fixtureEntry)
        XCTAssertNotEqual(merged.entries[1].id, fixtureEntry.id)
        XCTAssertEqual(merged.entries[1].secret, conflicting.secret)
        XCTAssertEqual(merged.entries[2], unrelated)
        XCTAssertEqual(Set(merged.entries.map(\.id)).count, 3)
        XCTAssertEqual(incoming.entries, [conflicting, unrelated])
    }

    func testMergingRespectsCapacityAfterExactDeduplication() throws {
        let entries = (0..<2000).map { _ -> SecretEntry in
            var entry = fixtureEntry; entry.id = UUID(); return entry
        }
        let existing = VaultDocument(entries: entries)
        XCTAssertEqual(try existing.merging(VaultDocument(entries: [entries[0]])).entries.count, 2000)
        var additional = fixtureEntry
        additional.id = UUID()
        XCTAssertThrowsError(try existing.merging(VaultDocument(entries: [additional])))
        XCTAssertEqual(existing.entries, entries)
    }
}
