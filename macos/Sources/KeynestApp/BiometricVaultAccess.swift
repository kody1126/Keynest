import Foundation
import CryptoKit
import LocalAuthentication
import Security
import Darwin

enum BiometricStatus: Equatable, Sendable {
    case unavailable(String)
    case notEnrolled
    case enrolled
}

enum BiometricAccessError: Error, LocalizedError, Sendable {
    case cancelled
    case unavailable(String)
    case notEnrolled
    case authenticationFailed
    case invalidEnrollment
    case storageFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: return "已取消 Touch ID 验证。"
        case .unavailable(let message): return message
        case .notEnrolled: return "尚未为这个密钥库启用 Touch ID，请先用主密码解锁。"
        case .authenticationFailed: return "Touch ID 未能解锁。请使用主密码；如已更改指纹，请重新启用 Touch ID。"
        case .invalidEnrollment: return "Touch ID 凭据已失效，请使用主密码解锁后重新启用。"
        case .storageFailed: return "无法安全读写本机 Touch ID 凭据，请检查数据目录权限。"
        }
    }
}

protocol BiometricVaultAccessing: Sendable {
    func status() async -> BiometricStatus
    func enroll(token: Data) async throws
    func unlockData() async throws -> Data
    func remove() async throws
    func cancel()
}

/// The opaque Secure Enclave key representation is device-bound. The vault
/// session token is AES-GCM-wrapped, never written as plaintext. Only the
/// enclave's private ECDH operation can unwrap it, and that operation has a
/// system-enforced current-biometric-set ACL. There is no LAContext-only gate,
/// device-password fallback, synchronizable item, or legacy Keychain fallback.
///
/// @unchecked Sendable: filesystem/crypto work is serialized on queue; the
/// cancellation epoch and active LAContext are protected by stateLock.
final class BiometricVaultAccess: BiometricVaultAccessing, @unchecked Sendable {
    typealias Status = BiometricStatus

    private struct Record: Codable {
        let format: String
        let version: Int
        let vaultBinding: String
        let opaquePrivateKey: Data
        let peerPublicKey: Data
        let hkdfSalt: Data
        let sealedToken: Data
    }

    private let queue = DispatchQueue(label: "local.keynest.biometric", qos: .userInitiated)
    private let stateLock = NSLock()
    private var generation: UInt64 = 0
    private var activeContext: LAContext?
    private let directory: URL
    private let binding: String
    private let filename = "biometric-unlock.keynestlocal"
    private let maximumRecordSize = 16 * 1024

    init(vaultIdentifier: String) {
        let vault = URL(fileURLWithPath: vaultIdentifier).standardizedFileURL.resolvingSymlinksInPath()
        directory = vault.deletingLastPathComponent()
        binding = SHA256.hash(data: Data(vault.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func status() async -> BiometricStatus {
        do {
            return try await perform { context, _ in
                context.interactionNotAllowed = true
                try self.requireBiometry(context)
                guard let data = try self.readRecord() else { return .notEnrolled }
                do {
                    let record = try self.decode(data)
                    // Rehydration validates the opaque representation without
                    // performing the protected private-key operation.
                    _ = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                        dataRepresentation: record.opaquePrivateKey, authenticationContext: context)
                    return .enrolled
                } catch { return .notEnrolled }
            }
        } catch BiometricAccessError.invalidEnrollment {
            return .notEnrolled
        } catch {
            return .unavailable(Self.friendly(error).localizedDescription)
        }
    }

    func enroll(token: Data) async throws {
        guard !token.isEmpty, token.count <= 4096 else { throw BiometricAccessError.invalidEnrollment }
        try await perform(checkingCompletion: false) { context, epoch in
            // Explicit enablement occurs only after password unlock. Wrapping
            // uses an ephemeral software peer and the enclave PUBLIC key, so
            // enrollment itself needs no biometric prompt or cached approval.
            context.interactionNotAllowed = true
            try self.requireBiometry(context)
            var error: Unmanaged<CFError>?
            guard let acl = SecAccessControlCreateWithFlags(nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet, .privateKeyUsage], &error) else {
                throw BiometricAccessError.unavailable("无法创建系统 Touch ID 访问控制。")
            }
            let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                accessControl: acl, authenticationContext: context)
            let peer = P256.KeyAgreement.PrivateKey()
            let salt = try self.randomData(count: 32)
            let shared = try peer.sharedSecretFromKeyAgreement(with: privateKey.publicKey)
            let key = self.wrappingKey(shared, salt: salt)
            let opaque = privateKey.dataRepresentation
            let publicKey = peer.publicKey.x963Representation
            let aad = self.authenticatedHeader(opaque: opaque, peer: publicKey, salt: salt)
            guard let sealed = try AES.GCM.seal(token, using: key, authenticating: aad).combined else {
                throw BiometricAccessError.invalidEnrollment
            }
            let record = Record(format: "keynest-biometric-envelope", version: 1, vaultBinding: self.binding,
                                opaquePrivateKey: opaque, peerPublicKey: publicKey, hkdfSalt: salt, sealedToken: sealed)
            let encoded = try JSONEncoder().encode(record)
            // Cancellation and commit are linearized by the same lock. A lock
            // before commit prevents enrollment; after commit it is completed.
            self.stateLock.lock()
            defer { self.stateLock.unlock() }
            guard self.generation == epoch else { throw BiometricAccessError.cancelled }
            try self.writeRecord(encoded)
        }
    }

    func unlockData() async throws -> Data {
        try await perform { context, epoch in
            try self.requireBiometry(context)
            guard let data = try self.readRecord() else { throw BiometricAccessError.notEnrolled }
            let record = try self.decode(data)
            let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: record.opaquePrivateKey, authenticationContext: context)
            let peer = try P256.KeyAgreement.PublicKey(x963Representation: record.peerPublicKey)
            // The OS challenges Touch ID here. No software key capable of this
            // private operation is persisted, and the LAContext is never reused.
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
            try self.check(epoch)
            let key = self.wrappingKey(shared, salt: record.hkdfSalt)
            let aad = self.authenticatedHeader(opaque: record.opaquePrivateKey, peer: record.peerPublicKey, salt: record.hkdfSalt)
            var token = try AES.GCM.open(AES.GCM.SealedBox(combined: record.sealedToken), using: key, authenticating: aad)
            do { try self.check(epoch) }
            catch { token.resetBytes(in: 0..<token.count); throw error }
            guard !token.isEmpty, token.count <= 4096 else { throw BiometricAccessError.invalidEnrollment }
            return token
        }
    }

    func remove() async throws {
        try await perform(checkingCompletion: false) { context, epoch in
            context.interactionNotAllowed = true
            self.stateLock.lock()
            defer { self.stateLock.unlock() }
            guard self.generation == epoch else { throw BiometricAccessError.cancelled }
            let fd = try self.openDirectory()
            defer { Darwin.close(fd) }
            guard try self.destinationExists(fd) else { return }
            guard unlinkat(fd, self.filename, 0) == 0, fsync(fd) == 0 else { throw BiometricAccessError.storageFailed }
        }
    }

    func cancel() {
        stateLock.lock()
        generation &+= 1
        let context = activeContext
        stateLock.unlock()
        context?.invalidate()
    }

    private func perform<T: Sendable>(checkingCompletion: Bool = true,
        _ operation: @escaping @Sendable (LAContext, UInt64) throws -> T) async throws -> T {
        let epoch = currentGeneration()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    let context = LAContext()
                    context.touchIDAuthenticationAllowableReuseDuration = 0
                    context.localizedFallbackTitle = ""
                    context.localizedReason = "使用 Touch ID 解锁 Keynest 密钥库"
                    do {
                        try self.activate(context, epoch: epoch)
                        defer { self.finish(context) }
                        let result = try operation(context, epoch)
                        // Mutations already validate and commit under stateLock;
                        // a later cancellation must not relabel a completed
                        // enrollment/removal as an uncommitted operation.
                        if checkingCompletion { try self.check(epoch) }
                        continuation.resume(returning: result)
                    } catch {
                        context.invalidate()
                        continuation.resume(throwing: Self.friendly(error))
                    }
                }
            }
        } onCancel: { self.cancel() }
    }

    private func currentGeneration() -> UInt64 {
        stateLock.lock(); defer { stateLock.unlock() }
        return generation
    }

    private func activate(_ context: LAContext, epoch: UInt64) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        guard generation == epoch else { throw BiometricAccessError.cancelled }
        activeContext = context
    }

    private func finish(_ context: LAContext) {
        stateLock.lock()
        if activeContext === context { activeContext = nil }
        stateLock.unlock()
        context.invalidate()
    }

    private func check(_ epoch: UInt64) throws {
        guard currentGeneration() == epoch else { throw BiometricAccessError.cancelled }
    }

    private func requireBiometry(_ context: LAContext) throws {
        guard SecureEnclave.isAvailable else { throw BiometricAccessError.unavailable("这台 Mac 暂时无法使用 Secure Enclave，请使用主密码。") }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .touchID else {
            throw BiometricAccessError.unavailable("Touch ID 暂不可用，请先在系统设置中录入指纹，或使用主密码。")
        }
    }

    private func decode(_ data: Data) throws -> Record {
        guard data.count <= maximumRecordSize else { throw BiometricAccessError.invalidEnrollment }
        let record: Record
        do { record = try JSONDecoder().decode(Record.self, from: data) }
        catch { throw BiometricAccessError.invalidEnrollment }
        guard record.format == "keynest-biometric-envelope", record.version == 1,
              record.vaultBinding == binding, (100...4096).contains(record.opaquePrivateKey.count),
              record.peerPublicKey.count == 65, record.hkdfSalt.count == 32,
              (29...4124).contains(record.sealedToken.count) else { throw BiometricAccessError.invalidEnrollment }
        return record
    }

    private func wrappingKey(_ shared: SharedSecret, salt: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
            sharedInfo: Data("Keynest|biometric-wrap|v1|\(binding)".utf8), outputByteCount: 32)
    }

    private func authenticatedHeader(opaque: Data, peer: Data, salt: Data) -> Data {
        Data("Keynest|biometric-envelope|v1|\(binding)|\(opaque.base64EncodedString())|\(peer.base64EncodedString())|\(salt.base64EncodedString())".utf8)
    }

    private func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        guard data.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }) == errSecSuccess else {
            throw BiometricAccessError.invalidEnrollment
        }
        return data
    }

    private func openDirectory() throws -> Int32 {
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BiometricAccessError.storageFailed }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else {
            Darwin.close(fd); throw BiometricAccessError.storageFailed
        }
        return fd
    }

    private func destinationExists(_ fd: Int32) throws -> Bool {
        var info = stat()
        if fstatat(fd, filename, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw BiometricAccessError.storageFailed }
            return false
        }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1 else {
            throw BiometricAccessError.storageFailed
        }
        return true
    }

    private func readRecord() throws -> Data? {
        let directoryFD = try openDirectory()
        defer { Darwin.close(directoryFD) }
        guard try destinationExists(directoryFD) else { return nil }
        let fd = openat(directoryFD, filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw BiometricAccessError.storageFailed }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(),
              info.st_nlink == 1,
              (info.st_mode & 0o077) == 0 else { throw BiometricAccessError.storageFailed }
        guard info.st_size <= maximumRecordSize else { throw BiometricAccessError.invalidEnrollment }
        var result = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let length = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            if length < 0 { if errno == EINTR { continue }; throw BiometricAccessError.storageFailed }
            if length == 0 { return result }
            guard result.count + length <= maximumRecordSize else { throw BiometricAccessError.storageFailed }
            result.append(contentsOf: bytes.prefix(length))
        }
    }

    private func writeRecord(_ data: Data) throws {
        guard data.count <= maximumRecordSize else { throw BiometricAccessError.invalidEnrollment }
        let directoryFD = try openDirectory()
        defer { Darwin.close(directoryFD) }
        _ = try destinationExists(directoryFD)
        let temporary = ".biometric-\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BiometricAccessError.storageFailed }
        defer { Darwin.close(fd); unlinkat(directoryFD, temporary, 0) }
        guard fchmod(fd, 0o600) == 0 else { throw BiometricAccessError.storageFailed }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let length = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if length < 0 { if errno == EINTR { continue }; throw BiometricAccessError.storageFailed }
                guard length > 0 else { throw BiometricAccessError.storageFailed }
                offset += length
            }
        }
        guard fsync(fd) == 0 else { throw BiometricAccessError.storageFailed }
        _ = try destinationExists(directoryFD)
        guard renameat(directoryFD, temporary, directoryFD, filename) == 0, fsync(directoryFD) == 0 else {
            throw BiometricAccessError.storageFailed
        }
    }

    private static func friendly(_ error: Error) -> BiometricAccessError {
        if let error = error as? BiometricAccessError { return error }
        if error is CancellationError { return .cancelled }
        let nsError = error as NSError
        if nsError.domain == LAError.errorDomain,
           [LAError.userCancel.rawValue, LAError.appCancel.rawValue, LAError.systemCancel.rawValue].contains(nsError.code) {
            return .cancelled
        }
        return .authenticationFailed
    }
}
