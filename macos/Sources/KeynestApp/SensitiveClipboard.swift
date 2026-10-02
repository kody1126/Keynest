import AppKit

/// Kept behind a small boundary so checks use an in-memory stand-in, never the
/// user's general pasteboard. Only the main actor operates the clipboard.
protocol VaultPasteboard: AnyObject {
    var changeCount: Int { get }
    func prepareForNewContents(with options: NSPasteboard.ContentsOptions) -> Int
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
    func clearContents() -> Int
}

extension NSPasteboard: VaultPasteboard {}

@MainActor final class SensitiveClipboard {
    private let pasteboard: any VaultPasteboard
    private var ownedChange: Int?
    private var expiry: Task<Void, Never>?
    private var generation = UUID()

    init(pasteboard: any VaultPasteboard = NSPasteboard.general) {
        self.pasteboard = pasteboard
    }

    func copy(_ value: String) -> Bool {
        let item = NSPasteboardItem()
        // Construct every representation before publishing. Clipboard observers
        // must never see the secret first and its sensitive markers later.
        guard item.setString(value, forType: .string),
              item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")),
              item.setData(Data(), forType: .init("org.nspasteboard.TransientType")) else { return false }
        expiry?.cancel(); expiry = nil; ownedChange = nil
        let copiedGeneration = UUID(); generation = copiedGeneration
        let ownership = pasteboard.prepareForNewContents(with: .currentHostOnly)
        guard pasteboard.writeObjects([item]) else { return false }
        // The prepare call establishes this writer's generation. Re-reading
        // after publication could accidentally claim another app's new copy.
        ownedChange = ownership
        expiry = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.generation == copiedGeneration else { return }
                self.clearOwnedContents()
            } catch { }
        }
        return true
    }

    func clearOwnedContents() {
        expiry?.cancel(); expiry = nil
        generation = UUID()
        if let count = ownedChange, pasteboard.changeCount == count { _ = pasteboard.clearContents() }
        ownedChange = nil
    }
}
