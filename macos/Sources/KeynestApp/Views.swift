import AppKit
import SwiftUI
import KeynestCore

struct MainView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.isDemo {
                Label("演示库 · 虚构密钥 · 请勿存放真实凭据", systemImage: "testtube.2")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
            Group {
                if model.isLocked {
                    VaultAccessView()
                } else {
                    LibraryView()
                }
            }
        }
        .frame(minWidth: 880, minHeight: 580)
        .sheet(isPresented: $model.presentingHomeProviderPicker) {
            ProviderPicker(selected: nil, onChoose: model.quickAdd, onCustom: model.addCustomCredential,
                           onCancel: { model.presentingHomeProviderPicker = false })
        }
        .sheet(item: $model.quickAddPreset) { preset in
            QuickAddSheet(preset: preset, existingEntries: model.entries, onSave: model.save, onAdvanced: model.openAdvancedEntry,
                          onCancel: { model.quickAddPreset = nil })
        }
        .sheet(isPresented: $model.presentingEditor) {
            EntryEditor(
                entry: model.editingEntry ?? SecretEntry(),
                tools: model.sortedTools,
                allowsQuotaQueries: !model.isDemo,
                onSave: { entry in
                    try model.save(entry)
                    model.presentingEditor = false
                },
                onCancel: { model.presentingEditor = false; model.editingEntry = nil }
            )
            .onDisappear { model.editingEntry = nil }
        }
        .sheet(isPresented: $model.presentingToolSetup) {
            ToolSetupSheet(entries: model.entries, onSave: model.saveTemplate,
                           onCustom: model.addCustomTool,
                           onCancel: { model.presentingToolSetup = false })
        }
        .sheet(isPresented: $model.presentingToolEditor) {
            ToolEditor(tool: model.editingTool ?? ToolGroup(), onSave: model.saveTool,
                       onCancel: { model.presentingToolEditor = false })
        }
        .sheet(isPresented: $model.presentingToolLinks) {
            if let tool = model.linkingTool {
                ToolCredentialsSheet(tool: tool, entries: model.entries,
                    onSave: { try model.saveLinks($0, for: tool) },
                    onCancel: { model.presentingToolLinks = false })
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.toast {
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .padding(.horizontal, 30)
                    .padding(.bottom, 22)
                    .accessibilityLabel(message)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct VaultAccessView: View {
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @State private var confirmation = ""
    @State private var validationMessage: String?
    @State private var usePassword = false
    @State private var enableAfterPassword = true
    @FocusState private var focusedField: Field?
    private enum Field { case password, confirmation }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 78, height: 78)
                .accessibilityHidden(true)
                .padding(.bottom, 18)
            Text(model.isDemo ? "Keynest 演示版" : model.isInitialized ? "解锁 Keynest" : "创建你的密钥库")
                .font(.title2.weight(.semibold))
            Text(model.biometricEnabled ? "使用 Touch ID，打开本机保存的 API 与密钥。" : model.isDemo ? "按工具整理多把密钥，体验搜索与本地取用。" : model.isInitialized ? "输入主密码，打开你的 API 与密钥收藏。" : "把工具要用的 API 密钥放在一起，随时在本地取用。")
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 27)

            VStack(alignment: .leading, spacing: 13) {
                if model.isInitialized && model.biometricEnabled && !usePassword {
                    Button { Task { await model.unlockWithBiometrics() } } label: {
                        HStack(spacing: 10) {
                            if model.busy { ProgressView().controlSize(.small) }
                            else { Image(systemName: "touchid").font(.title2) }
                            Text(model.busy ? "请完成系统验证…" : "使用 Touch ID 解锁")
                        }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.busy)
                    .accessibilityIdentifier("keynest.touchid.unlock")
                    Button("使用主密码") {
                        model.cancelBiometricAuthentication(); usePassword = true; focusedField = .password
                    }
                    .buttonStyle(.link).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("keynest.touchid.password")
                } else {
                SecureField(model.isDemo ? "测试密码" : "主密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focusedField, equals: .password)
                    .privacySensitive()
                    .onSubmit(submit)
                    .disabled(model.busy)
                if !model.isInitialized {
                    SecureField("再次输入主密码", text: $confirmation)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focusedField, equals: .confirmation)
                        .privacySensitive()
                        .onSubmit(submit)
                        .disabled(model.busy)
                }
                Text(model.isDemo ? "测试密码：\(DemoVault.password)" : model.isInitialized ? "闲置 10 分钟后会自动锁定。" : "至少 12 个字符。请妥善保存主密码，遗失后无法找回。")
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.biometricAvailable && !model.biometricEnabled {
                    Toggle("\(model.isInitialized ? "解锁" : "创建")后启用 Touch ID", isOn: $enableAfterPassword)
                        .font(.callout).disabled(model.busy)
                        .accessibilityIdentifier("keynest.touchid.optin")
                    Text("在这台 Mac 上用指纹解锁，主密码仍可备用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if model.busy { ProgressView().controlSize(.small) }
                        Text(model.busy ? "正在打开…" : model.isDemo ? "打开演示库" : model.isInitialized ? "解锁" : "创建密钥库")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy || password.isEmpty)
                .padding(.top, 3)
                if !model.isInitialized {
                    Button("从加密备份恢复…") { model.importBackup() }
                        .buttonStyle(.link)
                        .frame(maxWidth: .infinity)
                        .disabled(model.busy)
                        .padding(.top, 4)
                }
                if model.biometricEnabled {
                    Button("改用 Touch ID") { usePassword = false; password = ""; Task { await model.unlockWithBiometrics() } }
                        .buttonStyle(.link).frame(maxWidth: .infinity).disabled(model.busy)
                }
                }
                if let message = model.biometricMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("keynest.touchid.message")
                }
            }
            .frame(width: 340)
            Spacer(minLength: 35)
            VStack(spacing: 7) {
                Label(model.isDemo ? "独立测试库，与正式密钥库分开存储" : "本机加密存储", systemImage: "externaldrive.badge.checkmark")
                    .font(.caption)
                Text("实验版 · 未经独立安全审计")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.prepareAccess()
            focusedField = model.biometricEnabled && !usePassword ? nil : .password
        }
        .onDisappear { password = ""; confirmation = "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.prepareAccess() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            password = ""
            confirmation = ""
        }
    }

    private func submit() {
        guard !model.busy else { return }
        validationMessage = nil
        if !model.isInitialized {
            guard password.count >= 12 else {
                validationMessage = "主密码需要至少 12 个字符。"
                focusedField = .password
                return
            }
            guard password == confirmation else {
                validationMessage = "两次输入的主密码不一致。"
                focusedField = .confirmation
                return
            }
        }
        let suppliedPassword = password
        let shouldEnableBiometrics = enableAfterPassword && model.biometricAvailable && !model.biometricEnabled
        password = ""
        confirmation = ""
        Task {
            if model.isInitialized {
                await model.unlock(password: suppliedPassword)
            } else {
                await model.create(password: suppliedPassword)
            }
            if !model.isLocked && shouldEnableBiometrics { await model.enableBiometrics() }
            focusedField = .password
        }
    }
}

private struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var removingTool: ToolGroup?
    @State private var homeToolsExpanded = false
    @State private var homeTypesExpanded = false
    @State private var managementToolsExpanded = true
    @State private var managementTypesExpanded = true

    var body: some View {
        Group {
            if model.filter == .home {
                NavigationSplitView(columnVisibility: $visibility) {
                    sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 260)
                } detail: {
                    HomeView().navigationTitle("首页")
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                managementNavigation
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.addNew() } label: { Label("添加密钥", systemImage: "plus") }
                    .labelStyle(.titleAndIcon)
                    .help("添加密钥（⌘N）").accessibilityIdentifier("keynest.add.entry")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.lock() } label: { Label("锁定密钥库", systemImage: "lock") }
                    .help("锁定密钥库（⇧⌘L）")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("导出加密备份…", systemImage: "square.and.arrow.up") { model.exportBackup() }
                    Button("导入加密备份…", systemImage: "square.and.arrow.down") { model.importBackup() }
                    Divider()
                    Button("更改主密码…", systemImage: "key") { model.changePassword() }
                } label: { Label("密钥库选项", systemImage: "ellipsis.circle") }
                .help("密钥库选项").disabled(model.isDemo)
            }
        }
        .onChange(of: model.filteredEntries.map(\.id)) { _, ids in
            if model.filter == .home { model.selectedID = nil }
            else if model.selectedID.map({ ids.contains($0) }) != true { model.selectedID = ids.first }
        }
        .confirmationDialog("移除工具分组？", isPresented: Binding(
            get: { removingTool != nil }, set: { if !$0 { removingTool = nil } }
        ), titleVisibility: .visible) {
            Button("移除分组，保留密钥", role: .destructive) {
                if let tool = removingTool {
                    do { try model.removeTool(tool) } catch { model.errorMessage = error.localizedDescription }
                }
                removingTool = nil
            }
            Button("取消", role: .cancel) { removingTool = nil }
        } message: {
            Text("只移除“\(removingTool?.name ?? "")”的分组关系。所有密钥仍可在“全部密钥”中找到。")
        }
    }

    private var managementNavigation: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 260)
        } content: {
            collection.navigationSplitViewColumnWidth(min: 265, ideal: 310, max: 390)
        } detail: {
            if let entry = model.selectedEntry {
                EntryDetailView(entry: entry).id(entry.id)
            } else {
                ContentUnavailableView {
                    Label("要用的 API，就在这里", systemImage: "key.horizontal")
                } description: {
                    Text("先选择工具或密钥，直接复制密钥与 API 地址。\n同一工具可以管理多个平台、账号和环境。")
                } actions: {
                    if model.entries.isEmpty && model.tools.isEmpty {
                        Button("添加第一个工具") { model.addTool() }.buttonStyle(.borderedProminent)
                        Button("直接添加密钥") { model.addNew() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "搜索名称、平台、工具或账号")
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding<LibraryFilter?>(
                get: { model.filter }, set: { if let filter = $0 { model.selectFilter(filter) } }
            )) {
                Section("密钥库") {
                    SidebarRow(title: "首页", symbol: "house", count: 0).tag(LibraryFilter.home)
                    SidebarRow(title: "全部密钥", symbol: "key.horizontal", count: model.entries.count).tag(LibraryFilter.all)
                    SidebarRow(title: "常用密钥", symbol: "star", count: model.entries.filter(\.isFavorite).count).tag(LibraryFilter.favorites)
                    SidebarRow(title: "未归组", symbol: "tray", count: model.entries.filter { $0.toolIDs.isEmpty }.count).tag(LibraryFilter.ungrouped)
                }
                Section("我的工具", isExpanded: Binding(
                    get: { model.filter == .home ? homeToolsExpanded : managementToolsExpanded },
                    set: { if model.filter == .home { homeToolsExpanded = $0 } else { managementToolsExpanded = $0 } }
                )) {
                    ForEach(model.sortedTools) { tool in
                        HStack(spacing: 8) {
                            ToolIcon(templateID: tool.templateID, size: 22)
                            Text(tool.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(model.entries.filter { $0.toolIDs.contains(tool.id) }.count)")
                                .foregroundStyle(.secondary).monospacedDigit().font(.caption)
                        }
                            .tag(LibraryFilter.tool(tool.id))
                            .contextMenu {
                                Button("添加密钥…", systemImage: "plus") { model.selectFilter(.tool(tool.id)); model.addNew() }
                                Button("关联已有密钥…", systemImage: "link") { model.manageLinks(for: tool) }
                                Button("编辑工具…", systemImage: "pencil") { model.editTool(tool) }
                                Divider()
                                Button("移除工具分组…", systemImage: "folder.badge.minus", role: .destructive) { removingTool = tool }
                            }
                    }
                    if model.tools.isEmpty {
                        Text("把一个工具要用的密钥放在一起")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("密钥类型", isExpanded: Binding(
                    get: { model.filter == .home ? homeTypesExpanded : managementTypesExpanded },
                    set: { if model.filter == .home { homeTypesExpanded = $0 } else { managementTypesExpanded = $0 } }
                )) {
                    ForEach(EntryCategory.allCases, id: \.self) { category in
                        SidebarRow(title: category.title, symbol: category.symbol, count: model.entries.filter { $0.category == category }.count)
                            .tag(LibraryFilter.category(category))
                    }
                }
            }
            .listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 13) {
                Button { model.addTool() } label: { Label("添加工具", systemImage: "plus.circle") }
                    .buttonStyle(.borderless).accessibilityIdentifier("keynest.add.tool")
                Divider()
                Label(model.isDemo ? "独立演示库" : "本机加密存储", systemImage: "lock.shield").font(.caption)
                Text("闲置 10 分钟后锁定").font(.caption2).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).help(model.dataPath)
        }
        .navigationTitle(model.isDemo ? "Keynest Demo" : "Keynest")
    }

    private var collection: some View {
        VStack(spacing: 0) {
            if let tool = model.selectedTool {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ToolIcon(templateID: tool.templateID, size: 30)
                        Text(tool.name).font(.headline).lineLimit(2)
                        Spacer(minLength: 4)
                        Button { model.editTool(tool) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help("编辑工具").accessibilityLabel("编辑工具")
                    }
                    if !tool.notes.isEmpty { Text(tool.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    if let templateID = tool.templateID, let template = ToolTemplate.match(templateID: templateID),
                       let url = URL(string: template.website), url.scheme == "https" {
                        Link("配置文档 ↗", destination: url).font(.caption)
                    }
                    HStack(spacing: 8) {
                        Button("添加密钥", systemImage: "plus") { model.addNew() }
                        Button("关联已有", systemImage: "link") { model.manageLinks(for: tool) }
                            .accessibilityLabel("关联已有密钥").accessibilityIdentifier("keynest.tool.link")
                    }.controlSize(.small)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                Divider()
            }
            if model.environmentOptions.count > 1 || model.environmentFilter != nil {
                HStack {
                    Text("环境").font(.caption).foregroundStyle(.secondary)
                    Picker("筛选环境", selection: $model.environmentFilter) {
                        Text("全部环境").tag(nil as String?)
                        ForEach(model.environmentOptions, id: \.self) { environment in
                            Text(environment.isEmpty ? "未标注" : environment).tag(Optional(environment))
                        }
                    }.labelsHidden().pickerStyle(.menu).controlSize(.small)
                        .accessibilityIdentifier("keynest.filter.environment")
                    Spacer(minLength: 0)
                }.padding(.horizontal, 14).padding(.vertical, 9)
            }
            if model.filteredEntries.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: model.searchText.isEmpty ? "key.horizontal" : "magnifyingglass")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if !model.searchText.isEmpty || model.environmentFilter != nil {
                        Button("清除筛选") { model.searchText = ""; model.environmentFilter = nil }
                        if model.filter != .all {
                            Button("搜索全部密钥") { model.filter = .all; model.environmentFilter = nil }
                        }
                    } else if model.filter != .favorites {
                        Button("添加密钥") { model.addNew() }
                        if let tool = model.selectedTool { Button("关联已有密钥") { model.manageLinks(for: tool) } }
                    }
                }
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.filteredEntries) { entry in
                        EntryListRow(entry: entry).tag(entry.id)
                            .contextMenu {
                                Button("复制密钥", systemImage: "doc.on.doc") { model.copySecret(entry) }
                                Button("复制 API 地址", systemImage: "link") { model.copyAPIAddress(entry) }.disabled(entry.baseURL.isEmpty)
                                Button(entry.isFavorite ? "移出常用" : "加入常用", systemImage: "star") { model.toggleFavorite(entry) }
                                Divider()
                                Button("编辑密钥…", systemImage: "pencil") { model.edit(entry) }
                            }
                    }
                }.listStyle(.inset)
            }
            Text("\(model.filteredEntries.count) 把密钥 · 本地取用")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 9).background(.bar)
        }
        .navigationTitle(filterTitle)
    }
    private var filterTitle: String {
        switch model.filter {
        case .home: "首页"
        case .all: "全部密钥"
        case .favorites: "常用密钥"
        case .ungrouped: "未归组"
        case .tool: model.selectedTool?.name ?? "工具"
        case .category(let category): category.title
        }
    }
    private var emptyTitle: String {
        if !model.searchText.isEmpty || model.environmentFilter != nil { return "没有匹配的密钥" }
        if model.filter == .favorites { return "还没有常用密钥" }
        if model.filter == .ungrouped { return "密钥都已归组" }
        return model.selectedTool == nil ? "还没有密钥" : "为工具准备好 API"
    }
    private var emptyDescription: String {
        if !model.searchText.isEmpty || model.environmentFilter != nil { return "试试平台、账号、工具名称，或切换环境。" }
        if model.filter == .favorites { return "将常用密钥加星，下次更快找到。" }
        if model.filter == .ungrouped { return "没有关联工具的密钥会显示在这里。" }
        if model.selectedTool != nil { return "添加它要用的多把密钥，或关联已保存的密钥。" }
        return "保存一次，之后直接从本地复制。"
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let count: Int

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer(minLength: 6)
            if count > 0 {
                Text(count, format: .number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }
}

private struct EntryListRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: SecretEntry
    var body: some View {
        HStack(spacing: 10) {
            ProviderIcon(preset: ProviderPreset.match(provider: entry.provider), fallbackSymbol: entry.category.symbol, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(entry.name).font(.body.weight(.medium)).lineLimit(1)
                    if entry.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("常用") }
                }
                Text(entry.provider.isEmpty ? entry.category.title : entry.provider).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !entry.environment.isEmpty || !entry.accountLabel.isEmpty {
                    Text([entry.environment, entry.accountLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            Button { model.copySecret(entry) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("复制 \(entry.name) 的密钥").accessibilityLabel("复制 \(entry.name) 的密钥")
        }.padding(.vertical, 7).help(entry.name)
    }
}

private struct EntryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let entry: SecretEntry
    @State private var secretVisible = false
    @State private var revealTask: Task<Void, Never>?
    @State private var deleting = false
    @State private var quotaExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 10) {
                Button { model.copySecret(entry) } label: { Label("复制密钥", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("keynest.secret.copy")
                    .help("无需显示密钥即可复制（⇧⌘C）")
                Button { model.copyAPIAddress(entry) } label: { Label("复制 API 地址", systemImage: "link") }
                    .disabled(entry.baseURL.isEmpty).accessibilityIdentifier("keynest.address.copy")
                Spacer(minLength: 0)
            }.controlSize(.large).padding(.horizontal, 23).padding(.vertical, 12)
            Form {
                Section {
                    LabeledContent("密钥") {
                        HStack(spacing: 10) {
                            Group {
                                if secretVisible {
                                    Text(entry.secret).textSelection(.enabled).accessibilityLabel("密钥").accessibilityValue(entry.secret)
                                } else { Text("••••••••••••••••").accessibilityLabel("密钥已隐藏") }
                            }
                            .font(.system(.body, design: .monospaced)).privacySensitive()
                            .lineLimit(secretVisible ? 4 : 1).frame(maxWidth: .infinity, alignment: .trailing)
                            Button(action: toggleSecret) { Image(systemName: secretVisible ? "eye.slash" : "eye") }
                                .buttonStyle(.borderless)
                                .help(secretVisible ? "隐藏密钥" : "显示密钥 20 秒")
                                .accessibilityLabel(secretVisible ? "隐藏密钥" : "显示密钥")
                                .accessibilityIdentifier("keynest.secret.reveal")
                        }
                    }.accessibilityElement(children: .contain)
                    LabeledContent("API 地址") {
                        Text(entry.baseURL.isEmpty ? "未填写" : entry.baseURL)
                            .font(.system(.callout, design: .monospaced)).textSelection(.enabled).lineLimit(3)
                    }
                    if entry.baseURL.isEmpty {
                        Button("补充 API 地址…") { hideSecret(); model.edit(entry) }.font(.caption)
                    }
                    LabeledContent("账号", value: entry.accountLabel.isEmpty ? "未标注" : entry.accountLabel)
                    LabeledContent("环境", value: entry.environment.isEmpty ? "未标注" : entry.environment)
                } header: { Text("本地凭据") } footer: {
                    Text(secretVisible ? "密钥显示 20 秒后自动隐藏。" : "复制后 30 秒清除本次剪贴板内容；你新复制的其他内容会保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .contain)

                Section {
                    if model.tools(for: entry).isEmpty {
                        HStack {
                            Text("未归组").foregroundStyle(.secondary)
                            Spacer()
                            Button("关联工具…") { hideSecret(); model.edit(entry) }.buttonStyle(.link)
                        }
                    } else {
                        ForEach(model.tools(for: entry)) { tool in
                            HStack {
                                Label(tool.name, systemImage: "square.stack.3d.up")
                                Spacer(minLength: 8)
                                Button("查看") { hideSecret(); model.selectFilter(.tool(tool.id)) }.buttonStyle(.link)
                                    .accessibilityLabel("查看工具 \(tool.name)")
                            }
                        }
                    }
                } header: { Text("使用这把密钥的工具") } footer: {
                    if entry.toolIDs.count > 1 {
                        Text("多个工具共享同一条密钥记录，修改一次即可同步。")
                    }
                }

                if !entry.notes.isEmpty {
                    Section("用途与备注") {
                        Text(entry.notes).textSelection(.enabled).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !entry.tags.isEmpty {
                    Section("标签") { Text(entry.tags.joined(separator: " · ")).textSelection(.enabled) }
                }
                if !model.isDemo && entry.quotaProvider != .none {
                    Section {
                        DisclosureGroup("额度查询", isExpanded: $quotaExpanded) { quotaContent }
                    }.accessibilityElement(children: .contain)
                }
                Section("官网与来源") {
                    LabeledContent("平台", value: entry.provider.isEmpty ? "自定义服务" : entry.provider)
                    if let preset = ProviderPreset.match(provider: entry.provider), let website = URL(string: preset.website) {
                        LabeledContent("API 官网") {
                            Link(destination: website) {
                                Label(preset.website, systemImage: "arrow.up.right").lineLimit(2)
                            }
                            .help("打开 \(preset.name) 官方 API 网站")
                            .accessibilityLabel("打开 API 官网").accessibilityValue(preset.website)
                            .accessibilityIdentifier("keynest.official.open")
                        }.accessibilityElement(children: .contain)
                    }
                    if !entry.website.isEmpty && entry.website != ProviderPreset.match(provider: entry.provider)?.website, let website = safeWebsite {
                        LabeledContent("来源网站") {
                            Link(destination: website) { Label(entry.website, systemImage: "arrow.up.right").lineLimit(2) }
                                .accessibilityLabel("打开来源网站").accessibilityValue(entry.website)
                                .accessibilityIdentifier("keynest.source.open")
                        }.accessibilityElement(children: .contain)
                    }
                }
                Section {
                    LabeledContent("类型", value: entry.category.title)
                    LabeledContent("最后修改") { Text(entry.updatedAt.formatted(date: .abbreviated, time: .shortened)) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("删除“\(entry.name)”？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除密钥", role: .destructive) {
                do { try model.delete(entry) } catch { model.errorMessage = error.localizedDescription }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("这会删除本机密钥记录，并从所有关联工具中移除，无法直接撤销。服务商上的密钥仍然有效。")
        }
        .onChange(of: entry.secret) { _, _ in hideSecret() }
        .onChange(of: model.isLocked) { _, _ in hideSecret() }
        .onChange(of: model.quickAddPreset?.id) { _, presented in if presented != nil { hideSecret() } }
        .onChange(of: model.presentingHomeProviderPicker) { _, presented in if presented { hideSecret() } }
        .onChange(of: model.presentingEditor) { _, presented in if presented { hideSecret() } }
        .onChange(of: model.presentingToolSetup) { _, presented in if presented { hideSecret() } }
        .onChange(of: model.presentingToolEditor) { _, presented in if presented { hideSecret() } }
        .onChange(of: model.presentingToolLinks) { _, presented in if presented { hideSecret() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in hideSecret() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in hideSecret() }
        .onDisappear(perform: hideSecret)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            ProviderIcon(preset: ProviderPreset.match(provider: entry.provider), fallbackSymbol: entry.category.symbol, size: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.title2.weight(.semibold)).textSelection(.enabled).lineLimit(3)
                Text(entry.provider.isEmpty ? entry.category.title : entry.provider).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 12) {
                Button { model.toggleFavorite(entry) } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? Color.accentColor : Color.secondary)
                }.help(entry.isFavorite ? "移出常用" : "加入常用").accessibilityLabel(entry.isFavorite ? "移出常用" : "加入常用")
                Button { hideSecret(); model.edit(entry) } label: { Image(systemName: "pencil") }
                    .help("编辑密钥").accessibilityLabel("编辑密钥")
                Menu {
                    Button("删除密钥…", systemImage: "trash", role: .destructive) { hideSecret(); deleting = true }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help("更多操作").accessibilityLabel("更多操作")
            }.buttonStyle(.borderless)
        }.padding(.horizontal, 23).padding(.top, 24).padding(.bottom, 4)
    }

    @ViewBuilder private var quotaContent: some View {
        LabeledContent("查询服务", value: entry.quotaProvider.title)
        if let quota = entry.quota {
            ForEach(Array(quota.metrics.enumerated()), id: \.offset) { _, metric in
                LabeledContent(metric.label) {
                    Text(metricValue(metric, kind: quota.kind))
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            Text("查询于 \(quota.fetchedAt.formatted(date: .abbreviated, time: .shortened)) · 历史快照")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !quota.note.isEmpty {
                Text(quota.note).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("尚未查询。刷新时只访问所选服务商的官方接口。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if entry.quotaProvider == .openrouter {
            Text("显示此 Key 的限额与用量，不是账户总余额。未设置限额也不代表无限余额。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let message = model.syncErrors[entry.id] {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            if model.syncInProgress.contains(entry.id) { ProgressView().controlSize(.small) }
            Button(model.syncInProgress.contains(entry.id) ? "正在查询…" : "刷新额度") {
                model.activity()
                Task { await model.syncQuota(entry) }
            }
            .disabled(model.syncInProgress.contains(entry.id))
        }
        .padding(.top, 5)
    }

    private var safeWebsite: URL? {
        guard let validated = try? entry.validated(), let url = URL(string: validated.website),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private func metricValue(_ metric: QuotaMetric, kind: String) -> String {
        guard let value = metric.value else { return kind == "key_limit" ? "未设置 Key 上限" : "未提供" }
        return metric.currency.map { "\(value) \($0)" } ?? value
    }

    private func toggleSecret() {
        model.activity()
        guard !model.isLocked else { return }
        if secretVisible { hideSecret(); return }
        secretVisible = true
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(20)) }
            catch { return }
            secretVisible = false
        }
    }

    private func hideSecret() {
        revealTask?.cancel()
        revealTask = nil
        secretVisible = false
    }
}
