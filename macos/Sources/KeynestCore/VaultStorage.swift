import Foundation
import Darwin

/// Both cases mean the atomic replacement committed. Only durable confirms
/// the directory entry was also synced; callers must retain the new state in
/// either case and may surface a warning for durabilityUncertain.
public enum VaultWriteResult: Equatable, Sendable {
    case durable
    case durabilityUncertain
}

public struct VaultStorage: Sendable {
    public let directory: URL
    public let fileURL: URL
    private let directorySync: @Sendable (Int32) -> Int32
    private static let filename = "vault.keynest"
    private static let upgradeBackupFilename = "vault-before-0.11.keynest"

    public init(directory: URL) throws {
        try self.init(directory: directory, directorySync: { Darwin.fsync($0) })
    }

    /// Internal fault injection affects only write's post-rename directory sync.
    /// Production callers always use the public initializer and real fsync.
    internal init(directory: URL, directorySync: @escaping @Sendable (Int32) -> Int32) throws {
        guard directory.isFileURL else { throw VaultError.storage("数据目录必须是本机文件夹。") }
        let resolved = directory.standardizedFileURL
        var info = stat()
        if lstat(resolved.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR else {
                throw VaultError.storage("数据目录必须是普通文件夹，不能是符号链接。")
            }
        } else {
            guard errno == ENOENT else { throw VaultError.storage("无法检查数据目录权限。") }
            do {
                try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: NSNumber(value: 0o700)])
            } catch { throw VaultError.storage("无法创建本地数据目录，请检查权限。") }
        }
        self.directory = resolved
        self.fileURL = resolved.appendingPathComponent(Self.filename, isDirectory: false)
        self.directorySync = directorySync
        let descriptor = try openDirectory()
        defer { Darwin.close(descriptor) }
        guard fchmod(descriptor, mode_t(0o700)) == 0 else {
            throw VaultError.storage("无法将数据目录权限限制为仅当前用户可访问。")
        }
        try validateDestination(in: descriptor)
    }

    public var exists: Bool {
        // Any existing directory entry counts, including malformed files: never
        // mistake a damaged or hostile destination for a new, empty vault.
        var info = stat()
        return lstat(fileURL.path, &info) == 0 || errno != ENOENT
    }

    public func read() throws -> Data {
        let directoryDescriptor = try openDirectory()
        defer { Darwin.close(directoryDescriptor) }
        let descriptor = openat(directoryDescriptor, Self.filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw VaultError.storage("无法读取保险库，请检查文件是否存在及权限。") }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
            throw VaultError.storage("保险库必须是独立的普通文件，不能是符号链接、硬链接或特殊文件。")
        }
        guard info.st_size <= VaultCodec.maximumFileSize else { throw VaultError.fileTooLarge }
        guard info.st_size > 0 else { throw VaultError.invalidFormat }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw VaultError.storage("无法限制保险库文件权限。") }
        var result = Data()
        result.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let length = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress!, bytes.count)
            }
            if length < 0 {
                if errno == EINTR { continue }
                throw VaultError.storage("读取保险库失败，原文件未改变。")
            }
            if length == 0 { break }
            guard result.count + length <= VaultCodec.maximumFileSize else { throw VaultError.fileTooLarge }
            result.append(contentsOf: buffer.prefix(length))
        }
        try VaultCodec.validateEncryptedFile(result)
        return result
    }

    @discardableResult
    public func write(_ data: Data) throws -> VaultWriteResult {
        try VaultCodec.validateEncryptedFile(data)
        let directoryDescriptor = try openDirectory()
        defer { Darwin.close(directoryDescriptor) }
        try validateDestination(in: directoryDescriptor)
        let temporaryName = ".vault-\(UUID().uuidString).tmp"
        let descriptor = openat(directoryDescriptor, temporaryName,
                                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw VaultError.storage("无法创建保险库临时文件，原文件未改变。") }
        defer {
            Darwin.close(descriptor)
            unlinkat(directoryDescriptor, temporaryName, 0)
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw VaultError.storage("无法限制临时文件权限，原文件未改变。") }
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw VaultError.storage("写入保险库失败，原文件未改变。") }
                written += count
            }
        }
        guard fsync(descriptor) == 0 else { throw VaultError.storage("无法同步保险库临时文件，原文件未改变。") }
        try validateDestination(in: directoryDescriptor)
        guard renameat(directoryDescriptor, temporaryName, directoryDescriptor, Self.filename) == 0 else {
            throw VaultError.storage("无法替换保险库文件，原文件未改变。")
        }
        // The new file is already visible after rename. Throwing here would let
        // callers keep old memory and later overwrite this committed version.
        // Unsupported directory fsync is also an unconfirmed durability result.
        return directorySync(directoryDescriptor) == 0 ? .durable : .durabilityUncertain
    }

    /// Saves the original encrypted bytes before upgrading an existing payload.
    /// The first backup is retained unchanged across repeated attempts.
    public func preserveUpgradeBackup(_ data: Data) throws {
        try VaultCodec.validateEncryptedFile(data)
        let directoryDescriptor = try openDirectory()
        defer { Darwin.close(directoryDescriptor) }
        let descriptor = openat(directoryDescriptor, Self.upgradeBackupFilename,
                                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        if descriptor < 0 {
            guard errno == EEXIST else { throw VaultError.storage("无法保存升级前备份，原密钥库未改变。") }
            let existing = openat(directoryDescriptor, Self.upgradeBackupFilename,
                                  O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard existing >= 0 else { throw VaultError.storage("升级前备份必须是普通文件，不能是符号链接。") }
            defer { Darwin.close(existing) }
            var info = stat()
            guard fstat(existing, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
                throw VaultError.storage("升级前备份必须是独立的普通文件，不能是硬链接或特殊文件。")
            }
            guard fchmod(existing, mode_t(0o600)) == 0 else {
                throw VaultError.storage("无法验证升级前备份，原密钥库未改变。")
            }
            guard info.st_size > 0, info.st_size <= VaultCodec.maximumFileSize else {
                throw VaultError.storage("已有升级前备份不完整，原密钥库未改变。")
            }
            var saved = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(existing, $0.baseAddress!, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { throw VaultError.storage("无法读取升级前备份，原密钥库未改变。") }
                if count == 0 { break }
                guard saved.count + count <= VaultCodec.maximumFileSize else { throw VaultError.fileTooLarge }
                saved.append(contentsOf: buffer.prefix(count))
            }
            do { try VaultCodec.validateEncryptedFile(saved) }
            catch { throw VaultError.storage("已有升级前备份不完整，原密钥库未改变。") }
            return
        }
        var finished = false
        defer {
            Darwin.close(descriptor)
            if !finished { unlinkat(directoryDescriptor, Self.upgradeBackupFilename, 0) }
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw VaultError.storage("无法限制升级前备份权限，原密钥库未改变。")
        }
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw VaultError.storage("无法写入升级前备份，原密钥库未改变。") }
                written += count
            }
        }
        guard fsync(descriptor) == 0 else { throw VaultError.storage("无法同步升级前备份，原密钥库未改变。") }
        if fsync(directoryDescriptor) != 0 && errno != EINVAL && errno != ENOTSUP {
            throw VaultError.storage("无法同步升级前备份目录，原密钥库未改变。")
        }
        finished = true
    }

    private func openDirectory() throws -> Int32 {
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw VaultError.storage("数据目录不可访问，或已变为符号链接。") }
        return descriptor
    }

    private func validateDestination(in directoryDescriptor: Int32) throws {
        var info = stat()
        if fstatat(directoryDescriptor, Self.filename, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
                throw VaultError.storage("保险库必须是独立的普通文件，不能是符号链接、硬链接或特殊文件。")
            }
        } else if errno != ENOENT {
            throw VaultError.storage("无法检查保险库文件。")
        }
    }
}
