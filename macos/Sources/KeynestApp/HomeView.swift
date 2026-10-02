import SwiftUI
import AppKit
import KeynestCore

/// The daily-use surface. Every copy action belongs to an explicit credential;
/// the three-column library remains available for detail and maintenance.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var visibleProviderLimit = 80
    @State private var paginationQuery = ""
    @State private var paginationScope = HomeScope.all
    private let providerBatchSize = 80
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
        let visibleLimit = paginationQuery == model.searchText && paginationScope == model.homeScope
            ? visibleProviderLimit : providerBatchSize
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.entries.isEmpty {
                HStack(spacing: 16) {
                    Picker("首页筛选", selection: $model.homeScope) {
                        ForEach(HomeScope.allCases) { scope in Text(scope.title).tag(scope) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 350)
                    .accessibilityIdentifier("keynest.home.scope")
                    Spacer(minLength: 0)
                    Text("\(groups.count) 个平台 · \(groups.reduce(0) { $0 + $1.entries.count }) 把密钥")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                .frame(maxWidth: 1380)
                .padding(.horizontal, 24).padding(.bottom, 16)
            }
            Divider().overlay(.primary.opacity(0.02))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !groups.isEmpty {
                            HomeCardLayout {
                                ForEach(groups.prefix(visibleLimit)) { group in HomeProviderCard(group: group) }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("keynest.home.saved")
                            // Custom Layout measures its children eagerly. Bound the
                            // initial work for large custom catalogs; search above
                            // still includes the entire vault before this slice.
                            if groups.count > visibleLimit {
                                HStack {
                                    Text("已显示 \(visibleLimit) / \(groups.count) 个平台")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("显示更多平台") {
                                        paginationQuery = model.searchText
                                        paginationScope = model.homeScope
                                        visibleProviderLimit = visibleLimit + providerBatchSize
                                    }
                                        .accessibilityIdentifier("keynest.home.loadMore")
                                }
                            }
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
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id("keynest.home.results")
                }
                .onChange(of: model.searchText) { _, _ in
                    resetPagination()
                    proxy.scrollTo("keynest.home.results", anchor: .top)
                }
                .onChange(of: model.homeScope) { _, _ in
                    resetPagination()
                    proxy.scrollTo("keynest.home.results", anchor: .top)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.homeSearchFocusRequest, initial: true) { _, request in
            guard request > 0 else { return }
            searchFocused = true
            model.homeSearchFocusRequest = 0
        }
    }

    private func resetPagination() {
        visibleProviderLimit = providerBatchSize
        paginationQuery = model.searchText
        paginationScope = model.homeScope
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.entries.isEmpty ? "保存第一把 API 密钥" : "你的 API 密钥")
                    .font(.system(size: 24, weight: .semibold))
                Text(model.entries.isEmpty ? "选一个平台，粘贴密钥。下次直接复制。" : "找到平台，复制需要的那把密钥。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            searchField
                .frame(width: 280)
        }
        .frame(maxWidth: 1380, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 18)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(model.entries.isEmpty ? "搜索平台" : "搜索平台或密钥", text: $model.searchText)
                .textFieldStyle(.plain).font(.callout).focused($searchFocused)
                .accessibilityLabel("搜索密钥与平台")
                .help("搜索平台、密钥名称、账号、环境或工具 · ⌘F")
                .accessibilityIdentifier("keynest.home.search")
            if !model.searchText.isEmpty {
                Button { model.searchText = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除首页搜索")
            } else {
                Text("⌘F").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(searchFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: searchFocused ? 2 : 0.5))
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
