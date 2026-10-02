import SwiftUI
import KeynestCore

struct EntryEditor: View {
    private let original: SecretEntry
    private let tools: [ToolGroup]
    private let allowsQuotaQueries: Bool
    let onSave: (SecretEntry) throws -> Void
    let onCancel: () -> Void
    @State private var draft: SecretEntry
    @State private var tagsText: String
    @State private var validationMessage: String?
    @State private var advancedExpanded = false
    @State private var choosingProvider: Bool
    @State private var hasOpenedEditor: Bool
    private enum Field { case name, secret }
    @FocusState private var focusedField: Field?

    init(entry: SecretEntry, tools: [ToolGroup] = [], allowsQuotaQueries: Bool = true,
         onSave: @escaping (SecretEntry) throws -> Void, onCancel: @escaping () -> Void) {
        self.original = entry
        self.tools = tools
        self.allowsQuotaQueries = allowsQuotaQueries
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: entry)
        _tagsText = State(initialValue: entry.tags.joined(separator: ", "))
        _choosingProvider = State(initialValue: entry.name.isEmpty && entry.provider.isEmpty)
        _hasOpenedEditor = State(initialValue: !(entry.name.isEmpty && entry.provider.isEmpty))
    }

    var body: some View {
        VStack(spacing: 0) {
            if choosingProvider {
                ProviderPicker(selected: ProviderPreset.match(provider: draft.provider), onChoose: { preset in
                    draft = preset.applying(to: draft)
                    validationMessage = nil
                    hasOpenedEditor = true
                    choosingProvider = false
                }, onCustom: {
                    hasOpenedEditor = true
                    choosingProvider = false
                }, onCancel: {
                    if !hasOpenedEditor { cancel() }
                    else { choosingProvider = false }
                })
            } else {
                editorBody
            }
        }
        .onDisappear { draft.secret = "" }
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ProviderIcon(preset: ProviderPreset.match(provider: draft.provider), fallbackSymbol: "key.horizontal", size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(original.name.isEmpty ? "添加密钥" : "编辑密钥")
                        .font(.headline)
                    Text(draft.provider.isEmpty ? "选择平台或填写自定义提供商" : draft.provider)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let preset = ProviderPreset.match(provider: draft.provider), let website = URL(string: preset.website) {
                    Link(destination: website) { Label("API 官网", systemImage: "arrow.up.right") }
                        .help("打开 \(preset.name) 官方 API 网站")
                        .accessibilityIdentifier("keynest.preset.website")
                }
                Button("选择预设…") { choosingProvider = true }
                    .accessibilityIdentifier("keynest.preset.change")
            }
            .padding(.horizontal, 25)
            .padding(.top, 22)
            .padding(.bottom, 5)

            Form {
                Section {
                    TextField("名称", text: $draft.name, prompt: Text("例如：工作账号 · 主密钥"))
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("keynest.entry.name")
                    TextField("提供商", text: $draft.provider, prompt: Text("例如：OpenAI 或自建服务"))
                        .accessibilityIdentifier("keynest.entry.provider")
                    SecureField("API Key / 密钥", text: $draft.secret, prompt: Text("粘贴密钥"))
                        .privacySensitive()
                        .focused($focusedField, equals: .secret)
                        .accessibilityIdentifier("keynest.entry.secret")
                    TextField("API 地址", text: $draft.baseURL, prompt: Text("可选，例如 https://api.example.com/v1"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("keynest.entry.baseURL")
                } header: {
                    Text("基本信息")
                } footer: {
                    if let preset = ProviderPreset.match(provider: draft.provider), !preset.usageHint.isEmpty {
                        Text(preset.usageHint).font(.caption)
                    }
                    if ProviderPreset.match(provider: draft.provider)?.id == "openai" {
                        Text("这里保存 OpenAI API 密钥；ChatGPT 订阅与 API 额度分开。")
                            .font(.caption)
                    }
                }

                Section {
                    if tools.isEmpty {
                        Text("先保存密钥，稍后可在左侧添加工具并关联。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        toolChoices
                    }
                } header: {
                    HStack {
                        Text("使用位置")
                        Spacer()
                        if !draft.toolIDs.isEmpty {
                            Text("已选 \(draft.toolIDs.count) 个工具")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("可选择多个工具，它们引用同一条密钥记录，不会复制成多份。")
                        .font(.caption)
                }

                Section("账号与环境") {
                    TextField("账号", text: $draft.accountLabel, prompt: Text("可选，例如个人账号或工作邮箱"))
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .accessibilityIdentifier("keynest.entry.account")
                    TextField("环境", text: $draft.environment, prompt: Text("可选，也可以自定义"))
                        .accessibilityIdentifier("keynest.entry.environment")
                    HStack(spacing: 8) {
                        Text("常用环境")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(["开发", "测试", "生产"], id: \.self) { environment in
                            Button(environment) { draft.environment = environment }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("将环境设为\(environment)")
                        }
                        Spacer()
                        if !draft.environment.isEmpty {
                            Button("清空") { draft.environment = "" }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .accessibilityLabel("清空环境")
                        }
                    }
                }

                Section {
                    DisclosureGroup("高级选项", isExpanded: $advancedExpanded) {
                        advancedFields
                    }
                }
            }
            .formStyle(.grouped)

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 25)
                    .padding(.bottom, 12)
            }

            Divider()
            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("keynest.entry.cancel")
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.secret.isEmpty)
                    .accessibilityIdentifier("keynest.entry.save")
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 17)
        }
        .frame(width: 650, height: 680)
        .task { focusedField = draft.name.isEmpty || !original.secret.isEmpty ? .name : .secret }
    }

    private var toolChoices: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 4) {
                ForEach(tools) { tool in
                    Toggle(isOn: toolSelection(tool.id)) {
                        Text(tool.name).lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .help(tool.name)
                    .accessibilityIdentifier("keynest.entry.tool.\(tool.id.uuidString)")
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(height: min(CGFloat((tools.count + 1) / 2) * 32 + 4, 132))
    }

    private var advancedFields: some View {
        Group {
            TextField("来源网站", text: $draft.website, prompt: Text("https://example.com"))
                .autocorrectionDisabled()
            Text("来源网站可以是官网或控制台。")
                .font(.caption).foregroundStyle(.secondary)

            Picker("分类", selection: $draft.category) {
                ForEach(EntryCategory.allCases, id: \.self) { category in
                    Label(category.title, systemImage: category.symbol).tag(category)
                }
            }
            TextField("标签", text: $tagsText, prompt: Text("用逗号分隔"))
                .accessibilityIdentifier("keynest.entry.tags")
            Text("最多 12 个标签，每个不超过 40 字符。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("加入星标", isOn: $draft.isFavorite)
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 7) {
                Text("用途与备注").font(.callout)
                TextEditor(text: $draft.notes)
                    .font(.body)
                    .frame(height: 76)
                    .accessibilityLabel("用途与备注")
                    .accessibilityIdentifier("keynest.entry.notes")
                    .scrollContentBackground(.hidden)
            }
            .padding(.vertical, 4)

            Divider()
            if allowsQuotaQueries {
                Picker("额度查询", selection: $draft.quotaProvider) {
                    ForEach(QuotaProvider.allCases, id: \.self) { provider in
                        Text(provider == .none ? "不启用" : provider.title).tag(provider)
                    }
                }
                if let endpoint = draft.quotaProvider.endpoint {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("查询时，密钥只会发送到这个官方地址：")
                            .foregroundStyle(.secondary)
                        Text(endpoint.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        if draft.quotaProvider == .openrouter {
                            Text("OpenRouter 提供此 Key 的限额与用量，不是账户总余额。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                } else {
                    Text("保存密钥不需要开启额度查询。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("演示版使用虚构密钥，不发送额度查询请求。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func toolSelection(_ id: UUID) -> Binding<Bool> {
        Binding {
            draft.toolIDs.contains(id)
        } set: { selected in
            if selected {
                if !draft.toolIDs.contains(id) { draft.toolIDs.append(id) }
            } else {
                draft.toolIDs.removeAll { $0 == id }
            }
        }
    }

    private func save() {
        var result = draft
        result.tags = tagsText
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if result.secret != original.secret || result.baseURL != original.baseURL || result.provider != original.provider || result.quotaProvider != original.quotaProvider {
            result.quota = nil
        }
        do {
            result = try result.validated()
            try onSave(result)
            draft.secret = ""
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func cancel() {
        draft.secret = ""
        onCancel()
    }
}
