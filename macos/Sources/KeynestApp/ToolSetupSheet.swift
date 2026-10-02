import SwiftUI
import AppKit
import KeynestCore

struct ToolIcon: View {
    let templateID: String?
    var size: CGFloat = 36
    private var template: ToolTemplate? { ToolTemplate.all.first { $0.id == templateID } }
    private static let images: [String: NSImage] = {
        guard let root = Bundle.main.resourceURL else { return [:] }
        return Dictionary(uniqueKeysWithValues: ToolTemplate.all.compactMap { template in
            guard let logo = template.logoID,
                  let image = NSImage(contentsOf: root.appendingPathComponent("ToolIcons/\(logo).png")) else { return nil }
            return (template.id, image)
        })
    }()
    var body: some View {
        Group {
            if let template, let image = Self.images[template.id] {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .padding(size * 0.15).background(.white)
            } else if let providerID = template?.providerLogoIDs.first {
                ProviderIcon(preset: ProviderPreset.all.first { $0.id == providerID }, size: size)
            } else {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: size * 0.48)).foregroundStyle(.tint)
                    .frame(width: size, height: size).background(.quinary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23))
        .overlay(RoundedRectangle(cornerRadius: size * 0.23).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

private struct ProviderDraft {
    var reuse: Bool
    var entryID: UUID?
    var secret: String
    var baseURL: String
}

private struct SlotDraft: Identifiable {
    let slot: ToolCredentialSlot
    var id: String { slot.id }
    var enabled: Bool
    var providerID: String
    var reuse: Bool
    var entryID: UUID?
    var secret = ""
    var baseURL: String
    var providerDrafts: [String: ProviderDraft] = [:]
}

private struct TemplateDraft {
    var name: String
    var slots: [SlotDraft]
}

struct ToolSetupSheet: View {
    let entries: [SecretEntry]
    let onSave: (ToolTemplate, String, [ToolCredentialSelection]) throws -> Void
    let onCustom: () -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var kind: ToolTemplateKind?
    @State private var selected: ToolTemplate?
    @State private var name = ""
    @State private var drafts: [SlotDraft] = []
    @State private var templateDrafts: [String: TemplateDraft] = [:]
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    private var matches: [ToolTemplate] {
        ToolTemplate.all.filter { (kind == nil || $0.kind == kind) && $0.matches(search: query) }
    }
    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && drafts.filter(\.enabled).allSatisfy {
            $0.reuse ? $0.entryID != nil : !$0.secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selected { configuration(selected) } else { catalog }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            Divider()
            HStack {
                if selected == nil {
                    Button("自定义工具", action: onCustom).accessibilityIdentifier("keynest.template.custom")
                } else {
                    Button("返回模板") {
                        if let selected { templateDrafts[selected.id] = TemplateDraft(name: name, slots: drafts) }
                        selected = nil; drafts = []; errorMessage = nil
                    }
                }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                if selected != nil {
                    Button("添加工具", action: save).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction).disabled(!ready)
                        .accessibilityIdentifier("keynest.template.save")
                }
            }.padding(.horizontal, 24).padding(.vertical, 17)
        }
        .frame(width: 780, height: 670)
        .task { searchFocused = true }
        .onDisappear { drafts = []; templateDrafts = [:]; name = "" }
    }

    @ViewBuilder private var catalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择工具与 Skill").font(.title2.weight(.semibold))
                Spacer()
                Text("\(ToolTemplate.all.count) 个模板").foregroundStyle(.secondary)
            }
            Text("选择常用工具，快速整理它需要的 API。已有密钥可以直接复用。")
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索工具、Agent 或用途", text: $query).textFieldStyle(.plain)
                    .focused($searchFocused).accessibilityIdentifier("keynest.template.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                        .accessibilityLabel("清除工具搜索")
                }
            }.padding(10).background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            Picker("工具类型", selection: $kind) {
                Text("全部").tag(nil as ToolTemplateKind?)
                ForEach(ToolTemplateKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }.pickerStyle(.segmented).labelsHidden()
        }.padding(24)
        Divider()
        ScrollView {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(matches) { template in
                        Button { choose(template) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    ToolIcon(templateID: template.id, size: 38)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(template.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                        Text(template.kind.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                Text(template.summary).font(.callout).foregroundStyle(.secondary)
                                    .lineLimit(2).frame(height: 34, alignment: .topLeading)
                                HStack(spacing: 5) {
                                    ForEach(previewProviders(template), id: \.self) { providerID in
                                        ProviderIcon(preset: ProviderPreset.all.first { $0.id == providerID }, size: 21)
                                    }
                                    Spacer()
                                    Text("\(template.credentialSlots.count) 类凭据").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.09)))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel("选择 \(template.name) 模板")
                            .accessibilityIdentifier("keynest.template.\(template.id)")
                    }
                }.padding(24)
            }
        }.background(.quinary.opacity(0.35))
    }

    private func configuration(_ template: ToolTemplate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ToolIcon(templateID: template.id, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.title2.weight(.semibold))
                    Text("把这个工具要用的凭据保存在一起").foregroundStyle(.secondary)
                }
                Spacer()
                if let url = URL(string: template.website), url.scheme == "https" {
                    Link("配置文档 ↗", destination: url).font(.callout)
                }
            }.padding(24)
            Divider()
            Form {
                Section {
                    TextField("工具名称", text: $name).accessibilityIdentifier("keynest.template.name")
                }
                ForEach(drafts.indices, id: \.self) { index in slotSection(index) }
                if !template.notes.isEmpty {
                    Section { Text(template.notes).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }.formStyle(.grouped)
        }
    }

    private func slotSection(_ index: Int) -> some View {
        let draft = drafts[index]
        let providers = ProviderPreset.all.filter { draft.slot.providerIDs.contains($0.id) }
        let existing = matchingEntries(draft.providerID)
        let preset = providers.first { $0.id == draft.providerID }
        return Section {
            if draft.slot.isOptional {
                Toggle("添加\(draft.slot.title)", isOn: $drafts[index].enabled)
            }
            if draft.enabled {
                Picker("API 平台", selection: $drafts[index].providerID) {
                    ForEach(providers) { provider in
                        HStack {
                            ProviderIcon(preset: provider, size: 20)
                            Text(provider.name)
                        }.tag(provider.id)
                    }
                }.onChange(of: drafts[index].providerID) { previousID, providerID in
                    var changed = drafts[index]
                    changed.providerDrafts[previousID] = ProviderDraft(reuse: changed.reuse, entryID: changed.entryID,
                                                                      secret: changed.secret, baseURL: changed.baseURL)
                    let found = matchingEntries(providerID)
                    let remembered = changed.providerDrafts[providerID] ?? ProviderDraft(
                        reuse: !found.isEmpty, entryID: found.count == 1 ? found[0].id : nil,
                        secret: "", baseURL: providers.first { $0.id == providerID }?.baseURL ?? "")
                    changed.reuse = remembered.reuse; changed.entryID = remembered.entryID
                    changed.secret = remembered.secret; changed.baseURL = remembered.baseURL
                    drafts[index] = changed
                }
                if !existing.isEmpty {
                    Picker("凭据来源", selection: $drafts[index].reuse) {
                        Text("复用已有密钥").tag(true)
                        Text("保存新密钥").tag(false)
                    }.pickerStyle(.segmented)
                }
                if draft.reuse && !existing.isEmpty {
                    Picker("已有密钥", selection: $drafts[index].entryID) {
                        Text("请选择密钥").tag(nil as UUID?)
                        ForEach(existing) { entry in
                            Text([entry.name, entry.accountLabel, entry.environment].filter { !$0.isEmpty }.joined(separator: " · "))
                                .tag(Optional(entry.id))
                        }
                    }
                    Text("保留原密钥，再关联到此工具。").font(.caption).foregroundStyle(.secondary)
                } else {
                    SecureField("密钥 / Token", text: $drafts[index].secret)
                        .accessibilityIdentifier("keynest.template.secret.\(draft.id)")
                    TextField("API 地址", text: $drafts[index].baseURL,
                              prompt: Text("可选；按平台要求填写项目专属地址"))
                        .accessibilityIdentifier("keynest.template.url.\(draft.id)")
                    if let preset {
                        HStack(spacing: 8) {
                            ProviderIcon(preset: preset, size: 20)
                            if let url = URL(string: preset.website) { Link("\(preset.name) API 官网 ↗", destination: url) }
                        }
                        Text(preset.usageHint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } header: {
            Text(draft.slot.title + (draft.slot.isOptional ? " · 可选" : ""))
        }
    }

    private func previewProviders(_ template: ToolTemplate) -> [String] {
        let ids = template.providerLogoIDs.isEmpty ? template.credentialSlots.map(\.defaultProviderID) : template.providerLogoIDs
        var seen = Set<String>()
        return Array(ids.filter { seen.insert($0).inserted }.prefix(5))
    }

    private func matchingEntries(_ providerID: String) -> [SecretEntry] {
        entries.filter { ProviderPreset.match(provider: $0.provider)?.id == providerID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func choose(_ template: ToolTemplate) {
        errorMessage = nil
        if let remembered = templateDrafts[template.id] {
            name = remembered.name; drafts = remembered.slots; selected = template
            return
        }
        name = template.name
        drafts = template.credentialSlots.map { slot in
            let existing = matchingEntries(slot.defaultProviderID)
            return SlotDraft(slot: slot, enabled: !slot.isOptional, providerID: slot.defaultProviderID,
                             reuse: !existing.isEmpty, entryID: existing.count == 1 ? existing[0].id : nil,
                             baseURL: ProviderPreset.all.first { $0.id == slot.defaultProviderID }?.baseURL ?? "")
        }
        selected = template
    }
    private func save() {
        guard let selected else { return }
        let selections = drafts.filter(\.enabled).map {
            ToolCredentialSelection(slotID: $0.id, providerID: $0.providerID,
                                    existingEntryID: $0.reuse ? $0.entryID : nil,
                                    secret: $0.reuse ? "" : $0.secret, baseURL: $0.baseURL)
        }
        do { try onSave(selected, name, selections) }
        catch { errorMessage = error.localizedDescription }
    }
}
