import Foundation

/// A draft never leaves the form until all selected slots can be saved together.
public struct ToolCredentialSelection: Sendable {
    public var slotID: String
    public var providerID: String
    public var existingEntryID: UUID?
    public var secret: String
    public var baseURL: String

    public init(slotID: String, providerID: String, existingEntryID: UUID? = nil,
                secret: String = "", baseURL: String = "") {
        self.slotID = slotID; self.providerID = providerID; self.existingEntryID = existingEntryID
        self.secret = secret; self.baseURL = baseURL
    }
}

extension VaultDocument {
    /// Builds a new document without mutating the source. The caller commits it
    /// with one encrypted write; failures cannot leave a half-created tool.
    public func addingTool(templateID: String, name: String, selections: [ToolCredentialSelection]) throws
        -> (document: VaultDocument, tool: ToolGroup) {
        guard let template = ToolTemplate.all.first(where: { $0.id == templateID }) else {
            throw VaultError.invalidField("这个工具模板不存在，请重新选择。")
        }
        var result = try validated()
        let tool = try ToolGroup(name: name, templateID: template.id).validated()
        let slots = Dictionary(uniqueKeysWithValues: template.credentialSlots.map { ($0.id, $0) })
        let chosenIDs = selections.map(\.slotID)
        guard Set(chosenIDs).count == chosenIDs.count,
              Set(chosenIDs).isSubset(of: Set(slots.keys)),
              template.credentialSlots.filter({ !$0.isOptional }).allSatisfy({ chosenIDs.contains($0.id) }) else {
            throw VaultError.invalidField("请补全必需的凭据，每个用途只能选择一次。")
        }
        for selection in selections {
            guard let slot = slots[selection.slotID], slot.providerIDs.contains(selection.providerID),
                  let preset = ProviderPreset.all.first(where: { $0.id == selection.providerID }) else {
                throw VaultError.invalidField("所选服务与这个工具用途不匹配。")
            }
            if let entryID = selection.existingEntryID {
                guard let index = result.entries.firstIndex(where: { $0.id == entryID }),
                      ProviderPreset.match(provider: result.entries[index].provider)?.id == preset.id else {
                    throw VaultError.invalidField("已有密钥已变更或不属于所选平台，请重新选择。")
                }
                if !result.entries[index].toolIDs.contains(tool.id) {
                    result.entries[index].toolIDs.append(tool.id)
                    result.entries[index].updatedAt = Date()
                }
            } else {
                var entry = SecretEntry(name: "\(tool.name) · \(slot.title)",
                                        category: template.kind == .skill ? .skill : preset.suggestedCategory,
                                        provider: preset.name, secret: selection.secret,
                                        baseURL: selection.baseURL, website: preset.website,
                                        tags: [template.kind.title], notes: "\(slot.title) · \(preset.name)",
                                        toolIDs: [tool.id])
                entry = try entry.validated()
                result.entries.append(entry)
            }
        }
        result.tools.append(tool)
        return (try result.validated(), tool)
    }
}
