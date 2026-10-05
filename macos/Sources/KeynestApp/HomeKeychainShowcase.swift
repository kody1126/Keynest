import SwiftUI
import KeynestCore

struct HomeKeychainShowcase: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var resetToken = 0
    @State private var showsCustomization = false
    @State private var customizationSelectionID: String?
    @State private var keyboardIndex = 0
    @FocusState private var sceneFocused: Bool
    let onCollapse: () -> Void

    private var groups: [HomeProviderGroup] {
        model.isLocked ? [] : HomeCatalog.ordered(HomeCatalog.groups(entries: model.entries, tools: model.tools), by: model.homeProviderOrder)
    }
    private var items: [KeychainCatalogItem] {
        KeychainCatalog.resolved(configuration: model.keychainConfiguration, groups: groups)
            .filter { !$0.isUnavailable }
    }
    private var sceneCharms: [KeychainSceneCharm] {
        items.map { KeychainSceneCharm(id: $0.id, name: $0.name,
                                      brandID: $0.preset?.id, colorName: $0.selection.color.rawValue) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("钥匙串").font(.headline)
                    Text(reduceMotion ? "点击复制密钥 · 已减少动态效果" : "点击挂件，复制密钥。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { customize() } label: {
                    Label("定制", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("keynest.home.keychain.customize")
                Button { resetToken += 1 } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless).help("复位钥匙串").accessibilityLabel("复位钥匙串")
                .accessibilityIdentifier("keynest.home.keychain.reset")
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up").frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless).help("收起钥匙串").accessibilityLabel("收起钥匙串")
                .accessibilityIdentifier("keynest.home.keychain.collapse")
            }
            .padding(.horizontal, 22).padding(.top, 18)

            ZStack {
                KeychainSceneView(charms: sceneCharms, selectedID: focusedItem?.id,
                                  isActive: !model.isLocked && !showsCustomization,
                                  resetToken: resetToken,
                                  onSelect: activate,
                                  onRingTap: { customize() })
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                  .init(color: .black, location: 0.06),
                                                  .init(color: .black, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            }
            .frame(height: 292)
            .padding(.horizontal, 20).padding(.bottom, 12)
            .focusable(!items.isEmpty).focused($sceneFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .return, .space]) { press in
                guard !model.isLocked, !showsCustomization, !items.isEmpty else { return .ignored }
                if press.key == .leftArrow { keyboardIndex = (keyboardIndex + items.count - 1) % items.count }
                else if press.key == .rightArrow { keyboardIndex = (keyboardIndex + 1) % items.count }
                else { activate(items[min(keyboardIndex, items.count - 1)].id) }
                return .handled
            }
            .help("左右键选择挂件，空格或回车复制；也可直接点击挂件。")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("钥匙串挂件")
            .accessibilityChildren {
                ForEach(items) { item in
                    Button(accessibilityTitle(item)) { activate(item.id) }
                        .accessibilityIdentifier("keynest.home.keychain.platform.\(item.id)")
                }
            }

            if items.isEmpty {
                Button("选择想挂上的 API 平台") { customize() }
                    .buttonStyle(.borderless).padding(.bottom, 19)
            }

        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: .controlBackgroundColor))
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: 22).fill(
                        RadialGradient(colors: [Color.cyan.opacity(colorScheme == .dark ? 0.18 : 0.10),
                                                Color.indigo.opacity(0.035), .clear],
                                       center: .center, startRadius: 15, endRadius: 470))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
        .sheet(isPresented: $showsCustomization) {
            KeychainCustomizationView(initialSelectionID: customizationSelectionID).environmentObject(model)
        }
        .onChange(of: model.isLocked) { _, locked in
            if locked { customizationSelectionID = nil; showsCustomization = false; sceneFocused = false }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            keyboardIndex = min(keyboardIndex, max(0, ids.count - 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keynest.home.keychain")
    }

    private var focusedItem: KeychainCatalogItem? {
        guard sceneFocused, !items.isEmpty else { return nil }
        return items[min(keyboardIndex, items.count - 1)]
    }

    private func customize(_ id: String? = nil) {
        guard !model.isLocked else { return }
        customizationSelectionID = id
        showsCustomization = true
    }

    private func activate(_ id: String) {
        guard !model.isLocked, !model.busy, !showsCustomization,
              let item = items.first(where: { $0.id == id }) else { return }
        if let entry = item.copyEntry {
            model.copySecret(entry)
        } else if item.savedCount == 0, item.selection.credentialID == nil, let preset = item.preset {
            model.quickAdd(preset)
        } else {
            // Ambiguous, deleted or moved bindings are edited explicitly. Never
            // choose the first key or silently switch a previously saved binding.
            customize(id)
        }
    }

    private func accessibilityTitle(_ item: KeychainCatalogItem) -> String {
        if let entry = item.copyEntry { return "复制 \(item.name)：\(entry.name)" }
        if item.savedCount == 0, item.selection.credentialID == nil { return "为 \(item.name) 添加密钥" }
        return "选择 \(item.name) 点击时复制的密钥"
    }

}
