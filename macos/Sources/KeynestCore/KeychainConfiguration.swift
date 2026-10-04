import Foundation

public enum KeychainCharmColor: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case ice, lavender, mint, amber, rose, graphite

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ice: return "冰蓝"
        case .lavender: return "薰衣草"
        case .mint: return "薄荷"
        case .amber: return "琥珀"
        case .rose: return "玫瑰"
        case .graphite: return "石墨"
        }
    }
}

/// References only a platform group, never one implicitly chosen credential.
/// Custom group identifiers can contain private names and belong inside the
/// encrypted payload. They must not be copied into UserDefaults or asset paths.
public struct KeychainCharmSelection: Codable, Equatable, Identifiable, Sendable {
    public var providerID: String?
    public var customGroupID: String?
    public var color: KeychainCharmColor

    public var id: String { providerID.map { "provider:\($0)" } ?? customGroupID ?? "invalid" }

    public init(providerID: String? = nil, customGroupID: String? = nil, color: KeychainCharmColor = .ice) {
        self.providerID = providerID; self.customGroupID = customGroupID; self.color = color
    }

    private enum CodingKeys: String, CodingKey { case providerID, customGroupID, color }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Only omitted optionals mean absent; an explicit null is malformed.
        providerID = try values.contains(.providerID) ? values.decode(String.self, forKey: .providerID) : nil
        customGroupID = try values.contains(.customGroupID) ? values.decode(String.self, forKey: .customGroupID) : nil
        color = try values.decode(KeychainCharmColor.self, forKey: .color)
    }

    public func validated() throws -> KeychainCharmSelection {
        guard (providerID == nil) != (customGroupID == nil) else {
            throw VaultError.invalidField("每个挂件需要选择且只能选择一个平台。")
        }
        if let providerID {
            guard ProviderPreset.all.contains(where: { $0.id == providerID }) else {
                throw VaultError.invalidField("挂件的平台标识不受支持。")
            }
        }
        if let customGroupID {
            if customGroupID.hasPrefix("entry:") {
                let value = String(customGroupID.dropFirst(6))
                guard let id = UUID(uuidString: value), id.uuidString == value else {
                    throw VaultError.invalidField("挂件的自定义平台标识不正确。")
                }
            } else {
                guard customGroupID.hasPrefix("custom:"), customGroupID.count <= 512,
                      !customGroupID.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !customGroupID.unicodeScalars.contains(where: { $0.value == 0 }) else {
                    throw VaultError.invalidField("挂件的自定义平台标识不正确。")
                }
            }
        }
        return self
    }
}

/// A missing configuration means automatic defaults. An explicitly present
/// configuration with no charms is the user's intentional empty selection.
public struct KeychainConfiguration: Codable, Equatable, Sendable {
    public var charms: [KeychainCharmSelection]

    public init(charms: [KeychainCharmSelection] = []) { self.charms = charms }

    public func validated() throws -> KeychainConfiguration {
        guard charms.count <= 8 else { throw VaultError.invalidField("钥匙串最多选择 8 个挂件。") }
        var identifiers = Set<String>()
        let result = try charms.map { charm in
            let validated = try charm.validated()
            guard identifiers.insert(validated.id).inserted else {
                throw VaultError.invalidField("同一个平台只能选择一个挂件。")
            }
            return validated
        }
        return Self(charms: result)
    }

    internal func remappingEntries(_ identifiers: [UUID: UUID]) -> KeychainConfiguration {
        var result = self
        result.charms = charms.map { original in
            var charm = original
            if let group = charm.customGroupID, group.hasPrefix("entry:"),
               let id = UUID(uuidString: String(group.dropFirst(6))), let mapped = identifiers[id] {
                charm.customGroupID = "entry:\(mapped.uuidString)"
            }
            return charm
        }
        return result
    }
}
