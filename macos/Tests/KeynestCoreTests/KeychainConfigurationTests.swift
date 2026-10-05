import Foundation
import XCTest
import CryptoKit
@testable import KeynestCore

final class KeychainConfigurationTests: XCTestCase {
    private let password = "keychain-configuration-fixture-2026"

    private func credential() -> SecretEntry {
        SecretEntry(name: "Private fixture service", secret: "fake-only-keychain-test-credential",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
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

    func testConfigurationPreservesOrderColorsAndIntentionalEmpty() throws {
        let selection = ProviderPreset.all.prefix(8).enumerated().map {
            KeychainCharmSelection(providerID: $0.element.id, color: KeychainCharmColor.allCases[$0.offset % 6])
        }
        let original = KeychainConfiguration(charms: selection)
        XCTAssertEqual(try original.validated(), original)
        XCTAssertEqual(try JSONDecoder().decode(KeychainConfiguration.self, from: JSONEncoder().encode(original)), original)
        XCTAssertEqual(try KeychainConfiguration().validated().charms, [])
        XCTAssertNil(VaultDocument().keychainConfiguration)
        XCTAssertEqual(Set(KeychainCharmColor.allCases.map(\.rawValue)), ["ice", "lavender", "mint", "amber", "rose", "graphite"])
        XCTAssertEqual(selection.first?.id, "provider:\(ProviderPreset.all[0].id)")
    }

    func testTargetsAreExclusiveKnownAndUniqueWithEightLimit() throws {
        let id = UUID()
        let validCustom = KeychainCharmSelection(customGroupID: "custom:private fixture platform", color: .mint)
        let validEntry = KeychainCharmSelection(customGroupID: "entry:\(id.uuidString)")
        XCTAssertNoThrow(try validCustom.validated())
        XCTAssertNoThrow(try validEntry.validated())
        for invalid in [KeychainCharmSelection(), .init(providerID: "openai", customGroupID: "custom:x"),
                        .init(providerID: "not-a-catalog-provider"), .init(providerID: "../openai"),
                        .init(customGroupID: "custom:"), .init(customGroupID: "custom:   "),
                        .init(customGroupID: "custom:\0"), .init(customGroupID: "entry:not-uuid"),
                        .init(customGroupID: "file:///private/example"),
                        .init(customGroupID: "custom:" + String(repeating: "x", count: 512))] {
            XCTAssertThrowsError(try invalid.validated())
        }
        XCTAssertThrowsError(try KeychainConfiguration(charms: [.init(providerID: "openai"), .init(providerID: "openai", color: .rose)]).validated())
        XCTAssertThrowsError(try KeychainConfiguration(charms: [validCustom, validCustom]).validated())
        XCTAssertThrowsError(try KeychainConfiguration(charms: ProviderPreset.all.prefix(9).map { .init(providerID: $0.id) }).validated())
        XCTAssertNoThrow(try KeychainConfiguration(charms: [validCustom, validEntry]).validated())
    }

    func testEncryptedRoundTripKeepsAutomaticAndExplicitEmptyDistinct() throws {
        let configuration = KeychainConfiguration(charms: [
            .init(customGroupID: "custom:private lantern service", color: .lavender),
            .init(providerID: "openai", color: .rose)
        ])
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        for value: KeychainConfiguration? in [nil, KeychainConfiguration(), configuration] {
            let document = VaultDocument(entries: [credential()], keychainConfiguration: value)
            let bytes = try VaultCodec.encrypt(document, session: session)
            let opened = try VaultCodec.decrypt(bytes, biometricUnlockData: token)
            XCTAssertEqual(opened.document.keychainConfiguration, value)
            XCTAssertEqual(opened.sourceVersion, 5)
            XCTAssertFalse(opened.requiresUpgrade)
            XCTAssertEqual(opened.document.entries, document.entries)
            let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(envelope["version"] as? Int, 1)
            XCTAssertEqual(envelope["cipher"] as? String, "aes-256-gcm")
            for privateValue in ["keychainConfiguration", "custom:private lantern service", credential().secret] {
                XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(privateValue))
            }
        }
        let passwordOpened = try VaultCodec.decrypt(VaultCodec.encrypt(VaultDocument(keychainConfiguration: configuration), session: session), password: password)
        XCTAssertEqual(passwordOpened.document.keychainConfiguration, configuration)
    }

    func testAllPriorPayloadVersionsUpgradeWithoutChangingRecordsOrInventingConfiguration() throws {
        let original = VaultDocument(entries: [credential()])
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        for version in 1...4 {
            var payload = try object(original); payload["version"] = version
            let bytes = try encryptedPayload(payload, session: session)
            let opened = try VaultCodec.decrypt(bytes, biometricUnlockData: token)
            XCTAssertEqual(opened.sourceVersion, version)
            XCTAssertTrue(opened.requiresUpgrade)
            XCTAssertEqual(opened.document.version, 5)
            XCTAssertNil(opened.document.keychainConfiguration)
            XCTAssertEqual(opened.document.entries, original.entries)
            let updated = try VaultCodec.encrypt(opened.document, session: opened.session)
            let reopened = try VaultCodec.decrypt(updated, biometricUnlockData: token)
            XCTAssertEqual(reopened.sourceVersion, 5)
            XCTAssertFalse(reopened.requiresUpgrade)
            XCTAssertEqual(reopened.document.entries, original.entries)
            XCTAssertNil(reopened.document.keychainConfiguration)
        }
    }

    func testAuthenticatedConfigurationRejectsMalformedNestedSchema() throws {
        let session = try VaultCodec.createSession(password: password)
        let token = try VaultCodec.biometricUnlockData(session: session)
        let base = try object(VaultDocument())
        let good: [String: Any] = ["providerID": "openai", "color": "ice"]
        let configurations: [Any] = [
            NSNull(), [], "invalid", [:], ["charms": NSNull()], ["charms": [], "unknown": true],
            ["charms": [["providerID": "openai"]]],
            ["charms": [["providerID": NSNull(), "color": "ice"]]],
            ["charms": [["providerID": 1, "color": "ice"]]],
            ["charms": [["providerID": "openai", "customGroupID": "custom:x", "color": "ice"]]],
            ["charms": [["customGroupID": NSNull(), "color": "ice"]]],
            ["charms": [["providerID": "openai", "color": "unrecognized"]]],
            ["charms": [["providerID": "openai", "color": NSNull()]]],
            ["charms": [["providerID": "openai", "color": "ice", "unknown": true]]],
            ["charms": [["color": "ice"]]], ["charms": [good, good]],
            ["charms": ProviderPreset.all.prefix(9).map { ["providerID": $0.id, "color": "ice"] }]
        ]
        for configuration in configurations {
            var payload = base; payload["keychainConfiguration"] = configuration
            XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(payload, session: session), biometricUnlockData: token)) {
                XCTAssertEqual($0 as? VaultError, .invalidFormat)
            }
        }
        for version in 1...3 {
            var payload = base; payload["version"] = version; payload["keychainConfiguration"] = ["charms": [good]]
            XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(payload, session: session), biometricUnlockData: token))
            XCTAssertThrowsError(try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: payload)))
        }
        var null = base; null["keychainConfiguration"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(VaultDocument.self, from: JSONSerialization.data(withJSONObject: null)))
        var future = base; future["version"] = 6
        XCTAssertThrowsError(try VaultCodec.decrypt(encryptedPayload(future, session: session), biometricUnlockData: token))
    }

    func testMergeKeepsLocalChoicesIncludingIntentionalEmpty() throws {
        let incoming = VaultDocument(keychainConfiguration: .init(charms: [.init(providerID: "anthropic", color: .amber)]))
        for local in [KeychainConfiguration(), .init(charms: [.init(providerID: "openai", color: .mint)])] {
            let merged = try VaultDocument(keychainConfiguration: local).merging(incoming)
            XCTAssertEqual(merged.keychainConfiguration, local)
            XCTAssertEqual(try merged.merging(incoming).keychainConfiguration, local)
        }
        XCTAssertEqual(try VaultDocument().merging(incoming).keychainConfiguration, incoming.keychainConfiguration)
        XCTAssertNil(try VaultDocument().merging(VaultDocument()).keychainConfiguration)
    }

    func testMergeRemapsImportedAnonymousGroupAfterEntryIDConflict() throws {
        let existing = credential()
        var incomingEntry = existing; incomingEntry.secret = "fake-only-different-imported-credential"
        let source = VaultDocument(entries: [incomingEntry], keychainConfiguration: .init(charms: [
            .init(customGroupID: "entry:\(incomingEntry.id.uuidString)", color: .graphite, credentialID: incomingEntry.id),
            .init(providerID: "openai", color: .rose)
        ]))
        let merged = try VaultDocument(entries: [existing]).merging(source)
        let imported = try XCTUnwrap(merged.entries.first { $0.secret == incomingEntry.secret })
        XCTAssertNotEqual(imported.id, incomingEntry.id)
        XCTAssertEqual(merged.keychainConfiguration?.charms.first?.customGroupID, "entry:\(imported.id.uuidString)")
        XCTAssertEqual(merged.keychainConfiguration?.charms.first?.credentialID, imported.id)
        XCTAssertEqual(merged.keychainConfiguration?.charms.last, source.keychainConfiguration?.charms.last)
        XCTAssertEqual(try merged.merging(source).entries, merged.entries)
        XCTAssertEqual(try merged.merging(source).keychainConfiguration, merged.keychainConfiguration)
        XCTAssertEqual(source.keychainConfiguration?.charms.first?.customGroupID, "entry:\(existing.id.uuidString)")
    }

    func testDeletingMetadataAndDemoCatalogValidationRetainConfiguration() throws {
        let tool = ToolGroup(name: "Fixture tool")
        var entry = credential(); entry.toolIDs = [tool.id]
        let configuration = KeychainConfiguration(charms: [.init(customGroupID: "entry:\(entry.id.uuidString)", color: .mint)])
        var document = VaultDocument(entries: [entry], tools: [tool], keychainConfiguration: configuration)
        XCTAssertEqual(try document.removingTool(id: tool.id).keychainConfiguration, configuration)
        document.entries = []
        XCTAssertEqual(try document.validated().keychainConfiguration, configuration)
        let demo = try DemoVault.upgradingCatalog(document, fromRevision: 7)
        XCTAssertEqual(demo.entries, [])
        XCTAssertEqual(demo.tools, document.tools)
        XCTAssertEqual(demo.keychainConfiguration, configuration)
        XCTAssertEqual(DemoVault.catalogRevision, 7)
    }
}
