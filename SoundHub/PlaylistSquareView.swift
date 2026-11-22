import SwiftUI

/// 独立歌单广场页面：平台切换 + 分类 + 搜索 + 双列网格
struct PlaylistSquareView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var source: SearchProvider = .netease
    @State private var selectedCategory = "全部"
    @State private var playlists: [Playlist] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var searchText = ""
    @State private var searchResults: [Playlist] = []
    @State private var searching = false
    @State private var searchActive = false
    @State private var pageLimit = 30
    @State private var selectedPlaylist: Playlist?
    @State private var loadedOnce = false

    private var providers: [SearchProvider] { platformPrefs.enabledSearchProviders }

    private let categories = [
        "全部", "华语", "流行", "经典", "摇滚", "民谣", "电子", "影视原声", "ACG",
        "怀旧", "欧美", "日韩", "粤语", "古风", "轻音乐", "治愈", "学习", "运动", "夜晚"
    ]

    private var displayPlaylists: [Playlist] { searchActive ? searchResults : playlists }

    var body: some View {
        SoundHubNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.customBackground)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        providerPicker
                        searchField
                        if !searchActive {
                            categoryChips
                        }
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .soundhubScrollIndicatorsHidden()
                .refreshable { await reload(force: true) }
            }
            .navigationTitle(soundhubLocalized("歌单广场", "Playlist Square"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(soundhubLocalized("完成", "Done")) { dismiss() }
                }
            }
        }
        .task {
            guard !loadedOnce else { return }
            loadedOnce = true
            await reload(force: false)
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistView(playlist: playlist)
                .environmentObject(player)
                .environmentObject(auth)
                .environmentObject(theme)
        }
    }

    // MARK: - 子视图

    private var providerPicker: some View {
        HStack(spacing: 8) {
            ForEach(providers) { provider in
                Button {
                    guard source != provider else { return }
                    SoundHubHaptics.tap()
                    source = provider
                    selectedCategory = "全部"
                    playlistCache = [:]
                    Task { await reload(force: true) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: provider.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(LocalizedStringKey(provider.rawValue))
                            .font(SoundHubFont.appFont(13, .semibold))
                    }
                    .foregroundStyle(source == provider ? Color.white : Color.soundhubComment)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        if source == provider {
                            Capsule().fill(provider.tint)
                        } else {
                            Capsule().fill(Color.primary.opacity(0.06))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.soundhubComment)
            TextField(soundhubLocalized("搜索歌单", "Search playlists"), text: $searchText)
                .font(SoundHubFont.appFont(13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            if searching {
                ProgressView().scaleEffect(0.6)
            } else if searchActive || !searchText.isEmpty {
                Button {
                    SoundHubHaptics.tap()
                    searchText = ""
                    searchResults = []
                    searchActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.soundhubComment)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            SoundHubGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        guard selectedCategory != category else { return }
                        SoundHubHaptics.select()
                        selectedCategory = category
                        Task { await reload(force: true) }
                    } label: {
                        Text(category)
                            .font(SoundHubFont.appFont(12, .medium))
                            .foregroundStyle(selectedCategory == category ? Color.white : Color.soundhubLabel)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Capsule().fill(selectedCategory == category ? Color.soundhubHighlight : Color.primary.opacity(0.06))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && displayPlaylists.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let errorText, displayPlaylists.isEmpty {
            VStack(spacing: 10) {
                Text(errorText)
                    .font(SoundHubFont.appFont(13))
                    .foregroundStyle(Color.soundhubComment)
                    .multilineTextAlignment(.center)
                Button(soundhubLocalized("重试", "Retry")) { Task { await reload(force: true) } }
                    .font(SoundHubFont.appFont(13, .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if displayPlaylists.isEmpty {
            EmptyStateView(icon: "music.note.list", text: searchActive
                ? soundhubLocalized("没有找到相关歌单", "No playlists found")
                : soundhubLocalized("歌单广场暂时没有内容", "No playlists available"))
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                ForEach(displayPlaylists) { playlist in
                    Button {
                        SoundHubHaptics.tap()
                        selectedPlaylist = playlist
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CoverImage(url: playlist.coverURL, size: 148, cornerRadius: 16)
                                .frame(maxWidth: .infinity)
                            Text(playlist.name)
                                .font(SoundHubFont.appFont(12, .medium))
                                .foregroundStyle(Color.soundhubLabel)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if playlist.trackCount > 0 {
                                Text(soundhubSongCountText(playlist.trackCount))
                                    .font(SoundHubFont.appFont(11))
                                    .foregroundStyle(Color.soundhubComment)
                                    .lineLimit(1)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            SoundHubGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                    .buttonStyle(GlassPressButtonStyle(scale: 0.97))
                }
            }
            if !searchActive, displayPlaylists.count >= pageLimit {
                Button {
                    pageLimit += 30
                    Task { await reload(force: true) }
                } label: {
                    Text(soundhubLocalized("加载更多", "Load more"))
                        .font(SoundHubFont.appFont(13, .semibold))
                        .foregroundStyle(Color.soundhubHighlight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 数据

    @State private var playlistCache: [String: [Playlist]] = [:]

    @MainActor
    private func reload(force: Bool) async {
        guard !searchActive else { return }
        let key = "\(source.rawValue)|\(selectedCategory)|\(pageLimit)"
        if !force, let cached = playlistCache[key] {
            playlists = cached
            return
        }
        loading = true
        errorText = nil
        do {
            let result: [Playlist]
            switch source {
            case .netease:
                result = try await NetEaseAPI.shared.playlistSquare(cat: selectedCategory, order: "hot", limit: pageLimit)
            case .qq:
                result = try await QQMusicAPI.shared.hotPlaylists(limit: pageLimit)
            case .kugou:
                result = try await KugouMusicAPI.shared.recommendPlaylists(limit: pageLimit)
            }
            playlists = result
            playlistCache[key] = result
        } catch {
            if playlists.isEmpty {
                errorText = error.localizedDescription
            }
        }
        loading = false
    }

    @MainActor
    private func runSearch() async {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            searchActive = false
            searchResults = []
            return
        }
        searchActive = true
        searching = true
        defer { searching = false }
        do {
            switch source {
            case .netease:
                searchResults = try await NetEaseAPI.shared.searchPlaylists(keyword: keyword, limit: 30)
            case .qq:
                searchResults = try await QQMusicAPI.shared.searchPlaylists(keyword: keyword, limit: 30)
            case .kugou:
                searchResults = try await KugouMusicAPI.shared.searchPlaylists(keyword: keyword, limit: 30)
            }
        } catch {
            searchResults = []
        }
    }
}
