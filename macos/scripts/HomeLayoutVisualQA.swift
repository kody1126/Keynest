// Isolated manual visual fixture. Compiled only by build-home-layout-qa.sh.
// Uses production session/layout/rendering and fictional in-memory entries.
import SwiftUI
import AppKit
import KeynestCore

@MainActor final class AppModel: ObservableObject {
    enum CopyFeedback { case secret(UUID) }
    @Published var copyFeedback: CopyFeedback?
}
struct HomeProviderCard: View {
    let group: HomeProviderGroup
    var body: some View { HomeCardDragPresentation(presentation: HomeCardPresentation(group: group, copiedEntryID: nil)) }
}

@MainActor struct HomeLayoutQARoot: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var session = HomeLayoutDragSession()
    @StateObject private var model = AppModel()
    @State private var draft: [String] = []
    @State private var status = "纯虚构数据；可直接鼠标拖动，也可分阶段检查"
    @State private var stepping = false
    @State private var reducedMotion = false
    private let groups: [HomeProviderGroup]
    init() {
        let presets = ["openai", "anthropic", "google", "deepseek", "cloudflare", "github"]
        let entries = presets.enumerated().flatMap { offset, id in
            (0..<(offset % 3 + 1)).map { number in
                let preset = ProviderPreset.match(provider: id)!
                return SecretEntry(name: "演示 \(preset.name) \(number + 1)", category: .ai, provider: preset.name,
                    secret: "demo-only-not-a-real-key-\(offset)-\(number)", baseURL: preset.baseURL,
                    environment: number == 0 ? "开发" : "测试", accountLabel: "虚构账号 \(number + 1)")
            }
        }
        let all = HomeCatalog.groups(entries: entries)
        groups = presets.compactMap { id in all.first { $0.preset?.id == id } }
    }
    var body: some View {
        let displayed = HomeCatalog.ordered(groups, by: session.liveOrder ?? draft)
        VStack(alignment: .leading, spacing: 10) {
            Text("首页实时排序 · 隔离 QA").font(.title2.bold())
            HStack {
                Button("重置") { session.clear(); draft = groups.map(\.id); session.activate(ids: draft); status = "已重置" }
                Button("1 提起第3张") {
                    let source = HomeCatalog.ordered(groups, by: draft)[2]
                    let started = session.qaLift(id: source.id, presentation: HomeCardPresentation(group: source, copiedEntryID: nil),
                        order: draft, colorScheme: colorScheme, reduceMotion: reducedMotion, commit: { draft = $0; status = "已提交到本次 QA 草稿（无文件写入）" })
                    status = started ? "已提起；点击第2步，然后观察让位/占位" : "尚未测量，请重试"
                }.disabled(session.draggedID != nil)
                Button("2 移到第1张并停住") {
                    let target = groups[0].id
                    stepping = true
                    Task { await session.qaMove(over: target); stepping = false; status = "悬停暂停：临时顺序已变，草稿尚未变。可松手或取消。" }
                }.disabled(session.draggedID == nil)
                Button("3 松手") { session.qaRelease() }.disabled(session.draggedID == nil)
                Button("取消本次拖动") { session.cancelDrag(animated: true); status = "撤回本次拖动，保留此前草稿" }
                Button("区域外释放") { session.qaRelease(outside: true); status = "区域外释放，恢复此前草稿" }
            }.disabled(stepping)
            Toggle("分步测试：减少动态效果", isOn: $reducedMotion).disabled(session.draggedID != nil)
            HStack {
                Button("释放后立刻取消：竞态检查") {
                    stepping = true
                    Task {
                        let passed = await session.qaCancelPendingRelease()
                        status = passed ? "PASS：延迟释放被取消，提交次数 0，临时顺序已清理" : "FAIL：请先提起并悬停，再执行检查"
                        stepping = false
                    }
                }.disabled(stepping || session.draggedID == nil)
                Text(session.qaPreviewDescription).font(.caption).accessibilityIdentifier("qa.preview")
            }
            Text(status).font(.callout).accessibilityIdentifier("qa.status")
            Text("草稿：\(names(draft))").font(.caption).accessibilityIdentifier("qa.draft")
            Text("当前显示：\(displayed.map(\.name).joined(separator: " → "))").font(.caption).accessibilityIdentifier("qa.order")
            ScrollView {
                HomeCardLayout {
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, group in
                        HomeLayoutEditingCard(group: group, index: index, count: displayed.count, dragSession: session,
                            move: { offset in
                                session.endDrag()
                                guard let from = draft.firstIndex(of: group.id), draft.indices.contains(from + offset) else { return }
                                draft.swapAt(from, from + offset)
                            }, order: draft, commit: { draft = $0 })
                    }
                }.padding(24)
            }
            .coordinateSpace(name: HomeLayoutGeometry.coordinateSpace)
            .background(HomeLayoutViewportBridge(session: session).allowsHitTesting(false))
            .onPreferenceChange(HomeLayoutCardFrames.self) { session.updateCardFrames($0) }
            .onPreferenceChange(HomeLayoutCardBodyFrames.self) { session.updateCardBodyFrames($0) }
        }
        .padding(18).frame(minWidth: 1100, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { HomeLayoutPreviewBridge(session: session).allowsHitTesting(false).accessibilityHidden(true) }
        .environmentObject(model)
        .onAppear { draft = groups.map(\.id); session.activate(ids: draft) }
        .onDisappear { session.clear() }
    }
    private func names(_ ids: [String]) -> String {
        ids.compactMap { id in groups.first { $0.id == id }?.name }.joined(separator: " → ")
    }
}

@MainActor final class HomeLayoutQADelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1180, height: 820),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Keynest Live Layout QA — 虚构数据 / 无密钥库"
        window.contentView = NSHostingView(rootView: HomeLayoutQARoot())
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct HomeLayoutVisualQA {
    static func main() {
        let app = NSApplication.shared
        let delegate = HomeLayoutQADelegate()
        app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
