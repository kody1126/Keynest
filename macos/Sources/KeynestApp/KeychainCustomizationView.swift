import SwiftUI
import AppKit
import KeynestCore

struct KeychainCustomizationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = KeychainConfiguration()
    @State private var usesAutomaticSelection = false
    @State private var loaded = false
    @State private var search = ""
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    private var groups: [HomeProviderGroup] {
        model.isLocked ? [] : HomeCatalog.groups(entries: model.entries, tools: model.tools)
    }
    private var selectedIDs: Set<String> { Set(draft.charms.map(\.id)) }

    var body: some View {
        let currentGroups = groups
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                catalog(groups: currentGroups).frame(width: 386)
                Divider()
                selected(groups: currentGroups).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
        }
        .frame(width: 830, height: 646)
        .background(.regularMaterial)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            guard !model.isLocked else { dismiss(); return }
            draft = KeychainCatalog.effectiveConfiguration(model.keychainConfiguration, groups: groups)
            usesAutomaticSelection = model.keychainConfiguration == nil
            searchFocused = true
        }
        .opacity(model.isLocked ? 0 : 1)
        .accessibilityHidden(model.isLocked)
        .onChange(of: model.isLocked) { _, locked in
            if locked { draft = KeychainConfiguration(); search = ""; dismiss() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keynest.keychain.customization")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("定制你的钥匙串").font(.title2.weight(.semibold))
            Text("选择想挂上的 API 平台，点击挂件后取用对应密钥。最多 8 个挂件，也可以留空。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(22)
    }

    private func catalog(groups: [HomeProviderGroup]) -> some View {
        let matching = KeychainCatalog.candidates(groups: groups).filter { $0.matches(search: search) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索平台或自定义服务", text: $search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityIdentifier("keynest.keychain.search")
                if !search.isEmpty {
                    Button { search = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("清除平台搜索")
                }
            }
            .padding(9)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(searchFocused ? Color.accentColor : .primary.opacity(0.12), lineWidth: searchFocused ? 2 : 0.5))
            .padding(.horizontal, 18).padding(.top, 18)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    candidateSection("已保存的平台", items: matching.filter { $0.savedCount > 0 })
                    candidateSection("其他 API 平台", items: matching.filter { $0.savedCount == 0 })
                    if matching.isEmpty {
                        ContentUnavailableView.search(text: search).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder private func candidateSection(_ title: String, items: [KeychainCatalogItem]) -> some View {
        if !items.isEmpty {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
            ForEach(items) { item in candidateRow(item) }
        }
    }

    private func candidateRow(_ item: KeychainCatalogItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        let atLimit = draft.charms.count >= KeychainCatalog.maximumCharms
        return Button {
            guard !isSelected, !atLimit else { return }
            usesAutomaticSelection = false
            draft.charms.append(item.selection)
            errorMessage = nil
        } label: {
            HStack(spacing: 10) {
                KeychainPlatformAvatar(preset: item.preset, color: item.selection.color, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    Text(item.savedCount > 0 ? "已保存 \(item.savedCount) 把密钥" : "尚未保存密钥")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(isSelected || atLimit || model.isLocked)
        .help(isSelected ? "已选中，可在右侧调整" : atLimit ? "最多 8 个挂件，请先移除一项" : "将 \(item.name) 加到钥匙串")
        .accessibilityLabel("\(item.name)，\(item.savedCount) 把已保存密钥，\(isSelected ? "已选中" : "添加到钥匙串")")
        .accessibilityIdentifier("keynest.keychain.choose.\(item.id)")
    }

    private func selected(groups: [HomeProviderGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已选顺序").font(.headline)
                Spacer()
                Text("\(draft.charms.count) / \(KeychainCatalog.maximumCharms)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 18).padding(.top, 21)
            if usesAutomaticSelection {
                Label("自动选择已有平台；空库展示三个常见平台", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18)
            }
            ScrollView {
                VStack(spacing: 10) {
                    if draft.charms.isEmpty {
                        ContentUnavailableView {
                            Label("只保留钥匙环", systemImage: "circle")
                        } description: {
                            Text("从左侧加入平台，或保存空钥匙串。")
                        }
                    }
                    ForEach(Array(draft.charms.enumerated()), id: \.element.id) { index, charm in
                        selectedRow(charm, index: index, groups: groups)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }

    private func selectedRow(_ charm: KeychainCharmSelection, index: Int, groups: [HomeProviderGroup]) -> some View {
        let item = KeychainCatalog.resolve(selection: charm, groups: groups)
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                KeychainPlatformAvatar(preset: item.preset, color: charm.color, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.callout.weight(.medium)).lineLimit(2)
                    if item.isUnavailable {
                        Label("平台已不存在，展示中会略过", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(item.savedCount > 0 ? "\(item.savedCount) 把密钥" : "点击挂件后可添加 API")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                rowButton("上移 \(item.name)", symbol: "chevron.up", disabled: index == 0) { move(index, by: -1) }
                rowButton("下移 \(item.name)", symbol: "chevron.down", disabled: index == draft.charms.count - 1) { move(index, by: 1) }
                rowButton("移除 \(item.name)", symbol: "minus.circle", disabled: false) {
                    usesAutomaticSelection = false; draft.charms.removeAll { $0.id == charm.id }
                }
            }
            if KeychainPlatformAvatar.hasBrandIcon(for: item.preset) {
                Text("立体品牌图标 · 保留品牌配色")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text("挂件颜色").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    ForEach(KeychainCharmColor.allCases) { color in
                        Button { setColor(color, for: charm.id) } label: {
                            ZStack {
                                Circle().fill(color.keychainColor)
                                Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5)
                                if charm.color == color {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(color == .graphite ? Color.white : Color.black.opacity(0.75))
                                }
                            }
                            .frame(width: 23, height: 23).padding(2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(color.title)
                        .accessibilityLabel("\(item.name)的挂件颜色：\(color.title)")
                        .accessibilityValue(charm.color == color ? "已选中" : "未选中")
                        .accessibilityIdentifier("keynest.keychain.color.\(charm.id).\(color.rawValue)")
                    }
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    private func rowButton(_ label: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 22, height: 26) }
            .buttonStyle(.borderless).disabled(disabled).help(label).accessibilityLabel(label)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("恢复自动选择") {
                    draft = KeychainCatalog.automaticConfiguration(groups: groups)
                    usesAutomaticSelection = true; errorMessage = nil
                }
                .help("按已有平台自动选择最多三个挂件；此时仍需保存才生效")
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(model.isLocked || model.busy || !loaded)
                    .accessibilityIdentifier("keynest.keychain.save")
            }
        }
        .padding(18)
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard draft.charms.indices.contains(index), draft.charms.indices.contains(target) else { return }
        usesAutomaticSelection = false
        draft.charms.swapAt(index, target)
    }

    private func setColor(_ color: KeychainCharmColor, for id: String) {
        guard let index = draft.charms.firstIndex(where: { $0.id == id }) else { return }
        usesAutomaticSelection = false; draft.charms[index].color = color
    }

    private func save() {
        do {
            try model.saveKeychainConfiguration(usesAutomaticSelection ? nil : draft)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

extension KeychainCharmColor {
    var keychainColor: Color {
        switch self {
        case .ice: return Color(red: 0.53, green: 0.78, blue: 0.91)
        case .lavender: return Color(red: 0.72, green: 0.65, blue: 0.88)
        case .mint: return Color(red: 0.49, green: 0.78, blue: 0.68)
        case .amber: return Color(red: 0.93, green: 0.71, blue: 0.37)
        case .rose: return Color(red: 0.88, green: 0.56, blue: 0.64)
        case .graphite: return Color(red: 0.34, green: 0.39, blue: 0.46)
        }
    }
}

/// A missing brand image always becomes an explicitly colored key, never a
/// made-up logo or an unrelated category symbol.
struct KeychainPlatformAvatar: View {
    let preset: ProviderPreset?
    let color: KeychainCharmColor
    var size: CGFloat = 36

    private static let images: [String: NSImage] = {
        guard let root = Bundle.main.resourceURL else { return [:] }
        return Dictionary(uniqueKeysWithValues: ProviderPreset.all.compactMap { preset in
            guard preset.hasBundledIcon,
                  let image = NSImage(contentsOf: root.appendingPathComponent("ProviderIcons").appendingPathComponent(preset.iconFilename)) else { return nil }
            return (preset.id, image)
        })
    }()

    static func hasBrandIcon(for preset: ProviderPreset?) -> Bool {
        preset.flatMap { images[$0.id] } != nil
    }

    var body: some View {
        Group {
            if let preset, let image = Self.images[preset.id] {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .padding(size * 0.18).background(.white)
            } else {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: size * 0.53, weight: .medium))
                    .foregroundStyle(color.keychainColor)
                    .rotationEffect(.degrees(-35))
                    .frame(width: size, height: size)
                    .background(color.keychainColor.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
