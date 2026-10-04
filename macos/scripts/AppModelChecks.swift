import Foundation
import Darwin
import AppKit
import CryptoKit

/// Records publications in memory. Never touches NSPasteboard.general or an
/// actual clipboard service, so no user content is read or overwritten.
private final class FakePasteboard: VaultPasteboard {
    var changeCount = 0
    var options: NSPasteboard.ContentsOptions = []
    var value: String?
    var types: Set<NSPasteboard.PasteboardType> = []
    var writeCount = 0
    var failWrite = false
    var externalCopyDuringWrite = false
    func prepareForNewContents(with options: NSPasteboard.ContentsOptions) -> Int {
        self.options = options; value = nil; types = []; changeCount += 1
        return changeCount
    }
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        guard !failWrite, objects.count == 1, let item = objects.first as? NSPasteboardItem else { return false }
        value = item.string(forType: .string); types = Set(item.types)
        writeCount += 1
        if externalCopyDuringWrite { simulateExternalCopy("external copy during publication") }
        return true
    }
    func clearContents() -> Int { value = nil; types = []; changeCount += 1; return changeCount }
    func simulateExternalCopy(_ value: String) { self.value = value; changeCount += 1 }
}

private final class DirectorySyncControl: @unchecked Sendable {
    private let mutex = NSLock()
    private var shouldFail = false
    func setFailure(_ value: Bool) { mutex.withLock { shouldFail = value } }
    func sync(_ fd: Int32) -> Int32 {
        if mutex.withLock({ shouldFail }) { errno = EIO; return -1 }
        return Darwin.fsync(fd)
    }
}

private struct AppCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Deterministic authentication stand-in. These checks never call the real sensor.
private final class FakeBiometricAccess: BiometricVaultAccessing, @unchecked Sendable {
    private let mutex = NSLock()
    private var storedToken: Data?
    private var continuation: CheckedContinuation<Data, Error>?
    var failAuthentication = false
    var delayAuthentication = false
    private(set) var unlockCalls = 0
    var hasPendingAuthentication: Bool { mutex.withLock { continuation != nil } }
    var token: Data? { mutex.withLock { storedToken } }
    func status() async -> BiometricStatus { mutex.withLock { storedToken == nil ? .notEnrolled : .enrolled } }
    func enroll(token: Data) async throws { mutex.withLock { storedToken = token } }
    func remove() async throws { mutex.withLock { storedToken = nil } }
    func cancel() { /* Simulate a callback racing with cancellation. AppModel must reject it. */ }
    func unlockData() async throws -> Data {
        unlockCalls += 1
        if failAuthentication { throw AppCheckFailure(description: "Simulated failed authentication") }
        if delayAuthentication {
            return try await withCheckedThrowingContinuation { value in mutex.withLock { continuation = value } }
        }
        guard let token else { throw AppCheckFailure(description: "No enrolled token") }
        return token
    }
    func finishPendingAuthentication() {
        let pending = mutex.withLock { let result = continuation; continuation = nil; return result }
        pending?.resume(returning: token ?? Data())
    }
}

@MainActor
private final class AppChecks {
    private(set) var assertions = 0

    private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String,
                        line: UInt = #line) throws {
        assertions += 1
        guard try condition() else {
            throw AppCheckFailure(description: "line \(line): \(message)")
        }
    }

    private func entry(_ id: UUID, in model: AppModel) throws -> SecretEntry {
        try expect(model.entries.contains { $0.id == id }, "Expected saved entry to exist")
        return model.entries.first { $0.id == id }!
    }

    private func versionThreeFixture(password: String, entries: [SecretEntry] = []) throws -> Data {
        let session = try VaultCodec.createSession(password: password)
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(VaultDocument(entries: entries))) as! [String: Any]
        payload["version"] = 3
        var envelope = try JSONSerialization.jsonObject(with: VaultCodec.encrypt(VaultDocument(), session: session)) as! [String: Any]
        let nonce = AES.GCM.Nonce()
        let header = Data("Keynest|format=keynest-vault|version=1|cipher=aes-256-gcm|kdf=pbkdf2-sha256|iterations=600000|salt=\(session.salt.base64EncodedString())".utf8)
        let box = try AES.GCM.seal(JSONSerialization.data(withJSONObject: payload), using: session.key,
                                   nonce: nonce, authenticating: header)
        envelope["nonce"] = Data(nonce).base64EncodedString()
        envelope["ciphertext"] = box.ciphertext.base64EncodedString()
        envelope["tag"] = box.tag.base64EncodedString()
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    func run() async throws {
        // Refuse to initialize AppModel until a fresh, explicitly supplied
        // /private/tmp vault is proven. Never permit its default data directory.
        let arguments = CommandLine.arguments
        try expect(arguments.count == 3 && arguments[1] == "--test-data-directory",
                   "An explicit isolated test directory is required")
        let path = arguments[2]
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try expect(path.range(of: "^/private/tmp/keynest-app-checks\\.[A-Za-z0-9]+/vault$",
                              options: .regularExpression) != nil,
                   "Test directory must be an absolute generated temporary path")
        try expect(directory.lastPathComponent == "vault" &&
                   directory.deletingLastPathComponent().lastPathComponent.hasPrefix("keynest-app-checks.") &&
                   directory.deletingLastPathComponent().deletingLastPathComponent().path == "/private/tmp",
                   "Only a fresh keynest-app-checks temporary vault is accepted")
        var isDirectory: ObjCBool = false
        try expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue,
                   "Temporary vault directory must already exist")
        // Foundation may abbreviate an existing /private/tmp path to /tmp
        // when resolving symlinks. Inspect our two generated components instead.
        let vaultValues = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        let rootValues = try directory.deletingLastPathComponent().resourceValues(forKeys: [.isSymbolicLinkKey])
        try expect(vaultValues.isSymbolicLink == false && rootValues.isSymbolicLink == false,
                   "Generated temporary directories must not be symlinks")
        let initialFiles = try FileManager.default.contentsOfDirectory(atPath: path)
        try expect(initialFiles.isEmpty, "Temporary vault directory must be empty")
        try expect(Bundle.main.bundleIdentifier != "local.keynest.demo", "Never initialize a demo or real bundle profile")

        let biometric = FakeBiometricAccess()
        let pasteboard = FakePasteboard()
        let directorySync = DirectorySyncControl()
        var uptime: TimeInterval = 100
        let model = AppModel(biometricAccess: biometric, pasteboard: pasteboard, monotonicNow: { uptime },
                             makeStorage: { try VaultStorage(directory: $0, directorySync: { directorySync.sync($0) }) })
        defer { model.lock() }
        try expect(model.dataPath == directory.standardizedFileURL.appendingPathComponent("vault.keynest").path,
                   "AppModel must use the explicit temporary directory")
        try expect(model.errorMessage == nil && !model.isInitialized && model.isLocked,
                   "Isolated model must start without an existing vault")
        try expect(model.filter == .home && model.selectedID == nil && model.homeScope == .all,
                   "An empty model starts on Home without implicitly selecting a credential")
        let password = "Keynest-App-Checks-Only-2026"
        await model.create(password: password)
        try expect(model.errorMessage == nil && model.isInitialized && !model.isLocked,
                   "Create should open an empty encrypted vault")
        try expect(model.filter == .home && model.selectedID == nil && model.homeScope == .all,
                   "Creating a vault must keep Home as the default without a selected credential")

        // Only this proven temporary empty vault receives a historical fixture.
        try expect(model.keychainConfiguration == nil, "A new vault uses automatic keychain defaults")
        model.lock()
        let legacyBytes = try versionThreeFixture(password: password)
        try VaultStorage(directory: directory).write(legacyBytes)
        await model.unlock(password: password)
        try expect(!model.isLocked && model.keychainConfiguration == nil && model.entries.isEmpty,
                   "Payload three unlock must not invent a custom configuration or credentials")
        let keychain = KeychainConfiguration(charms: [
            .init(providerID: "openai", color: .rose),
            .init(customGroupID: "custom:private fixture keychain", color: .graphite)
        ])
        try model.saveKeychainConfiguration(keychain)
        try expect(model.keychainConfiguration == keychain, "Configuration becomes visible after the encrypted save")
        let upgradeBackup = directory.appendingPathComponent("vault-before-0.10.keynest")
        try expect(try Data(contentsOf: upgradeBackup) == legacyBytes,
                   "First payload-four save must preserve the original encrypted payload-three bytes")
        let savedConfigurationBytes = try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))
        let savedConfiguration = try VaultCodec.decrypt(savedConfigurationBytes, password: password)
        try expect(savedConfiguration.sourceVersion == 4 && !savedConfiguration.requiresUpgrade &&
                   savedConfiguration.document.keychainConfiguration == keychain,
                   "The configuration must round-trip in payload four")
        try expect(!String(decoding: savedConfigurationBytes, as: UTF8.self).contains("private fixture keychain"),
                   "Private custom group identifiers must not appear outside encryption")
        let failedConfiguration = KeychainConfiguration(charms: [.init(providerID: "anthropic", color: .amber)])
        let hardLink = directory.appendingPathComponent("fake-configuration-write-blocker")
        try FileManager.default.linkItem(at: directory.appendingPathComponent("vault.keynest"), to: hardLink)
        do {
            try model.saveKeychainConfiguration(failedConfiguration)
            throw AppCheckFailure(description: "Saving over a hard-linked fixture unexpectedly succeeded")
        } catch is VaultError { }
        try expect(model.keychainConfiguration == keychain &&
                   (try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == savedConfigurationBytes,
                   "A pre-commit storage failure must preserve both configuration memory and ciphertext")
        try FileManager.default.removeItem(at: hardLink)
        do {
            try model.saveKeychainConfiguration(.init(charms: [.init(providerID: "openai"), .init(providerID: "openai")]))
            throw AppCheckFailure(description: "Duplicate charm targets were saved")
        } catch is VaultError { }
        try expect(model.keychainConfiguration == keychain &&
                   (try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == savedConfigurationBytes,
                   "Invalid configuration must leave memory and the encrypted file unchanged")
        try model.saveKeychainConfiguration(.init())
        model.lock(); await model.unlock(password: password)
        try expect(model.keychainConfiguration?.charms == [], "Intentional empty selection must survive lock and unlock")
        try model.saveKeychainConfiguration(nil)
        model.lock(); await model.unlock(password: password)
        try expect(model.keychainConfiguration == nil, "Restoring automatic defaults must survive lock and unlock")
        try model.saveKeychainConfiguration(keychain)
        try expect(try Data(contentsOf: upgradeBackup) == legacyBytes, "Later saves must not overwrite the upgrade backup")

        let orbit = ToolGroup(name: "Orbit Lab", notes: "Fictional test tool")
        let notebook = ToolGroup(name: "Notebook Bench", notes: "Fictional test tool")
        try model.saveTool(orbit)
        try model.saveTool(notebook)
        try expect(Set(model.tools.map(\.id)) == [orbit.id, notebook.id], "Both tools must be saved")
        let shared = SecretEntry(name: "Shared test credential", provider: "Example Test Provider",
                                 secret: "fake-only-secret-alpha-z7q9-not-an-api-key",
                                 baseURL: "https://api.example.invalid/v1", toolIDs: [orbit.id, notebook.id],
                                 environment: "development", accountLabel: "personal-sample")
        let production = SecretEntry(name: "Production test credential", provider: "Example Test Provider",
                                     secret: "fake-only-secret-beta-v8r4-not-an-api-key",
                                     baseURL: "https://api.example.invalid/v2", toolIDs: [notebook.id],
                                     environment: "production", accountLabel: "work-sample")
        try model.save(shared)
        try model.save(production)
        try expect(model.entries.count == 2 && model.tools.count == 2, "Saving entries must preserve tool records")
        try expect(model.keychainConfiguration == keychain, "Saving credentials and tools must retain keychain choices")
        try expect(Set(try entry(shared.id, in: model).toolIDs) == [orbit.id, notebook.id],
                   "One shared entry must refer to both tools")

        model.selectFilter(.tool(orbit.id))
        try expect(model.filteredEntries.map(\.id) == [shared.id], "Tool filter must select its associated entry")
        model.searchText = "personal-sample"
        try expect(model.filteredEntries.map(\.id) == [shared.id], "Account search must match metadata")
        model.environmentFilter = "development"
        model.selectFilter(.tool(notebook.id))
        try expect(model.searchText.isEmpty && model.environmentFilter == nil,
                   "Switching tools must clear the previous search and environment")
        try expect(Set(model.filteredEntries.map(\.id)) == [shared.id, production.id],
                   "The second tool must show both associated entries")
        try expect(model.selectedID.map { Set(model.filteredEntries.map(\.id)).contains($0) } == true,
                   "Tool switching must select an entry from the new result set")
        model.environmentFilter = "production"
        try expect(model.filteredEntries.map(\.id) == [production.id], "Environment filter must narrow within a tool")
        model.searchText = "work-sample"
        try expect(model.filteredEntries.map(\.id) == [production.id], "Account and environment filters must combine")
        model.selectFilter(.all)
        model.searchText = "Orbit Lab"
        try expect(model.filteredEntries.map(\.id) == [shared.id], "Tool name must be searchable from all entries")
        model.searchText = "development"
        try expect(model.filteredEntries.map(\.id) == [shared.id], "Environment text must be searchable")
        model.searchText = shared.secret
        try expect(model.filteredEntries.isEmpty, "Search must never match secret text")
        model.searchText = production.secret
        try expect(model.filteredEntries.isEmpty, "Search must exclude every entry's secret text")

        try model.saveLinks([production.id], for: orbit)
        try expect(Set(model.entries.map(\.id)) == [shared.id, production.id],
                   "Changing associations must not duplicate or delete credential entities")
        try expect(Set(try entry(shared.id, in: model).toolIDs) == [notebook.id],
                   "Unchecking a link must preserve the other tool association")
        try expect(Set(try entry(production.id, in: model).toolIDs) == [orbit.id, notebook.id],
                   "Adding a link must preserve the existing association")
        try expect(model.tools.count == 2, "Saving links must preserve tool records")
        try expect(model.filter == .tool(orbit.id) && model.selectedID == production.id,
                   "Saving links must select the edited tool and one of its current entries")

        model.toggleFavorite(shared)
        try expect(model.errorMessage == nil, "Favorite persistence must succeed")
        let favorite = try entry(shared.id, in: model)
        try expect(favorite.isFavorite && favorite.toolIDs == [notebook.id],
                   "Favorite updates must preserve current associations even with a stale caller snapshot")
        try expect(model.tools.count == 2, "Favorite updates must preserve tools")
        let untouched = try entry(production.id, in: model)
        let toolsBeforeEdit = model.tools
        var edited = favorite
        edited.name = "Edited shared credential"
        edited.environment = "staging"
        edited.accountLabel = "personal-updated"
        try model.save(edited)
        try expect(model.tools == toolsBeforeEdit, "Saving an edit must preserve both tool records")
        try expect(try entry(production.id, in: model) == untouched, "Saving one entry must not change another")
        try expect(try entry(shared.id, in: model).toolIDs == [notebook.id], "Editing metadata must retain associations")

        var renamed = model.tools.first { $0.id == orbit.id }!
        renamed.name = "Renamed Orbit Lab"
        let entriesBeforeRename = model.entries
        try model.saveTool(renamed)
        try expect(model.entries == entriesBeforeRename && model.tools.count == 2,
                   "Editing a tool must preserve all entries and the other tool")
        try model.removeTool(renamed)
        try expect(model.tools.map(\.id) == [notebook.id], "Removing a tool must preserve the other tool")
        try expect(Set(model.entries.map(\.id)) == [shared.id, production.id], "Removing a tool must retain both credentials")
        try expect(model.entries.allSatisfy { $0.toolIDs == [notebook.id] },
                   "Removing a tool must remove only its own associations")
        try expect(model.filter == .all, "Removing the selected tool must return to an existing filter")
        try expect(model.keychainConfiguration == keychain, "Edits, favorites, links and tool removal must preserve keychain configuration")

        model.addTool()
        try expect(model.presentingToolSetup && !model.presentingToolEditor,
                   "Add tool must open the template picker")
        model.presentingToolSetup = false
        let cline = ToolTemplate.match(templateID: "cline")!
        let slot = cline.credentialSlots[0]
        let preset = ProviderPreset.all.first { $0.id == slot.defaultProviderID }!
        try model.saveTemplate(cline, name: "Fixture Cline", selections: [
            ToolCredentialSelection(slotID: slot.id, providerID: preset.id,
                                    secret: "fake-only-template-key", baseURL: preset.baseURL)
        ])
        let firstTemplate = model.tools.first { $0.name == "Fixture Cline" }!
        let templateKey = model.entries.first { $0.toolIDs.contains(firstTemplate.id) }!
        try expect(firstTemplate.templateID == "cline" && model.entries.count == 3 && model.tools.count == 2,
                   "Template creation must persist the tool and its new credential together")
        try expect(!model.presentingToolSetup && model.filter == .tool(firstTemplate.id),
                   "Successful creation closes the sheet and selects the new tool")
        try model.saveTemplate(cline, name: "Fixture shared Cline", selections: [
            ToolCredentialSelection(slotID: slot.id, providerID: preset.id, existingEntryID: templateKey.id)
        ])
        try expect(model.entries.count == 3 && model.entries.first { $0.id == templateKey.id }!.toolIDs.count == 2,
                   "Reusing a credential must associate the same entity without duplicating its secret")
        try expect(model.keychainConfiguration == keychain, "Template creation must retain keychain configuration")
        let beforeFailure = try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))
        let toolsBeforeFailure = model.tools
        do {
            try model.saveTemplate(cline, name: "Invalid fixture", selections: [])
            throw AppCheckFailure(description: "Missing template credentials were accepted")
        } catch is VaultError { }
        try expect(model.tools == toolsBeforeFailure &&
                   (try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == beforeFailure,
                   "An invalid template must not change memory or the encrypted file")

        // Home is a browsing surface. Opening a draft or choosing a provider
        // must not persist a credential or silently choose one of several keys.
        model.searchText = "previous tool query"
        model.environmentFilter = "old environment"
        model.homeScope = .favorites
        model.selectFilter(.home)
        try expect(model.filter == .home && model.selectedID == nil && model.searchText.isEmpty &&
                   model.environmentFilter == nil && model.homeScope == .all,
                   "Entering Home must clear prior tool selection, query, environment and scope")
        let homePreset = ProviderPreset.match(provider: "openai")!
        let beforeHomeDraft = try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))
        let entriesBeforeHomeDraft = model.entries
        let toolsBeforeHomeDraft = model.tools
        model.addNew()
        try expect(model.presentingHomeProviderPicker && !model.presentingEditor && model.editingEntry == nil,
                   "Add from Home must open the platform picker before creating an entry draft")
        try expect(model.entries == entriesBeforeHomeDraft && model.tools == toolsBeforeHomeDraft &&
                   (try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == beforeHomeDraft,
                   "Opening the Home provider picker must not alter memory or ciphertext")
        model.quickAdd(homePreset)
        try expect(!model.presentingHomeProviderPicker && model.quickAddPreset == homePreset &&
                   model.editingEntry == nil && !model.presentingEditor,
                   "Choosing a preset opens only the quick draft and dismisses the platform picker")
        try expect(model.entries == entriesBeforeHomeDraft && model.tools == toolsBeforeHomeDraft &&
                   (try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == beforeHomeDraft,
                   "Quick add must not insert an empty record or change the encrypted file")

        var homeDraft = homePreset.applying(to: SecretEntry())
        homeDraft.name = "Home work credential"
        homeDraft.secret = "fake-only-home-work-secret-not-an-api-key"
        homeDraft.baseURL = "https://home-work.example.invalid/v1"
        homeDraft.website = "https://home-console.example.invalid"
        homeDraft.category = .skill; homeDraft.tags = ["home-fixture", "work"]
        homeDraft.notes = "Preserve this draft when opening advanced fields"
        homeDraft.accountLabel = "home-work-account"; homeDraft.environment = "production"
        homeDraft.toolIDs = [notebook.id]; homeDraft.isFavorite = true
        model.openAdvancedEntry(homeDraft)
        try expect(model.quickAddPreset == nil && !model.presentingHomeProviderPicker &&
                   model.presentingEditor && model.editingEntry == homeDraft,
                   "Opening advanced entry must preserve every draft field and dismiss quick add")
        try expect(model.entries == entriesBeforeHomeDraft && model.tools == toolsBeforeHomeDraft &&
                   (try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == beforeHomeDraft,
                   "Opening advanced fields must leave saved entries and ciphertext untouched")
        model.searchText = "would hide a new key"
        model.environmentFilter = "nonmatching environment"
        model.homeScope = .services
        try model.save(homeDraft)
        try expect(model.filter == .home && model.selectedID == nil && model.homeScope == .all &&
                   model.searchText.isEmpty && model.environmentFilter == nil,
                   "Saving from Home stays on Home, clears filters and never auto-selects a key")
        try expect(!model.presentingEditor && model.editingEntry == nil && model.quickAddPreset == nil,
                   "Saving the Home draft must close and clear both editor states")
        var savedHome = try entry(homeDraft.id, in: model)
        savedHome.createdAt = homeDraft.createdAt; savedHome.updatedAt = homeDraft.updatedAt
        try expect(savedHome == homeDraft && model.tools == toolsBeforeHomeDraft &&
                   model.entries.count == entriesBeforeHomeDraft.count + 1,
                   "The saved Home credential must preserve all user fields and existing tools")

        let personalHome = SecretEntry(name: "Home personal credential", provider: "ChatGPT",
                                       secret: "fake-only-home-personal-secret-not-an-api-key",
                                       baseURL: "https://home-personal.example.invalid/v1",
                                       environment: "development", accountLabel: "home-personal-account")
        model.quickAdd(homePreset)
        try model.save(personalHome)
        let homeGroups = HomeCatalog.groups(entries: model.entries, tools: model.tools)
        let openAIGroup = homeGroups.first { $0.id == "openai" }
        try expect(openAIGroup?.entries.count == 2 &&
                   Set(openAIGroup?.entries.map(\.id) ?? []) == [homeDraft.id, personalHome.id],
                   "Two keys on one provider remain distinct entries in the same Home group")
        try expect(model.selectedID == nil && model.filter == .home && model.quickAddPreset == nil,
                   "Saving a second key must not implicitly choose either provider credential")
        let beforeExplicitNavigation = try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))
        let entriesBeforeNavigation = model.entries
        var stalePersonalSnapshot = personalHome
        stalePersonalSnapshot.name = "Do not overwrite saved display name"
        stalePersonalSnapshot.secret = "Do not use stale credential data"
        model.showEntry(stalePersonalSnapshot)
        try expect(model.filter == .all && model.selectedID == personalHome.id &&
                   model.selectedEntry == model.entries.first { $0.id == personalHome.id },
                   "Opening a provider row explicitly selects its current saved record by ID")
        try expect(model.selectedEntry?.secret == personalHome.secret &&
                   model.entries == entriesBeforeNavigation &&
                   (try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == beforeExplicitNavigation,
                   "Explicit navigation must neither reuse stale caller data nor write the vault")
        model.searchText = "retained query"; model.environmentFilter = "retained environment"
        model.homeScope = .models
        model.showEntry(SecretEntry(name: "Deleted fixture", secret: "fake-only-deleted"))
        try expect(model.filter == .all && model.selectedID == personalHome.id &&
                   model.searchText == "retained query" && model.environmentFilter == "retained environment" &&
                   model.homeScope == .models,
                   "A stale or deleted entry ID must not change navigation or search state")

        model.selectFilter(.home)
        model.addNew()
        model.addCustomCredential()
        try expect(model.presentingEditor && !model.presentingHomeProviderPicker && model.quickAddPreset == nil &&
                   model.editingEntry?.name == "自定义 API" && model.editingEntry?.category == .other &&
                   model.editingEntry?.secret.isEmpty == true && model.editingEntry?.provider.isEmpty == true,
                   "Custom API must bypass the provider picker and open an empty advanced draft")
        try expect(model.entries == entriesBeforeNavigation &&
                   (try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == beforeExplicitNavigation,
                   "Starting a custom draft must not save an incomplete credential")
        model.presentingEditor = false; model.editingEntry = nil
        model.addTool()

        let savedEntries = model.entries
        let savedTools = model.tools
        model.editTool(savedTools[0])
        model.manageLinks(for: savedTools[0])
        model.edit(savedEntries[0])
        model.presentingRestore = true
        model.presentingPasswordChange = true
        model.searchText = "temporary query"
        model.environmentFilter = "staging"
        model.homeScope = .favorites
        model.quickAdd(homePreset)
        model.presentingHomeProviderPicker = true
        model.lock()
        try expect(model.isLocked && model.entries.isEmpty && model.tools.isEmpty, "Lock must clear decrypted entries and tools")
        try expect(model.keychainConfiguration == nil, "Lock must clear decrypted custom platform identifiers and choices")
        try expect(!model.presentingToolSetup && !model.presentingToolEditor && model.editingTool == nil, "Lock must close and clear the tool editor")
        try expect(!model.presentingToolLinks && model.linkingTool == nil, "Lock must close and clear the association sheet")
        try expect(!model.presentingEditor && model.editingEntry == nil, "Lock must close and clear the credential editor")
        try expect(!model.presentingRestore && !model.presentingPasswordChange, "Lock must close backup/password sheets")
        try expect(model.searchText.isEmpty && model.environmentFilter == nil && model.filter == .home &&
                   model.homeScope == .all && model.selectedID == nil,
                   "Lock must reset Home, search, environment, scope and selection")
        try expect(!model.presentingHomeProviderPicker && model.quickAddPreset == nil && model.copyFeedback == nil,
                   "Lock must close quick add and the provider picker and clear copy feedback")
        let lockedFile = try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))
        do {
            try model.saveKeychainConfiguration(keychain)
            throw AppCheckFailure(description: "Locked configuration save unexpectedly succeeded")
        } catch is AppError { }
        try expect(model.keychainConfiguration == nil, "A rejected locked save must not publish decrypted configuration")
        model.addNew(); model.quickAdd(homePreset); model.openAdvancedEntry(homeDraft)
        model.addCustomCredential(); model.showEntry(savedEntries[0])
        try expect(model.isLocked && model.filter == .home && model.selectedID == nil &&
                   !model.presentingHomeProviderPicker && model.quickAddPreset == nil &&
                   !model.presentingEditor && model.editingEntry == nil && model.entries.isEmpty && model.tools.isEmpty,
                   "Locked Home actions must not open drafts, select a record or restore decrypted state")
        try expect((try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))) == lockedFile,
                   "Rejected locked Home actions must not alter the encrypted vault")
        await model.unlock(password: password)
        try expect(model.errorMessage == nil && !model.isLocked, "The same isolated vault must unlock")
        try expect(model.entries == savedEntries, "Unlock must recover saved credentials and their associations exactly")
        try expect(model.tools == savedTools, "Unlock must recover saved tool records exactly")
        try expect(model.keychainConfiguration == keychain, "Password unlock must recover the encrypted keychain choices")
        try expect(model.filter == .home && model.selectedID == nil && model.homeScope == .all &&
                   model.searchText.isEmpty && model.environmentFilter == nil,
                   "Password unlock must open Home with no implicitly selected credential")

        await model.refreshBiometricStatus()
        try expect(model.biometricAvailable && !model.biometricEnabled, "A capable device starts with biometrics disabled")
        await model.enableBiometrics()
        try expect(model.biometricEnabled && biometric.token != nil, "Enrollment stores a token only after an unlocked session")
        model.lock()
        await model.unlockWithBiometrics()
        try expect(!model.isLocked && model.entries == savedEntries && model.tools == savedTools,
                   "Authenticated token must decrypt exactly the same vault")
        try expect(model.keychainConfiguration == keychain, "Biometric token decrypt must retain configuration without hardware access")
        try expect(model.filter == .home && model.selectedID == nil && model.homeScope == .all &&
                   model.searchText.isEmpty && model.environmentFilter == nil,
                   "Biometric unlock must open Home with no implicitly selected credential")
        model.lock()
        let callsAfterLock = biometric.unlockCalls
        await model.prepareAccess()
        try expect(model.isLocked && biometric.unlockCalls == callsAfterLock,
                   "An explicit lock must not immediately trigger an automatic unlock")
        await model.disableBiometrics()
        try expect(biometric.token != nil, "A locked model must not change enrollment")
        biometric.failAuthentication = true
        await model.unlockWithBiometrics()
        try expect(model.isLocked && model.entries.isEmpty && model.biometricMessage != nil,
                   "Failed biometric authentication must leave decrypted state empty")
        biometric.failAuthentication = false
        biometric.delayAuthentication = true
        let pendingUnlock = Task { await model.unlockWithBiometrics() }
        for _ in 0..<100 where !biometric.hasPendingAuthentication { try await Task.sleep(for: .milliseconds(10)) }
        try expect(biometric.hasPendingAuthentication, "The fake authentication callback must be pending")
        model.lock()
        biometric.finishPendingAuthentication()
        await pendingUnlock.value
        try expect(model.isLocked && model.entries.isEmpty && model.tools.isEmpty,
                   "A late biometric callback must never undo a newer lock")
        let cancelledUnlock = Task { await model.unlockWithBiometrics() }
        for _ in 0..<100 where !biometric.hasPendingAuthentication { try await Task.sleep(for: .milliseconds(10)) }
        try expect(biometric.hasPendingAuthentication, "The second callback must be pending before password fallback")
        model.cancelBiometricAuthentication()
        biometric.finishPendingAuthentication()
        await cancelledUnlock.value
        try expect(model.isLocked && model.entries.isEmpty,
                   "A late biometric callback must not unlock after the user switches to password")
        biometric.delayAuthentication = false
        await model.unlock(password: password)
        let replacementPassword = "Keynest-App-Checks-New-2026"
        await model.replacePassword(old: password, new: replacementPassword)
        try expect(model.errorMessage == nil && !model.biometricEnabled && biometric.token == nil,
                   "Changing the main password must revoke the old biometric token")
        model.lock()
        await model.unlock(password: replacementPassword)
        try expect(!model.isLocked && model.entries == savedEntries, "New password must preserve all saved credentials")
        try expect(model.keychainConfiguration == keychain, "Password replacement must retain encrypted keychain choices")
        try expect(model.filter == .home && model.selectedID == nil,
                   "Unlock after changing the password must still default to Home without selection")
        await model.enableBiometrics()
        await model.disableBiometrics()
        try expect(!model.biometricEnabled && biometric.token == nil, "Disabling biometrics must remove its persisted token")

        // A cancelled decrypt must not merge records after its sheet disappears.
        let importPassword = "Fake-Import-Checks-2026"
        let imported = SecretEntry(name: "Cancelled import fixture", secret: "fake-only-import-must-not-leak")
        let importedConfiguration = KeychainConfiguration(charms: [.init(providerID: "anthropic", color: .lavender)])
        let incoming = try VaultCodec.encrypt(VaultDocument(entries: [imported], keychainConfiguration: importedConfiguration),
                                             session: VaultCodec.createSession(password: importPassword))
        let beforeImportEntries = model.entries
        let beforeImportBytes = try Data(contentsOf: directory.appendingPathComponent("vault.keynest"))
        try model.stageImport(incoming)
        let cancelledRestore = Task { await model.restore(password: importPassword) }
        for _ in 0..<1000 {
            if model.busy { break }
            await Task.yield()
        }
        try expect(model.busy, "Restore must reach its asynchronous decryption before cancellation")
        model.cancelRestore()
        await cancelledRestore.value
        try expect(model.entries == beforeImportEntries && !model.presentingRestore && !model.busy,
                   "Cancelling a pending import must leave entries unchanged and its sheet closed")
        try expect(try Data(contentsOf: directory.appendingPathComponent("vault.keynest")) == beforeImportBytes,
                   "Cancelled import must not rewrite encrypted storage")
        try expect(model.errorMessage == nil, "Cancelled import must not post a delayed error")
        try model.stageImport(incoming)
        await model.restore(password: importPassword)
        try expect(model.entries.contains { $0.id == imported.id } && !model.presentingRestore,
                   "A new non-cancelled import must still merge and close successfully")
        try expect(model.keychainConfiguration == keychain, "Merging a backup must retain a local explicit keychain choice")
        try model.saveKeychainConfiguration(.init())
        try model.stageImport(incoming); await model.restore(password: importPassword)
        try expect(model.keychainConfiguration?.charms == [], "Backup merge must not override intentional empty keychain selection")
        try model.saveKeychainConfiguration(nil)
        try model.stageImport(incoming); await model.restore(password: importPassword)
        try expect(model.keychainConfiguration == importedConfiguration, "Without a local override, backup merge adopts the imported choices")
        try model.saveKeychainConfiguration(keychain)

        // Publish one complete, local-only item, using the current record by ID.
        var stale = imported; stale.secret = "stale-do-not-copy"
        model.copySecret(stale)
        try expect(pasteboard.value == imported.secret && pasteboard.writeCount == 1,
                   "Copy must publish the current credential exactly once, not a stale snapshot")
        try expect(pasteboard.options.contains(.currentHostOnly),
                   "Copied credentials must explicitly opt out of Universal Clipboard")
        try expect(pasteboard.types.contains(.string) &&
                   pasteboard.types.contains(.init("org.nspasteboard.ConcealedType")) &&
                   pasteboard.types.contains(.init("org.nspasteboard.TransientType")),
                   "Sensitive markers must accompany the secret in the same publication")
        try expect(model.copyFeedback == .secret(imported.id), "Successful copy should identify the actual record")
        model.lock()
        try expect(pasteboard.value == nil && model.copyFeedback == nil, "Lock must clear an owned copied secret")
        model.copySecret(imported)
        try expect(pasteboard.writeCount == 1, "Locked copy must never republish a supplied credential")
        model.errorMessage = nil
        await model.unlock(password: replacementPassword)
        model.copySecret(imported)
        pasteboard.simulateExternalCopy("unrelated user clipboard")
        model.lock()
        try expect(pasteboard.value == "unrelated user clipboard", "Lock must preserve a later unrelated copy")
        await model.unlock(password: replacementPassword)
        pasteboard.externalCopyDuringWrite = true
        model.copySecret(imported)
        model.lock()
        try expect(pasteboard.value == "external copy during publication",
                   "A competing copy during write must not be mistaken for our owned content")
        pasteboard.externalCopyDuringWrite = false
        await model.unlock(password: replacementPassword)
        pasteboard.failWrite = true
        model.copySecret(imported)
        try expect(model.copyFeedback == nil && model.errorMessage != nil, "Failed clipboard writes must not report success")
        pasteboard.failWrite = false; model.errorMessage = nil

        // Idle expiry uses elapsed monotonic time, independent of wall-clock edits.
        uptime += 599
        model.copySecret(imported)
        try expect(!model.isLocked, "Activity before ten minutes must still succeed")
        let writesBeforeIdle = pasteboard.writeCount
        uptime += 601
        model.copySecret(imported)
        try expect(model.isLocked && pasteboard.value == nil && pasteboard.writeCount == writesBeforeIdle,
                   "An expired session must lock and clear the clipboard before allowing a copy")
        try expect(model.entries.isEmpty && model.tools.isEmpty, "Idle expiry must release decrypted records")

        model.errorMessage = nil
        await model.unlock(password: replacementPassword)
        directorySync.setFailure(true)
        var durableFixture = imported; durableFixture.name = "Committed despite directory sync failure"
        try model.save(durableFixture)
        try expect(model.entries.first(where: { $0.id == imported.id })?.name == durableFixture.name && model.errorMessage != nil,
                   "A committed write with uncertain directory durability must update memory and warn")
        let committed = try VaultCodec.decrypt(Data(contentsOf: directory.appendingPathComponent("vault.keynest")),
                                              password: replacementPassword).document
        try expect(committed.entries == model.entries && committed.tools == model.tools && committed.keychainConfiguration == keychain,
                   "A post-rename sync failure must not leave disk and memory diverged")
        model.errorMessage = nil
        let faultPassword = "Keynest-Sync-Fault-Password-2026"
        await model.replacePassword(old: replacementPassword, new: faultPassword)
        try expect(model.errorMessage != nil && !model.presentingPasswordChange,
                   "A committed password change must close successfully with a durability warning")
        directorySync.setFailure(false)
        model.lock()
        await model.unlock(password: faultPassword)
        try expect(!model.isLocked && model.entries.first(where: { $0.id == imported.id })?.name == durableFixture.name,
                   "The new password must unlock committed data after a post-rename directory sync failure")
        try expect(model.keychainConfiguration == keychain, "Durability-warning saves and rekey must retain keychain choices")

        // A password change can be the first write after a format upgrade.
        // Replace only this already-proven temporary fixture, with no preceding
        // configuration save that could hide a missing rekey backup guard.
        model.lock()
        try expect(try Data(contentsOf: upgradeBackup) == legacyBytes,
                   "Only the known temporary upgrade fixture may be reset for the rekey checks")
        try FileManager.default.removeItem(at: upgradeBackup)
        let legacyRekeyPassword = "Keynest-Legacy-Rekey-Old-2026"
        let nextRekeyPassword = "Keynest-Legacy-Rekey-New-2026"
        let legacyRekeyEntry = SecretEntry(name: "Legacy password upgrade fixture", provider: "OpenAI",
                                          secret: "demo-only-not-a-real-key-password-upgrade")
        let legacyRekeyBytes = try versionThreeFixture(password: legacyRekeyPassword, entries: [legacyRekeyEntry])
        let rekeyStorage = try VaultStorage(directory: directory)
        try rekeyStorage.write(legacyRekeyBytes)
        await model.unlock(password: legacyRekeyPassword)
        try expect(!model.isLocked && model.entries == [legacyRekeyEntry],
                   "The legacy rekey fixture must unlock before any upgraded save")
        await model.enableBiometrics()
        let originalRekeyToken = biometric.token
        try expect(model.biometricEnabled && originalRekeyToken != nil,
                   "The rekey failure fixture uses an in-memory biometric stand-in")

        // A directory at the reserved backup filename deterministically refuses
        // preservation without relying on user permissions or real storage.
        try FileManager.default.createDirectory(at: upgradeBackup, withIntermediateDirectories: false)
        model.presentingPasswordChange = true
        await model.replacePassword(old: legacyRekeyPassword, new: nextRekeyPassword)
        try expect(model.errorMessage != nil && !model.isLocked && !model.busy && model.presentingPasswordChange,
                   "Failed upgrade preservation must keep the unlocked password form available for retry")
        try expect(try rekeyStorage.read() == legacyRekeyBytes,
                   "A password change must not replace legacy ciphertext when its upgrade backup fails")
        try expect(model.entries == [legacyRekeyEntry] && model.keychainConfiguration == nil,
                   "Failed legacy rekey must preserve the in-memory document")
        try expect(biometric.token == originalRekeyToken && model.biometricEnabled,
                   "A rejected upgrade backup must fail before revoking the old biometric token")

        // Re-enrollment exposes a fake token generated from the *current*
        // in-memory session, so this detects an accidental early session switch.
        await model.enableBiometrics()
        guard let unchangedSessionToken = biometric.token else {
            throw AppCheckFailure(description: "The failed-rekey session token is missing")
        }
        let unchangedSession = try VaultCodec.decrypt(legacyRekeyBytes, biometricUnlockData: unchangedSessionToken)
        try expect(unchangedSession.sourceVersion == 3 && unchangedSession.document.entries == [legacyRekeyEntry],
                   "A failed first-write rekey must keep the session capable of decrypting the original vault")

        try FileManager.default.removeItem(at: upgradeBackup)
        model.errorMessage = nil
        await model.replacePassword(old: legacyRekeyPassword, new: nextRekeyPassword)
        try expect(model.errorMessage == nil && !model.isLocked && !model.presentingPasswordChange,
                   "Retrying the first legacy write as a password change must complete after backup recovery")
        let preservedRekeyBytes = try Data(contentsOf: upgradeBackup)
        try expect(preservedRekeyBytes == legacyRekeyBytes,
                   "First-write rekey must preserve the exact original ciphertext, before changing its password")
        let preservedRekey = try VaultCodec.decrypt(preservedRekeyBytes, password: legacyRekeyPassword)
        try expect(preservedRekey.sourceVersion == 3 && preservedRekey.document.entries == [legacyRekeyEntry],
                   "The upgrade backup must retain both its old payload and original password")
        let upgradedRekey = try VaultCodec.decrypt(rekeyStorage.read(), password: nextRekeyPassword)
        try expect(upgradedRekey.sourceVersion == 4 && !upgradedRekey.requiresUpgrade &&
                   upgradedRekey.document.entries == [legacyRekeyEntry],
                   "The new password must decrypt the upgraded document without losing legacy records")
        try expect(biometric.token == nil && !model.biometricEnabled,
                   "A successful first-write rekey must revoke the previous biometric token")
        model.lock()
        await model.unlock(password: nextRekeyPassword)
        try expect(!model.isLocked && model.entries == [legacyRekeyEntry],
                   "The first-write replacement password must survive a lock and fresh unlock")
        try model.saveKeychainConfiguration(.init())
        try expect(try Data(contentsOf: upgradeBackup) == legacyRekeyBytes,
                   "Subsequent saves must not replace the original legacy-rekey backup")
    }
}

@main
private struct AppModelCheckMain {
    @MainActor static func main() async {
        let checks = AppChecks()
        do {
            try await checks.run()
            print("PASS AppModel integration: \(checks.assertions) assertions; isolated temporary vault only.")
            exit(0)
        } catch {
            print("FAIL AppModel integration after \(checks.assertions) assertions: \(error)")
            exit(1)
        }
    }
}
