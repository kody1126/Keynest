import SwiftUI
import AppKit
import KeynestCore

struct ProviderIcon: View {
    let preset: ProviderPreset?
    var fallbackSymbol = "key.horizontal"
    var size: CGFloat = 36

    private static let images: [String: NSImage] = {
        guard let resources = Bundle.main.resourceURL else { return [:] }
        return Dictionary(uniqueKeysWithValues: ProviderPreset.all.filter(\.hasBundledIcon).compactMap { preset in
            let url = resources.appendingPathComponent("ProviderIcons").appendingPathComponent(preset.iconFilename)
            guard let image = NSImage(contentsOf: url) else { return nil }
            return (preset.id, image)
        })
    }()

    var body: some View {
        Group {
            if let preset, let image = Self.images[preset.id] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.18)
                    .background(.white)
            } else {
                Image(systemName: preset?.fallbackSymbol ?? fallbackSymbol)
                    .font(.system(size: size * 0.48, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: size, height: size)
                    .background(.quinary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

struct ProviderPicker: View {
    let selected: ProviderPreset?
    let onChoose: (ProviderPreset) -> Void
    let onCustom: () -> Void
    let onCancel: () -> Void
    @State private var search = ""
    @State private var group: ProviderPresetGroup?
    @FocusState private var searchFocused: Bool

    private var matching: [ProviderPreset] {
        ProviderPreset.all.filter { (group == nil || $0.group == group) && $0.matches(search: search) }
    }
    private var visibleGroups: [ProviderPresetGroup] {
        ProviderPresetGroup.allCases.filter { candidate in matching.contains { $0.group == candidate } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("选择 API 平台").font(.title2.weight(.semibold))
                    Spacer()
                    Text("\(ProviderPreset.all.count) 个预设").font(.callout).foregroundStyle(.secondary)
                }
                Text("从常用服务开始，也可以保存自己的服务商与 Skill。")
                    .foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索平台、模型或用途", text: $search)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityIdentifier("keynest.preset.search")
                    if !search.isEmpty {
                        Button { search = ""; searchFocused = true } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).accessibilityLabel("清除平台搜索")
                    }
                }
                .padding(9)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(searchFocused ? Color.accentColor : .clear, lineWidth: 2))
                .padding(.top, 4)
                Picker("平台用途", selection: $group) {
                    Text("全部").tag(Optional<ProviderPresetGroup>.none)
                    ForEach(ProviderPresetGroup.allCases) { item in
                        Text(item.title).tag(Optional(item))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("keynest.preset.group")
            }
            .padding(24)
            .padding(.bottom, -8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(visibleGroups) { section in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 6) {
                                Label(section.title, systemImage: section.symbol)
                                Text("\(matching.filter { $0.group == section }.count)")
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                                ForEach(matching.filter { $0.group == section }) { preset in
                                    presetButton(preset)
                                }
                            }
                        }
                    }
                    if matching.isEmpty {
                        ContentUnavailableView {
                            Label("没有匹配的平台", systemImage: "magnifyingglass")
                        } description: {
                            Text("试试其他名称或用途，或添加自定义服务。")
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            Divider()
            HStack {
                Button(action: onCustom) { Label("自定义服务商 / Skill", systemImage: "square.and.pencil") }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
            }
            .padding(24)
        }
        .frame(width: 720, height: 620)
        .onAppear { searchFocused = true }
    }

    private func presetButton(_ preset: ProviderPreset) -> some View {
        Button { onChoose(preset) } label: {
            HStack(spacing: 9) {
                ProviderIcon(preset: preset, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(preset.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if selected?.id == preset.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(selected?.id == preset.id ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected?.id == preset.id ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("\(preset.name)：\(preset.summary)\n\(preset.usageHint)")
        .accessibilityLabel("\(preset.name)，\(preset.summary)")
        .accessibilityIdentifier("keynest.preset.\(preset.id)")
    }
}
