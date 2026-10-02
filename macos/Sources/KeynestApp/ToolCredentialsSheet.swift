import SwiftUI
import KeynestCore

struct ToolCredentialsSheet: View {
    let tool: ToolGroup
    let entries: [SecretEntry]
    let onSave: (Set<UUID>) throws -> Void
    let onCancel: () -> Void
    @State private var selected: Set<UUID>
    @State private var search = ""
    @State private var error: String?

    init(tool: ToolGroup, entries: [SecretEntry], onSave: @escaping (Set<UUID>) throws -> Void,
         onCancel: @escaping () -> Void) {
        self.tool = tool; self.entries = entries; self.onSave = onSave; self.onCancel = onCancel
        _selected = State(initialValue: Set(entries.filter { $0.toolIDs.contains(tool.id) }.map(\.id)))
    }

    private var matching: [SecretEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            query.isEmpty || [entry.name, entry.provider, entry.environment, entry.accountLabel]
                .contains { $0.localizedStandardContains(query) }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("为“\(tool.name)”关联密钥").font(.title2.weight(.semibold)).lineLimit(2)
                Text("一把密钥可供多个工具使用，更新一次即可。取消勾选只移除关联。")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("搜索名称、平台、环境或账号", text: $search)
                    .textFieldStyle(.roundedBorder).padding(.top, 8)
                    .accessibilityIdentifier("keynest.tool.links.search")
            }.padding(24)
            if entries.isEmpty {
                ContentUnavailableView("还没有可关联的密钥", systemImage: "key.horizontal",
                                       description: Text("先添加一把密钥，之后就能在多个工具间复用。"))
            } else if matching.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(matching) { entry in
                    Toggle(isOn: Binding(get: { selected.contains(entry.id) }, set: { value in
                        if value { selected.insert(entry.id) } else { selected.remove(entry.id) }
                    })) {
                        HStack(spacing: 10) {
                            ProviderIcon(preset: ProviderPreset.match(provider: entry.provider), fallbackSymbol: entry.category.symbol, size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(.body.weight(.medium))
                                Text([entry.provider, entry.environment, entry.accountLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }.toggleStyle(.checkbox).accessibilityIdentifier("keynest.tool.links.\(entry.id.uuidString)")
                }.listStyle(.inset)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal, 24).padding(.bottom, 12) }
            Divider()
            HStack {
                Text("已选择 \(selected.count) 把密钥").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存关联") {
                    do { try onSave(selected) } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 650, height: 560)
    }
}
