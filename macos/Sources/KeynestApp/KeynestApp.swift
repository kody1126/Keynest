import SwiftUI
import AppKit

@main struct KeynestApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window(model.isDemo ? "Keynest Demo" : "Keynest", id: "main") {
            MainView().environmentObject(model)
                .frame(minWidth: 1020, minHeight: 680)
                .tint(Color.accentColor)
                .sheet(isPresented: $model.presentingRestore) { RestoreSheet().environmentObject(model) }
                .sheet(isPresented: $model.presentingPasswordChange) { PasswordChangeSheet().environmentObject(model) }
                .alert("未能完成操作", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("好", role: .cancel) { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加密钥…") { model.addNew() }.keyboardShortcut("n").disabled(model.isLocked)
                Button("添加工具…") { model.addTool() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(model.isLocked)
                Divider()
                Button("导入加密备份…") { model.importBackup() }.disabled(model.isDemo || (model.isInitialized && model.isLocked))
                Button("导出加密备份…") { model.exportBackup() }.disabled(model.isDemo || model.isLocked)
            }
            CommandGroup(after: .sidebar) {
                Button("显示首页") { model.selectFilter(.home) }.keyboardShortcut("1").disabled(model.isLocked)
                Button("管理全部密钥") { model.selectFilter(.all) }.keyboardShortcut("2").disabled(model.isLocked)
            }
            CommandGroup(after: .textEditing) {
                Button("搜索密钥") { model.searchHome() }.keyboardShortcut("f").disabled(model.isLocked)
            }
            CommandMenu("密钥") {
                Button("复制密钥") { if let entry = model.selectedEntry { model.copySecret(entry) } }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(model.selectedEntry == nil || model.isLocked)
                Button("复制 API 地址") { if let entry = model.selectedEntry { model.copyAPIAddress(entry) } }.disabled(model.isLocked || model.selectedEntry?.baseURL.isEmpty != false)
                Button("编辑密钥…") { if let entry = model.selectedEntry { model.edit(entry) } }.keyboardShortcut("e").disabled(model.selectedEntry == nil || model.isLocked)
                Divider()
                Button("锁定密钥库") { model.lock() }.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(model.isLocked)
                Button("更改主密码…") { model.changePassword() }.disabled(model.isDemo || model.isLocked)
            }
        }
        Settings { SettingsView().environmentObject(model) }
    }
}

private struct RestoreSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("导入加密备份", systemImage: "square.and.arrow.down").font(.title2.weight(.semibold))
            Text(model.isInitialized ? "输入备份的主密码。条目会合并到当前密钥库，现有记录不会被覆盖。" : "输入备份的主密码。恢复后，继续使用这个密码解锁密钥库。")
                .foregroundStyle(.secondary)
            SecureField("备份的主密码", text: $password).textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("取消") { password = ""; model.cancelRestore() }.keyboardShortcut(.cancelAction)
                Button(model.busy ? "正在导入…" : "导入") { let value = password; password = ""; Task { await model.restore(password: value) } }.keyboardShortcut(.defaultAction).disabled(password.isEmpty || model.busy)
            }
        }.padding(28).frame(width: 420).onDisappear { password = ""; model.cancelRestore() }
    }
}

private struct PasswordChangeSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("更改主密码", systemImage: "key.horizontal").font(.title2.weight(.semibold))
            Text("新密码至少 12 个字符。已有备份仍需要各自导出时的密码。").foregroundStyle(.secondary)
            SecureField("当前主密码", text: $oldPassword).textFieldStyle(.roundedBorder)
            SecureField("新主密码", text: $newPassword).textFieldStyle(.roundedBorder)
            SecureField("再次输入新主密码", text: $confirmation).textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("取消") { model.presentingPasswordChange = false }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(model.busy ? "正在更新…" : "更新密码") {
                    let old = oldPassword, new = newPassword
                    oldPassword = ""; newPassword = ""; confirmation = ""
                    Task { await model.replacePassword(old: old, new: new) }
                }.keyboardShortcut(.defaultAction).disabled(oldPassword.isEmpty || newPassword.count < 12 || newPassword != confirmation || model.busy)
            }
        }.padding(28).frame(width: 430)
            .interactiveDismissDisabled(model.busy)
            .onDisappear { oldPassword = ""; newPassword = ""; confirmation = "" }
    }
}

private struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("隐私与安全") {
                Toggle("使用 Touch ID 解锁", isOn: Binding(
                    get: { model.biometricEnabled },
                    set: { enabled in Task {
                        if enabled { await model.enableBiometrics() }
                        else { await model.disableBiometrics() }
                    } }
                ))
                .disabled(model.isLocked || model.busy || !model.biometricAvailable)
                .accessibilityIdentifier("keynest.touchid.setting")
                Text(model.isLocked ? "先解锁密钥库，即可管理指纹解锁。" : model.biometricUnavailableReason ?? "启用后，打开 App 时使用系统 Touch ID；主密码始终可用。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = model.biometricMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("存储方式", value: "本机加密文件 · 无云端账户")
                LabeledContent("自动锁定", value: "闲置 10 分钟或系统休眠")
                LabeledContent("剪贴板", value: "30 秒后清除本次复制内容")
                LabeledContent("密钥显示", value: "20 秒后自动隐藏")
            }
            Section("密钥库") {
                Text(model.dataPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("导出加密备份…") { model.exportBackup() }.disabled(model.isDemo || model.isLocked)
                    Button("更改主密码…") { model.changePassword() }.disabled(model.isDemo || model.isLocked)
                }
            }
            Section {
                Text("Keynest 0.10.0 · 本地实验版\n仅在你点击额度查询时访问对应平台的官方接口。尚未经过独立安全审计。").font(.footnote).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(12).frame(width: 520, height: 510)
            .task { await model.refreshBiometricStatus() }
    }
}
