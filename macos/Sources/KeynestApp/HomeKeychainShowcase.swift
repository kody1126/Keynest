import SwiftUI

/// A local, decorative object. It never receives a credential or clipboard action.
struct HomeKeychainShowcase: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var resetToken = 0
    let onCollapse: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(RadialGradient(colors: [Color.cyan.opacity(colorScheme == .dark ? 0.10 : 0.075), .clear],
                                     center: .center, startRadius: 20, endRadius: 420))

            KeychainSceneView(brandIDs: ["openai", "anthropic", "google"],
                              isActive: scenePhase == .active, resetToken: resetToken)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            VStack {
                HStack(alignment: .center) {
                    Label("Keynest 钥匙串", systemImage: "link")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { resetToken += 1 } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 24, height: 24)
                    }
                    .help("复位钥匙串")
                    .accessibilityLabel("复位钥匙串")
                    .accessibilityIdentifier("keynest.home.keychain.reset")
                    Button(action: onCollapse) {
                        Image(systemName: "chevron.up")
                            .frame(width: 24, height: 24)
                    }
                    .help("收起钥匙串")
                    .accessibilityLabel("收起钥匙串")
                    .accessibilityIdentifier("keynest.home.keychain.collapse")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(reduceMotion ? "拖动挂件 · 已减少动态效果" : "拖动挂件，松手让它轻轻摆动")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keynest.home.keychain")
    }
}
