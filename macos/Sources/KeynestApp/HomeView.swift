import SwiftUI
import AppKit
import KeynestCore

/// The daily-use surface. Every copy action belongs to an explicit credential;
/// the three-column library remains available for detail and maintenance.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool
    private let columns = [GridItem(.adaptive(minimum: 285, maximum: 430), spacing: 16, alignment: .top)]
    private let suggestionColumns = [GridItem(.adaptive(minimum: 190), spacing: 10)]

    private var suggestions: [ProviderPreset] {
        let saved = Set(model.entries.compactMap { ProviderPreset.match(provider: $0.provider)?.id })
        if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(ProviderPreset.all.filter { !saved.contains($0.id) && $0.matches(search: model.searchText) }.prefix(12))
        }
        let common = ["openai", "anthropic", "google", "deepseek", "qwen", "kimi", "doubao", "openrouter",
                      "tavily", "firecrawl", "github", "cloudflare", "notion", "elevenlabs", "supabase", "resend"]
        return Array(common.compactMap { id in ProviderPreset.all.first { $0.id == id && !saved.contains(id) } }.prefix(8))
    }

    var body: some View {
        let groups = HomeCatalog.groups(entries: model.entries, tools: model.tools,
                                        query: model.searchText, scope: model.homeScope)
        let recommended = suggestions
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.entries.isEmpty {
                HStack(spacing: 16) {
                    Picker("首页筛选", selection: $model.homeScope) {
                        ForEach(HomeScope.allCases) { scope in Text(scope.title).tag(scope) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 390)
                    .accessibilityIdentifier("keynest.home.scope")
                    Spacer(minLength: 0)
                    Text("\(groups.count) 个平台 · \(groups.reduce(0) { $0 + $1.entries.count }) 把密钥")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }.padding(.horizontal, 28).padding(.bottom, 18)
            }
            Divider().overlay(.primary.opacity(0.02))
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !groups.isEmpty {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(groups) { group in HomeProviderCard(group: group) }
                        }
                        .accessibilityIdentifier("keynest.home.saved")
                    } else if !model.entries.isEmpty {
                        emptyResults
                    }
                    if !recommended.isEmpty {
                        suggestedPlatforms(recommended)
                    } else if model.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("没有找到这个平台").font(.headline)
                            Text("自建服务也能收藏，填写自己的名称和 API 地址即可。")
                                .foregroundStyle(.secondary)
                            Button("添加自定义 API", action: model.addCustomCredential)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
                        Text("也可以按工具，把多把密钥放在一起。")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("选择工具模板…", action: model.addTool).buttonStyle(.borderless)
                            .accessibilityIdentifier("keynest.home.templates")
                    }
                    .padding(.top, 3)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: 1380, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.homeSearchFocusRequest, initial: true) { _, request in
            guard request > 0 else { return }
            searchFocused = true
            model.homeSearchFocusRequest = 0
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.entries.isEmpty ? "保存第一把 API 密钥" : "你的 API 密钥")
                        .font(.system(size: 27, weight: .semibold))
                    Text(model.entries.isEmpty ? "选一个平台，粘贴密钥。下次打开就能直接复制。" : "找到平台，复制需要的那把密钥。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Label("本机加密", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 7)
            }
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(model.entries.isEmpty ? "搜索你要添加的平台" : "搜索平台、密钥名称、账号或环境", text: $model.searchText)
                    .textFieldStyle(.plain).font(.body).focused($searchFocused)
                    .accessibilityLabel("搜索密钥与平台")
                    .accessibilityIdentifier("keynest.home.search")
                if !model.searchText.isEmpty {
                    Button { model.searchText = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除首页搜索")
                } else {
                    Text("⌘F").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(searchFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: searchFocused ? 2 : 0.5))
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
    }

    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.homeScope == .favorites && model.searchText.isEmpty ? "把常用的密钥放在这里" : "没有找到已保存的密钥",
                  systemImage: model.homeScope == .favorites ? "star" : "magnifyingglass")
                .font(.headline)
            Text(model.homeScope == .favorites && model.searchText.isEmpty ? "在密钥的更多菜单中选择“加入常用”，下次更快找到。" : "试试平台、账号、环境或工具名称，也可以切换到全部。")
                .font(.callout).foregroundStyle(.secondary)
            Button("查看全部已保存密钥") { model.homeScope = .all; model.searchText = "" }
                .buttonStyle(.borderless)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func suggestedPlatforms(_ presets: [ProviderPreset]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.entries.isEmpty ? "从一个平台开始" : "添加其他平台").font(.headline)
                    Text("选择平台后粘贴你自己的密钥。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("全部 \(ProviderPreset.all.count) 个平台") { model.presentingHomeProviderPicker = true }
                    .buttonStyle(.borderless).accessibilityIdentifier("keynest.home.providers")
            }
            LazyVGrid(columns: suggestionColumns, alignment: .leading, spacing: 10) {
                ForEach(presets) { preset in
                    Button { model.quickAdd(preset) } label: {
                        HStack(spacing: 10) {
                            ProviderIcon(preset: preset, size: 32)
                            Text(preset.name).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle").font(.body).foregroundStyle(.tint)
                        }
                        .padding(13).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain).help("添加 \(preset.name) 的密钥")
                    .accessibilityLabel("添加 \(preset.name) 的密钥")
                    .accessibilityIdentifier("keynest.home.add.\(preset.id)")
                }
            }
        }
    }
}
