import SwiftUI
import AppKit
import KeynestCore
import UniformTypeIdentifiers
import Darwin

enum LibraryFilter: Hashable { case home, all, favorites, ungrouped, tool(UUID), category(EntryCategory) }

enum CopyFeedback: Equatable { case secret(UUID), address(UUID) }

@MainActor final class AppModel: ObservableObject {
    let isDemo = Bundle.main.bundleIdentifier == "local.keynest.demo"
    @Published var entries: [SecretEntry] = []
    @Published var tools: [ToolGroup] = []
    @Published private(set) var keychainConfiguration: KeychainConfiguration?
    @Published private(set) var homeProviderOrder: [String]?
    @Published var environmentFilter: String?
    @Published var presentingToolEditor = false
    @Published var presentingToolSetup = false
    @Published var editingTool: ToolGroup?
    @Published var presentingToolLinks = false
    @Published var linkingTool: ToolGroup?
    @Published var isLocked = true
    @Published var isInitialized = false
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var toast: String?
    @Published var selectedID: UUID?
    @Published var searchText = ""
    @Published var filter: LibraryFilter = .home
    @Published var presentingHomeProviderPicker = false
    @Published var quickAddPreset: ProviderPreset?
    @Published var homeSearchFocusRequest = 0
    @Published var homeScope: HomeScope = .all
    @Published private(set) var copyFeedback: CopyFeedback?
    private var copyFeedbackGeneration = UUID()
    @Published var presentingEditor = false
    @Published var editingEntry: SecretEntry?
    @Published var syncInProgress: Set<UUID> = []
    @Published var syncErrors: [UUID: String] = [:]
    @Published var presentingRestore = false
    @Published var presentingPasswordChange = false
    @Published private(set) var biometricStatus: BiometricStatus = .unavailable("正在检查 Touch ID…")
    @Published var biometricMessage: String?

    private var biometricAccess: (any BiometricVaultAccessing)?
    private var automaticBiometricAttemptPending = true
    private var needsUpgradeBackup = false
    private var storage: VaultStorage?
    private var session: VaultSession?
    private var pendingImport: Data?
    private var importGeneration = UUID()
    private var epoch = UUID()
    private let monotonicNow: () -> TimeInterval
    private var lastActivity: TimeInterval
    private var timer: Timer?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private let clipboard: SensitiveClipboard
    private var lockFD: Int32 = -1
    private var messageID = UUID()
    private var quotaTasks: [UUID: Task<QuotaSnapshot, Error>] = [:]

    var dataPath: String { storage?.fileURL.path ?? "数据目录不可用" }
    var biometricEnabled: Bool { biometricStatus == .enrolled }
    var biometricAvailable: Bool {
        switch biometricStatus { case .enrolled, .notEnrolled: return true; case .unavailable: return false }
    }
    var biometricUnavailableReason: String? {
        if case .unavailable(let reason) = biometricStatus { return reason }
        return nil
    }
    var selectedEntry: SecretEntry? { entries.first { $0.id == selectedID } }
    var sortedTools: [ToolGroup] { tools.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var selectedTool: ToolGroup? {
        if case .tool(let id) = filter { return tools.first { $0.id == id } }
        return nil
    }
    func tools(for entry: SecretEntry) -> [ToolGroup] { sortedTools.filter { entry.toolIDs.contains($0.id) } }
    private func includes(_ entry: SecretEntry) -> Bool {
        switch filter {
        case .home, .all: return true
        case .favorites: return entry.isFavorite
        case .ungrouped: return entry.toolIDs.isEmpty
        case .tool(let id): return entry.toolIDs.contains(id)
        case .category(let category): return entry.category == category
        }
    }
    var environmentOptions: [String] { Array(Set(entries.filter(includes).map(\.environment))).sorted() }
    var filteredEntries: [SecretEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let haystack = [entry.name, entry.provider, entry.notes, entry.website, entry.baseURL,
                            entry.environment, entry.accountLabel] + entry.tags + tools(for: entry).map(\.name)
            return includes(entry) && (environmentFilter == nil || entry.environment == environmentFilter) &&
                (query.isEmpty || haystack.contains { $0.localizedStandardContains(query) })
        }.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
    func selectFilter(_ value: LibraryFilter) {
        filter = value; environmentFilter = nil; searchText = ""; activity()
        selectedID = value == .home ? nil : filteredEntries.first?.id
        if value == .home { homeScope = .all }
    }

    func searchHome() {
        guard !isLocked, !busy else { return }
        if filter != .home { selectFilter(.home) }
        homeScope = .all; homeSearchFocusRequest += 1
    }

    func showEntry(_ entry: SecretEntry) {
        guard !isLocked, !busy, entries.contains(where: { $0.id == entry.id }) else { return }
        selectFilter(.all); selectedID = entry.id
    }

    func quickAdd(_ preset: ProviderPreset) {
        guard !isLocked, !busy else { return }
        presentingHomeProviderPicker = false
        quickAddPreset = preset
    }

    func openAdvancedEntry(_ draft: SecretEntry) {
        guard !isLocked, !busy else { return }
        quickAddPreset = nil; presentingHomeProviderPicker = false
        editingEntry = draft; presentingEditor = true
    }

    func addCustomCredential() {
        openAdvancedEntry(SecretEntry(name: "自定义 API", category: .other))
    }

    func addForProvider(_ group: HomeProviderGroup) {
        if let preset = group.preset { quickAdd(preset) }
        else { openAdvancedEntry(SecretEntry(name: group.name, category: group.entries.first?.category ?? .other, provider: group.name)) }
    }

    init(biometricAccess injectedBiometricAccess: (any BiometricVaultAccessing)? = nil,
         pasteboard: any VaultPasteboard = NSPasteboard.general,
         monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         makeStorage: (URL) throws -> VaultStorage = { try VaultStorage(directory: $0) }) {
        self.monotonicNow = monotonicNow
        self.lastActivity = monotonicNow()
        self.clipboard = SensitiveClipboard(pasteboard: pasteboard)
        do {
            var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(isDemo ? DemoVault.directoryName : "Keynest", isDirectory: true)
            // Explicit developer-only profile: never auto-detect or import other apps' secrets.
            if !isDemo, let index = CommandLine.arguments.firstIndex(of: "--test-data-directory"), CommandLine.arguments.count > index + 1 {
                directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            } else if Bundle.main.bundleIdentifier == "local.keynest.qa", let path = Bundle.main.object(forInfoDictionaryKey: "KeynestTestDataDirectory") as? String {
                directory = URL(fileURLWithPath: path, isDirectory: true)
            }
            let store = try makeStorage(directory)
            let lockURL = directory.appendingPathComponent("instance.lock")
            lockFD = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, S_IRUSR | S_IWUSR)
            var lockInfo = stat()
            guard lockFD >= 0, fstat(lockFD, &lockInfo) == 0,
                  (lockInfo.st_mode & S_IFMT) == S_IFREG, lockInfo.st_nlink == 1, lockInfo.st_uid == geteuid(),
                  fchmod(lockFD, mode_t(0o600)) == 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
                if lockFD >= 0 { Darwin.close(lockFD); lockFD = -1 }
                throw AppError("这个密钥库正在另一个 Keynest 实例中使用，请先关闭它。")
            }
            self.storage = store
            // Command-line checks never access a real system credential store.
            if let injectedBiometricAccess { biometricAccess = injectedBiometricAccess }
            else if ["local.keynest.mac", "local.keynest.demo", "local.keynest.qa"].contains(Bundle.main.bundleIdentifier ?? "") {
                biometricAccess = BiometricVaultAccess(vaultIdentifier: store.fileURL.path)
            }
            if isDemo && !store.exists {
                let demoSession = try VaultCodec.createSession(password: DemoVault.password)
                try writeCommitted(VaultCodec.encrypt(DemoVault.document(), session: demoSession), to: store)
                UserDefaults.standard.set(DemoVault.catalogRevision, forKey: "KeynestDemoCatalogRevision")
            }
            isInitialized = store.exists
        } catch { errorMessage = friendly(error) }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            self?.activity(); return event
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.lock() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        })
    }

    private func friendly(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
        return "操作未完成。请检查文件权限或备份格式后重试。"
    }
    private func report(_ error: Error) { errorMessage = friendly(error) }
    private func requireUnlocked() throws {
        checkIdle()
        guard !isLocked, session != nil, storage != nil else { throw AppError("密钥库已锁定，请先解锁。") }
    }
    private func checkIdle() { if !isLocked && monotonicNow() - lastActivity >= 600 { lock() } }
    func activity() { checkIdle(); if !isLocked { lastActivity = monotonicNow() } }
    func notify(_ text: String) {
        let id = UUID(); messageID = id; toast = text
        Task { try? await Task.sleep(for: .seconds(3)); if messageID == id { toast = nil } }
    }

    func refreshBiometricStatus() async {
        guard let biometricAccess else {
            biometricStatus = .unavailable("当前运行环境不支持 Touch ID。")
            return
        }
        biometricStatus = await biometricAccess.status()
    }

    /// Once per launch, never immediately after an explicit lock or cancellation.
    func prepareAccess() async {
        await refreshBiometricStatus()
        guard automaticBiometricAttemptPending, isLocked, isInitialized, !busy, NSApp.isActive else { return }
        automaticBiometricAttemptPending = false
        if biometricEnabled { await unlockWithBiometrics() }
    }

    func enableBiometrics() async {
        guard !busy else { return }
        do { try requireUnlocked() } catch { report(error); return }
        guard let session, let biometricAccess else { return }
        let generation = epoch
        busy = true; biometricMessage = nil
        defer { busy = false }
        do {
            var token = try VaultCodec.biometricUnlockData(session: session)
            defer { token.resetBytes(in: 0..<token.count) }
            try await biometricAccess.enroll(token: token)
            guard generation == epoch, !isLocked else { return }
            await refreshBiometricStatus()
            if biometricEnabled { notify("已启用 Touch ID，下次打开可用指纹解锁") }
        } catch {
            guard generation == epoch else { return }
            biometricMessage = friendly(error)
            await refreshBiometricStatus()
        }
    }

    func disableBiometrics() async {
        guard !busy, !isLocked, let biometricAccess else { return }
        do { try requireUnlocked() } catch { report(error); return }
        let generation = epoch
        busy = true; biometricMessage = nil
        defer { busy = false }
        do {
            try await biometricAccess.remove()
            guard generation == epoch else { return }
            await refreshBiometricStatus()
            notify("已关闭 Touch ID，继续使用主密码解锁")
        } catch { if generation == epoch { biometricMessage = friendly(error) } }
    }

    func unlockWithBiometrics() async {
        guard !busy, isLocked, isInitialized, biometricEnabled, let biometricAccess, let storage else { return }
        automaticBiometricAttemptPending = false
        let generation = epoch
        busy = true; biometricMessage = nil
        defer { busy = false }
        do {
            var token = try await biometricAccess.unlockData()
            defer { token.resetBytes(in: 0..<token.count) }
            guard generation == epoch else { return }
            let data = try storage.read()
            let tokenForDecryption = token
            let result = try await Task.detached(priority: .userInitiated) {
                try VaultCodec.decrypt(data, biometricUnlockData: tokenForDecryption)
            }.value
            guard generation == epoch else { return }
            try acceptUnlocked(result)
        } catch {
            guard generation == epoch else { return }
            biometricMessage = "\(friendly(error)) 可使用主密码解锁。"
            await refreshBiometricStatus()
        }
    }

    func cancelBiometricAuthentication() {
        automaticBiometricAttemptPending = false
        // Also reject a token that has already left the hardware callback and
        // is still decrypting when the user switches to password entry.
        if isLocked { epoch = UUID() }
        biometricAccess?.cancel()
    }

    private func acceptUnlocked(_ result: (document: VaultDocument, session: VaultSession, requiresUpgrade: Bool, sourceVersion: Int)) throws {
        session = result.session; entries = result.document.entries; tools = result.document.tools
        keychainConfiguration = result.document.keychainConfiguration
        homeProviderOrder = result.document.homeProviderOrder
        needsUpgradeBackup = result.requiresUpgrade
        isLocked = false; lastActivity = monotonicNow(); biometricMessage = nil
        if isDemo {
            let savedRevision = UserDefaults.standard.integer(forKey: "KeynestDemoCatalogRevision")
            // Payload 3 shipped with catalog 7. A missing preference must not
            // re-add samples deleted from that already upgraded demo library.
            let inferredRevision = result.sourceVersion >= 3 ? DemoVault.catalogRevision : 5
            let revision = result.sourceVersion == 1 ? 4 : (savedRevision > 0 ? savedRevision : inferredRevision)
            if revision < DemoVault.catalogRevision {
                let enriched = try DemoVault.upgradingCatalog(result.document, fromRevision: revision)
                try persist(enriched.entries, tools: enriched.tools)
                UserDefaults.standard.set(DemoVault.catalogRevision, forKey: "KeynestDemoCatalogRevision")
            }
        }
        filter = .home; homeScope = .all; searchText = ""; environmentFilter = nil; selectedID = nil
    }

    func create(password: String) async {
        guard !isDemo, !busy, !isInitialized, let storage else { return }
        let generation = epoch; busy = true
        defer { busy = false }
        do {
            let newSession = try await Task.detached(priority: .userInitiated) { try VaultCodec.createSession(password: password) }.value
            guard epoch == generation else { return }
            let data = try VaultCodec.encrypt(VaultDocument(), session: newSession)
            guard !storage.exists else { throw AppError("密钥库已经存在，请重新打开应用后解锁。") }
            try await biometricAccess?.remove()
            guard epoch == generation else { return }
            guard !storage.exists else { throw AppError("密钥库已经存在，未覆盖现有文件。") }
            try writeCommitted(data, to: storage)
            session = newSession; entries = []; tools = []; keychainConfiguration = nil; homeProviderOrder = nil
            needsUpgradeBackup = false; isInitialized = true; isLocked = false; lastActivity = monotonicNow()
            await refreshBiometricStatus()
        } catch { if generation == epoch { report(error) } }
    }
    func unlock(password: String) async {
        guard !busy, isLocked, isInitialized, let storage else { return }
        let generation = epoch; busy = true
        defer { busy = false }
        do {
            let data = try storage.read()
            let result = try await Task.detached(priority: .userInitiated) { try VaultCodec.decrypt(data, password: password) }.value
            guard generation == epoch else { return }
            try acceptUnlocked(result)
        } catch { if generation == epoch { report(error) } }
    }
    func lock() {
        biometricAccess?.cancel(); automaticBiometricAttemptPending = false; biometricMessage = nil
        for task in quotaTasks.values { task.cancel() }; quotaTasks.removeAll()
        epoch = UUID(); session = nil; entries = []; tools = []; keychainConfiguration = nil; homeProviderOrder = nil; selectedID = nil; searchText = ""
        filter = .home; homeScope = .all; environmentFilter = nil; needsUpgradeBackup = false
        presentingHomeProviderPicker = false; quickAddPreset = nil
        copyFeedback = nil; copyFeedbackGeneration = UUID()
        presentingToolSetup = false; presentingToolEditor = false; editingTool = nil; presentingToolLinks = false; linkingTool = nil
        isLocked = true; presentingEditor = false; editingEntry = nil
        cancelRestore(); presentingPasswordChange = false
        syncInProgress = []; syncErrors = [:]; toast = nil; errorMessage = nil
        clipboard.clearOwnedContents()
    }
    private func persist(_ newEntries: [SecretEntry], tools newTools: [ToolGroup]? = nil) throws {
        try persist(VaultDocument(entries: newEntries, tools: newTools ?? tools,
                                  keychainConfiguration: keychainConfiguration, homeProviderOrder: homeProviderOrder))
    }
    private var currentDocument: VaultDocument {
        VaultDocument(entries: entries, tools: tools, keychainConfiguration: keychainConfiguration,
                      homeProviderOrder: homeProviderOrder)
    }
    private func persist(_ document: VaultDocument) throws {
        try requireUnlocked()
        guard let session, let storage else { throw AppError("密钥库不可用。") }
        let data = try VaultCodec.encrypt(document, session: session)
        if needsUpgradeBackup { try storage.preserveUpgradeBackup(storage.read()) }
        try writeCommitted(data, to: storage)
        needsUpgradeBackup = false; entries = document.entries; tools = document.tools
        keychainConfiguration = document.keychainConfiguration
        homeProviderOrder = document.homeProviderOrder
    }
    /// Nil restores automatic defaults; an empty charm array remains an explicit
    /// user choice. Nothing is published until the encrypted replacement commits.
    func saveKeychainConfiguration(_ configuration: KeychainConfiguration?) throws {
        try requireUnlocked()
        guard !busy else { throw AppError("当前正在处理密钥库，请稍后再保存钥匙串。") }
        var document = currentDocument
        document.keychainConfiguration = try configuration?.validated()
        try persist(document)
        notify("钥匙串已保存")
    }
    func saveHomeProviderOrder(_ order: [String]?) throws {
        try requireUnlocked()
        guard !busy else { throw AppError("当前正在处理密钥库，请稍后再保存首页顺序。") }
        var document = currentDocument
        document.homeProviderOrder = order
        try persist(document)
        notify("首页平台顺序已保存")
    }
    private func writeCommitted(_ data: Data, to storage: VaultStorage) throws {
        if try storage.write(data) == .durabilityUncertain {
            // The atomic replacement already committed: callers must advance
            // memory/session as well, including after a password change.
            errorMessage = "密钥库已写入，但无法确认磁盘目录同步完成。当前内容已更新，请尽快导出加密备份并检查磁盘。"
        }
    }
    func addNew(category: EntryCategory? = nil) {
        guard !isLocked, !busy else { return }
        if filter == .home && category == nil { presentingHomeProviderPicker = true; return }
        var entry = SecretEntry()
        if let category { entry.category = category }
        else if case .category(let category) = filter { entry.category = category }
        if case .tool(let id) = filter { entry.toolIDs = [id] }
        if let environmentFilter { entry.environment = environmentFilter }
        editingEntry = entry; presentingEditor = true
    }
    func edit(_ entry: SecretEntry) { guard !isLocked, !busy else { return }; editingEntry = entry; presentingEditor = true }
    func save(_ input: SecretEntry) throws {
        try requireUnlocked()
        var entry = try input.validated()
        if isDemo { entry.quotaProvider = .none; entry.quota = nil }
        var newEntries = entries
        if let index = newEntries.firstIndex(where: { $0.id == entry.id }) {
            let previous = newEntries[index]
            entry.createdAt = previous.createdAt
            if entry.secret != previous.secret || entry.baseURL != previous.baseURL || entry.quotaProvider != previous.quotaProvider {
                quotaTasks[entry.id]?.cancel(); quotaTasks[entry.id] = nil
                entry.quota = nil
            } else { entry.quota = previous.quota }
            entry.updatedAt = Date(); newEntries[index] = entry
        } else {
            entry.createdAt = Date(); entry.updatedAt = Date(); newEntries.append(entry)
        }
        try persist(newEntries)
        activity(); selectedID = filter == .home ? nil : entry.id; searchText = ""; environmentFilter = nil
        if !includes(entry) { filter = .all }
        if filter == .home { homeScope = .all }
        presentingEditor = false; editingEntry = nil; quickAddPreset = nil; notify("已保存密钥")
    }
    func delete(_ entry: SecretEntry) throws {
        try persist(entries.filter { $0.id != entry.id })
        quotaTasks[entry.id]?.cancel(); quotaTasks[entry.id] = nil
        if selectedID == entry.id { selectedID = filter == .home ? nil : filteredEntries.first?.id }
        syncErrors[entry.id] = nil; notify("已删除本机记录，服务商上的密钥仍然有效")
    }
    func toggleFavorite(_ entry: SecretEntry) {
        do {
            try requireUnlocked()
            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
            var next = entries; next[index].isFavorite.toggle()
            try persist(next)
        } catch { report(error) }
    }
    func addTool() {
        guard !isLocked, !busy else { return }
        presentingToolSetup = true
    }
    func addCustomTool() {
        guard !isLocked, !busy else { return }
        presentingToolSetup = false
        editingTool = ToolGroup(); presentingToolEditor = true
    }

    func saveTemplate(_ template: ToolTemplate, name: String, selections: [ToolCredentialSelection]) throws {
        try requireUnlocked()
        let result = try currentDocument
            .addingTool(templateID: template.id, name: name, selections: selections)
        try persist(result.document.entries, tools: result.document.tools)
        presentingToolSetup = false
        activity(); selectFilter(.tool(result.tool.id))
        notify("已添加 \(result.tool.name)")
    }

    func editTool(_ tool: ToolGroup) {
        guard !isLocked, !busy else { return }
        editingTool = tool; presentingToolEditor = true
    }
    func saveTool(_ input: ToolGroup) throws {
        try requireUnlocked()
        var tool = try input.validated(), next = tools
        if let index = next.firstIndex(where: { $0.id == tool.id }) {
            tool.createdAt = next[index].createdAt; tool.updatedAt = Date(); next[index] = tool
        } else { tool.createdAt = Date(); tool.updatedAt = Date(); next.append(tool) }
        try persist(entries, tools: next)
        presentingToolEditor = false; editingTool = nil; selectFilter(.tool(tool.id))
        notify("已保存工具，可以添加新密钥或关联已有密钥")
    }
    func removeTool(_ tool: ToolGroup) throws {
        try requireUnlocked()
        let next = try currentDocument.removingTool(id: tool.id)
        try persist(next.entries, tools: next.tools)
        if filter == .tool(tool.id) { selectFilter(.all) }
        notify("已移除工具分组，密钥仍保留在全部密钥中")
    }
    func manageLinks(for tool: ToolGroup) {
        guard !isLocked, !busy else { return }
        linkingTool = tool; presentingToolLinks = true
    }
    func saveLinks(_ selected: Set<UUID>, for tool: ToolGroup) throws {
        try requireUnlocked()
        guard tools.contains(where: { $0.id == tool.id }) else { throw AppError("这个工具已不存在。") }
        let next = entries.map { entry -> SecretEntry in
            var result = entry
            if selected.contains(entry.id) && !result.toolIDs.contains(tool.id) { result.toolIDs.append(tool.id) }
            else if !selected.contains(entry.id) { result.toolIDs.removeAll { $0 == tool.id } }
            if result.toolIDs != entry.toolIDs { result.updatedAt = Date() }
            return result
        }
        try persist(next)
        presentingToolLinks = false; linkingTool = nil; selectFilter(.tool(tool.id))
        notify("工具的密钥关联已更新")
    }
    func copySecret(_ entry: SecretEntry) {
        do {
            try requireUnlocked()
            guard let current = entries.first(where: { $0.id == entry.id }) else { return }
            if copyToClipboard(current.secret, label: "密钥") { showCopyFeedback(.secret(current.id)) }
        } catch { report(error) }
    }
    func copyAPIAddress(_ entry: SecretEntry) {
        do {
            try requireUnlocked()
            guard let current = entries.first(where: { $0.id == entry.id }), !current.baseURL.isEmpty else { return }
            // Legacy metadata may be recoverable but need correction. Never
            // send a malformed address to another app through the clipboard.
            let validated = try current.validated()
            if copyToClipboard(validated.baseURL, label: "API 地址") { showCopyFeedback(.address(current.id)) }
        } catch { report(error) }
    }
    private func showCopyFeedback(_ feedback: CopyFeedback) {
        let generation = UUID(); copyFeedbackGeneration = generation; copyFeedback = feedback
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, copyFeedbackGeneration == generation else { return }
            copyFeedback = nil
        }
    }
    private func copyToClipboard(_ value: String, label: String) -> Bool {
        guard clipboard.copy(value) else {
            copyFeedback = nil
            errorMessage = "无法写入剪贴板，请重试。"
            return false
        }
        activity(); notify("已复制\(label)，60 秒后清除本次复制内容")
        return true
    }
    func syncQuota(_ entry: SecretEntry) async {
        guard !isDemo else { errorMessage = "演示版使用虚构密钥，不发送额度查询请求。"; return }
        do { try requireUnlocked() } catch { report(error); return }
        guard !syncInProgress.contains(entry.id), let current = entries.first(where: { $0.id == entry.id }) else { return }
        let generation = epoch
        syncInProgress.insert(current.id); syncErrors[current.id] = nil
        let request = Task { try await QuotaClient.fetch(entry: current) }
        quotaTasks[current.id] = request
        defer { if generation == epoch { syncInProgress.remove(current.id); quotaTasks[current.id] = nil } }
        do {
            let result = try await request.value
            guard generation == epoch, !isLocked, let index = entries.firstIndex(where: { $0.id == current.id }), entries[index].secret == current.secret, entries[index].quotaProvider == current.quotaProvider, entries[index].baseURL == current.baseURL else { return }
            var next = entries; next[index].quota = result
            try persist(next)
        } catch {
            if generation == epoch { syncErrors[entry.id] = friendly(error) }
        }
    }
    func exportBackup() {
        guard !isDemo else { errorMessage = "演示版不导出备份，请使用正式版管理真实密钥。"; return }
        do {
            try requireUnlocked()
            let panel = NSSavePanel()
            panel.title = "导出加密备份"; panel.nameFieldStringValue = "Keynest-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).keynest"
            panel.allowedContentTypes = [UTType(filenameExtension: "keynest") ?? .data]
            panel.message = "备份仍需当前主密码才能打开，请妥善保管。"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try requireUnlocked()
            guard let storage else { return }
            let data = try storage.read()
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            notify("加密备份已导出")
        } catch { report(error) }
    }
    func importBackup() {
        guard !busy else { return }
        guard !isDemo else { errorMessage = "演示版不导入备份，避免混入真实密钥。"; return }
        if isInitialized && isLocked { errorMessage = "请先解锁现有密钥库，再合并导入备份。"; return }
        let generation = epoch
        let requiresUnlockedVault = isInitialized
        let panel = NSOpenPanel(); panel.title = "导入 Keynest 加密备份"
        panel.allowedContentTypes = [UTType(filenameExtension: "keynest") ?? .data, .json]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard epoch == generation else { return }
            if requiresUnlockedVault { try requireUnlocked() }
            let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw AppError("无法读取备份文件。") }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var info = stat()
            guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw AppError("请选择普通备份文件。") }
            let limit = 4 * 1024 * 1024
            var data = Data()
            while let chunk = try handle.read(upToCount: min(65536, limit + 1 - data.count)), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= limit else { throw AppError("备份文件超过 4 MiB。") }
            }
            try stageImport(data)
        } catch { report(error) }
    }
    /// Shared by the file-panel path and isolated integration checks.
    func stageImport(_ data: Data) throws {
        guard !isDemo, !busy else { throw AppError("当前无法导入备份。") }
        if isInitialized { try requireUnlocked() }
        guard !data.isEmpty, data.count <= VaultCodec.maximumFileSize else { throw VaultError.invalidFormat }
        importGeneration = UUID(); pendingImport = data; presentingRestore = true
    }
    func restore(password: String) async {
        guard !isDemo, !busy, let data = pendingImport, let storage else { return }
        let generation = epoch, restoringImport = importGeneration; busy = true
        let recoveringNewVault = !isInitialized
        defer { busy = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try VaultCodec.decrypt(data, password: password) }.value
            guard generation == epoch, restoringImport == importGeneration else { return }
            if isInitialized {
                try requireUnlocked()
                let merged = try currentDocument.merging(result.document)
                try persist(merged)
            } else {
                guard !storage.exists else { throw AppError("密钥库已经存在，未覆盖现有文件。") }
                try await biometricAccess?.remove()
                guard generation == epoch, restoringImport == importGeneration else { return }
                guard !storage.exists else { throw AppError("密钥库已经存在，未覆盖现有文件。") }
                try writeCommitted(VaultCodec.encrypt(result.document, session: result.session), to: storage)
                session = result.session; entries = result.document.entries; tools = result.document.tools
                keychainConfiguration = result.document.keychainConfiguration
                homeProviderOrder = result.document.homeProviderOrder
                needsUpgradeBackup = false; isInitialized = true; isLocked = false; lastActivity = monotonicNow()
            }
            presentingRestore = false; pendingImport = nil; selectedID = filter == .home ? nil : filteredEntries.first?.id; notify("已导入加密备份")
            // Close the cancellable UI in the same actor turn as the commit.
            // A status refresh must not leave a Cancel button after data is saved.
            if recoveringNewVault { await refreshBiometricStatus() }
        } catch { if generation == epoch, restoringImport == importGeneration { report(error) } }
    }
    func cancelRestore() { importGeneration = UUID(); pendingImport = nil; presentingRestore = false }
    func changePassword() { if !isDemo && !isLocked { presentingPasswordChange = true } }
    func replacePassword(old: String, new: String) async {
        guard !isDemo, !busy, !isLocked, let storage else { return }
        let generation = epoch; busy = true
        defer { busy = false }
        do {
            let oldData = try storage.read()
            let newSession = try await Task.detached(priority: .userInitiated) {
                _ = try VaultCodec.decrypt(oldData, password: old)
                return try VaultCodec.createSession(password: new)
            }.value
            guard generation == epoch else { return }
            try requireUnlocked()
            if needsUpgradeBackup { try storage.preserveUpgradeBackup(storage.read()) }
            // Revoke the old biometric key before replacing the password-derived key.
            // A failed write leaves the old password usable, with biometrics disabled.
            try await biometricAccess?.remove()
            guard generation == epoch else { return }
            try requireUnlocked()
            let updatedData = try VaultCodec.encrypt(currentDocument, session: newSession)
            try writeCommitted(updatedData, to: storage)
            needsUpgradeBackup = false
            session = newSession; presentingPasswordChange = false
            await refreshBiometricStatus()
            notify("主密码已更新；如需指纹解锁，请重新启用 Touch ID。旧备份仍使用原密码。")
        } catch {
            guard generation == epoch else { return }
            report(error)
            // Revocation may have succeeded even if the ciphertext write failed.
            await refreshBiometricStatus()
        }
    }
}

struct AppError: LocalizedError { let text: String; init(_ text: String) { self.text = text }; var errorDescription: String? { text } }
