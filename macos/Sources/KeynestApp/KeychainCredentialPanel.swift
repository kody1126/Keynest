import SwiftUI
import KeynestCore

/// Credentials are resolved from the current unlocked model when this panel is
/// shown. Selecting a charm alone never copies or chooses the first key.
struct KeychainCredentialPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let selection: KeychainCharmSelection
    let onClose: () -> Void

    private var item: KeychainCatalogItem {
        KeychainCatalog.resolve(selection: selection, groups: model.isLocked ? [] : HomeCatalog.groups(entries: model.entries, tools: model.tools))
    }

    var body: some View {
        let current = item
        VStack(alignment: .leading, spacing: 0) {
            if !model.isLocked {
                header(current)
                Divider()
                if let group = current.group, !group.entries.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 15) {
                            ForEach(group.entries) { entry in
                                HomeCredentialRow(entry: entry)
                                if entry.id != group.entries.last?.id { Divider() }
                            }
                        }
                        .padding(20)
                    }
                    .frame(height: min(390, max(105, CGFloat(group.entries.count) * 98)))
                } else {
                    ContentUnavailableView {
                        Label(current.isUnavailable ? "这个平台已不存在" : "还没有保存密钥", systemImage: current.isUnavailable ? "key.slash" : "key")
                    } description: {
                        Text(current.isUnavailable ? "可在定制钥匙串中移除，或重新选择平台。" : "为这个平台添加 API 密钥，之后点击挂件就能取用。")
                    }
                    .frame(height: 200)
                }
                Divider()
                footer(current)
            }
        }
        .frame(width: 450)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keynest.keychain.credentials")
        .onChange(of: model.isLocked, initial: true) { _, locked in if locked { close() } }
        .onChange(of: model.presentingEditor) { _, presenting in if presenting { close() } }
        .onChange(of: model.quickAddPreset?.id) { _, id in if id != nil { close() } }
        .onChange(of: model.filter) { _, filter in if filter != .home { close() } }
    }

    private func header(_ item: KeychainCatalogItem) -> some View {
        HStack(spacing: 11) {
            KeychainPlatformAvatar(preset: item.preset, color: selection.color, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.headline).lineLimit(2)
                Text(item.savedCount > 0 ? "\(item.savedCount) 把密钥 · 选择需要的一把复制" : "API 平台")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                .buttonStyle(.plain).help("关闭平台密钥").accessibilityLabel("关闭平台密钥")
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private func footer(_ item: KeychainCatalogItem) -> some View {
        HStack {
            if item.preset != nil || item.group != nil {
                Button { addCredential(item) } label: { Label("添加 API 密钥", systemImage: "plus") }
                    .disabled(model.busy || model.isLocked)
                    .accessibilityIdentifier("keynest.keychain.addCredential")
            }
            Spacer()
            if let preset = item.preset, let url = URL(string: preset.website) {
                Link(destination: url) { Label("API 官网", systemImage: "arrow.up.right") }
                    .accessibilityLabel("打开 \(preset.name) 的官方 API 网站")
            }
        }
        .font(.callout).padding(18)
    }

    private func addCredential(_ item: KeychainCatalogItem) {
        guard !model.isLocked, !model.busy else { return }
        close()
        if let preset = item.preset { model.quickAdd(preset) }
        else if let group = item.group { model.addForProvider(group) }
    }

    private func close() { onClose(); dismiss() }
}
