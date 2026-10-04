import SwiftUI
import KeynestCore

struct HomeKeychainShowcase: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var resetToken = 0
    @State private var showsCustomization = false
    @State private var selected: KeychainCharmSelection?
    let onCollapse: () -> Void

    private var groups: [HomeProviderGroup] {
        model.isLocked ? [] : HomeCatalog.groups(entries: model.entries, tools: model.tools)
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
                    Text("你的钥匙串").font(.headline)
                    Text(reduceMotion ? "点击挂件取用 API · 已减少动态效果" : "把常用 API 挂在手边，点一下就能取用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { selected = nil; showsCustomization = true } label: {
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

            KeychainSceneView(charms: sceneCharms, selectedID: selected?.id,
                              isActive: !model.isLocked && !showsCustomization && selected == nil,
                              resetToken: resetToken,
                              onSelect: { id in
                                  guard !model.isLocked else { return }
                                  selected = items.first { $0.id == id }?.selection
                              }, onRingTap: { selected = nil; showsCustomization = true })
                .frame(height: 292)
                .padding(.horizontal, 20)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                              .init(color: .black, location: 0.06),
                                              .init(color: .black, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .popover(item: $selected, arrowEdge: .bottom) { selection in
                    KeychainCredentialPanel(selection: selection, onClose: { selected = nil })
                        .environmentObject(model)
                }

            if items.isEmpty {
                Button("选择想挂上的 API 平台") { showsCustomization = true }
                    .buttonStyle(.borderless).padding(.bottom, 19)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            Button { selected = item.selection } label: {
                                HStack(spacing: 6) {
                                    KeychainPlatformAvatar(preset: item.preset, color: item.selection.color, size: 16)
                                    Text(item.name).lineLimit(1)
                                    if item.savedCount > 0 {
                                        Text("\(item.savedCount)").foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }
                                .font(.caption.weight(.medium)).padding(.horizontal, 11).padding(.vertical, 7)
                                .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial), in: Capsule())
                                .overlay(Capsule().strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("查看 \(item.name) 的密钥")
                            .accessibilityLabel("查看 \(item.name)，\(item.savedCount) 把密钥")
                            .accessibilityIdentifier("keynest.home.keychain.platform.\(item.id)")
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 4)
                    .frame(minWidth: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
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
            KeychainCustomizationView().environmentObject(model)
        }
        .onChange(of: model.isLocked) { _, locked in
            if locked { selected = nil; showsCustomization = false }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected.id) { self.selected = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keynest.home.keychain")
    }
}
