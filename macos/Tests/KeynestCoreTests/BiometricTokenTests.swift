import XCTest
import Foundation
import CryptoKit
@testable import KeynestCore

final class BiometricTokenTests: XCTestCase {
    private let password = "fake-biometric-tests-only-2026"

    func testBiometricTokenRoundTripAndContinuedSaving() throws {
        let session = try VaultCodec.createSession(password: password)
        let tool = ToolGroup(name: "Fictional tool")
        let entry = SecretEntry(name: "Fake credential", secret: "fake-test-secret-only", toolIDs: [tool.id])
        let document = VaultDocument(entries: [entry], tools: [tool])
        let encrypted = try VaultCodec.encrypt(document, session: session)
        let token = try VaultCodec.biometricUnlockData(session: session)
        XCTAssertFalse(token.range(of: Data(password.utf8)) != nil)
        XCTAssertFalse(token.range(of: Data(entry.secret.utf8)) != nil)
        let unlocked = try VaultCodec.decrypt(encrypted, biometricUnlockData: token)
        XCTAssertEqual(unlocked.document.entries, document.entries)
        XCTAssertEqual(unlocked.document.tools, document.tools)
        XCTAssertEqual(unlocked.document.version, document.version)
        XCTAssertFalse(unlocked.requiresUpgrade)
        let saved = try VaultCodec.encrypt(document, session: unlocked.session)
        XCTAssertEqual(try VaultCodec.decrypt(saved, password: password).document.entries, document.entries)
        XCTAssertEqual(try VaultCodec.decrypt(saved, biometricUnlockData: token).document.tools, document.tools)
    }

    func testEverySingleByteTokenMutationIsRejected() throws {
        let session = try VaultCodec.createSession(password: password)
        let encrypted = try VaultCodec.encrypt(VaultDocument(), session: session)
        let token = try VaultCodec.biometricUnlockData(session: session)
        for index in token.indices {
            var modified = token
            modified[index] ^= 1
            XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: modified))
        }
        XCTAssertNoThrow(try VaultCodec.decrypt(encrypted, biometricUnlockData: token))
    }

    func testTokenSlicesUseOffsetsRelativeToTheirActualStartIndex() throws {
        let session = try VaultCodec.createSession(password: password)
        let entry = SecretEntry(name: "Sliced-token fixture", secret: "fake-sliced-token-secret")
        let encrypted = try VaultCodec.encrypt(VaultDocument(entries: [entry]), session: session)
        let token = try VaultCodec.biometricUnlockData(session: session)
        for prefixLength in [1, 200] {
            let padded = Data(repeating: 0, count: prefixLength) + token
            let slice = padded.dropFirst(prefixLength)
            XCTAssertEqual(slice.startIndex, prefixLength)
            XCTAssertEqual(slice.count, token.count)
            let reopened = try VaultCodec.decrypt(encrypted, biometricUnlockData: slice)
            XCTAssertEqual(reopened.document.entries, [entry])
            XCTAssertEqual(reopened.sourceVersion, 5)
            var damaged = slice
            damaged[damaged.endIndex - 1] ^= 1
            XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: damaged)) {
                XCTAssertEqual($0 as? VaultError, .authenticationFailed)
            }
            XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: slice.dropLast())) {
                XCTAssertEqual($0 as? VaultError, .invalidFormat)
            }
        }
    }

    func testTruncatedExtendedAndEmptyTokensAreRejected() throws {
        let session = try VaultCodec.createSession(password: password)
        let encrypted = try VaultCodec.encrypt(VaultDocument(), session: session)
        let token = try VaultCodec.biometricUnlockData(session: session)
        for count in 0..<token.count {
            XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: Data(token.prefix(count))))
        }
        XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: token + Data([0])))
        XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: Data(repeating: 0, count: 4096)))
    }

    func testAnotherVaultWithSamePasswordRejectsToken() throws {
        let first = try VaultCodec.createSession(password: password)
        let second = try VaultCodec.createSession(password: password)
        let encrypted = try VaultCodec.encrypt(VaultDocument(), session: second)
        XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: VaultCodec.biometricUnlockData(session: first))) { error in
            XCTAssertEqual(error as? VaultError, .authenticationFailed)
        }
        XCTAssertNoThrow(try VaultCodec.decrypt(encrypted, password: password))
    }

    func testChangedMasterPasswordRejectsOldToken() throws {
        let old = try VaultCodec.createSession(password: password)
        let replacementPassword = "fake-replacement-password-only-2026"
        let replacement = try VaultCodec.createSession(password: replacementPassword)
        let encrypted = try VaultCodec.encrypt(VaultDocument(), session: replacement)
        XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: VaultCodec.biometricUnlockData(session: old)))
        XCTAssertNoThrow(try VaultCodec.decrypt(encrypted, password: replacementPassword))
        XCTAssertNoThrow(try VaultCodec.decrypt(encrypted, biometricUnlockData: VaultCodec.biometricUnlockData(session: replacement)))
    }

    func testWrongKeyWithCorrectSaltStillRequiresAEADAuthentication() throws {
        let session = try VaultCodec.createSession(password: password)
        let forgedSession = VaultSession(key: SymmetricKey(size: .bits256), salt: session.salt)
        let encrypted = try VaultCodec.encrypt(VaultDocument(), session: session)
        XCTAssertThrowsError(try VaultCodec.decrypt(encrypted, biometricUnlockData: VaultCodec.biometricUnlockData(session: forgedSession))) { error in
            XCTAssertEqual(error as? VaultError, .authenticationFailed)
        }
    }

    func testTamperedVaultAndWrongFormatAreRejectedWithoutWriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keynest-biometric-token-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storage = try VaultStorage(directory: directory)
        let session = try VaultCodec.createSession(password: password)
        let original = try VaultCodec.encrypt(VaultDocument(), session: session)
        try storage.write(original)
        let token = try VaultCodec.biometricUnlockData(session: session)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var tag = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(envelope["tag"] as? String)))
        tag[0] ^= 1
        envelope["tag"] = tag.base64EncodedString()
        XCTAssertThrowsError(try VaultCodec.decrypt(JSONSerialization.data(withJSONObject: envelope), biometricUnlockData: token))
        envelope["format"] = "other-format"
        XCTAssertThrowsError(try VaultCodec.decrypt(JSONSerialization.data(withJSONObject: envelope), biometricUnlockData: token))
        XCTAssertEqual(try storage.read(), original)
        XCTAssertNoThrow(try VaultCodec.decrypt(storage.read(), password: password))
    }
}
