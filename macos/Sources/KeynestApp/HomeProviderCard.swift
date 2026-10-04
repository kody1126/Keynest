import SwiftUI
import KeynestCore

struct HomeProviderCard: View {
    @EnvironmentObject private var model: AppModel
    let group: HomeProviderGroup
    @State private var showingAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProviderIcon(preset: group.preset, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                        .help(group.name)
                    Text("\(group.entries.count) 把密钥")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 12) {
                ForEach(Array(group.entries.prefix(2))) { entry in
                    HomeCredentialRow(entry: entry)
                    if entry.id != group.entries.prefix(2).last?.id {
                        Divider()
                    }
                }
            }

            if group.entries.count > 2 {
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
            }

            Divider()
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
        .padding(16)
        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
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

    private var accountAndEnvironment: String {
        [entry.accountLabel, entry.environment].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var addressHost: String? {
        guard let components = URLComponents(string: entry.baseURL), let host = components.host else { return nil }
        if let port = components.port { return "\(host):\(port)" }
        return host
    }

    private var credentialDescription: String {
        [entry.name, accountAndEnvironment, addressHost ?? ""].filter { !$0.isEmpty }.joined(separator: "，")
    }

    private var copied: Bool { model.copyFeedback == .secret(entry.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(entry.name).font(.callout.weight(.medium)).lineLimit(1)
                    if entry.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                if !accountAndEnvironment.isEmpty {
                    Text(accountAndEnvironment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let addressHost {
                    Text(addressHost)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(credentialDescription)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(credentialDescription + (entry.isFavorite ? "，常用" : ""))

            Button { model.copySecret(entry) } label: {
                Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .fixedSize()
                    .frame(width: 61)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 30)
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
