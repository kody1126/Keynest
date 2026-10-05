import Foundation
import XCTest
import CryptoKit
@testable import KeynestCore

final class HomeProviderOrderTests: XCTestCase {
    private let password = "home-order-fixture-password-2026"

    private func object(_ document: VaultDocument) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    }

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

    func testOrderValidationKeepsNilEmptyAndKnownCustomAnonymousIDsDistinct() throws {
        let id = UUID()
        let order = ["openai", "custom:private home fixture", "entry:\(id.uuidString)"]
        XCTAssertNil(try VaultDocument().validated().homeProviderOrder)
        XCTAssertEqual(try VaultDocument(homeProviderOrder: []).validated().homeProviderOrder, [])
        XCTAssertEqual(try VaultDocument(homeProviderOrder: order).validated().homeProviderOrder, order)
        let maximum = (0..<2000).map { "custom:fixture-\($0)" }
        XCTAssertEqual(try VaultDocument(homeProviderOrder: maximum).validated().homeProviderOrder, maximum)
        for invalid in [["openai", "openai"], maximum + ["custom:one-too-many"], ["unknown-provider"],
                        ["provider:openai"], ["custom:"], ["custom:   "], ["custom:\0"],
                        ["entry:bad-uuid"], ["entry:\(id.uuidString.lowercased())"],
                        ["custom:" + String(repeating: "x", count: 512)], ["file:///private/test"]] {
            XCTAssertThrowsError(try VaultDocument(homeProviderOrder: invalid).validated())
        }
    }

    func testEncryptedRoundTripPreservesExplicitCredentialSelectionAndOrder() throws {
        let entry = SecretEntry(name: "Private key fixture", provider: "OpenAI", secret: "fake-only-home-order-key")
        let configuration = KeychainConfiguration(charms: [.init(providerID: "openai", color: .mint, credentialID: entry.id)])
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        for order: [String]? in [nil, [], ["custom:private catalog fixture", "openai"]] {
            let document = VaultDocument(entries: [entry], keychainConfiguration: configuration, homeProviderOrder: order)
            let bytes = try VaultCodec.encrypt(document, session: session)
            let opened = try VaultCodec.decrypt(bytes, biometricUnlockData: token)
            XCTAssertEqual(opened.sourceVersion, 5)
            XCTAssertFalse(opened.requiresUpgrade)
            XCTAssertEqual(opened.document.homeProviderOrder, order)
            XCTAssertEqual(opened.document.keychainConfiguration, configuration)
            XCTAssertEqual(opened.document.entries, [entry])
            for value in ["homeProviderOrder", "credentialID", "private catalog fixture", entry.id.uuidString, entry.secret] {
                XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(value))
            }
            let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(envelope["version"] as? Int, 1)
        }
    }

    func testPayloadFourUpgradesWithoutInventingASelectedCredentialOrOrder() throws {
        let entry = SecretEntry(name: "Previous release", provider: "OpenAI", secret: "fake-only-previous-release-key")
        let configuration = KeychainConfiguration(charms: [.init(providerID: "openai", color: .rose)])
        let document = VaultDocument(entries: [entry], keychainConfiguration: configuration)
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        var payload = try object(document); payload["version"] = 4
        let original = try encryptedPayload(payload, session: session)
        let opened = try VaultCodec.decrypt(original, biometricUnlockData: token)
        XCTAssertEqual(opened.sourceVersion, 4)
        XCTAssertTrue(opened.requiresUpgrade)
        XCTAssertEqual(opened.document.version, 5)
        XCTAssertEqual(opened.document.keychainConfiguration, configuration)
        XCTAssertNil(opened.document.keychainConfiguration?.charms.first?.credentialID)
        XCTAssertNil(opened.document.homeProviderOrder)
        let rewritten = try VaultCodec.decrypt(VaultCodec.encrypt(opened.document, session: opened.session), biometricUnlockData: token)
        XCTAssertEqual(rewritten.sourceVersion, 5)
        XCTAssertEqual(rewritten.document.entries, [entry])
        XCTAssertEqual(rewritten.document.keychainConfiguration, configuration)
        XCTAssertNil(rewritten.document.homeProviderOrder)
    }

    func testAuthenticatedSchemaRejectsMalformedOrderAndOldVersionFieldSmuggling() throws {
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        let base = try object(VaultDocument())
        let invalidOrders: [Any] = [NSNull(), "openai", 7, [:], [NSNull()], [7], ["openai", "openai"],
                                    ["provider:openai"], ["custom:"], ["entry:invalid"],
                                    (0..<2001).map { "custom:fixture-\($0)" }]
        for order in invalidOrders {
            var payload = base; payload["homeProviderOrder"] = order
            XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(payload, session: session), biometricUnlockData: token)) {
                XCTAssertEqual($0 as? VaultError, .invalidFormat)
            }
        }
        for version in 1...4 {
            var payload = base; payload["version"] = version; payload["homeProviderOrder"] = ["openai"]
            let data = try JSONSerialization.data(withJSONObject: payload)
            XCTAssertThrowsError(try JSONDecoder().decode(VaultDocument.self, from: data))
            XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(payload, session: session), biometricUnlockData: token))
        }
        var null = base; null["homeProviderOrder"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: null)))
    }

    func testCredentialSelectionRejectsExplicitNullMalformedUUIDAndPreVersionFiveField() throws {
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        let base = try object(VaultDocument())
        for value: Any in [NSNull(), 42, "not-a-uuid", [], ["id": UUID().uuidString]] {
            let charm: [String: Any] = ["providerID": "openai", "color": "ice", "credentialID": value]
            XCTAssertThrowsError(try JSONDecoder().decode(KeychainCharmSelection.self, from: JSONSerialization.data(withJSONObject: charm)))
            var payload = base; payload["keychainConfiguration"] = ["charms": [charm]]
            XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(payload, session: session), biometricUnlockData: token))
        }
        let selection = KeychainCharmSelection(providerID: "openai", credentialID: UUID())
        var payload = try object(VaultDocument(keychainConfiguration: .init(charms: [selection])))
        payload["version"] = 4
        XCTAssertThrowsError(try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: payload)))
        XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(payload, session: session), biometricUnlockData: token))
        XCTAssertEqual(try selection.validated(), selection, "A missing credential remains an explicit unresolved selection")
    }

    func testMergeKeepsExplicitLocalOrderAndRemapsImportedEntryAndCredentialIDs() throws {
        let localEntry = SecretEntry(name: "Unnamed provider", secret: "fake-only-local-key")
        var importedEntry = localEntry; importedEntry.secret = "fake-only-imported-key"
        let source = VaultDocument(entries: [importedEntry], keychainConfiguration: .init(charms: [
            .init(customGroupID: "entry:\(importedEntry.id.uuidString)", credentialID: importedEntry.id)
        ]), homeProviderOrder: ["entry:\(importedEntry.id.uuidString)", "openai"])
        let local = VaultDocument(entries: [localEntry])
        let merged = try local.merging(source)
        let imported = try XCTUnwrap(merged.entries.first { $0.secret == importedEntry.secret })
        XCTAssertNotEqual(imported.id, localEntry.id)
        XCTAssertEqual(merged.homeProviderOrder, ["entry:\(imported.id.uuidString)", "openai"])
        XCTAssertEqual(merged.keychainConfiguration?.charms.first?.credentialID, imported.id)
        XCTAssertEqual(merged.keychainConfiguration?.charms.first?.customGroupID, "entry:\(imported.id.uuidString)")
        let repeated = try merged.merging(source)
        XCTAssertEqual(repeated.entries, merged.entries)
        XCTAssertEqual(repeated.homeProviderOrder, merged.homeProviderOrder)
        XCTAssertEqual(repeated.keychainConfiguration, merged.keychainConfiguration)
        for order in [[], ["openai", "custom:my order"]] {
            let kept = try VaultDocument(entries: [localEntry], homeProviderOrder: order).merging(source)
            XCTAssertEqual(kept.homeProviderOrder, order)
            XCTAssertEqual(try kept.merging(source).homeProviderOrder, order)
        }
    }

    func testImportedDanglingIDsNeverBindToUnrelatedLocalCredential() throws {
        let localEntry = SecretEntry(name: "Local only", provider: "OpenAI", secret: "fake-only-local-collision")
        let source = VaultDocument(keychainConfiguration: .init(charms: [
            .init(providerID: "openai", credentialID: localEntry.id),
            .init(customGroupID: "entry:\(localEntry.id.uuidString)", credentialID: localEntry.id)
        ]), homeProviderOrder: ["entry:\(localEntry.id.uuidString)"])
        let merged = try VaultDocument(entries: [localEntry]).merging(source)
        let missingID = try XCTUnwrap(merged.keychainConfiguration?.charms.first?.credentialID)
        XCTAssertNotEqual(missingID, localEntry.id)
        XCTAssertFalse(merged.entries.contains { $0.id == missingID })
        XCTAssertEqual(merged.keychainConfiguration?.charms.last?.credentialID, missingID)
        XCTAssertEqual(merged.keychainConfiguration?.charms.last?.customGroupID, "entry:\(missingID.uuidString)")
        XCTAssertEqual(merged.homeProviderOrder, ["entry:\(missingID.uuidString)"])
        XCTAssertEqual(try merged.merging(source).keychainConfiguration, merged.keychainConfiguration)
        XCTAssertEqual(try VaultDocument(entries: [localEntry]).merging(source).homeProviderOrder, merged.homeProviderOrder)
        XCTAssertEqual(source.keychainConfiguration?.charms.first?.credentialID, localEntry.id)
    }

    func testDeletionAndDemoValidationPreserveExplicitStaleSelectionsWithoutRebinding() throws {
        let tool = ToolGroup(name: "Temporary fixture tool")
        let entry = SecretEntry(name: "Temporary fixture key", secret: "fake-only-deleted-key", toolIDs: [tool.id])
        let selection = KeychainCharmSelection(customGroupID: "entry:\(entry.id.uuidString)", credentialID: entry.id)
        let document = VaultDocument(entries: [entry], tools: [tool], keychainConfiguration: .init(charms: [selection]),
                                     homeProviderOrder: ["entry:\(entry.id.uuidString)"])
        var removed = try document.removingTool(id: tool.id)
        XCTAssertEqual(removed.homeProviderOrder, document.homeProviderOrder)
        XCTAssertEqual(removed.keychainConfiguration, document.keychainConfiguration)
        removed.entries = []
        let demo = try DemoVault.upgradingCatalog(removed, fromRevision: 7)
        XCTAssertEqual(demo.entries, [])
        XCTAssertEqual(demo.homeProviderOrder, document.homeProviderOrder)
        XCTAssertEqual(demo.keychainConfiguration, document.keychainConfiguration)
        XCTAssertEqual(DemoVault.catalogRevision, 7)
    }

    func testImportCannotReactivateLocalDeletedCredentialOrAnonymousGroup() throws {
        let branded = SecretEntry(name: "Imported replacement", provider: "OpenAI", secret: "fake-only-imported-replacement")
        let anonymous = SecretEntry(name: "Imported anonymous", secret: "fake-only-imported-anonymous")
        let configuration = KeychainConfiguration(charms: [
            .init(providerID: "openai", credentialID: branded.id),
            .init(customGroupID: "entry:\(anonymous.id.uuidString)")
        ])
        let local = VaultDocument(keychainConfiguration: configuration,
                                  homeProviderOrder: ["entry:\(anonymous.id.uuidString)", "openai"])
        let source = VaultDocument(entries: [branded, anonymous])
        let merged = try local.merging(source)
        XCTAssertEqual(merged.entries.count, 2)
        XCTAssertEqual(merged.keychainConfiguration, configuration)
        XCTAssertEqual(merged.homeProviderOrder, local.homeProviderOrder)
        XCTAssertFalse(merged.entries.contains { $0.id == branded.id || $0.id == anonymous.id })
        XCTAssertEqual(Set(merged.entries.map(\.secret)), Set(source.entries.map(\.secret)))
        let groups = HomeCatalog.groups(entries: merged.entries)
        XCTAssertFalse(groups.contains { $0.id == "entry:\(anonymous.id.uuidString)" })
        XCTAssertFalse(groups.first { $0.id == "openai" }?.entries.contains { $0.id == branded.id } ?? true)
        let repeated = try merged.merging(source)
        XCTAssertEqual(repeated.entries, merged.entries)
        XCTAssertEqual(repeated.keychainConfiguration, configuration)
        XCTAssertEqual(repeated.homeProviderOrder, local.homeProviderOrder)
        XCTAssertEqual(try local.merging(source).entries, merged.entries)
        XCTAssertEqual(source.entries, [branded, anonymous])
        XCTAssertTrue(local.entries.isEmpty)
    }

    func testLocalStaleOrderReservesIDWhileImportedConfigurationFollowsRemappedRecord() throws {
        let entry = SecretEntry(name: "Imported standalone", secret: "fake-only-imported-standalone")
        let local = VaultDocument(homeProviderOrder: ["entry:\(entry.id.uuidString)"])
        let source = VaultDocument(entries: [entry], keychainConfiguration: .init(charms: [
            .init(customGroupID: "entry:\(entry.id.uuidString)", credentialID: entry.id)
        ]), homeProviderOrder: ["entry:\(entry.id.uuidString)"])
        let merged = try local.merging(source)
        let imported = try XCTUnwrap(merged.entries.first)
        XCTAssertNotEqual(imported.id, entry.id)
        XCTAssertEqual(imported.secret, entry.secret)
        XCTAssertEqual(merged.homeProviderOrder, local.homeProviderOrder)
        XCTAssertEqual(merged.keychainConfiguration?.charms.first?.credentialID, imported.id)
        XCTAssertEqual(merged.keychainConfiguration?.charms.first?.customGroupID, "entry:\(imported.id.uuidString)")
        let repeated = try merged.merging(source)
        XCTAssertEqual(repeated.entries, merged.entries)
        XCTAssertEqual(repeated.keychainConfiguration, merged.keychainConfiguration)
        XCTAssertEqual(repeated.homeProviderOrder, merged.homeProviderOrder)
    }
}
