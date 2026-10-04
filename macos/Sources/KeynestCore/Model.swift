import Foundation
import CryptoKit

public enum VaultError: LocalizedError, Equatable, Sendable {
    case invalidPassword
    case invalidField(String)
    case invalidFormat
    case authenticationFailed
    case fileTooLarge
    case cryptographyFailed
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPassword: return "主密码需要 12–1024 个字符。"
        case .invalidField(let message): return message
        case .invalidFormat: return "不支持此保险库格式，或文件已经损坏。"
        case .authenticationFailed: return "主密码不正确，或保险库文件已被修改。"
        case .fileTooLarge: return "保险库超过 4 MiB 的实验版容量上限。"
        case .cryptographyFailed: return "无法完成加密操作，请重试。"
        case .storage(let message): return message
        }
    }
}

public enum EntryCategory: String, Codable, CaseIterable, Sendable {
    case ai, skill, service, other

    public var title: String {
        switch self {
        case .ai: return "AI 模型"
        case .skill: return "Skill 与插件"
        case .service: return "开发服务"
        case .other: return "其他"
        }
    }

    public var symbol: String {
        switch self {
        case .ai: return "sparkles"
        case .skill: return "puzzlepiece.extension"
        case .service: return "terminal"
        case .other: return "key.horizontal"
        }
    }
}

public enum QuotaProvider: String, Codable, CaseIterable, Sendable {
    case none, deepseek, siliconflow, openrouter

    public var title: String {
        switch self {
        case .none: return "仅收藏，不同步"
        case .deepseek: return "DeepSeek"
        case .siliconflow: return "硅基流动"
        case .openrouter: return "OpenRouter"
        }
    }

    public var endpoint: URL? {
        switch self {
        case .none: return nil
        case .deepseek: return URL(string: "https://api.deepseek.com/user/balance")
        case .siliconflow: return URL(string: "https://api.siliconflow.cn/v1/user/info")
        case .openrouter: return URL(string: "https://openrouter.ai/api/v1/key")
        }
    }
}

public struct QuotaMetric: Codable, Equatable, Sendable {
    public var label: String
    public var value: String?
    public var currency: String?

    public init(label: String, value: String?, currency: String? = nil) {
        self.label = label
        self.value = value
        self.currency = currency
    }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public var kind: String
    public var metrics: [QuotaMetric]
    public var note: String
    public var fetchedAt: Date

    public init(kind: String, metrics: [QuotaMetric], note: String = "", fetchedAt: Date = Date()) {
        self.kind = kind
        self.metrics = metrics
        self.note = note
        self.fetchedAt = fetchedAt
    }

    internal func validate() throws {
        guard ["balance", "key_limit"].contains(kind),
              metrics.count <= 32, note.count <= 4000,
              fetchedAt.timeIntervalSinceReferenceDate.isFinite,
              metrics.allSatisfy({ !$0.label.isEmpty && $0.label.count <= 120 &&
                  ($0.value?.count ?? 0) <= 128 && ($0.currency?.count ?? 0) <= 16 }) else {
            throw VaultError.invalidField("额度快照格式不正确。")
        }
    }
}

public struct ToolGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var templateID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String = "", notes: String = "", templateID: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.notes = notes; self.templateID = templateID
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, notes, templateID, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        notes = try values.decode(String.self, forKey: .notes)
        // Older payloads omit this field. An explicit null is malformed data,
        // not permission to silently discard a template association.
        templateID = try values.contains(.templateID) ? values.decode(String.self, forKey: .templateID) : nil
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }

    public func validated() throws -> ToolGroup {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, name.count <= 80 else {
            throw VaultError.invalidField("工具名称不能为空，且最多 80 个字符。")
        }
        if let templateID {
            guard !templateID.isEmpty, templateID.count <= 80,
                  templateID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                throw VaultError.invalidField("工具模板标识格式不正确。")
            }
        }
        guard notes.count <= 1000 else { throw VaultError.invalidField("工具备注最多 1000 个字符。") }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite, updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw VaultError.invalidField("工具时间格式不正确。")
        }
        return result
    }
}

public struct SecretEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: EntryCategory
    public var provider: String
    public var secret: String
    public var baseURL: String
    public var website: String
    public var tags: [String]
    public var notes: String
    public var isFavorite: Bool
    public var quotaProvider: QuotaProvider
    public var quota: QuotaSnapshot?
    public var createdAt: Date
    public var updatedAt: Date
    public var toolIDs: [UUID]
    public var environment: String
    public var accountLabel: String

    public init(id: UUID = UUID(), name: String = "", category: EntryCategory = .ai,
                provider: String = "", secret: String = "", baseURL: String = "",
                website: String = "", tags: [String] = [], notes: String = "",
                isFavorite: Bool = false, quotaProvider: QuotaProvider = .none,
                quota: QuotaSnapshot? = nil, createdAt: Date = Date(), updatedAt: Date = Date(),
                toolIDs: [UUID] = [], environment: String = "", accountLabel: String = "") {
        self.id = id
        self.name = name
        self.category = category
        self.provider = provider
        self.secret = secret
        self.baseURL = baseURL
        self.website = website
        self.tags = tags
        self.notes = notes
        self.isFavorite = isFavorite
        self.quotaProvider = quotaProvider
        self.quota = quota
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.toolIDs = toolIDs
        self.environment = environment
        self.accountLabel = accountLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, provider, secret, baseURL, website, tags, notes
        case isFavorite, quotaProvider, quota, createdAt, updatedAt, toolIDs, environment, accountLabel
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        category = try values.decode(EntryCategory.self, forKey: .category)
        provider = try values.decode(String.self, forKey: .provider)
        secret = try values.decode(String.self, forKey: .secret)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        website = try values.decode(String.self, forKey: .website)
        tags = try values.decode([String].self, forKey: .tags)
        notes = try values.decode(String.self, forKey: .notes)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        quotaProvider = try values.decode(QuotaProvider.self, forKey: .quotaProvider)
        quota = try values.decodeIfPresent(QuotaSnapshot.self, forKey: .quota)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        // Only absent fields receive legacy defaults; malformed/null fields fail.
        toolIDs = try values.contains(.toolIDs) ? values.decode([UUID].self, forKey: .toolIDs) : []
        environment = try values.contains(.environment) ? values.decode(String.self, forKey: .environment) : ""
        accountLabel = try values.contains(.accountLabel) ? values.decode(String.self, forKey: .accountLabel) : ""
    }

    public func validated() throws -> SecretEntry {
        try validated(preservingStoredURLMetadata: false)
    }

    /// Stored URL metadata must not prevent access to otherwise valid secrets.
    /// New/edited entries use the strict public validator; decoded documents
    /// retain legacy nonstandard ports and escape formerly accepted controls.
    internal func validated(preservingStoredURLMetadata: Bool) throws -> SecretEntry {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, name.count <= 120 else {
            throw VaultError.invalidField("名称不能为空，且最多 120 个字符。")
        }
        guard provider.count <= 120 else { throw VaultError.invalidField("服务商名称最多 120 个字符。") }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              secret.count <= 8192,
              !secret.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 10 || $0.value == 13 }) else {
            throw VaultError.invalidField("密钥不能为空，最多 8192 个字符，且不能包含换行或空字符。")
        }
        guard tags.count <= 12, tags.allSatisfy({ $0.count <= 40 }) else {
            throw VaultError.invalidField("最多 12 个标签，每个最多 40 个字符。")
        }
        guard notes.count <= 4000 else { throw VaultError.invalidField("备注最多 4000 个字符。") }
        guard environment.count <= 40 else { throw VaultError.invalidField("环境名称最多 40 个字符。") }
        guard accountLabel.count <= 120 else { throw VaultError.invalidField("账户名称最多 120 个字符。") }
        var seenToolIDs = Set<UUID>()
        result.toolIDs = toolIDs.filter { seenToolIDs.insert($0).inserted }
        guard result.toolIDs.count <= 20 else { throw VaultError.invalidField("每个密钥最多关联 20 个工具。") }
        result.environment = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        result.accountLabel = accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard createdAt.timeIntervalSinceReferenceDate.isFinite, updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw VaultError.invalidField("条目时间格式不正确。")
        }
        result.baseURL = try Self.validateURL(baseURL, label: "API 地址", preservingStoredMetadata: preservingStoredURLMetadata)
        result.website = try Self.validateURL(website, label: "控制台或来源网址", preservingStoredMetadata: preservingStoredURLMetadata)
        result.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        result.tags = tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seen.insert(trimmed).inserted ? trimmed : nil
        }
        try quota?.validate()
        return result
    }

    private static func validateURL(_ value: String, label: String, preservingStoredMetadata: Bool) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let containsControls = trimmed.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }
        // Escaping an old, valid-length path can increase its stored length.
        // Accept that representation again on subsequent decrypt/save cycles.
        let withinStoredLength = preservingStoredMetadata && (trimmed.removingPercentEncoding?.count ?? Int.max) <= 2048
        guard trimmed.count <= 2048 || withinStoredLength,
              preservingStoredMetadata || !containsControls,
              let components = URLComponents(string: trimmed), let url = components.url,
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty,
              preservingStoredMetadata || (components.port.map({ (1...65535).contains($0) }) ?? true),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw VaultError.invalidField("\(label)需要完整的 http 或 https 网址和有效端口，且不能含控制字符、用户名、密码、查询参数或片段。")
        }
        return containsControls ? url.absoluteString : trimmed
    }
}

public struct VaultDocument: Codable, Sendable {
    public var version: Int = 4
    public var entries: [SecretEntry]
    public var tools: [ToolGroup]
    public var keychainConfiguration: KeychainConfiguration?

    public init(entries: [SecretEntry] = [], tools: [ToolGroup] = [], keychainConfiguration: KeychainConfiguration? = nil) {
        self.entries = entries; self.tools = tools; self.keychainConfiguration = keychainConfiguration
    }

    private enum CodingKeys: String, CodingKey { case version, entries, tools, keychainConfiguration }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard [1, 2, 3, 4].contains(version) else { throw VaultError.invalidFormat }
        entries = try values.decode([SecretEntry].self, forKey: .entries)
        tools = try values.contains(.tools) ? values.decode([ToolGroup].self, forKey: .tools) : []
        if values.contains(.keychainConfiguration) {
            guard version == 4 else { throw VaultError.invalidFormat }
            keychainConfiguration = try values.decode(KeychainConfiguration.self, forKey: .keychainConfiguration)
        } else { keychainConfiguration = nil }
    }

    public func encode(to encoder: Encoder) throws {
        guard [1, 2, 3, 4].contains(version) else { throw VaultError.invalidFormat }
        var values = encoder.container(keyedBy: CodingKeys.self)
        // Every newly written payload advertises the fields older apps cannot retain.
        try values.encode(4, forKey: .version)
        try values.encode(entries, forKey: .entries)
        try values.encode(tools, forKey: .tools)
        try values.encodeIfPresent(keychainConfiguration, forKey: .keychainConfiguration)
    }

    public func merging(_ incoming: VaultDocument) throws -> VaultDocument {
        let current = try validated()
        let source = try incoming.validated()
        var mergedTools = current.tools
        var toolLookup = Dictionary(uniqueKeysWithValues: mergedTools.map { ($0.id, $0) })
        var toolMapping: [UUID: UUID] = [:]
        for original in source.tools {
            var tool = original
            var attempt = 0
            while let existing = toolLookup[tool.id], existing != tool {
                tool.id = try Self.conflictID(original, kind: "tool", attempt: attempt)
                attempt += 1
            }
            toolMapping[original.id] = tool.id
            if toolLookup[tool.id] == nil {
                mergedTools.append(tool); toolLookup[tool.id] = tool
            }
        }

        var mergedEntries = current.entries
        var entryLookup = Dictionary(uniqueKeysWithValues: mergedEntries.map { ($0.id, $0) })
        var entryMapping: [UUID: UUID] = [:]
        for original in source.entries {
            var mapped = original
            mapped.toolIDs = try original.toolIDs.map { id in
                guard let mappedID = toolMapping[id] else { throw VaultError.invalidFormat }
                return mappedID
            }
            var entry = mapped
            var attempt = 0
            while let existing = entryLookup[entry.id], existing != entry {
                entry.id = try Self.conflictID(mapped, kind: "entry", attempt: attempt)
                attempt += 1
            }
            entryMapping[original.id] = entry.id
            if entryLookup[entry.id] == nil {
                mergedEntries.append(entry); entryLookup[entry.id] = entry
            }
        }
        let configuration = current.keychainConfiguration ?? source.keychainConfiguration?.remappingEntries(entryMapping)
        return try VaultDocument(entries: mergedEntries, tools: mergedTools, keychainConfiguration: configuration).validated()
    }

    /// Removes the group and its references, retaining every credential unchanged
    /// apart from those references. The original document is never mutated.
    public func removingTool(id: UUID) throws -> VaultDocument {
        let current = try validated()
        let remainingEntries = current.entries.map { original -> SecretEntry in
            var entry = original
            entry.toolIDs.removeAll { $0 == id }
            return entry
        }
        return try VaultDocument(entries: remainingEntries, tools: current.tools.filter { $0.id != id },
                                 keychainConfiguration: current.keychainConfiguration).validated()
    }

    internal func validated() throws -> VaultDocument {
        guard [1, 2, 3, 4].contains(version), entries.count <= 2000, tools.count <= 100 else { throw VaultError.invalidFormat }
        var toolIdentifiers = Set<UUID>()
        let validatedTools = try tools.map { tool in
            guard toolIdentifiers.insert(tool.id).inserted else { throw VaultError.invalidFormat }
            return try tool.validated()
        }
        var ids = Set<UUID>()
        let validatedEntries = try entries.map { entry in
            guard ids.insert(entry.id).inserted else { throw VaultError.invalidFormat }
            let validatedEntry = try entry.validated(preservingStoredURLMetadata: true)
            guard Set(validatedEntry.toolIDs).isSubset(of: toolIdentifiers) else {
                throw VaultError.invalidField("密钥关联的工具不存在。")
            }
            return validatedEntry
        }
        return VaultDocument(entries: validatedEntries, tools: validatedTools,
                             keychainConfiguration: try keychainConfiguration?.validated())
    }

    /// Stable conflict IDs make reimporting the same backup idempotent without
    /// conflating intentionally distinct records that happen to share a name.
    private static func conflictID<T: Encodable>(_ value: T, kind: String, attempt: Int) throws -> UUID {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var bytes = Data("Keynest|merge-v2|\(kind)|\(attempt)|".utf8)
        bytes.append(try encoder.encode(value))
        var digest = Array(SHA256.hash(data: bytes).prefix(16))
        digest[6] = (digest[6] & 0x0f) | 0x80
        digest[8] = (digest[8] & 0x3f) | 0x80
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }
}
