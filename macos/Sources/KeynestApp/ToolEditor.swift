import SwiftUI
import KeynestCore

struct ToolEditor: View {
    private let original: ToolGroup
    let onSave: (ToolGroup) throws -> Void
    let onCancel: () -> Void
    @State private var draft: ToolGroup
    @State private var validationMessage: String?
    @FocusState private var nameFocused: Bool

    init(tool: ToolGroup, onSave: @escaping (ToolGroup) throws -> Void, onCancel: @escaping () -> Void) {
        self.original = tool
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: tool)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ToolIcon(templateID: draft.templateID)
                VStack(alignment: .leading, spacing: 4) {
                    Text(original.name.isEmpty ? "添加工具" : "编辑工具")
                        .font(.headline)
                    Text("记录密钥用在哪里")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 25)
            .padding(.top, 22)
            .padding(.bottom, 5)

            Form {
                Section {
                    TextField("名称", text: $draft.name, prompt: Text("例如：Cursor、工作项目或自建服务"))
                        .focused($nameFocused)
                        .accessibilityIdentifier("keynest.tool.name")
                } header: {
                    Text("工具信息")
                } footer: {
                    Text("工具用于整理使用位置，同一把密钥可以关联多个工具。")
                        .font(.caption)
                }
                Section("备注（可选）") {
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .frame(height: 110)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("工具备注")
                        .accessibilityIdentifier("keynest.tool.notes")
                }
            }
            .formStyle(.grouped)

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 25)
                    .padding(.bottom, 12)
            }

            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("keynest.tool.cancel")
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("keynest.tool.save")
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 17)
        }
        .frame(width: 650, height: 430)
        .task { nameFocused = true }
    }

    private func save() {
        var result = draft
        result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try onSave(result)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
