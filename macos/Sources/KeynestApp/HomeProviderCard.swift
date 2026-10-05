import SwiftUI
import KeynestCore

struct HomeProviderCard: View {
    @EnvironmentObject private var model: AppModel
    let group: HomeProviderGroup
    @State private var showingAll = false

    var body: some View {
        HomeProviderCardLayout(name: group.name, preset: group.preset, keyCount: group.entries.count,
                               rowCount: min(2, group.entries.count)) { index in
            HomeCredentialRow(entry: group.entries[index])
        } more: {
            Button {
                showingAll = true
            } label: {
                HStack {
                    Text("查看全部 \(group.entries.count) 把")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .font(.callout)
            .accessibilityLabel("查看 \(group.name) 的全部 \(group.entries.count) 把密钥")
            .accessibilityIdentifier("keynest.home.more.\(group.id)")
            .popover(isPresented: $showingAll, arrowEdge: .bottom) {
                allCredentials
            }
        } footer: {
            HStack(spacing: 12) {
                Button {
                    model.addForProvider(group)
                } label: {
                    Label("添加密钥", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("为 \(group.name) 添加密钥")
                .accessibilityIdentifier("keynest.home.add.\(group.id)")

                Spacer(minLength: 0)

                if let preset = group.preset, let website = URL(string: preset.website) {
                    Link(destination: website) {
                        Label("API 官网", systemImage: "arrow.up.right")
                    }
                    .help("打开 \(preset.name) 官方 API 网站")
                    .accessibilityLabel("打开 \(preset.name) 的 API 官网")
                }
            }
            .font(.callout)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keynest.home.provider.\(group.id)")
        .onChange(of: model.isLocked) { _, locked in
            if locked { showingAll = false }
        }
    }

    private var allCredentials: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ProviderIcon(preset: group.preset, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name).font(.headline).lineLimit(2)
                    Text("全部 \(group.entries.count) 把密钥")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { showingAll = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭密钥列表")
                .accessibilityLabel("关闭 \(group.name) 的密钥列表")
                .accessibilityIdentifier("keynest.home.more.close")
            }
            .padding(18)
            Divider()
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(group.entries) { entry in
                        HomeCredentialRow(entry: entry)
                        if entry.id != group.entries.last?.id { Divider() }
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 430, height: min(480, CGFloat(group.entries.count) * 105 + 90))
        .accessibilityElement(children: .contain)
    }
}

struct HomeCredentialRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: SecretEntry

    private var presentation: HomeCredentialPresentation { HomeCredentialPresentation(entry: entry, copied: copied) }
    private var credentialDescription: String { presentation.description }

    private var copied: Bool { model.copyFeedback == .secret(entry.id) }

    var body: some View {
        HomeCredentialRowLayout(presentation: presentation) {
            HomeCredentialCopyButton(copied: copied) { model.copySecret(entry) }
            .help("复制 \(credentialDescription) 的密钥")
            .accessibilityLabel(copied ? "已复制 \(credentialDescription) 的密钥" : "复制 \(credentialDescription) 的密钥")
            .accessibilityIdentifier("keynest.home.copy.\(entry.id.uuidString)")

            Menu {
                Button("复制 API 地址", systemImage: "link") { model.copyAPIAddress(entry) }
                    .disabled(entry.baseURL.isEmpty)
                Button(entry.isFavorite ? "移出常用" : "加入常用", systemImage: entry.isFavorite ? "star.slash" : "star") {
                    model.toggleFavorite(entry)
                }
                Divider()
                Button("查看详情", systemImage: "info.circle") { model.showEntry(entry) }
                Button("编辑", systemImage: "pencil") { model.edit(entry) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("\(credentialDescription) 的更多操作")
            .accessibilityLabel("\(credentialDescription) 的更多操作")
            .accessibilityIdentifier("keynest.home.actions.\(entry.id.uuidString)")
        }
        .accessibilityElement(children: .contain)
    }
}
