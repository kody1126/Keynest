import Foundation
import Darwin

private struct CatalogCheckFailure: Error { let message: String }

/// Pure catalog checks. No AppModel, window, renderer, clipboard, real vault,
/// networking, or system authentication is initialized.
@main struct KeychainCatalogChecks {
    static func main() {
        var assertions = 0
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            assertions += 1
            if !condition { throw CatalogCheckFailure(message: message) }
        }
        func passed(_ label: String) { checks += 1; print("PASS \(label)") }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func entry(name: String, provider: String, category: EntryCategory = .service) -> SecretEntry {
            SecretEntry(name: name, category: category, provider: provider,
                        secret: "fake-catalog-only-secret-not-a-real-key",
                        baseURL: "https://private-catalog.example.test/v1", notes: "private-catalog-note",
                        createdAt: date, updatedAt: date, environment: "fixture", accountLabel: "fictional account")
        }

        do {
            let emptyAutomatic = KeychainCatalog.resolved(configuration: nil, groups: [])
            try expect(emptyAutomatic.map { $0.selection.providerID } == ["openai", "anthropic", "google"], "empty vault uses the three built-in defaults")
            try expect(emptyAutomatic.allSatisfy { !$0.isUnavailable && $0.savedCount == 0 }, "unsaved built-in platforms are valid choices")
            try expect(Set(emptyAutomatic.map { $0.selection.color }).count == 3, "defaults have distinct color values")
            passed("empty-vault automatic defaults")

            let explicitEmpty = KeychainConfiguration(charms: [])
            try expect(KeychainCatalog.resolved(configuration: explicitEmpty, groups: []).isEmpty, "explicit empty selection is not replaced with defaults")
            try expect(KeychainCatalog.effectiveConfiguration(explicitEmpty, groups: []).charms.isEmpty, "effective configuration keeps explicit zero")
            passed("intentional empty keyring")

            let openA = entry(name: "OpenAI personal", provider: "OpenAI", category: .ai)
            let openB = entry(name: "OpenAI team", provider: "ChatGPT", category: .ai)
            let claude = entry(name: "Claude work", provider: "Anthropic", category: .ai)
            let customA = entry(name: "Custom A", provider: "Résumé Gateway")
            let customB = entry(name: "Custom B", provider: "Résumé-Gateway")
            let unassigned = entry(name: "Unassigned sample", provider: "")
            let entries = [openA, openB, claude, customA, customB, unassigned]
            let groups = HomeCatalog.groups(entries: entries)
            let catalog = KeychainCatalog.candidates(groups: groups)
            let customCount = groups.filter { $0.preset == nil }.count
            try expect(catalog.count == ProviderPreset.all.count + customCount, "every preset and every custom group is offered exactly once")
            try expect(Set(catalog.map(\.id)).count == catalog.count, "candidate identities do not collide")
            try expect(Set(catalog.compactMap { $0.selection.providerID }) == Set(ProviderPreset.all.map(\.id)), "catalog includes all known provider identifiers")
            try expect(catalog.prefix(groups.count).allSatisfy { $0.savedCount > 0 }, "saved groups appear before unsaved presets")
            try expect(catalog.dropFirst(groups.count).allSatisfy { $0.savedCount == 0 }, "remaining catalog items have no saved credentials")
            try expect(catalog.filter { $0.selection.providerID == "openai" }.count == 1, "provider aliases share one choice")
            passed("complete catalog with saved platforms first")

            let openAI = KeychainCatalog.resolve(selection: KeychainCharmSelection(providerID: "openai"), groups: groups)
            try expect(openAI.savedCount == 2, "both actual OpenAI credentials remain available")
            try expect(Set(openAI.group?.entries.map(\.id) ?? []) == Set([openA.id, openB.id]), "resolving a provider never silently chooses its first key")
            try expect(openAI.matches(search: "CHAT GPT"), "provider aliases are searchable")
            passed("multiple credentials and provider aliases")

            try expect(openAI.copyEntry == nil, "multiple keys without an explicit binding never copy the first")
            let bound = KeychainCharmSelection(providerID: "openai", credentialID: openB.id)
            try expect(KeychainCatalog.resolve(selection: bound, groups: groups).copyEntry?.id == openB.id, "explicit binding selects exactly the intended key")
            let missingBound = KeychainCharmSelection(providerID: "openai", credentialID: UUID())
            let singleGroups = HomeCatalog.groups(entries: [openA, claude])
            try expect(KeychainCatalog.resolve(selection: missingBound, groups: singleGroups).copyEntry == nil, "deleted binding never falls back to the remaining key")
            let wrongGroup = KeychainCharmSelection(providerID: "openai", credentialID: claude.id)
            try expect(KeychainCatalog.resolve(selection: wrongGroup, groups: groups).copyEntry == nil, "binding cannot copy a key from another platform")
            try expect(KeychainCatalog.resolve(selection: KeychainCharmSelection(providerID: "openai"), groups: singleGroups).copyEntry?.id == openA.id, "one unambiguous key can be copied without setup")
            try expect(KeychainCatalog.resolve(selection: bound, groups: []).copyEntry == nil, "locked or empty catalog cannot resolve any key")
            try expect(KeychainCatalog.resolve(selection: bound, groups: HomeCatalog.groups(entries: Array(entries.reversed()))).copyEntry?.id == openB.id, "key binding does not depend on presentation order")
            passed("direct copy with explicit binding and no unsafe fallback")

            let automatic = KeychainCatalog.automaticConfiguration(groups: groups)
            let automaticItems = KeychainCatalog.resolved(configuration: nil, groups: groups)
            try expect(automatic.charms.count == 3, "saved-vault automatic choice is limited to three")
            try expect(automaticItems.allSatisfy { $0.savedCount > 0 }, "saved platforms take priority over unsaved defaults")
            try expect(automaticItems.compactMap { $0.group?.id } == Array(groups.prefix(3).map(\.id)), "automatic choice preserves Home group priority")
            try expect(KeychainCatalog.resolved(configuration: explicitEmpty, groups: groups).isEmpty, "explicit empty also wins when credentials exist")
            passed("saved-vault automatic choice and explicit override")

            let colors = KeychainCharmColor.allCases
            let eight = KeychainConfiguration(charms: ProviderPreset.all.prefix(8).reversed().enumerated().map { index, preset in
                KeychainCharmSelection(providerID: preset.id, color: colors[index % colors.count])
            })
            _ = try eight.validated()
            let ordered = KeychainCatalog.resolved(configuration: eight, groups: groups)
            try expect(KeychainCatalog.maximumCharms == 8, "UI maximum matches the intended contract")
            try expect(ordered.map(\.selection) == eight.charms, "eight explicit selections keep exact order and colors")
            let changedGroups = HomeCatalog.groups(entries: Array(entries.reversed()))
            try expect(KeychainCatalog.resolved(configuration: eight, groups: changedGroups).map(\.selection) == eight.charms, "entry order changes do not reorder manual selections")
            var nine = eight; nine.charms.append(KeychainCharmSelection(providerID: ProviderPreset.all[8].id))
            var rejectedNine = false
            do { _ = try nine.validated() } catch { rejectedNine = true }
            try expect(rejectedNine, "configuration rejects a ninth selection")
            passed("ordered zero-to-eight contract")

            let customItem = try unwrap(catalog.first { $0.group?.entries.contains(where: { $0.id == customA.id }) == true }, "custom choice exists")
            try expect(customItem.selection.providerID == nil && customItem.selection.customGroupID == customItem.group?.id, "custom choice uses its exact Home identity")
            try expect(customItem.matches(search: "resume GATEWAY"), "custom name search supports case and diacritics")
            for excluded in [customA.secret, "private-catalog-note", "private-catalog.example.test", "fictional account"] {
                try expect(!customItem.matches(search: excluded), "custom catalog search excludes credential fields")
            }
            try expect(catalog.filter { $0.name.contains("Gateway") }.count == 2, "punctuation-distinct custom names remain separate")
            passed("custom targets and metadata-only catalog search")

            var coloredCustom = customItem.selection; coloredCustom.color = .graphite
            let removed = KeychainCatalog.resolve(selection: coloredCustom, groups: [])
            try expect(removed.isUnavailable && removed.group == nil && removed.preset == nil, "deleted custom target is marked unavailable")
            try expect(removed.selection == coloredCustom, "missing target and chosen color are retained for cleanup")
            let missingConfiguration = KeychainConfiguration(charms: [coloredCustom, KeychainCharmSelection(providerID: "openai")])
            let missingOrdered = KeychainCatalog.resolved(configuration: missingConfiguration, groups: [])
            try expect(missingOrdered.count == 2 && missingOrdered[0].isUnavailable && !missingOrdered[1].isUnavailable, "resolution does not drop or reorder a missing selection")
            let spoofed = KeychainCatalog.resolve(selection: KeychainCharmSelection(customGroupID: "custom:openai"), groups: groups)
            try expect(spoofed.isUnavailable && spoofed.group == nil, "custom identity never rebinds to an official provider with a similar name")
            passed("missing-target cleanup without guessing replacements")

            let unassignedChoice = KeychainCharmSelection(customGroupID: "entry:\(unassigned.id.uuidString)", color: .rose)
            let unassignedItem = KeychainCatalog.resolve(selection: unassignedChoice, groups: groups)
            try expect(unassignedItem.name == unassigned.name && unassignedItem.savedCount == 1, "entry-backed unnamed provider resolves to its one actual entry")
            try expect(unassignedItem.group?.entries.first?.id == unassigned.id, "entry-backed target does not select another credential")
            try expect(KeychainCatalog.resolve(selection: unassignedChoice, groups: []).isUnavailable, "deleted entry-backed target becomes unavailable")
            passed("entry-backed custom platform lifecycle")

            let serialized = String(decoding: try JSONEncoder().encode(missingConfiguration), as: UTF8.self)
            for excluded in [customA.secret, customA.baseURL, customA.notes, customA.accountLabel] {
                try expect(!serialized.contains(excluded), "selection persistence does not contain credential values")
            }
            try expect(KeychainCharmColor.allCases.map(\.rawValue) == ["ice", "lavender", "mint", "amber", "rose", "graphite"], "all six supported color names remain stable")
            passed("selection metadata and six colors")

            print("PASS Keychain catalog: \(checks) checks, \(assertions) assertions; fake in-memory data only.")
        } catch let error as CatalogCheckFailure {
            print("FAIL Keychain catalog: \(error.message)")
            exit(1)
        } catch {
            print("FAIL Keychain catalog: unexpected error after \(assertions) assertions.")
            exit(1)
        }
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CatalogCheckFailure(message: message) }
        return value
    }
}
