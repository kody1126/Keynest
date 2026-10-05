import Foundation
import CryptoKit
import CommonCrypto
import Security

public struct VaultSession: Sendable {
    internal let key: SymmetricKey
    internal let salt: Data
}

public enum VaultCodec {
    public static let maximumFileSize = 4 * 1024 * 1024
    private static let iterations = 600_000
    private static let formatName = "keynest-vault"
    private static let cipherName = "aes-256-gcm"
    private static let kdfName = "pbkdf2-sha256"
    private static let biometricTokenPrefix = Data("KeynestBiometricSession/v1\0".utf8)

    private struct KDF: Codable {
        let name: String
        let iterations: Int
        let salt: String
    }

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let cipher: String
        let kdf: KDF
        let nonce: String
        let ciphertext: String
        let tag: String
    }

    public static func validatePassword(_ password: String) throws {
        guard (12...1024).contains(password.count) else { throw VaultError.invalidPassword }
    }

    public static func createSession(password: String) throws -> VaultSession {
        // A grapheme may contain arbitrarily many combining scalars. Bound new
        // passwords in bytes, while decrypt keeps accepting legacy passwords.
        guard password.utf8.count <= 16 * 1024 else {
            throw VaultError.invalidField("新主密码的 UTF-8 编码不能超过 16 KiB。")
        }
        try validatePassword(password)
        let salt = try randomData(count: 32)
        return VaultSession(key: try deriveKey(password: password, salt: salt), salt: salt)
    }

    public static func encrypt(_ document: VaultDocument, session: VaultSession) throws -> Data {
        guard session.salt.count == 32, session.key.bitCount == 256 else { throw VaultError.cryptographyFailed }
        let validated = try document.validated()
        var plaintext: Data
        do { plaintext = try JSONEncoder().encode(validated) }
        catch { throw VaultError.invalidFormat }
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        guard plaintext.count <= maximumFileSize else { throw VaultError.fileTooLarge }
        do {
            let nonceData = try randomData(count: 12)
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.seal(plaintext, using: session.key, nonce: nonce,
                                       authenticating: authenticatedHeader(salt: session.salt))
            let envelope = Envelope(format: formatName, version: 1, cipher: cipherName,
                                    kdf: KDF(name: kdfName, iterations: iterations, salt: session.salt.base64EncodedString()),
                                    nonce: nonceData.base64EncodedString(),
                                    ciphertext: box.ciphertext.base64EncodedString(), tag: box.tag.base64EncodedString())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(envelope)
            guard encoded.count <= maximumFileSize else { throw VaultError.fileTooLarge }
            return encoded
        } catch let error as VaultError { throw error }
        catch { throw VaultError.cryptographyFailed }
    }

    public static func decrypt(_ data: Data, password: String) throws -> (document: VaultDocument, session: VaultSession, requiresUpgrade: Bool, sourceVersion: Int) {
        let envelope = try parseEnvelope(data)
        try validatePassword(password)
        let salt = try canonicalBase64(envelope.kdf.salt, count: 32)
        let key = try deriveKey(password: password, salt: salt)
        return try decrypt(envelope, key: key, salt: salt)
    }

    /// This contains the derived vault key, not the password. Treat the returned
    /// bytes as a secret: persist only behind a system-enforced biometric ACL.
    /// The format digest and random vault salt prevent cross-vault/rekey reuse.
    public static func biometricUnlockData(session: VaultSession) throws -> Data {
        guard session.salt.count == 32, session.key.bitCount == 256 else { throw VaultError.cryptographyFailed }
        var token = biometricTokenPrefix
        token.append(contentsOf: SHA256.hash(data: authenticatedHeader(salt: session.salt)))
        token.append(session.salt)
        session.key.withUnsafeBytes { token.append(contentsOf: $0) }
        return token
    }

    public static func decrypt(_ data: Data, biometricUnlockData token: Data) throws -> (document: VaultDocument, session: VaultSession, requiresUpgrade: Bool, sourceVersion: Int) {
        let envelope = try parseEnvelope(data)
        let prefixCount = biometricTokenPrefix.count
        guard token.count == prefixCount + 96, token.prefix(prefixCount) == biometricTokenPrefix else {
            throw VaultError.invalidFormat
        }
        let salt = try canonicalBase64(envelope.kdf.salt, count: 32)
        // Data slices retain their original indices. Offsets in this wire format
        // are relative to the slice start, not necessarily index zero.
        let bodyStart = token.startIndex + prefixCount
        let tokenSalt = token.subdata(in: (bodyStart + 32)..<(bodyStart + 64))
        guard tokenSalt == salt else { throw VaultError.authenticationFailed }
        let digest = Data(SHA256.hash(data: authenticatedHeader(salt: salt)))
        guard token.subdata(in: bodyStart..<(bodyStart + 32)) == digest else { throw VaultError.invalidFormat }
        var keyBytes = token.subdata(in: (bodyStart + 64)..<(bodyStart + 96))
        defer { keyBytes.resetBytes(in: 0..<keyBytes.count) }
        return try decrypt(envelope, key: SymmetricKey(data: keyBytes), salt: salt)
    }

    private static func decrypt(_ envelope: Envelope, key: SymmetricKey, salt: Data) throws -> (document: VaultDocument, session: VaultSession, requiresUpgrade: Bool, sourceVersion: Int) {
        var plaintext: Data
        do {
            let nonce = try AES.GCM.Nonce(data: canonicalBase64(envelope.nonce, count: 12))
            let box = try AES.GCM.SealedBox(nonce: nonce,
                                          ciphertext: canonicalBase64(envelope.ciphertext),
                                          tag: canonicalBase64(envelope.tag, count: 16))
            plaintext = try AES.GCM.open(box, using: key, authenticating: authenticatedHeader(salt: salt))
        } catch { throw VaultError.authenticationFailed }
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        do {
            try validatePayloadSchema(plaintext)
            let decoded = try JSONDecoder().decode(VaultDocument.self, from: plaintext)
            let document = try decoded.validated()
            return (document, VaultSession(key: key, salt: salt), decoded.version < 5, decoded.version)
        } catch { throw VaultError.invalidFormat }
    }

    // Storage accepts only structurally valid encrypted envelopes. Authentication
    // is performed separately by decrypt before a backup is restored.
    internal static func validateEncryptedFile(_ data: Data) throws {
        _ = try parseEnvelope(data)
    }

    private static func parseEnvelope(_ data: Data) throws -> Envelope {
        guard data.count <= maximumFileSize else { throw VaultError.fileTooLarge }
        guard !data.isEmpty else { throw VaultError.invalidFormat }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            let envelopeObject = try strictObject(object, required: ["format", "version", "cipher", "kdf", "nonce", "ciphertext", "tag"])
            _ = try strictObject(envelopeObject["kdf"] as Any, required: ["name", "iterations", "salt"])
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.format == formatName, envelope.version == 1, envelope.cipher == cipherName,
                  envelope.kdf.name == kdfName, envelope.kdf.iterations == iterations else {
                throw VaultError.invalidFormat
            }
            _ = try canonicalBase64(envelope.kdf.salt, count: 32)
            _ = try canonicalBase64(envelope.nonce, count: 12)
            _ = try canonicalBase64(envelope.tag, count: 16)
            let ciphertext = try canonicalBase64(envelope.ciphertext)
            guard !ciphertext.isEmpty else { throw VaultError.invalidFormat }
            return envelope
        } catch { throw VaultError.invalidFormat }
    }

    private static func authenticatedHeader(salt: Data) -> Data {
        Data("Keynest|format=\(formatName)|version=1|cipher=\(cipherName)|kdf=\(kdfName)|iterations=\(iterations)|salt=\(salt.base64EncodedString())".utf8)
    }

    private static func canonicalBase64(_ value: String, count: Int? = nil) throws -> Data {
        guard let decoded = Data(base64Encoded: value), decoded.base64EncodedString() == value,
              count == nil || decoded.count == count else { throw VaultError.invalidFormat }
        return decoded
    }

    private static func randomData(count: Int) throws -> Data {
        var result = Data(count: count)
        let status = result.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw VaultError.cryptographyFailed }
        return result
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        // Borrow contiguous UTF-8 rather than allocate a second full byte array
        // for legacy passwords that predate the new-password byte limit.
        var contiguousPassword = password
        var derived = [UInt8](repeating: 0, count: 32)
        defer {
            _ = derived.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }
        let status = contiguousPassword.withUTF8 { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                derived.withUnsafeMutableBytes { derivedBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                        UnsafeRawPointer(passwordBuffer.baseAddress!).assumingMemoryBound(to: Int8.self), passwordBuffer.count,
                                        saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                        derivedBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw VaultError.cryptographyFailed }
        return SymmetricKey(data: derived)
    }

    private static func strictObject(_ value: Any, required: Set<String>, optional: Set<String> = []) throws -> [String: Any] {
        guard let object = value as? [String: Any],
              required.isSubset(of: Set(object.keys)),
              Set(object.keys).isSubset(of: required.union(optional)) else { throw VaultError.invalidFormat }
        return object
    }

    private static func validatePayloadSchema(_ data: Data) throws {
        let document = try strictObject(JSONSerialization.jsonObject(with: data), required: ["version", "entries"], optional: ["tools", "keychainConfiguration", "homeProviderOrder"])
        let version = document["version"] as? Int ?? 0
        if let order = document["homeProviderOrder"] {
            guard version == 5, let ids = order as? [String], ids.count <= 2000 else { throw VaultError.invalidFormat }
        }
        if let configuration = document["keychainConfiguration"] {
            guard [4, 5].contains(version) else { throw VaultError.invalidFormat }
            let object = try strictObject(configuration, required: ["charms"])
            guard let charms = object["charms"] as? [Any], charms.count <= 8 else { throw VaultError.invalidFormat }
            for charm in charms {
                let optional: Set<String> = version == 5 ? ["providerID", "customGroupID", "credentialID"] : ["providerID", "customGroupID"]
                _ = try strictObject(charm, required: ["color"], optional: optional)
            }
        }
        guard let entries = document["entries"] as? [Any], entries.count <= 2000 else { throw VaultError.invalidFormat }
        if let toolValue = document["tools"] {
            guard let tools = toolValue as? [Any], tools.count <= 100 else { throw VaultError.invalidFormat }
            for tool in tools {
                let object = try strictObject(tool, required: ["id", "name", "notes", "createdAt", "updatedAt"], optional: ["templateID"])
                if let template = object["templateID"] {
                    guard [3, 4, 5].contains(version), template is String else { throw VaultError.invalidFormat }
                }
            }
        }
        let entryKeys: Set<String> = ["id", "name", "category", "provider", "secret", "baseURL", "website", "tags", "notes", "isFavorite", "quotaProvider", "createdAt", "updatedAt"]
        for value in entries {
            let entry = try strictObject(value, required: entryKeys, optional: ["quota", "toolIDs", "environment", "accountLabel"])
            if let quota = entry["quota"], !(quota is NSNull) {
                let snapshot = try strictObject(quota, required: ["kind", "metrics", "note", "fetchedAt"])
                guard let metrics = snapshot["metrics"] as? [Any], metrics.count <= 32 else { throw VaultError.invalidFormat }
                for metric in metrics {
                    _ = try strictObject(metric, required: ["label"], optional: ["value", "currency"])
                }
            }
        }
    }
}
