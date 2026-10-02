import Foundation

extension ProviderPreset {
    /// Fill preset-owned or empty fields; keep credentials and user-customized values.
    public func applying(to entry: SecretEntry) -> SecretEntry {
        var result = entry
        let previous = Self.match(provider: entry.provider)
        // Only the untouched default category receives a suggestion. Changing
        // templates later must not recategorize a user's existing draft.
        let isEmptyDraft = [entry.name, entry.provider, entry.secret, entry.baseURL,
                            entry.website, entry.notes, entry.environment, entry.accountLabel]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && entry.tags.isEmpty
        if isEmptyDraft && entry.category == .ai { result.category = suggestedCategory }
        if entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.name == previous?.name {
            result.name = name
        }
        if entry.website.isEmpty || entry.website == previous?.website { result.website = website }
        if entry.baseURL.isEmpty || entry.baseURL == previous?.baseURL { result.baseURL = baseURL }
        result.provider = name
        if previous?.id != id {
            // Selecting a template never authorizes a network request.
            result.quotaProvider = .none
            result.quota = nil
        }
        return result
    }
}
