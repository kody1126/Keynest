import SwiftUI
import KeynestCore

/// Only the fields already shown on Home. No secret, notes, full URL, or model
/// reference can enter the drag renderer through this presentation value.
struct HomeCredentialPresentation {
    let name: String
    let accountAndEnvironment: String
    let addressHost: String?
    let isFavorite: Bool
    let copied: Bool

    init(entry: SecretEntry, copied: Bool = false) {
        name = entry.name
        accountAndEnvironment = [entry.accountLabel, entry.environment].filter { !$0.isEmpty }.joined(separator: " · ")
        if let components = URLComponents(string: entry.baseURL), let host = components.host {
            addressHost = components.port.map { "\(host):\($0)" } ?? host
        } else { addressHost = nil }
        isFavorite = entry.isFavorite
        self.copied = copied
    }

    var description: String {
        [name, accountAndEnvironment, addressHost ?? ""].filter { !$0.isEmpty }.joined(separator: "，")
    }
}

struct HomeCardPresentation {
    let name: String
    let preset: ProviderPreset?
    let keyCount: Int
    let rows: [HomeCredentialPresentation]

    init(group: HomeProviderGroup, copiedEntryID: UUID?) {
        name = group.name; preset = group.preset; keyCount = group.entries.count
        rows = group.entries.prefix(2).map { HomeCredentialPresentation(entry: $0, copied: $0.id == copiedEntryID) }
    }
}

/// Live cards and the metadata-only drag image use identical spacing, fonts,
/// dividers, and surfaces. Interactions are supplied only by the live card.
struct HomeProviderCardLayout<Row: View, More: View, Footer: View>: View {
    let name: String
    let preset: ProviderPreset?
    let keyCount: Int
    let rowCount: Int
    @ViewBuilder let row: (Int) -> Row
    @ViewBuilder let more: () -> More
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProviderIcon(preset: preset, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline).lineLimit(1).help(name)
                    Text("\(keyCount) 把密钥").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 12) {
                ForEach(0..<rowCount, id: \.self) { index in
                    row(index)
                    if index < rowCount - 1 { Divider() }
                }
            }
            if keyCount > 2 { more() }
            Divider()
            footer().font(.callout)
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
        }
    }
}

struct HomeCredentialRowLayout<Actions: View>: View {
    let presentation: HomeCredentialPresentation
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(presentation.name).font(.callout.weight(.medium)).lineLimit(1)
                    if presentation.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
                if !presentation.accountAndEnvironment.isEmpty {
                    Text(presentation.accountAndEnvironment).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let addressHost = presentation.addressHost {
                    Text(addressHost).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(presentation.description)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.description + (presentation.isFavorite ? "，常用" : ""))
            actions()
        }
        .accessibilityElement(children: .contain)
    }
}

struct HomeCredentialCopyButton: View {
    let copied: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                .fixedSize().frame(width: 61)
        }
        .buttonStyle(.borderedProminent).controlSize(.small).frame(minHeight: 30)
    }
}

struct HomeCardDragPresentation: View {
    let presentation: HomeCardPresentation
    var body: some View {
        HomeProviderCardLayout(name: presentation.name, preset: presentation.preset,
                               keyCount: presentation.keyCount, rowCount: presentation.rows.count) { index in
            let row = presentation.rows[index]
            HomeCredentialRowLayout(presentation: row) {
                HomeCredentialCopyButton(copied: row.copied, action: {})
                // ImageRenderer cannot render AppKit-backed menu or link
                // controls. The drag image uses inert display primitives only.
                Image(systemName: "ellipsis").frame(width: 20, height: 30).fixedSize()
                    .foregroundStyle(Color.accentColor.opacity(0.4))
            }
        } more: {
            HStack {
                Text("查看全部 \(presentation.keyCount) 把")
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor.opacity(0.4)).font(.callout)
        } footer: {
            HStack(spacing: 12) {
                Label("添加密钥", systemImage: "plus")
                Spacer(minLength: 0)
                if let preset = presentation.preset, URL(string: preset.website) != nil {
                    Label("API 官网", systemImage: "arrow.up.right")
                }
            }
            .foregroundStyle(Color.accentColor.opacity(0.4))
        }
        .disabled(true).allowsHitTesting(false).accessibilityHidden(true)
    }
}
