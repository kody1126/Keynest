// Reproducible hardware check: only fresh /private/tmp fake profiles.
// --file-only checks only temporary filesystem and cancellation boundaries,
// without querying biometric availability or creating Secure Enclave keys.
// Never invoke unlockData(): the sole private-key operation below explicitly
// sets interactionNotAllowed, so it must fail without showing a prompt.
import Foundation
import CryptoKit
import LocalAuthentication
import Darwin
struct ProbeFailure: Error { let message: String }
@main struct Probe {
    @MainActor static func main() async {
        var count = 0
        func expect(_ value: Bool, _ message: String) throws { count += 1; if !value { throw ProbeFailure(message: message) } }
        let root = URL(fileURLWithPath: "/private/tmp/keynest-biometric-service-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: root) }
            let files = root.appendingPathComponent("file-boundaries", isDirectory: true)
            try FileManager.default.createDirectory(at: files, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let fileService = BiometricVaultAccess(vaultIdentifier: files.appendingPathComponent("fake-vault.keynest").path)
            let record = files.appendingPathComponent("biometric-unlock.keynestlocal")
            let victim = root.appendingPathComponent("unrelated-file-boundary-fixture")
            let marker = Data("unrelated-fake-file-must-not-change".utf8)
            try marker.write(to: victim)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: victim.path)

            // An existing hard link must not be removed, replaced, or chmodded.
            try FileManager.default.linkItem(at: victim, to: record)
            var refusedHardLink = false
            do { try await fileService.remove() }
            catch BiometricAccessError.storageFailed { refusedHardLink = true }
            try expect(refusedHardLink, "remove rejects hard-linked enrollment")
            try expect(try Data(contentsOf: victim) == marker, "hard-link target content preserved")
            let victimMode = try FileManager.default.attributesOfItem(atPath: victim.path)[.posixPermissions] as? NSNumber
            try expect(victimMode?.intValue == 0o644, "hard-link target permissions preserved")
            try expect(FileManager.default.fileExists(atPath: record.path), "rejected hard link remains unchanged")
            try FileManager.default.removeItem(at: record)

            try FileManager.default.createSymbolicLink(at: record, withDestinationURL: victim)
            var refusedSymlink = false
            do { try await fileService.remove() }
            catch BiometricAccessError.storageFailed { refusedSymlink = true }
            try expect(refusedSymlink, "remove rejects symbolic-link enrollment")
            try expect(try Data(contentsOf: victim) == marker, "symbolic-link target content preserved")
            try FileManager.default.removeItem(at: record)

            try FileManager.default.createDirectory(at: record, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            var refusedDirectory = false
            do { try await fileService.remove() }
            catch BiometricAccessError.storageFailed { refusedDirectory = true }
            try expect(refusedDirectory, "remove rejects a directory at the record path")
            try FileManager.default.removeItem(at: record)

            try expect(mkfifo(record.path, 0o600) == 0, "create fake FIFO fixture")
            var refusedFIFO = false
            do { try await fileService.remove() }
            catch BiometricAccessError.storageFailed { refusedFIFO = true }
            try expect(refusedFIFO, "remove rejects FIFO without opening or blocking")
            try FileManager.default.removeItem(at: record)

            try marker.write(to: record)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: files.path)
            var refusedPublicDirectory = false
            do { try await fileService.remove() }
            catch BiometricAccessError.storageFailed { refusedPublicDirectory = true }
            try expect(refusedPublicDirectory, "remove rejects a shared enrollment directory")
            try expect(try Data(contentsOf: record) == marker, "unsafe-directory record remains unchanged")
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: files.path)

            // The child inherits MainActor and cannot enter remove() before this
            // synchronous cancellation, making this check deterministic.
            let cancelledRemoval = Task { try await fileService.remove() }
            cancelledRemoval.cancel()
            var wasCancelled = false
            do { try await cancelledRemoval.value }
            catch is CancellationError { wasCancelled = true }
            catch BiometricAccessError.cancelled { wasCancelled = true }
            try expect(wasCancelled, "pre-cancelled removal reports cancellation")
            try expect(try Data(contentsOf: record) == marker, "cancelled removal leaves enrollment unchanged")
            try await fileService.remove()
            try expect(!FileManager.default.fileExists(atPath: record.path), "a fresh removal still works after cancellation")
            try await fileService.remove()
            try expect(!FileManager.default.fileExists(atPath: record.path), "removing an absent record is a no-op")
            if CommandLine.arguments.contains("--file-only") {
                print("PASS biometric filesystem checks: \(count) assertions; no biometric availability query, authentication UI, or Secure Enclave key creation; temporary fake data cleaned.")
                return
            }
            let service = BiometricVaultAccess(vaultIdentifier: root.appendingPathComponent("vault.keynest").path)
            try expect(await service.status() == .notEnrolled, "fresh temporary profile")
            let token = Data("fake-service-probe-token-not-a-real-vault-key".utf8)
            try await service.enroll(token: token)
            try expect(await service.status() == .enrolled, "enrollment without prompt")
            let file = root.appendingPathComponent("biometric-unlock.keynestlocal")
            let encoded = try Data(contentsOf: file)
            try expect(encoded.range(of: token) == nil, "token must not be plaintext")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            try expect(permissions?.intValue == 0o600, "0600 enrollment")
            let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            let opaque = Data(base64Encoded: object["opaquePrivateKey"] as! String)!
            let peer = Data(base64Encoded: object["peerPublicKey"] as! String)!
            let context = LAContext(); context.interactionNotAllowed = true; context.touchIDAuthenticationAllowableReuseDuration = 0
            let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: opaque, authenticationContext: context)
            var denied = false
            do { _ = try privateKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: peer)) }
            catch { denied = true; let error = error as NSError; print("Protected operation refused without UI: \(error.domain) \(error.code)") }
            context.invalidate()
            try expect(denied, "stored envelope must require real system biometric authentication")
            let other = root.appendingPathComponent("other", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try encoded.write(to: other.appendingPathComponent("biometric-unlock.keynestlocal"))
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: other.appendingPathComponent("biometric-unlock.keynestlocal").path)
            let otherService = BiometricVaultAccess(vaultIdentifier: other.appendingPathComponent("vault.keynest").path)
            try expect(await otherService.status() == .notEnrolled, "cross-profile copied record rejected")
            var changed = object; changed["opaquePrivateKey"] = Data(repeating: 0, count: opaque.count).base64EncodedString()
            try JSONSerialization.data(withJSONObject: changed).write(to: file)
            try expect(await service.status() == .notEnrolled, "invalid opaque key re-enrollable")
            try await service.enroll(token: token)
            try expect(await service.status() == .enrolled, "replace invalid enrollment")
            try await service.remove()
            try expect(!FileManager.default.fileExists(atPath: file.path), "remove clears local enrollment")
            try await service.remove()
            try expect(await service.status() == .notEnrolled, "remove absent is no-op")
            let legacyVictim = root.appendingPathComponent("unrelated-fake-file")
            try Data("do-not-change".utf8).write(to: legacyVictim)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: legacyVictim)
            var refused = false
            do { try await service.remove() } catch { refused = true }
            try expect(refused, "remove refuses symbolic link")
            try expect(try Data(contentsOf: legacyVictim) == Data("do-not-change".utf8), "symlink target preserved")
            service.cancel()
            print("PASS Secure Enclave service: \(count) assertions; no authentication UI; temporary fake data cleaned.")
        } catch {
            try? FileManager.default.removeItem(at: root)
            print("FAIL Secure Enclave service after \(count) assertions: \(error)")
            exit(1)
        }
    }
}
