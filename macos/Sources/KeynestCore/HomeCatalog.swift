import Foundation

public enum HomeScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, models, services, favorites

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "全部"
        case .models: return "模型"
        case .services: return "Skill 与服务"
        case .favorites: return "常用"
        }
    }
}

/// A display-only group retains each credential, including multiple accounts or
/// environments on the same platform. It never chooses a credential to copy.
public struct HomeProviderGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let preset: ProviderPreset?
    public let name: String
    public let entries: [SecretEntry]
}

/// Pure local presentation logic. Filtering happens before grouping, so a search
/// never exposes unrelated credentials merely because their provider matched.
public enum HomeCatalog {
    public static func groups(entries: [SecretEntry], tools: [ToolGroup] = [],
                              query: String = "", scope: HomeScope = .all) -> [HomeProviderGroup] {
        let terms = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.map(searchFold)
        var toolNames: [UUID: [String]] = [:]
        for tool in tools { toolNames[tool.id, default: []].append(searchFold(tool.name)) }
        var buckets: [String: Bucket] = [:]

        for entry in entries {
            let preset = ProviderPreset.match(provider: entry.provider)
            let isModel = isModel(entry, preset: preset)
            switch scope {
            case .all: break
            case .models: if !isModel { continue }
            case .services: if isModel { continue }
            case .favorites: if !entry.isFavorite { continue }
            }

            if !terms.isEmpty {
                // Deliberately exclude secret, URLs, notes, quota values and tool
                // notes: pasted credentials in those fields are not searchable.
                var fields = ([entry.name, entry.provider, entry.accountLabel, entry.environment] + entry.tags)
                    .map(searchFold)
                if let preset { fields += ([preset.id, preset.name] + preset.aliases).map(searchFold) }
                fields += entry.toolIDs.flatMap { toolNames[$0] ?? [] }
                guard terms.allSatisfy({ term in fields.contains { $0.contains(term) } }) else { continue }
            }

            let provider = entry.provider.trimmingCharacters(in: .whitespacesAndNewlines)
            let id: String
            let name: String
            if let preset {
                id = preset.id; name = preset.name
            } else if provider.isEmpty {
                id = "entry:\(entry.id.uuidString)"; name = entry.name
            } else {
                // Do not strip punctuation or diacritics from custom names.
                // Unrelated gateways must not be guessed as one provider.
                id = "custom:\(provider.folding(options: [.caseInsensitive], locale: locale))"
                name = provider
            }
            if var bucket = buckets[id] {
                bucket.entries.append(entry)
                bucket.isModel = bucket.isModel || isModel
                if nameBefore(name, bucket.name) { bucket.name = name }
                buckets[id] = bucket
            } else {
                buckets[id] = Bucket(id: id, preset: preset, name: name, entries: [entry], isModel: isModel)
            }
        }

        return buckets.values.sorted { lhs, rhs in
            if lhs.isModel != rhs.isModel { return lhs.isModel }
            let leftFavorite = lhs.entries.contains(where: \.isFavorite)
            let rightFavorite = rhs.entries.contains(where: \.isFavorite)
            if leftFavorite != rightFavorite { return leftFavorite }
            let leftName = searchFold(lhs.name), rightName = searchFold(rhs.name)
            if leftName != rightName { return leftName < rightName }
            return lhs.id < rhs.id
        }.map { bucket in
            HomeProviderGroup(id: bucket.id, preset: bucket.preset, name: bucket.name,
                              entries: bucket.entries.sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            })
        }
    }

    private struct Bucket {
        let id: String
        let preset: ProviderPreset?
        var name: String
        var entries: [SecretEntry]
        var isModel: Bool
    }

    private static let locale = Locale(identifier: "en_US_POSIX")

    private static func searchFold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
    }

    private static func nameBefore(_ lhs: String, _ rhs: String) -> Bool {
        let left = searchFold(lhs), right = searchFold(rhs)
        return left == right ? lhs < rhs : left < right
    }

    private static func isModel(_ entry: SecretEntry, preset: ProviderPreset?) -> Bool {
        if let preset { return preset.group == .languageModels || preset.group == .media }
        return entry.category == .ai
    }
}
