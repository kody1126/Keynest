import Foundation
import KeynestCore

/// UI-only resolution. `group` includes credentials and must never be forwarded
/// to the renderer; the scene receives only id/name/brand/color metadata.
struct KeychainCatalogItem: Identifiable {
    let selection: KeychainCharmSelection
    let name: String
    let preset: ProviderPreset?
    let group: HomeProviderGroup?

    var id: String { selection.id }
    var isUnavailable: Bool { preset == nil && group == nil }
    var savedCount: Int { group?.entries.count ?? 0 }

    func matches(search: String) -> Bool {
        if let preset { return preset.matches(search: search) }
        let terms = search.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        return terms.allSatisfy { term in
            folded.contains(term.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current))
        }
    }
}

enum KeychainCatalog {
    static let maximumCharms = 8

    /// Existing groups retain Home's useful order; the remaining offline
    /// presets follow. Every preset and every existing custom group is offered.
    static func candidates(groups: [HomeProviderGroup]) -> [KeychainCatalogItem] {
        let saved = groups.map { group in
            KeychainCatalogItem(selection: selection(for: group), name: group.name,
                                preset: group.preset, group: group)
        }
        let savedProviderIDs = Set(groups.compactMap { $0.preset?.id })
        let remaining = ProviderPreset.all.filter { !savedProviderIDs.contains($0.id) }.map { preset in
            KeychainCatalogItem(selection: KeychainCharmSelection(providerID: preset.id),
                                name: preset.name, preset: preset, group: nil)
        }
        return saved + remaining
    }

    static func automaticConfiguration(groups: [HomeProviderGroup]) -> KeychainConfiguration {
        let colors: [KeychainCharmColor] = [.ice, .lavender, .mint]
        if !groups.isEmpty {
            return KeychainConfiguration(charms: groups.prefix(3).enumerated().map { index, group in
                selection(for: group, color: colors[index])
            })
        }
        return KeychainConfiguration(charms: ["openai", "anthropic", "google"].enumerated().map { index, id in
            KeychainCharmSelection(providerID: id, color: colors[index])
        })
    }

    static func effectiveConfiguration(_ configuration: KeychainConfiguration?, groups: [HomeProviderGroup]) -> KeychainConfiguration {
        configuration ?? automaticConfiguration(groups: groups)
    }

    /// Keeps selected order, including missing targets so the editor can explain
    /// and remove them. The renderer must exclude `isUnavailable` items.
    static func resolved(configuration: KeychainConfiguration?, groups: [HomeProviderGroup]) -> [KeychainCatalogItem] {
        effectiveConfiguration(configuration, groups: groups).charms.map { resolve(selection: $0, groups: groups) }
    }

    static func resolve(selection: KeychainCharmSelection, groups: [HomeProviderGroup]) -> KeychainCatalogItem {
        if let providerID = selection.providerID {
            let preset = ProviderPreset.all.first { $0.id == providerID }
            let group = groups.first { $0.preset?.id == providerID }
            return KeychainCatalogItem(selection: selection, name: preset?.name ?? "不可用的平台",
                                       preset: preset, group: group)
        }
        let group = groups.first { $0.preset == nil && $0.id == selection.customGroupID }
        let name: String
        if let group { name = group.name }
        else if let id = selection.customGroupID, id.hasPrefix("custom:") { name = String(id.dropFirst(7)) }
        else { name = "已移除的自定义平台" }
        return KeychainCatalogItem(selection: selection, name: name, preset: nil, group: group)
    }

    private static func selection(for group: HomeProviderGroup, color: KeychainCharmColor = .ice) -> KeychainCharmSelection {
        if let preset = group.preset { return KeychainCharmSelection(providerID: preset.id, color: color) }
        return KeychainCharmSelection(customGroupID: group.id, color: color)
    }
}
