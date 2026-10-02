import SwiftUI
import KeynestCore

struct QuickAddSheet: View {
    let preset: ProviderPreset
    let onSave: (SecretEntry) throws -> Void
    let onAdvanced: (SecretEntry) -> Void
    let onCancel: () -> Void
    private let existingCount: Int

    @State private var draft: SecretEntry
    @State private var detailsExpanded = false
    @State private var validationMessage: String?
    @FocusState private var secretFocused: Bool

    init(preset: ProviderPreset,
         existingEntries: [SecretEntry],
         onSave: @escaping (SecretEntry) throws -> Void,
         onAdvanced: @escaping (SecretEntry) -> Void,
         onCancel: @escaping () -> Void) {
        self.preset = preset
        self.onSave = onSave
        self.onAdvanced = onAdvanced
        self.onCancel = onCancel
        let existing = existingEntries.filter { ProviderPreset.match(provider: $0.provider)?.id == preset.id }
        existingCount = existing.count
        var initialDraft = preset.applying(to: SecretEntry())
        if !existing.isEmpty {
            let names = Set(existing.map(\.name))
            var number = existing.count + 1
            while names.contains("\(preset.name) · \(number)") { number += 1 }
            initialDraft.name = "\(preset.name) · \(number)"
        }
        _draft = State(initialValue: initialDraft)
        _detailsExpanded = State(initialValue: !existing.isEmpty)
    }

    private var hasSecret: Bool {
        !draft.secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("API Key / 密钥")
                            .font(.headline)
                        SecureField("API Key / 密钥", text: $draft.secret, prompt: Text("粘贴密钥"))
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .autocorrectionDisabled()
                            .privacySensitive()
                            .focused($secretFocused)
                            .accessibilityIdentifier("keynest.quickadd.secret")

                        if !preset.usageHint.isEmpty {
                            Text(preset.usageHint)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    DisclosureGroup("账号、环境与地址（可选）", isExpanded: $detailsExpanded) {
                        VStack(alignment: .leading, spacing: 14) {
                            if existingCount > 0 {
                                Text("这个平台已有 \(existingCount) 把密钥。建议填写账号或用途，复制时更容易区分。")
                                    .font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            detailField("显示名称", text: $draft.name, prompt: "例如：\(preset.name) · 个人")
                            detailField("账号标签", text: $draft.accountLabel, prompt: "例如：个人账号或项目 ID")
                                .privacySensitive()
                            detailField("使用环境", text: $draft.environment, prompt: "例如：开发、正式或个人")
                            detailField("API 地址", text: $draft.baseURL, prompt: "https://api.example.com")
                        }
                        .padding(.top, 12)
                    }
                    .accessibilityIdentifier("keynest.quickadd.details")
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                    .accessibilityIdentifier("keynest.quickadd.validation")
            }

            Divider()
            HStack(spacing: 10) {
                Button("完整编辑…") { onAdvanced(draft) }
                    .accessibilityIdentifier("keynest.quickadd.advanced")
                Spacer()
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("keynest.quickadd.cancel")
                Button("保存到首页", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasSecret)
                    .accessibilityIdentifier("keynest.quickadd.save")
            }
            .padding(20)
        }
        .frame(width: 520, height: detailsExpanded ? 620 : 500)
        .background(.background)
        .task { secretFocused = true }
        .onDisappear { draft.secret = "" }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ProviderIcon(preset: preset, size: 44)
            VStack(alignment: .leading, spacing: 7) {
                Text(preset.name)
                    .font(.title2.weight(.semibold))
                Text("粘贴一次，下次从首页直接复制。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let website = URL(string: preset.website) {
                    Link(destination: website) {
                        Label("API 官网", systemImage: "arrow.up.right")
                    }
                    .font(.callout)
                    .help("打开 \(preset.name) 官方 API 网站")
                    .accessibilityIdentifier("keynest.quickadd.website")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }

    private func detailField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private func save() {
        guard hasSecret else { return }
        do {
            let result = try draft.validated()
            try onSave(result)
            draft.secret = ""
            validationMessage = nil
        } catch let error as VaultError {
            validationMessage = error.localizedDescription
        } catch let error as AppError {
            validationMessage = error.localizedDescription
        } catch {
            validationMessage = "暂时无法保存，请重试。"
        }
    }

    private func cancel() {
        draft.secret = ""
        onCancel()
    }
}
