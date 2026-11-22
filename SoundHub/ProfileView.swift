import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// 自动下载新版 IPA 的结果
enum DownloadOutcome {
    case success(fileName: String)
    case failure(message: String)
}

struct ProfileView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @AppStorage("soundhub.themeMode") private var themeModeRaw = SoundHubThemeMode.system.rawValue
    @AppStorage("soundhub.uiStyle") private var uiStyleRaw = SoundHubUIStyle.liquid.rawValue
    @AppStorage("soundhub.homeHeaderHideSort") private var homeHeaderHideSort = false
    @AppStorage("soundhub.pauseHomeRendering") private var homeRenderingPaused = false

    @State private var showHistory = false

    /// 统一账号登录面板（网易云 + QQ 音乐整合）
    @State private var showAccountHub = false
    /// 设置页（外观 + 歌词翻译等）
    @State private var showSettings = false
    @State private var showSectionSort = false
    /// 我的界面板块顺序（账号 / 关于，可自定义）
    @State private var profileOrder = SectionOrderStore.load(SectionOrderStore.profileKey, defaults: SectionOrderStore.profileDefaults)
    /// 手动检查更新
    @State private var checkingUpdate = false
    @State private var updateResult: UpdateChecker.CheckResult?
    @State private var showUpdateResult = false
    /// 自动下载新版 IPA
    @ObservedObject private var ipaDownloader = IPADownloader.shared
    @State private var showDownloadOverlay = false
    @State private var downloadOutcome: DownloadOutcome?
    @State private var showDownloadOutcome = false
    @State private var pendingUpdateInfo: UpdateChecker.ReleaseInfo?
    @State private var updateShareFile: ShareFileItem?
    @State private var updateShareFileURL: URL?
    @State private var didRefreshProfileAccount = false
    @State private var donationExpanded = false
    @State private var showWeChatOpenError = false
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @AppStorage("soundhub.language") private var languageRaw = AppLanguage.chinese.rawValue

    private var themeMode: SoundHubThemeMode {
        SoundHubThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var isNativeClean: Bool {
        SoundHubUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var isEnglish: Bool { languageRaw == AppLanguage.english.rawValue }

    private var displayPlatformSummary: String {
        if !isEnglish { return platformPrefs.summaryText }
        return platformPrefs.enabledSearchProviders.map { provider in
            switch provider {
            case .netease: return "NetEase Cloud Music"
            case .qq: return "QQ Music"
            case .kugou: return "Kugou Music"
            }
        }.joined(separator: " / ")
    }

    private var appVersionText: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
        return "SoundHub · \(ver)"
    }

    /// 登录状态的合并提示（展示各平台真实昵称）
    private var accountStatusLine: String {
        var parts: [String] = []
        if platformPrefs.isEnabled(SearchProvider.netease), auth.isLoggedIn {
            if let nick = auth.user?.nickname, !nick.isEmpty {
                parts.append("网易云音乐 \(nick)")
            } else {
                parts.append("网易云音乐 UID \(auth.user?.uid ?? 0)")
            }
        }
        if platformPrefs.isEnabled(SearchProvider.qq), qqAuth.isLoggedIn {
                parts.append(qqAuth.nickname.isEmpty ? (isEnglish ? "QQ Music Logged In" : "QQ 已登录") : qqAuth.nickname)
        }
        if platformPrefs.isEnabled(SearchProvider.kugou), kugouAuth.isLoggedIn {
                parts.append(kugouAuth.nickname.isEmpty ? (isEnglish ? "Kugou Music Logged In" : "酷狗已登录") : kugouAuth.nickname)
        }
        if parts.isEmpty {
            return isEnglish ? "Sign in to sync \(displayPlatformSummary) playlists" : "登录后可同步 \(platformPrefs.summaryText) 歌单"
        }
        return parts.joined(separator: " · ")
    }

    private var hasVisibleAccountLogin: Bool {
        (platformPrefs.isEnabled(SearchProvider.netease) && auth.isLoggedIn)
            || (platformPrefs.isEnabled(SearchProvider.qq) && qqAuth.isLoggedIn)
            || (platformPrefs.isEnabled(SearchProvider.kugou) && kugouAuth.isLoggedIn)
    }

    /// 顶部标题 + 右上角设置齿轮
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("我的")
                    .font(SoundHubFont.appFont(30, .bold))
                    .foregroundStyle(Color.soundhubLabel)
            Text(isEnglish ? "\(displayPlatformSummary) account and appearance settings" : "\(platformPrefs.summaryText) 账号与外观设置")
                    .font(SoundHubFont.appFont(13))
                    .foregroundStyle(Color.soundhubComment)
            }
            Spacer()
            HStack(spacing: 10) {
                if !homeHeaderHideSort {
                    GlassIconButton(systemName: "arrow.up.arrow.down", forceLiquid: isNativeClean) {
                        SoundHubHaptics.tap()
                        showSectionSort = true
                    }
                }
                GlassIconButton(systemName: "gearshape.fill", forceLiquid: true) {
                    SoundHubHaptics.tap()
                    homeRenderingPaused = true
                    showSettings = true
                }
            }
        }
        .padding(.top, 8)
    }

    private var appleHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                Text("我的")
                    .font(SoundHubFont.appFont(38, .bold))
                    .foregroundStyle(Color.soundhubLabel)
                Spacer(minLength: 12)
                if !homeHeaderHideSort {
                    GlassIconButton(systemName: "arrow.up.arrow.down", forceLiquid: isNativeClean) {
                        SoundHubHaptics.tap()
                        showSectionSort = true
                    }
                }
                GlassIconButton(systemName: "gearshape", forceLiquid: true) {
                    SoundHubHaptics.tap()
                    homeRenderingPaused = true
                    showSettings = true
                }
            }
            Text(LocalizedStringKey(accountStatusLine))
                .font(SoundHubFont.appFont(12, .medium))
                .foregroundStyle(Color.soundhubComment)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            Rectangle()
                .fill(Color.soundhubLabel.opacity(0.10))
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    var body: some View {
        let _ = theme.accent
        ZStack {
            // 页面背景：同步开启时显示壁纸/背景色，否则默认氛围渐变
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            // 实例级 UITabBar 清透风格（固定全透明，无需调节）
            TabBarAppearanceConfigurator()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: isNativeClean ? 26 : 22) {
                    if isNativeClean {
                        appleHeader
                    } else {
                        header
                    }
                    // 板块按用户自定义顺序渲染（可拖拽排序）
                    ForEach(profileOrder, id: \.self) { key in
                        switch key {
                        case "账号":
                            userCard
                        case "关于":
                            EmptyView()
                        default:
                            EmptyView()
                        }
                    }
                    // 更新入口固定放在“我的”页面最底部，避免被板块排序隐藏。
                    updateLinkCard
                    communityCard
                    donationCard
                    profileVersionFooter
                }
                .padding(.horizontal, isNativeClean ? 24 : 16)
                .padding(.top, isNativeClean ? 14 : 8)
                .padding(.bottom, 190)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .soundhubScrollIndicatorsHidden()
        }
        .task {
            guard !didRefreshProfileAccount else { return }
            didRefreshProfileAccount = true
            await auth.refreshAccount()
            if qqAuth.isLoggedIn {
                await qqAuth.fetchVIPStatus()
            }
        }
        .background {
            HighRefreshConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .alert("无法打开微信", isPresented: $showWeChatOpenError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请使用微信扫描上方二维码完成赞助。")
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(player)
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showAccountHub) {
            AccountHubSheet()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(player)
                .environmentObject(auth)
                .ignoresSafeArea(.all)
        }
        .sheet(isPresented: $showSectionSort) {
            SectionOrderSheet(
                title: "我的板块排序",
                sections: SectionOrderStore.profileDefaults,
                order: $profileOrder,
                platformOrder: Binding(
                    get: { platformPrefs.orderedRaw },
                    set: { platformPrefs.orderedRaw = $0 }
                )
            )
                .onDisappear { SectionOrderStore.save(SectionOrderStore.profileKey, profileOrder) }
        }
        .sheet(item: $updateShareFile, onDismiss: cleanupUpdateShareFile) { item in
            ShareSheet(items: [item.url])
        }
        .alert("检查更新", isPresented: $showUpdateResult, presenting: updateResult) { result in
            switch result {
            case .update(let info):
                Button("立即更新") { UIApplication.shared.open(info.htmlURL) }
                Button("取消", role: .cancel) {}
            case .upToDate:
                Button("好", role: .cancel) {}
            case .failed:
                Button("好", role: .cancel) {}
            }
        } message: { result in
            switch result {
            case .update(let info):
                Text("发现新版本 \(info.version)，是否前往 GitHub 下载更新？")
            case .upToDate:
                Text("当前已是最新版本 \(UpdateChecker.currentVersion)")
            case .failed:
                Text("检查失败，请检查网络后重试")
            }
        }
        .overlay {
            if showDownloadOverlay { downloadProgressOverlay }
        }
        .alert("下载新版", isPresented: $showDownloadOutcome, presenting: downloadOutcome) { outcome in
            switch outcome {
            case .success:
                Button("好", role: .cancel) {}
            case .failure:
                Button("好", role: .cancel) {}
                Button("前往更新页") {
                    if let info = pendingUpdateInfo {
                        UIApplication.shared.open(info.htmlURL)
                    }
                }
            }
        } message: { outcome in
            switch outcome {
            case .success(let fileName):
                Text("新版 IPA 已下载完成，但未能打开分享面板。\n文件名：\(fileName)")
            case .failure(let message):
                Text("下载失败：\(message)")
            }
        }
    }

    /// 下载进度浮层（居中卡片，兼容所有系统版本）
    private var downloadProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.soundhubHighlight)
                    Text("正在下载新版 IPA")
                        .font(SoundHubFont.appFont(15, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                }
                if ipaDownloader.progress >= 0 {
                    ProgressView(value: ipaDownloader.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.soundhubAmber)
                    Text("\(Int(ipaDownloader.progress * 100))%")
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                } else {
                    ProgressView()
                        .tint(Color.soundhubAmber)
                    Text("正在获取更新…")
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                }
                EmptyView()
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .soundhubCardShadow(radius: 12, y: 6)
            .padding(32)
        }
        .transition(.opacity)
    }

    private var userCard: some View {
        VStack(spacing: 16) {
            Button {
                SoundHubHaptics.tap()
                // 统一账号面板：网易云 + QQ 音乐登录整合在一起
                showAccountHub = true
            } label: {
                HStack(spacing: 14) {
                    // 头像：主题渐变描边环
                    AsyncImage(url: auth.user?.avatarURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.soundhubComment)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .background(Color.soundhubGlassFill, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(auth.user?.nickname ?? (auth.isLoggedIn ? (isEnglish ? "NetEase Cloud Music Logged In" : "网易云音乐已登录") : (isEnglish ? "Guest · Tap to Sign In" : "免登录 · 点击登录")))
                                .font(SoundHubFont.appFont(20, .bold))
                                .foregroundStyle(Color.soundhubLabel)
                                .lineLimit(1)
                            if auth.isLoggedIn, let badge = auth.user?.vipBadge {
                                VIPBadgeView(text: badge)
                            }
                        }
                        Text(accountStatusLine)
                            .font(SoundHubFont.appFont(12, .regular, .monospaced))
                            .foregroundStyle(Color.soundhubComment)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.soundhubComment.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if (platformPrefs.isEnabled(SearchProvider.netease) && auth.isLoggedIn)
                || (platformPrefs.isEnabled(SearchProvider.qq) && qqAuth.isLoggedIn)
                || (platformPrefs.isEnabled(SearchProvider.kugou) && kugouAuth.isLoggedIn) {
                platformStatusRow
            }
        }
        .padding(16)
        .background {
                        SoundHubGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .soundhubCardShadow(radius: 10, y: 4)
    }

    /// 每个登录平台单独展示登录成功状态（网易云 / QQ 音乐）
    private var platformStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if platformPrefs.isEnabled(SearchProvider.netease), auth.isLoggedIn {
                platformChip(imageName: "BrandNetease", name: "网易云音乐", status: auth.user?.nickname ?? "已登录", badge: auth.user?.vipBadge)
            }
            if platformPrefs.isEnabled(SearchProvider.qq), qqAuth.isLoggedIn {
                platformChip(imageName: "BrandQQ", name: "QQ 音乐", status: qqAuth.nickname.isEmpty ? "已登录" : qqAuth.nickname, badge: qqAuth.vipBadge)
            }
            if platformPrefs.isEnabled(SearchProvider.kugou), kugouAuth.isLoggedIn {
                platformChip(imageName: "BrandKugou", name: "酷狗音乐", status: kugouAuth.nickname.isEmpty ? "已登录" : kugouAuth.nickname, badge: kugouAuth.vipBadge)
            }
        }
        .padding(.top, 2)
    }

    private func platformChip(imageName: String, name: String, status: String, badge: String?) -> some View {
        HStack(spacing: 6) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(name)
                .font(SoundHubFont.appFont(12, .semibold))
                .foregroundStyle(Color.soundhubLabel)
            Text(status)
                .font(SoundHubFont.appFont(11))
                .foregroundStyle(Color.soundhubComment)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let badge {
                VIPBadgeView(text: badge)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background { SoundHubSurface(shape: Capsule()) }
    }



    /// 壁纸格子：点击应用为当前背景；使用中的壁纸显示主题色边框+勾选；右上角删除
    private func wallpaperCell(path: String) -> some View {
        let isActive = path == theme.backgroundImagePath
        return ZStack(alignment: .topTrailing) {
            Button {
                SoundHubHaptics.tap()
                theme.applyWallpaper(at: path)
            } label: {
                Group {
                    if let img = SoundHubImageFileCache.image(at: path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.soundhubGlassFill
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.soundhubAmber)
                            .background { SoundHubSurface(shape: Circle()) }
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                SoundHubHaptics.medium()
                theme.deleteWallpaper(at: path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.soundhubComment)
                    .frame(width: 28, height: 28)
                    .background { SoundHubSurface(shape: Circle()) }
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .zIndex(2)
        }
    }

    /// 功能宫格：常用功能统一整合排版
    private var featuresGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的功能")
            VStack(spacing: 12) {
                featureCell(icon: "clock.arrow.circlepath", title: "播放历史", subtitle: String(format: NSLocalizedString("最近播放 %d 首", comment: ""), player.history.count)) {
                    showHistory = true
                }
                featureCell(icon: hasVisibleAccountLogin ? "checkmark.seal.fill" : "globe", title: isEnglish ? "Accounts and Sign-in" : "账号与登录", subtitle: hasVisibleAccountLogin ? accountStatusLine : (isEnglish ? "Sign in to \(displayPlatformSummary)" : "登录 \(platformPrefs.summaryText)")) {
                    SoundHubHaptics.tap()
                    showAccountHub = true
                }
            }
        }
    }

    private func featureCell(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundHubHaptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.soundhubAmber)
                    .frame(width: 34, height: 34)
                    .background(Color.soundhubGlassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(SoundHubFont.appFont(14, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background {
                                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private func startAutoDownload(info: UpdateChecker.ReleaseInfo, assetURL: URL) {
        showDownloadOverlay = true
        Task {
            do {
                let url = try await ipaDownloader.download(assetURL: assetURL, version: info.version)
                await MainActor.run {
                    showDownloadOverlay = false
                    updateShareFileURL = url
                    updateShareFile = ShareFileItem(url: url)
                }
            } catch {
                await MainActor.run {
                    showDownloadOverlay = false
                    downloadOutcome = .failure(message: error.localizedDescription)
                    showDownloadOutcome = true
                }
            }
        }
    }

    private func cleanupUpdateShareFile() {
        guard let url = updateShareFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        updateShareFile = nil
        updateShareFileURL = nil
    }

    /// 更新地址 + 检查更新（GitHub 项目，可点击交互）
    private var updateLinkCard: some View {
        VStack(spacing: 0) {
            Button {
                SoundHubHaptics.tap()
                if let url = URL(string: "https://github.com/qiangnanbie/SoundHub") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.soundhubHighlight)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("更新地址")
                            .font(SoundHubFont.appFont(14, .semibold))
                            .foregroundStyle(Color.soundhubLabel)
                        Text("GitHub：qiangnanbie/SoundHub")
                            .font(SoundHubFont.appFont(11))
                            .foregroundStyle(Color.soundhubComment)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.soundhubComment)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(Color.soundhubComment.opacity(0.16))
                .padding(.horizontal, 16)

            Button {
                SoundHubHaptics.tap()
                guard !checkingUpdate else { return }
                checkingUpdate = true
                Task {
                    let result = await UpdateChecker.checkNow()
                    await MainActor.run {
                        checkingUpdate = false
                        updateResult = result
                        if case .update(let info) = result {
                            pendingUpdateInfo = info
                            if let assetURL = info.assetURL {
                                startAutoDownload(info: info, assetURL: assetURL)
                            } else {
                                showUpdateResult = true
                            }
                        } else {
                            showUpdateResult = true
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: checkingUpdate ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.soundhubHighlight)
                        .frame(width: 26)
                        .rotationEffect(.degrees(checkingUpdate ? 360 : 0))
                        .animation(checkingUpdate ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: checkingUpdate)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(checkingUpdate ? "正在检查…" : "检查更新")
                            .font(SoundHubFont.appFont(14, .semibold))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            .disabled(checkingUpdate)
        }
        .background {
            SoundHubGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .soundhubCardShadow(radius: 9, y: 3)
    }

    /// 我的页底部交流群入口
    private var communityCard: some View {
        Button {
            SoundHubHaptics.tap()
            if let url = URL(string: "https://t.me/SoundHub888") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.soundhubHighlight)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("交流群")
                        .font(SoundHubFont.appFont(14, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Text("点击跳转 Telegram")
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.soundhubComment)
            }
            .padding(16)
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
        .soundhubCardShadow(radius: 9, y: 3)
    }

    private var profileVersionFooter: some View {
        Text(appVersionText)
            .font(SoundHubFont.appFont(11))
            .foregroundStyle(Color.soundhubComment.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    /// 我的页底部赞助入口与赞助排行榜
    private var donationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    donationExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.soundhubAmber)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自愿赞助")
                            .font(SoundHubFont.appFont(16, .bold))
                            .foregroundStyle(Color.soundhubLabel)
                        Text(donationExpanded ? "点击收起赞助信息" : "点击展开赞助信息")
                            .font(SoundHubFont.appFont(11))
                            .foregroundStyle(Color.soundhubComment)
                    }
                    Spacer()
                    Image(systemName: donationExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.soundhubComment)
                }
            }
            .buttonStyle(.plain)

            if donationExpanded {
                Image("DonationQR")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.soundhubComment.opacity(0.14), lineWidth: 0.8)
                }

                Button {
                    openWeChatPayment()
                } label: {
                    Label("打开微信", systemImage: "arrow.up.forward.app")
                        .font(SoundHubFont.appFont(13, .semibold))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.soundhubAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.98))

                VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("赞助人员")
                        .font(SoundHubFont.appFont(15, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    Text("按金额排序")
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                }

                ForEach(displayedDonors.indices, id: \.self) { index in
                    let donor = displayedDonors[index]
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(SoundHubFont.appFont(13, .bold))
                            .foregroundStyle(index == 0 ? Color.soundhubAmber : Color.soundhubComment)
                            .frame(width: 24, height: 24)
                            .background(
                                (index == 0 ? Color.soundhubAmber : Color.soundhubComment).opacity(index == 0 ? 0.16 : 0.08),
                                in: Circle()
                            )
                        Text(donor.name)
                            .font(SoundHubFont.appFont(13, .medium))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                        Text(String(format: "¥ %.2f", donor.amount))
                            .font(SoundHubFont.appFont(13, .semibold))
                            .foregroundStyle(index == 0 ? Color.soundhubAmber : Color.soundhubLabel)
                    }
                    if index < displayedDonors.count - 1 {
                        Divider().overlay(Color.soundhubComment.opacity(0.12))
                    }
                }
                }
            }
        }
        .padding(16)
        .background {
            SoundHubGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .soundhubCardShadow(radius: 9, y: 3)
    }

    private func openWeChatPayment() {
        guard let paymentURL = URL(string: "wxp://f2f03Cvy7dWnLLRbIhQJqY-MxVACiIS4JBNSui8VmUk3_Qg") else {
            showWeChatOpenError = true
            return
        }

        UIApplication.shared.open(paymentURL, options: [:]) { opened in
            guard !opened, let weChatURL = URL(string: "weixin://") else { return }
            UIApplication.shared.open(weChatURL, options: [:]) { openedWeChat in
                if !openedWeChat {
                    showWeChatOpenError = true
                }
            }
        }
    }

    private var displayedDonors: [Donor] {
        Self.donors
    }

    private struct Donor {
        let name: String
        let amount: Double
    }

    private static let donors: [Donor] = [
        Donor(name: "WeChat", amount: 26.66),
        Donor(name: "Aert", amount: 8.88),
        Donor(name: "wxx", amount: 5),
        Donor(name: "！", amount: 3),
    ]
}

// MARK: - 交流群二维码

struct CommunityQRSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SoundHubNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                VStack(spacing: 18) {
                    Image("CommunityQR")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.soundhubComment.opacity(0.16), lineWidth: 0.8)
                        }
                        .padding(.horizontal, 24)
                    Text("扫码加入交流群")
                        .font(SoundHubFont.appFont(15, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Text("如二维码过期，可在 GitHub 或更新说明中获取最新入口")
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .padding(.vertical, 22)
            }
            .navigationTitle("交流群")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(SoundHubSheetModifier(detents: [.medium, .large]))
    }
}

// MARK: - 统一账号登录面板（网易云 + QQ 音乐整合）

struct AccountHubSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @AppStorage("soundhub.language") private var languageRaw = AppLanguage.chinese.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var showNeteaseLogin = false
    @State private var showQQLogin = false
    @State private var showKugouLogin = false
    @State private var confirmNeteaseLogout = false
    @State private var confirmQQLogout = false
    @State private var confirmKugouLogout = false

    private var isEnglish: Bool { languageRaw == AppLanguage.english.rawValue }
    private var displayPlatformSummary: String {
        if !isEnglish { return platformPrefs.summaryText }
        return platformPrefs.enabledSearchProviders.map { provider in
            switch provider {
            case .netease: return "NetEase Cloud Music"
            case .qq: return "QQ Music"
            case .kugou: return "Kugou Music"
            }
        }.joined(separator: " / ")
    }

    var body: some View {
        SoundHubNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "账号")
                        if platformPrefs.isEnabled(SearchProvider.netease) { neteaseCard }
                        if platformPrefs.isEnabled(SearchProvider.qq) { qqCard }
                        if platformPrefs.isEnabled(SearchProvider.kugou) { kugouCard }
                        Text(isEnglish ? "Sign in to \(displayPlatformSummary) to sync playlists and improve playback availability" : "\(platformPrefs.summaryText) 登录后可同步歌单并提升可播成功率")
                            .font(SoundHubFont.appFont(11))
                            .foregroundStyle(Color.soundhubComment)
                            .padding(.horizontal, 4)
                    }
                    .padding(16)
                }
                .soundhubScrollIndicatorsHidden()
            }
            .navigationTitle("账号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showNeteaseLogin) {
            LoginView()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showQQLogin) {
            QQLoginSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showKugouLogin) {
            KugouLoginSheet()
                .environmentObject(theme)
        }
        .confirmationDialog("退出网易云登录？", isPresented: $confirmNeteaseLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                auth.logout()
                WebLoginDataCleaner.clearNetEase()
                ToastCenter.shared.show("已退出网易云账号")
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("退出 QQ 音乐？", isPresented: $confirmQQLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                qqAuth.logout()
                WebLoginDataCleaner.clearQQMusic()
                ToastCenter.shared.show("已退出 QQ 音乐")
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("退出酷狗音乐？", isPresented: $confirmKugouLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                kugouAuth.logout()
                WebLoginDataCleaner.clearKugou()
                ToastCenter.shared.show("已退出酷狗音乐")
            }
            Button("取消", role: .cancel) {}
        }
    }

    /// 网易云账号卡片
    private var neteaseCard: some View {
        Button {
            SoundHubHaptics.tap()
            if auth.isLoggedIn { confirmNeteaseLogout = true } else { showNeteaseLogin = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image("BrandNetease")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("网易云音乐")
                        .font(SoundHubFont.appFont(15, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    HStack(spacing: 6) {
                        Group {
                            if auth.isLoggedIn {
                                Text(auth.user?.nickname ?? NSLocalizedString("已登录", comment: ""))
                            } else {
                                Text(LocalizedStringKey("未登录 · 扫码登录同步歌单"))
                            }
                        }
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        if auth.isLoggedIn, let badge = auth.user?.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(auth.isLoggedIn ? "退出" : "登录")
                    .font(SoundHubFont.appFont(13, .medium))
                    .foregroundStyle(auth.isLoggedIn ? Color.red : Color.soundhubAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background { SoundHubSurface(shape: Capsule()) }
            }
            .padding(14)
            .background {
                                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    /// QQ 音乐账号卡片
    private var qqCard: some View {
        Button {
            SoundHubHaptics.tap()
            if qqAuth.isLoggedIn { confirmQQLogout = true } else { showQQLogin = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image("BrandQQ")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("QQ 音乐")
                        .font(SoundHubFont.appFont(15, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    HStack(spacing: 6) {
                        Group {
                            if qqAuth.isLoggedIn {
                                Text(qqAuth.nickname.isEmpty ? NSLocalizedString("已登录", comment: "") : qqAuth.nickname)
                            } else {
                                Text(LocalizedStringKey("未登录 · 网页 / 扫码 / Cookie 登录"))
                            }
                        }
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        if qqAuth.isLoggedIn, let badge = qqAuth.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(qqAuth.isLoggedIn ? "退出" : "登录")
                    .font(SoundHubFont.appFont(13, .medium))
                    .foregroundStyle(qqAuth.isLoggedIn ? Color.red : Color.soundhubAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background { SoundHubSurface(shape: Capsule()) }
            }
            .padding(14)
            .background {
                                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private var kugouCard: some View {
        Button {
            SoundHubHaptics.tap()
            if kugouAuth.isLoggedIn { confirmKugouLogout = true } else { showKugouLogin = true }
        } label: {
            HStack(spacing: 14) {
                Image("BrandKugou")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color(red: 0.08, green: 0.43, blue: 1.0).opacity(0.22), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("酷狗音乐")
                        .font(SoundHubFont.appFont(15, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    HStack(spacing: 6) {
                        Group {
                            if kugouAuth.isLoggedIn {
                                Text(kugouAuth.nickname.isEmpty ? NSLocalizedString("已登录", comment: "") : kugouAuth.nickname)
                            } else {
                                Text(LocalizedStringKey("未登录 · App 扫码同步歌单"))
                            }
                        }
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        if kugouAuth.isLoggedIn, let badge = kugouAuth.vipBadge {
                            VIPBadgeView(text: badge)
                        }
                    }
                }
                Spacer()
                Text(kugouAuth.isLoggedIn ? "退出" : "登录")
                    .font(SoundHubFont.appFont(13, .medium))
                    .foregroundStyle(kugouAuth.isLoggedIn ? Color.red : Color.soundhubAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background { SoundHubSurface(shape: Capsule()) }
            }
            .padding(14)
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

}

// MARK: - 设置页（外观 + 歌词翻译，从「我的」右上角齿轮进入）

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared
    @State private var showAccountCenter = false
    @State private var platformDisplayExpanded = false
    @AppStorage("soundhub.immersiveDetail") private var immersiveDetail = true
    @AppStorage("soundhub.lockScreenImmersiveCover") private var lockScreenImmersiveCover = true
    @AppStorage("soundhub.disableLiquid") private var disableLiquidMode = false
    @AppStorage("soundhub.tabIconStyle") private var tabIconStyle = "sfSymbols"
    @AppStorage("soundhub.liquidTintHex") private var liquidTintHex = ""
    @AppStorage("soundhub.globalParticleStyle") private var globalParticleStyle = "off"
    @AppStorage("soundhub.dailyRecommendLegacy") private var dailyRecommendLegacy = false
    @AppStorage("soundhub.hideSponsor") private var hideSponsor = true
    @AppStorage("soundhub.playbackSourceMode") private var playbackSourceMode = "auto"
    @AppStorage("soundhub.quality.byNetwork") private var qualityByNetwork = false
    @AppStorage("soundhub.quality.wifi") private var wifiQualityRaw = SoundHubAudioQuality.hires.rawValue
    @AppStorage("soundhub.quality.cellular") private var cellularQualityRaw = SoundHubAudioQuality.exhigh.rawValue
    @AppStorage("soundhub.playback.autoSwitchPlatform") private var autoSwitchPlatform = true
    @State private var showFeedbackSheet = false
    @State private var showDisclaimerSheet = false
    @State private var showEnvironmentSheet = false
    @State private var sourceQualityExpanded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("soundhub.themeMode") private var themeModeRaw = SoundHubThemeMode.system.rawValue
    @AppStorage("soundhub.language") private var languageRaw = AppLanguage.chinese.rawValue
    @AppStorage("soundhub.homeWallpaperBlur") private var homeWallpaperBlur = 0.0
    /// 底栏是否显示文字（关闭后只显示图标）
    @AppStorage("soundhub.tabLabelsVisible") private var tabLabelsVisible = true
    @AppStorage("soundhub.legacyTabCornerRadius") private var legacyTabCornerRadius = 32.0
    @AppStorage("soundhub.legacyTabWidth") private var legacyTabWidth = 356.0
    @AppStorage("soundhub.legacyTabOffsetX") private var legacyTabOffsetX = 0.0
    @AppStorage("soundhub.legacyTabOffsetY") private var legacyTabOffsetY = 0.0
    /// 第三方音源播放会员歌成功时提醒，默认开启
    @AppStorage("soundhub.showThirdPartyVIPNotice") private var showThirdPartyVIPNotice = true
    @AppStorage("soundhub.showSongVIPBadge") private var showSongVIPBadge = true
    /// 高刷新率请求，默认开启
    @AppStorage("soundhub.enableHighRefresh") private var enableHighRefresh = true
    @AppStorage("soundhub.audio.mixothers.v1") private var mixesWithOthers = false
    @AppStorage("soundhub.audioQuality") private var playbackAudioQualityRaw = SoundHubAudioQuality.hires.rawValue
    @AppStorage(SoundHubHaptics.enabledKey) private var hapticsEnabled = true
    @AppStorage("soundhub.playback.autoResumeLast") private var autoResumeLastPlayback = false
    @AppStorage("soundhub.labelColorHex") private var labelColorHex = ""
    @AppStorage("soundhub.homeGreetingText") private var homeGreetingText = ""
    @AppStorage("soundhub.homeGreetingSize") private var homeGreetingSize = 30.0
    @AppStorage("soundhub.homeGreetingHeight") private var homeGreetingHeight = 0.0
    @AppStorage("soundhub.homeGreetingColorHex") private var homeGreetingColorHex = ""
    @AppStorage("soundhub.homeGreetingLine1Size") private var homeGreetingLine1Size = 0.0
    @AppStorage("soundhub.homeGreetingLine2Size") private var homeGreetingLine2Size = 0.0
    @AppStorage("soundhub.homeGreetingLine3Size") private var homeGreetingLine3Size = 0.0
    @AppStorage("soundhub.homeGreetingLine1ColorHex") private var homeGreetingLine1ColorHex = ""
    @AppStorage("soundhub.homeGreetingLine2ColorHex") private var homeGreetingLine2ColorHex = ""
    @AppStorage("soundhub.homeGreetingLine3ColorHex") private var homeGreetingLine3ColorHex = ""
    @AppStorage("soundhub.homeGreetingLine1OffsetY") private var homeGreetingLine1OffsetY = 0.0
    @AppStorage("soundhub.homeGreetingLine2OffsetY") private var homeGreetingLine2OffsetY = 0.0
    @AppStorage("soundhub.homeGreetingLine3OffsetY") private var homeGreetingLine3OffsetY = 0.0
    @AppStorage("soundhub.homeGreetingLine1GradientStartHex") private var homeGreetingLine1GradientStartHex = ""
    @AppStorage("soundhub.homeGreetingLine2GradientStartHex") private var homeGreetingLine2GradientStartHex = ""
    @AppStorage("soundhub.homeGreetingLine3GradientStartHex") private var homeGreetingLine3GradientStartHex = ""
    @AppStorage("soundhub.homeGreetingLine1GradientEndHex") private var homeGreetingLine1GradientEndHex = ""
    @AppStorage("soundhub.homeGreetingLine2GradientEndHex") private var homeGreetingLine2GradientEndHex = ""
    @AppStorage("soundhub.homeGreetingLine3GradientEndHex") private var homeGreetingLine3GradientEndHex = ""
    @AppStorage("soundhub.homeGreetingGlowEnabled") private var homeGreetingGlowEnabled = false
    @AppStorage("soundhub.homeGreetingGlowIntensity") private var homeGreetingGlowIntensity = 0.45
    @AppStorage("soundhub.homeGreetingUnderline") private var homeGreetingUnderline = false
    @AppStorage("soundhub.homeGreetingGradient") private var homeGreetingGradient = false
    @AppStorage("soundhub.homeGreetingGradientStartHex") private var homeGreetingGradientStartHex = ""
    @AppStorage("soundhub.homeGreetingGradientEndHex") private var homeGreetingGradientEndHex = ""
    @AppStorage("soundhub.homeGreetingFont") private var homeGreetingFontName = ""
    @AppStorage("soundhub.pauseHomeRendering") private var homeRenderingPaused = false
    @AppStorage("soundhub.homeHideUsername") private var homeHideUsername = false
    @AppStorage("soundhub.homeHeaderHideSort") private var homeHeaderHideSort = false
    @AppStorage("soundhub.homeHeaderHideRefresh") private var homeHeaderHideRefresh = true
    @AppStorage(PlatformPreferenceStore.hidePickerKey) private var hidePlatformPicker = false
    @ObservedObject private var sourceStore = UnblockSourceStore.shared
    @ObservedObject private var equalizer = SoundHubEqualizer.shared
    @AppStorage(ThirdPartyAudioQuality.storageKey) private var thirdPartyAudioQualityRaw = ThirdPartyAudioQuality.kb320.rawValue
    @State private var appearanceExpanded = false
    @State private var platformExpanded = false
    @State private var playbackExpanded = false
    @State private var showWallpaperPicker = false
    @State private var wallpaperAppearanceTarget: SoundHubWallpaperAppearance = .light
    @State private var showFontImporter = false
    @State private var showGreetingFontImporter = false
    /// 更新日志
    @State private var showChangelog = false
    @State private var backupDoc: BackupDocument?
    @State private var showExportBackup = false
    @State private var showRestorePicker = false
    @State private var pendingRestore: [String: Any]?
    @State private var showRestoreConfirm = false
    @State private var showSourceManager = false
    @State private var showEqualizer = false
    @State private var backupExpanded = false
    @State private var backupIncludeAccounts = false
    @State private var backupIncludeWallpapers = false
    @State private var backupMessage: String?
    /// 日志
    @State private var showLogViewer = false

    private var themeMode: SoundHubThemeMode {
        SoundHubThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var customSourceCount: Int {
        sourceStore.managementVisibleSources.count
    }

    private var thirdPartyAudioQualityOptions: [ThirdPartyAudioQuality] {
        let options = sourceStore.availableThirdPartyQualities()
        return options.isEmpty ? ThirdPartyAudioQuality.allCases : options
    }

    private var thirdPartyAudioQualitySelection: Binding<ThirdPartyAudioQuality> {
        Binding(
            get: {
                let stored = ThirdPartyAudioQuality(sourceValue: thirdPartyAudioQualityRaw) ?? .kb320
                return thirdPartyAudioQualityOptions.first(where: { $0 == stored }) ?? thirdPartyAudioQualityOptions.first ?? .kb320
            },
            set: { newValue in
                thirdPartyAudioQualityRaw = newValue.rawValue
            }
        )
    }

    private var thirdPartyAudioQualityTitle: String {
        soundhubLocalized("第三方音源音质", "Third-party source quality")
    }

    private var thirdPartyAudioQualityHint: String {
        soundhubLocalized("会优先按所选音质解析第三方音源，不可用时会自动降级。", "Third-party sources will try the selected quality first and downgrade automatically when unavailable.")
    }

    private var thirdPartyAudioQualityOptionsSignature: String {
        thirdPartyAudioQualityOptions.map(\.rawValue).joined(separator: ",")
    }

    private func normalizeThirdPartyAudioQualitySelection() {
        let valid = thirdPartyAudioQualityOptions.first(where: { $0.rawValue == thirdPartyAudioQualityRaw }) ?? thirdPartyAudioQualityOptions.first ?? .kb320
        if valid.rawValue != thirdPartyAudioQualityRaw {
            thirdPartyAudioQualityRaw = valid.rawValue
        }
    }

    private var playbackAudioQualitySelection: Binding<SoundHubAudioQuality> {
        Binding(
            get: { SoundHubAudioQuality(rawValue: playbackAudioQualityRaw) ?? .hires },
            set: { playbackAudioQualityRaw = $0.rawValue }
        )
    }

    private var playbackQualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.soundhubAmber)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(soundhubLocalized("播放音质", "Playback quality"))
                        .font(SoundHubFont.appFont(14, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Text(soundhubLocalized("按列表选择，无法使用时会由平台自动降级。", "Choose a quality below; the platform will downgrade automatically when unavailable."))
                        .font(SoundHubFont.appFont(10))
                        .foregroundStyle(Color.soundhubComment)
                        .lineLimit(1)
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SoundHubAudioQuality.allCases) { quality in
                        let selected = playbackAudioQualitySelection.wrappedValue == quality
                        Button {
                            playbackAudioQualitySelection.wrappedValue = quality
                            SoundHubHaptics.select()
                        } label: {
                            HStack(spacing: 5) {
                                Text(quality.displayName)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .font(SoundHubFont.appFont(12, selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.soundhubAmber : Color.soundhubLabel)
                            .padding(.horizontal, 12)
                            .frame(height: 31)
                            .background {
                                Capsule()
                                    .fill(selected ? Color.soundhubAmber.opacity(0.14) : Color.soundhubLabel.opacity(0.055))
                            }
                            .overlay {
                                Capsule()
                                    .strokeBorder(selected ? Color.soundhubAmber.opacity(0.42) : Color.soundhubLabel.opacity(0.08), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var homeGreetingLines: [String] {
        let custom = homeGreetingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty { return ["自动问候"] }
        return custom.components(separatedBy: .newlines)
    }

    private func greetingLineSizeBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                switch index {
                case 0: return homeGreetingLine1Size > 0 ? homeGreetingLine1Size : homeGreetingSize
                case 1: return homeGreetingLine2Size > 0 ? homeGreetingLine2Size : homeGreetingSize
                default: return homeGreetingLine3Size > 0 ? homeGreetingLine3Size : homeGreetingSize
                }
            },
            set: { value in
                switch index {
                case 0: homeGreetingLine1Size = value
                case 1: homeGreetingLine2Size = value
                default: homeGreetingLine3Size = value
                }
            }
        )
    }

    private func greetingLineColorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let raw: String
                switch index {
                case 0: raw = homeGreetingLine1ColorHex
                case 1: raw = homeGreetingLine2ColorHex
                default: raw = homeGreetingLine3ColorHex
                }
                return Color(hex: raw) ?? (Color(hex: homeGreetingColorHex) ?? Color.soundhubLabel)
            },
            set: { color in
                let hex = color.hexString
                switch index {
                case 0: homeGreetingLine1ColorHex = hex
                case 1: homeGreetingLine2ColorHex = hex
                default: homeGreetingLine3ColorHex = hex
                }
            }
        )
    }

    private func greetingLineOffsetBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                switch index {
                case 0: return homeGreetingLine1OffsetY
                case 1: return homeGreetingLine2OffsetY
                default: return homeGreetingLine3OffsetY
                }
            },
            set: { value in
                switch index {
                case 0: homeGreetingLine1OffsetY = value
                case 1: homeGreetingLine2OffsetY = value
                default: homeGreetingLine3OffsetY = value
                }
            }
        )
    }

    private func greetingLineGradientStartBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let raw: String
                switch index {
                case 0: raw = homeGreetingLine1GradientStartHex
                case 1: raw = homeGreetingLine2GradientStartHex
                default: raw = homeGreetingLine3GradientStartHex
                }
                return Color(hex: raw) ?? (Color(hex: homeGreetingGradientStartHex) ?? Color.soundhubLabel)
            },
            set: { color in
                switch index {
                case 0: homeGreetingLine1GradientStartHex = color.hexString
                case 1: homeGreetingLine2GradientStartHex = color.hexString
                default: homeGreetingLine3GradientStartHex = color.hexString
                }
            }
        )
    }

    private func greetingLineGradientEndBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let raw: String
                switch index {
                case 0: raw = homeGreetingLine1GradientEndHex
                case 1: raw = homeGreetingLine2GradientEndHex
                default: raw = homeGreetingLine3GradientEndHex
                }
                return Color(hex: raw) ?? (Color(hex: homeGreetingGradientEndHex) ?? Color.soundhubLabel)
            },
            set: { color in
                switch index {
                case 0: homeGreetingLine1GradientEndHex = color.hexString
                case 1: homeGreetingLine2GradientEndHex = color.hexString
                default: homeGreetingLine3GradientEndHex = color.hexString
                }
            }
        )
    }

    private func resetGreetingLineStyle(_ index: Int) {
        switch index {
        case 0:
            homeGreetingLine1Size = 0
            homeGreetingLine1ColorHex = ""
            homeGreetingLine1OffsetY = 0
            homeGreetingLine1GradientStartHex = ""
            homeGreetingLine1GradientEndHex = ""
        case 1:
            homeGreetingLine2Size = 0
            homeGreetingLine2ColorHex = ""
            homeGreetingLine2OffsetY = 0
            homeGreetingLine2GradientStartHex = ""
            homeGreetingLine2GradientEndHex = ""
        default:
            homeGreetingLine3Size = 0
            homeGreetingLine3ColorHex = ""
            homeGreetingLine3OffsetY = 0
            homeGreetingLine3GradientStartHex = ""
            homeGreetingLine3GradientEndHex = ""
        }
    }

    var body: some View {
        SoundHubNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        accountPlatformSection
                        themeSection
                        sourceQualitySection
                        playbackSection
                        equalizerSection
                        changelogSection
                        supportSection
                        backupSection
                        logSection
                        footerNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
                .soundhubScrollIndicatorsHidden()
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(themeMode.colorScheme)
        .onAppear {
            wallpaperAppearanceTarget = colorScheme == .dark ? .dark : .light
        }
        .sheet(isPresented: $showWallpaperPicker) {
            WallpaperPhotoPicker { data in
                theme.addWallpaper(data, for: wallpaperAppearanceTarget.colorScheme)
                SoundHubHaptics.success()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAccountCenter) {
            AccountCenterView()
                .environmentObject(auth)
                .environmentObject(theme)
        }
        .fullScreenCover(isPresented: $showFontImporter) {
            FontDocumentPicker { url in
                installFont(from: url)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showGreetingFontImporter) {
            FontDocumentPicker { url in
                installGreetingFont(from: url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogListView()
                .environmentObject(theme)
        }
        .fileExporter(
            isPresented: $showExportBackup,
            document: backupDoc,
            contentType: .json,
            defaultFilename: "SoundHub设置备份-\(Self.backupDateString())"
        ) { result in
            switch result {
            case .success:
                backupMessage = "配置备份已导出"
                ToastCenter.shared.show("配置备份已导出")
            case .failure(let error):
                backupMessage = "导出失败：\(error.localizedDescription)"
                ToastCenter.shared.show("导出失败")
            }
        }
        .sheet(isPresented: $showLogViewer) {
            LogViewerSheet(importedText: nil)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showFeedbackSheet) {
            infoSheet(title: "问题反馈", body: "遇到问题时请附上复现步骤与截图，反馈到 GitHub Issues：\nhttps://github.com/qiangnanbie/SoundHub/issues")
        }
        .sheet(isPresented: $showDisclaimerSheet) {
            infoSheet(title: "免责声明", body: infoSheetText.disclaimer)
        }
        .sheet(isPresented: $showEnvironmentSheet) {
            infoSheet(title: "运行环境", body: infoSheetText.environment)
        }
        .sheet(isPresented: $showSourceManager) {
            ThirdPartySourceManagerSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerSettingsView()
                .environmentObject(theme)
        }
        .fullScreenCover(isPresented: $showRestorePicker) {
            BackupDocumentPicker { url in
                handleBackupImport(url)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("导入备份将覆盖当前部分设置，是否继续？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("恢复", role: .destructive) {
                applyRestore(pendingRestore)
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            homeRenderingPaused = true
        }
        .onDisappear {
            homeRenderingPaused = false
        }
    }

    /// 主题相关设置统一归组，避免平台和排行榜外观选项散落在设置页。
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            appearanceSection
        }
    }

    /// 校验扩展名并安装字体（asCopy 返回的 URL 已在沙盒内，可直接读取）
    private func installFont(from url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            ToastCenter.shared.show("请选择 ttf / otf 字体文件")
            return
        }
        if let name = FontManager.install(from: url) {
            SoundHubHaptics.success()
            ToastCenter.shared.show("字体已应用：\(name)")
        } else {
            ToastCenter.shared.show("字体安装失败，请使用 ttf / otf 文件")
        }
    }

    private func installGreetingFont(from url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            ToastCenter.shared.show("请选择 ttf / otf 字体文件")
            return
        }
        if let name = FontManager.installGreeting(from: url) {
            homeGreetingFontName = name
            SoundHubHaptics.success()
            ToastCenter.shared.show("主页问候字体已应用：\(name)")
        } else {
            ToastCenter.shared.show("主页问候字体安装失败，请使用 ttf / otf 文件")
        }
    }

    /// 账号与平台
    private var accountPlatformSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("账号与平台")
                .font(SoundHubFont.appFont(12, .semibold))
                .foregroundStyle(Color.soundhubComment)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Button {
                    SoundHubHaptics.tap()
                    showAccountCenter = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubHighlight)
                            .frame(width: 28)
                        Text("账号登录")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                        Text(platformPrefs.summaryText)
                            .font(SoundHubFont.appFont(11))
                            .foregroundStyle(Color.soundhubComment)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.soundhubComment.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.99))

                Divider().opacity(0.25).padding(.leading, 54)

                Button {
                    SoundHubHaptics.select()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        platformDisplayExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubHighlight)
                            .frame(width: 28)
                        Text("平台显示")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                        Image(systemName: platformDisplayExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.soundhubComment.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.99))

                if platformDisplayExpanded {
                    PlatformPreferencePicker()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// 外观设置（原「我的」页外观折叠内容）
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 外观设置行：点击展开 / 收起全部外观设置
            Button {
                SoundHubHaptics.select()
                withAnimation(.easeInOut(duration: 0.25)) {
                    appearanceExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    Text("主题模式")
                        .font(SoundHubFont.appFont(15))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    Image(systemName: appearanceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.soundhubComment.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background {
                                        SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if appearanceExpanded {
            VStack(alignment: .leading, spacing: 14) {
                Picker("主题模式", selection: $themeModeRaw) {
                    ForEach(SoundHubThemeMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("语言", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.soundhubAmber)

                Toggle(isOn: $tabLabelsVisible) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("底栏显示文字")
                                .font(SoundHubFont.appFont(15))
                                .foregroundStyle(Color.soundhubLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Toggle(isOn: $immersiveDetail) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text("沉浸详情界面")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Toggle(isOn: $lockScreenImmersiveCover) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.rectangle.stack")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text("锁屏沉浸封面")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Toggle(isOn: $disableLiquidMode) {
                    HStack(spacing: 12) {
                        Image(systemName: "drop.halffull")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text("关闭液态模式")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                pickerRow(title: "底栏图标样式", icon: "square.grid.2x2", selection: $tabIconStyle, options: [
                    ("appleMusic", "Apple Music"), ("sfSymbols", "SF Symbols"), ("rounded", "圆润样式")
                ])

                pickerRow(title: "全局漂浮特效", icon: "sparkles", selection: $globalParticleStyle, options: [
                    ("off", "关闭"), ("snow", "雪花"), ("text", "文字 / Emoji")
                ])

                Toggle(isOn: $dailyRecommendLegacy) {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text("每日推荐使用旧版样式")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Toggle(isOn: $hideSponsor) {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.slash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text("隐藏自愿赞助")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Toggle(isOn: $showSongVIPBadge) {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示歌曲 VIP 图标")
                                .font(SoundHubFont.appFont(15))
                                .foregroundStyle(Color.soundhubLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                if #unavailable(iOS 26) {
                    legacyTabBarSettings

                    Divider().overlay(Color.soundhubComment.opacity(0.15))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text("全局 UI 样式")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                    }
                    Picker("全局 UI 样式", selection: Binding(
                        get: { theme.uiStyle },
                        set: { theme.setUIStyle($0) }
                    )) {
                        ForEach(SoundHubUIStyle.allCases, id: \.self) { style in
                            Text(LocalizedStringKey(style.title)).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                HStack {
                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    Text("自定义强调色")
                        .font(SoundHubFont.appFont(15))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { theme.customAccent ?? Color.soundhubAmber },
                        set: { theme.setCustomAccent($0.hexString) }
                    ))
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    Button {
                        theme.clearCustomAccent()
                        SoundHubHaptics.select()
                    } label: {
                        Text("恢复预设")
                            .font(SoundHubFont.appFont(13, .medium))
                            .foregroundStyle(Color.soundhubAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background { SoundHubSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                            Text(LocalizedStringKey(theme.customAccentHex == nil ? "使用预设主题" : "已自定义"))
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                }

                    Divider().overlay(Color.soundhubComment.opacity(0.15))

                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text(soundhubLocalized("主页背景色", "Home Background Color"))
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                    }
                    Picker(soundhubLocalized("背景模式", "Background Mode"), selection: $wallpaperAppearanceTarget) {
                        ForEach(SoundHubWallpaperAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.soundhubAmber)
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text(soundhubLocalized("背景颜色", "Background Color"))
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { theme.customBackground(for: wallpaperAppearanceTarget.colorScheme) ?? Color.soundhubBackground },
                            set: { theme.setBackground($0.hexString, for: wallpaperAppearanceTarget.colorScheme) }
                        ))
                        .labelsHidden()
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Button {
                            showWallpaperPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("上传壁纸（可多张）")
                                    .font(SoundHubFont.appFont(15))
                                    .foregroundStyle(Color.soundhubLabel)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.soundhubAmber)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    // 壁纸库：所有已上传壁纸，点击即应用为当前背景
                    if !theme.wallpaperPaths.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(theme.wallpaperPaths, id: \.self) { path in
                                wallpaperCell(path: path, appearance: wallpaperAppearanceTarget)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.soundhubComment)
                            Text("还没有壁纸，上传后会显示在这里")
                                .font(SoundHubFont.appFont(12))
                                .foregroundStyle(Color.soundhubComment)
                            Spacer()
                        }
                    }
                    HStack(spacing: 12) {
                        if theme.customBackgroundImage(for: wallpaperAppearanceTarget.colorScheme) != nil {
                            Button {
                                theme.clearBackgroundImage(for: wallpaperAppearanceTarget.colorScheme)
                                SoundHubHaptics.select()
                            } label: {
                                Text("清除当前背景")
                                    .font(SoundHubFont.appFont(13, .medium))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background { SoundHubSurface(shape: Capsule()) }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                            Text(LocalizedStringKey(theme.customBackgroundImage(for: wallpaperAppearanceTarget.colorScheme) == nil ? "当前：默认背景" : "当前：已应用壁纸"))
                            .font(SoundHubFont.appFont(12))
                            .foregroundStyle(Color.soundhubComment)
                    }
                Toggle(isOn: Binding(
                    get: { theme.backgroundSyncAll },
                    set: { theme.setBackgroundSyncAll($0) }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.soundhubAmber)
                        Text(LocalizedStringKey("同步到搜索 / 音乐库 / 我的"))
                            .font(SoundHubFont.appFont(13))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                HStack {
                    Button {
                        theme.setBackground("")
                        SoundHubHaptics.select()
                    } label: {
                        Text("恢复默认背景")
                            .font(SoundHubFont.appFont(13, .medium))
                            .foregroundStyle(Color.soundhubAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        .background { SoundHubSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                HStack {
                    Image(systemName: "text.quote")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    Text("注释文字颜色")
                        .font(SoundHubFont.appFont(15))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: {
                            if let raw = UserDefaults.standard.string(forKey: "soundhub.commentColorHex"),
                               let c = Color(hex: raw) { return c }
                            return Color.soundhubComment
                        },
                        set: { UserDefaults.standard.set($0.hexString, forKey: "soundhub.commentColorHex") }
                    ))
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    Button {
                        UserDefaults.standard.removeObject(forKey: "soundhub.commentColorHex")
                        SoundHubHaptics.select()
                    } label: {
                        Text("恢复默认")
                            .font(SoundHubFont.appFont(13, .medium))
                            .foregroundStyle(Color.soundhubAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        .background { SoundHubSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(LocalizedStringKey("全 App 说明文字颜色"))
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                }

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                HStack {
                    Image(systemName: "house.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    Text("主文字颜色")
                        .font(SoundHubFont.appFont(15))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: {
                            if let c = Color(hex: labelColorHex) { return c }
                            return Color.soundhubLabel
                        },
                        set: {
                            labelColorHex = $0.hexString
                            theme.objectWillChange.send()
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    Button {
                        labelColorHex = ""
                        theme.objectWillChange.send()
                        SoundHubHaptics.select()
                    } label: {
                        Text("恢复默认")
                            .font(SoundHubFont.appFont(13, .medium))
                            .foregroundStyle(Color.soundhubAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        .background { SoundHubSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(LocalizedStringKey("全 App 主文字颜色"))
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                }

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                // Greeting customization was removed; retain only wallpaper controls below.
                if false {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "text.badge.star")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text("主页问候文字")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: homeGreetingColorHex) ?? Color.soundhubLabel },
                            set: { homeGreetingColorHex = $0.hexString }
                        ), supportsOpacity: false)
                        .labelsHidden()
                    }

                    HStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text("主页壁纸模糊度")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                        Text("\(Int(homeWallpaperBlur))")
                            .font(SoundHubFont.appFont(12))
                            .foregroundStyle(Color.soundhubComment)
                    }
                    Slider(value: $homeWallpaperBlur, in: 0...30, step: 1)
                        .tint(Color.soundhubAmber)
                    TextEditor(text: $homeGreetingText)
                        .font(SoundHubFont.appFont(15))
                        .frame(minHeight: 88, maxHeight: 180)
                        .padding(6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            if homeGreetingText.isEmpty {
                                Text(LocalizedStringKey("留空自动显示早上好/下午好/晚上好"))
                                    .font(SoundHubFont.appFont(13))
                                    .foregroundStyle(Color.soundhubComment.opacity(0.8))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                    VStack(spacing: 8) {
                        HStack {
                            Text("文字大小")
                            Spacer()
                            Text("\(Int(homeGreetingSize))")
                                .foregroundStyle(Color.soundhubComment)
                        }
                        Slider(value: $homeGreetingSize, in: 20...64, step: 1)
                        HStack {
                            Text("标题区高度")
                            Spacer()
                            Text(homeGreetingHeight <= 0 ? "自动" : "\(Int(homeGreetingHeight))")
                                .foregroundStyle(Color.soundhubComment)
                        }
                        Slider(value: $homeGreetingHeight, in: 0...260, step: 1)
                    }
                    .font(SoundHubFont.appFont(12))
                    .foregroundStyle(Color.soundhubLabel)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("开启文字背景发光", isOn: $homeGreetingGlowEnabled)
                        HStack {
                            Text("发光强度")
                            Spacer()
                            Text("\(Int(homeGreetingGlowIntensity * 100))%")
                                .foregroundStyle(Color.soundhubComment)
                        }
                        Slider(value: $homeGreetingGlowIntensity, in: 0...2, step: 0.01)
                            .tint(Color.soundhubAmber)
                            .disabled(!homeGreetingGlowEnabled)
                    }
                    .font(SoundHubFont.appFont(12))
                    .foregroundStyle(Color.soundhubLabel)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "textformat")
                                .foregroundStyle(Color.soundhubAmber)
                            Text("问候语专属字体")
                            Spacer()
                            Text(LocalizedStringKey(homeGreetingFontName.isEmpty ? "跟随全局" : "已设置"))
                                .foregroundStyle(Color.soundhubComment)
                        }
                        HStack(spacing: 10) {
                            Button {
                                showGreetingFontImporter = true
                            } label: {
                                Label("选择字体", systemImage: "text.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.soundhubAmber)
                            if !homeGreetingFontName.isEmpty {
                                Button("清除专属字体") {
                                    FontManager.clearGreeting()
                                    homeGreetingFontName = ""
                                    SoundHubHaptics.select()
                                }
                                .buttonStyle(.bordered)
                                .tint(Color.soundhubComment)
                            }
                        }
                        Text("仅主页问候语使用该字体；清除后跟随全局字体，没有全局字体时使用系统字体。")
                            .font(SoundHubFont.appFont(11))
                            .foregroundStyle(Color.soundhubComment)
                    }
                    .font(SoundHubFont.appFont(12))
                    .foregroundStyle(Color.soundhubLabel)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("显示底部横线", isOn: $homeGreetingUnderline)
                        Toggle("开启上下渐变字", isOn: $homeGreetingGradient)
                        if homeGreetingGradient {
                            ColorPicker("渐变起始颜色", selection: Binding(
                                get: { Color(hex: homeGreetingGradientStartHex) ?? (Color(hex: homeGreetingColorHex) ?? Color.soundhubLabel) },
                                set: { homeGreetingGradientStartHex = $0.hexString }
                            ), supportsOpacity: false)
                            ColorPicker("渐变结束颜色", selection: Binding(
                                get: { Color(hex: homeGreetingGradientEndHex) ?? (Color(hex: homeGreetingColorHex) ?? Color.soundhubLabel) },
                                set: { homeGreetingGradientEndHex = $0.hexString }
                            ), supportsOpacity: false)
                        }
                    }
                    .font(SoundHubFont.appFont(12))
                    .foregroundStyle(Color.soundhubLabel)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("逐行调节")
                            .font(SoundHubFont.appFont(13, .semibold))
                            .foregroundStyle(Color.soundhubLabel)
                        ForEach(Array(homeGreetingLines.prefix(3).enumerated()), id: \.offset) { index, line in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(String(format: NSLocalizedString("第%d行", comment: ""), index + 1))
                                        .font(SoundHubFont.appFont(12, .semibold))
                                    Text(line.isEmpty ? "空行" : line)
                                        .font(SoundHubFont.appFont(11))
                                        .foregroundStyle(Color.soundhubComment)
                                        .lineLimit(1)
                                    Spacer()
                                    Button("跟随全局") {
                                        resetGreetingLineStyle(index)
                                    }
                                    .font(SoundHubFont.appFont(11, .medium))
                                    .foregroundStyle(Color.soundhubAmber)
                                    .buttonStyle(.plain)
                                }
                                HStack {
                                    Text("字号")
                                    Spacer()
                                    Text("\(Int(greetingLineSizeBinding(index).wrappedValue))")
                                        .foregroundStyle(Color.soundhubComment)
                                }
                                Slider(value: greetingLineSizeBinding(index), in: 12...80, step: 1)
                                    .tint(Color.soundhubAmber)
                                HStack(spacing: 12) {
                                    ColorPicker("颜色", selection: greetingLineColorBinding(index), supportsOpacity: false)
                                    Spacer()
                                    Text("上下偏移 \(Int(greetingLineOffsetBinding(index).wrappedValue))")
                                        .foregroundStyle(Color.soundhubComment)
                                }
                                Slider(value: greetingLineOffsetBinding(index), in: -80...80, step: 1)
                                    .tint(Color.soundhubAmber)
                                if homeGreetingGradient {
                                    HStack(spacing: 12) {
                                        ColorPicker("渐变起始", selection: greetingLineGradientStartBinding(index), supportsOpacity: false)
                                        Spacer()
                                        ColorPicker("渐变结束", selection: greetingLineGradientEndBinding(index), supportsOpacity: false)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .font(SoundHubFont.appFont(12))
                    .foregroundStyle(Color.soundhubLabel)
                }

                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("主页壁纸模糊度")
                        Spacer()
                        Text("\(Int(homeWallpaperBlur))")
                            .foregroundStyle(Color.soundhubComment)
                    }
                    .font(SoundHubFont.appFont(12))
                    Slider(value: $homeWallpaperBlur, in: 0...30, step: 1)
                        .tint(Color.soundhubAmber)
                }

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                Toggle("隐藏主页用户名", isOn: $homeHideUsername)
                    .font(SoundHubFont.appFont(13))
                Toggle("隐藏所有界面排序按钮", isOn: $homeHeaderHideSort)
                    .font(SoundHubFont.appFont(13))
                Toggle("隐藏顶部平台列表", isOn: $hidePlatformPicker)
                    .font(SoundHubFont.appFont(13))
                Toggle("隐藏主页刷新按钮", isOn: $homeHeaderHideRefresh)
                    .font(SoundHubFont.appFont(13))

                HStack {
                    Image(systemName: "textformat")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    Text("全局字体")
                        .font(SoundHubFont.appFont(15))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    Text(FontManager.installedFontName ?? "系统默认")
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                }
                HStack(spacing: 12) {
                    Button {
                        showFontImporter = true
                    } label: {
                        Text("上传字体")
                            .font(SoundHubFont.appFont(13, .medium))
                            .foregroundStyle(Color.soundhubAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    .background { SoundHubSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Button {
                        FontManager.clear()
                        SoundHubHaptics.select()
                        ToastCenter.shared.show("已恢复系统默认字体")
                    } label: {
                        Text("恢复默认字体")
                            .font(SoundHubFont.appFont(13, .medium))
                            .foregroundStyle(Color.soundhubAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    .background { SoundHubSurface(shape: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(16)
            .background {
                        SoundHubGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
            .soundhubCardShadow(radius: 9, y: 3)
            }
        }
    }

    /// 播放与歌词设置。
    /// 音源与音质
    private var sourceQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                SoundHubHaptics.select()
                withAnimation(.easeInOut(duration: 0.22)) { sourceQualityExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("音源与音质")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                        Text(qualityByNetwork ? "已按 Wi-Fi / 蜂窝网络分别选择" : "统一使用当前音质")
                            .font(SoundHubFont.appFont(10))
                            .foregroundStyle(Color.soundhubComment)
                    }
                    Spacer()
                    Image(systemName: sourceQualityExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.soundhubComment.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background { SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if sourceQualityExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text("播放来源")
                        .font(SoundHubFont.appFont(13, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Picker("播放来源", selection: $playbackSourceMode) {
                        Text("自动").tag("auto")
                        Text("官方").tag("official")
                        Text("第三方").tag("thirdParty")
                    }
                    .pickerStyle(.segmented)
                    Text("优先官方，失败后尝试已启用音源")
                        .font(SoundHubFont.appFont(10))
                        .foregroundStyle(Color.soundhubComment)

                    Toggle(isOn: $qualityByNetwork) {
                        Text("按网络类型选择音质")
                            .font(SoundHubFont.appFont(14))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                    .toggleStyle(.switch)
                    .tint(Color.soundhubAmber)

                    qualityChips(title: "Wi-Fi", selection: $wifiQualityRaw)
                    qualityChips(title: "蜂窝数据", selection: $cellularQualityRaw)

                    Toggle(isOn: $autoSwitchPlatform) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("播放失败时切换平台")
                                .font(SoundHubFont.appFont(14))
                                .foregroundStyle(Color.soundhubLabel)
                            Text("当前平台音源失败后，匹配其它平台的同一首歌")
                                .font(SoundHubFont.appFont(10))
                                .foregroundStyle(Color.soundhubComment)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Color.soundhubAmber)

                    Button {
                        SoundHubHaptics.tap()
                        showSourceManager = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.soundhubHighlight)
                            Text("管理 / 导入音源")
                                .font(SoundHubFont.appFont(13, .medium))
                                .foregroundStyle(Color.soundhubLabel)
                            Spacer()
                            Text("\(customSourceCount) 个")
                                .font(SoundHubFont.appFont(11))
                                .foregroundStyle(Color.soundhubComment)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.soundhubComment.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background { RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.05)) }
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background { SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func qualityChips(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SoundHubFont.appFont(12, .semibold))
                .foregroundStyle(Color.soundhubLabel)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SoundHubAudioQuality.allCases) { quality in
                        let selected = selection.wrappedValue == quality.rawValue
                        Button {
                            selection.wrappedValue = quality.rawValue
                            SoundHubHaptics.select()
                        } label: {
                            Text(quality.displayName)
                                .font(SoundHubFont.appFont(12, .medium))
                                .foregroundStyle(selected ? Color.white : Color.soundhubLabel)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background {
                                    Capsule().fill(selected ? Color.soundhubHighlight : Color.primary.opacity(0.06))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func pickerRow(title: String, icon: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.soundhubAmber)
                .frame(width: 28)
            Text(LocalizedStringKey(title))
                .font(SoundHubFont.appFont(15))
                .foregroundStyle(Color.soundhubLabel)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { option in
                    Text(LocalizedStringKey(option.1)).tag(option.0)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.soundhubComment)
        }
    }

    private var equalizerSection: some View {
        Button {
            SoundHubHaptics.select()
            showEqualizer = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.soundhubAmber)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(soundhubLocalized("均衡器", "Equalizer"))
                        .font(SoundHubFont.appFont(15))
                        .foregroundStyle(Color.soundhubLabel)
                    Text(soundhubLocalized("调节低音、人声与高音", "Adjust bass, vocals, and treble"))
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                }
                Spacer()
                Text(equalizer.isEnabled ? soundhubLocalized("已开启", "On") : soundhubLocalized("已关闭", "Off"))
                    .font(SoundHubFont.appFont(12, .medium))
                    .foregroundStyle(equalizer.isEnabled ? Color.soundhubAmber : Color.soundhubComment)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.soundhubComment.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.98))
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                SoundHubHaptics.select()
                withAnimation(.easeInOut(duration: 0.22)) {
                    playbackExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("播放设置")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                    Spacer()
                    Image(systemName: playbackExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.soundhubComment.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background {
                    SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.98))

            if playbackExpanded {
            VStack(spacing: 14) {
                Toggle(isOn: $mixesWithOthers) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("与其他音频同时播放")
                                .font(SoundHubFont.appFont(15))
                                .foregroundStyle(Color.soundhubLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)
                .onChange(of: mixesWithOthers) { value in
                    PlayerManager.applyAudioMixPreference(value)
                }

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                HStack(spacing: 12) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("120Hz 高刷新")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.soundhubAmber)
                }
                .onAppear {
                    enableHighRefresh = true
                    HighRefreshKeeper.shared.configure(enabled: true)
                }

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                Toggle(isOn: $autoResumeLastPlayback) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.square.stack.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(soundhubLocalized("启动时自动播放上次歌曲", "Auto-play the last song on launch"))
                                .font(SoundHubFont.appFont(15))
                                .foregroundStyle(Color.soundhubLabel)
                            Text(soundhubLocalized("打开软件后自动恢复上次未播放完的歌曲", "Automatically resume the last unfinished song when the app starts."))
                                .font(SoundHubFont.appFont(11))
                                .foregroundStyle(Color.soundhubComment)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                playbackQualitySection

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                Toggle(isOn: $hapticsEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text(soundhubLocalized("触感反馈", "Haptic Feedback"))
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                Divider().overlay(Color.soundhubComment.opacity(0.15))

                Toggle(isOn: $showThirdPartyVIPNotice) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(soundhubLocalized("第三方播放会员歌提醒", "VIP song notice for third-party playback"))
                                .font(SoundHubFont.appFont(15))
                                .foregroundStyle(Color.soundhubLabel)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.soundhubAmber)

                HStack(spacing: 10) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                    Text(soundhubLocalized("第三方音源", "Third-party Sources"))
                        .font(SoundHubFont.appFont(13, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    Text(soundhubLocalized("\(customSourceCount) 个", "\(customSourceCount) sources"))
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                }

                Button {
                    showSourceManager = true
                    SoundHubHaptics.tap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        Text(soundhubLocalized("管理 / 导入音源", "Manage / Import Sources"))
                    }
                    .font(SoundHubFont.appFont(13, .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.97))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.soundhubAmber)
                            .frame(width: 28)
                        Text(thirdPartyAudioQualityTitle)
                            .font(SoundHubFont.appFont(13, .semibold))
                            .foregroundStyle(Color.soundhubLabel)
                        Spacer()
                        Text(thirdPartyAudioQualitySelection.wrappedValue.displayName)
                            .font(SoundHubFont.appFont(12))
                            .foregroundStyle(Color.soundhubComment)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(thirdPartyAudioQualityOptions) { quality in
                                let selected = thirdPartyAudioQualitySelection.wrappedValue == quality
                                Button {
                                    thirdPartyAudioQualitySelection.wrappedValue = quality
                                    SoundHubHaptics.select()
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(quality.displayName)
                                        if selected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                    }
                                    .font(SoundHubFont.appFont(12, selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? Color.soundhubAmber : Color.soundhubLabel)
                                    .padding(.horizontal, 12)
                                    .frame(height: 31)
                                    .background {
                                        Capsule()
                                            .fill(selected ? Color.soundhubAmber.opacity(0.14) : Color.soundhubLabel.opacity(0.055))
                                    }
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(selected ? Color.soundhubAmber.opacity(0.42) : Color.soundhubLabel.opacity(0.08), lineWidth: 0.8)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    Text(thirdPartyAudioQualityHint)
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                }

            }
            .padding(16)
            .background {
                                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .soundhubCardShadow(radius: 9, y: 3)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .task(id: thirdPartyAudioQualityOptionsSignature) {
                normalizeThirdPartyAudioQualitySelection()
            }
            }
        }
    }

    /// 更新日志入口
    /// 关于与支持
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "关于与支持")
            VStack(spacing: 0) {
                supportRow(icon: "bubble.left.and.bubble.right", title: "问题反馈") {
                    showFeedbackSheet = true
                }
                Divider().opacity(0.2).padding(.leading, 46)
                supportRow(icon: "trash.circle", title: "缓存清理") {
                    URLCache.shared.removeAllCachedResponses()
                    SoundHubImageFileCache.removeAll()
                    SoundHubHaptics.success()
                    ToastCenter.shared.show("缓存已清理")
                }
                Divider().opacity(0.2).padding(.leading, 46)
                supportRow(icon: "exclamationmark.triangle", title: "免责声明") {
                    showDisclaimerSheet = true
                }
                Divider().opacity(0.2).padding(.leading, 46)
                supportRow(icon: "iphone", title: "运行环境") {
                    showEnvironmentSheet = true
                }
            }
            .background { SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func supportRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundHubHaptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.soundhubHighlight)
                    .frame(width: 26)
                Text(LocalizedStringKey(title))
                    .font(SoundHubFont.appFont(15))
                    .foregroundStyle(Color.soundhubLabel)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.soundhubComment.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.99))
    }

    private var infoSheetText: (disclaimer: String, environment: String) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        let env = """
        应用版本：\(version) (\(build))
        系统版本：\(device.systemName) \(device.systemVersion)
        设备型号：\(device.model)
        架构：\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "真机")
        """
        let disclaimer = """
        本应用仅供个人学习与技术研究使用。

        所有音乐内容版权归网易云音乐、QQ 音乐、酷狗音乐等平台所有，本应用不提供任何内容托管与下载服务。

        请支持正版音乐。使用本应用产生的任何后果由使用者自行承担。
        """
        return (disclaimer, env)
    }

    private var changelogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                SoundHubHaptics.tap()
                showChangelog = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 28)
                    Text("更新日志")
                        .font(SoundHubFont.appFont(15))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    Text("v\(ChangelogStore.currentVersion)")
                        .font(SoundHubFont.appFont(12))
                        .foregroundStyle(Color.soundhubComment)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.soundhubComment.opacity(0.6))
                }
                .padding(16)
                .background {
                                    SoundHubGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .soundhubCardShadow(radius: 8, y: 3)
        }
    }
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                SoundHubHaptics.select()
                withAnimation(.easeInOut(duration: 0.22)) {
                    backupExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(Color.soundhubAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("备份与恢复")
                            .font(SoundHubFont.appFont(15))
                            .foregroundStyle(Color.soundhubLabel)
                    }
                    Spacer()
                    Image(systemName: backupExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.soundhubComment)
                }
                .padding(14)
                .background {
                    SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .buttonStyle(.plain)

            if backupExpanded {
            VStack(spacing: 10) {
                Toggle("备份登录信息", isOn: $backupIncludeAccounts)
                    .tint(Color.soundhubAmber)
                    .font(SoundHubFont.appFont(13))
                Divider().opacity(0.35)
                Toggle("备份壁纸图片", isOn: $backupIncludeWallpapers)
                    .tint(Color.soundhubAmber)
                    .font(SoundHubFont.appFont(13))
                Divider().opacity(0.35)
                Text("默认不带账号登录信息；关闭壁纸后只备份普通设置，不写入壁纸图片数据")
                    .font(SoundHubFont.appFont(11))
                    .foregroundStyle(Color.soundhubComment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            HStack(spacing: 10) {
                backupActionButton(icon: "square.and.arrow.up", title: "导出备份") {
                    SoundHubHaptics.tap()
                    exportBackup(includeAccounts: backupIncludeAccounts, includeWallpapers: backupIncludeWallpapers)
                }
                backupActionButton(icon: "square.and.arrow.down", title: "导入恢复") {
                    SoundHubHaptics.tap()
                    showRestorePicker = true
                }
            }
            if let backupMessage {
                Text(backupMessage)
                    .font(SoundHubFont.appFont(11))
                    .foregroundStyle(Color.soundhubComment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
    }

    private func backupActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(LocalizedStringKey(title))
            }
            .font(SoundHubFont.appFont(14, .semibold))
            .foregroundStyle(Color.soundhubLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.95))
    }

    private static func isAccountBackupKey(_ key: String) -> Bool {
        key == "soundhub.user"
            || key.hasPrefix("soundhub.netease.")
            || key.hasPrefix("soundhub.qqmusic.")
            || key.hasPrefix("soundhub.kugou.")
    }

    private static func isPrivacyBackupKey(_ key: String) -> Bool {
        key.hasPrefix("soundhub.search.")
            || key.hasPrefix("soundhub.log")
            || key.hasPrefix("soundhub.crash")
            || key == "soundhub.thirdPartyAPIKeys"
            || key == "soundhub.launchInProgress"
            || key == "soundhub.wallpapers.deleted"
    }

    private static func isWallpaperBackupKey(_ key: String) -> Bool {
        key == "soundhub.background.image"
            || key == "soundhub.background.image.light"
            || key == "soundhub.background.image.dark"
            || key == "soundhub.background.custom"
            || key == "soundhub.background.custom.light"
            || key == "soundhub.background.custom.dark"
            || key == "soundhub.wallpapers.list"
            || key == "soundhub.wallpapers.data"
            || key == "soundhub.lyricBackground.image"
            || key == "soundhub.lyricBackground.data"
    }

    private static func isSystemBackupKey(_ key: String) -> Bool {
        key.hasPrefix("Apple")
            || key.hasPrefix("NS")
            || key.hasPrefix("com.apple.")
            || key == "AddingEmojiKeybordHandled"
    }

    private static func isBackupCandidateKey(_ key: String) -> Bool {
        key.hasPrefix("soundhub.") && !isSystemBackupKey(key)
    }

    private static func isExcludedBackupKey(_ key: String, includeAccounts: Bool = false, includeWallpapers: Bool = true) -> Bool {
        (!includeAccounts && isAccountBackupKey(key))
            || (!includeWallpapers && isWallpaperBackupKey(key))
            || isPrivacyBackupKey(key)
            || key == "soundhub.backup.meta"
            || key == "soundhub.font.restore"
    }

    /// 导出：收集本 App 设置，排除账号、搜索记录和日志，交给系统原生导出面板
    private func exportBackup(includeAccounts: Bool, includeWallpapers: Bool) {
        let defaults = UserDefaults.standard
        var payload: [String: Any] = [:]
        if includeWallpapers {
            theme.refreshWallpaperBackupForExport()
            LyricBackgroundStore.refreshForExport()
        }
        for (key, value) in defaults.dictionaryRepresentation() {
            guard Self.isBackupCandidateKey(key) else { continue }
            guard !Self.isExcludedBackupKey(key, includeAccounts: includeAccounts, includeWallpapers: includeWallpapers) else { continue }
            // 超大原始 Data 直接跳过（壁纸 base64 已以字符串形式存于 soundhub.wallpapers.data，不受影响）
            if let data = value as? Data, data.count > 2 * 1024 * 1024 { continue }
            let safe = backupJSONSafe(value)
            // 逐个校验可序列化，异常类型直接跳过，避免整份备份生成失败
            guard JSONSerialization.isValidJSONObject([key: safe]) else { continue }
            payload[key] = safe
        }
        // 字体文件（Documents/Fonts）随备份一起导出
        if let font = FontManager.exportFontData() {
            payload["soundhub.font.restore"] = [
                "name": font.name,
                "data": font.data.base64EncodedString(),
            ] as [String: Any]
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        payload["soundhub.backup.meta"] = [
            "app": "SoundHub",
            "created": ISO8601DateFormatter().string(from: Date()),
            "version": version,
            "includedAccounts": includeAccounts,
            "includedWallpapers": includeWallpapers,
            "excluded": [
                includeAccounts ? nil : "account",
                includeWallpapers ? nil : "wallpapers",
                "search history",
                "logs",
            ].compactMap { $0 }.joined(separator: ", "),
        ] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            backupMessage = "备份生成失败：存在无法序列化的设置项"
            ToastCenter.shared.show("备份生成失败")
            return
        }
        backupDoc = BackupDocument(data: data)
        backupMessage = nil
        SoundHubLogger.shared.log("导出配置备份（\(payload.count) 项，账号=\(includeAccounts ? "包含" : "排除") 壁纸=\(includeWallpapers ? "包含" : "排除")）", level: .info)
        showExportBackup = true
    }

    private static func backupDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// 读取用户选择的备份文件并解析，弹确认后恢复
    private func handleBackupImport(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ToastCenter.shared.show("备份文件解析失败")
            return
        }
        pendingRestore = json
        showRestoreConfirm = true
    }

    /// 恢复：把 JSON 备份中除账号、搜索记录和日志外的本 App 设置写回 UserDefaults
    private func applyRestore(_ json: [String: Any]?) {
        guard let json else { return }
        let defaults = UserDefaults.standard
        var count = 0
        for (key, value) in json {
            guard Self.isBackupCandidateKey(key) else { continue }
            guard !Self.isExcludedBackupKey(key, includeAccounts: true, includeWallpapers: true) else { continue }
            guard let restored = backupPlistSafe(value) else { continue }
            defaults.set(restored, forKey: key)
            count += 1
        }
        // 兼容旧备份：旧版本只有一套背景，恢复后让浅色和深色都继承它。
        if json["soundhub.background.custom.light"] == nil,
           json["soundhub.background.custom.dark"] == nil,
           let legacy = json["soundhub.background.custom"] as? String {
            defaults.set(legacy, forKey: "soundhub.background.custom.light")
            defaults.set(legacy, forKey: "soundhub.background.custom.dark")
        }
        if json["soundhub.background.image.light"] == nil,
           json["soundhub.background.image.dark"] == nil,
           let legacy = json["soundhub.background.image"] as? String {
            defaults.set(legacy, forKey: "soundhub.background.image.light")
            defaults.set(legacy, forKey: "soundhub.background.image.dark")
        }
        theme.reloadBackgroundSettings()
        defaults.removeObject(forKey: "soundhub.wallpapers.deleted")
        // 恢复壁纸：写回 soundhub.wallpapers.* 后重建文件（沙盒路径变化也能恢复）
        theme.reloadWallpapersFromBackup()
        // 恢复歌词背景图片：路径变化时按备份的 base64 重建文件
        LyricBackgroundStore.restoreFromBackup()
        // 恢复字体文件
        if let fontPayload = json["soundhub.font.restore"] as? [String: Any],
           let name = fontPayload["name"] as? String,
           let b64 = fontPayload["data"] as? String,
           let fontData = Data(base64Encoded: b64) {
            if FontManager.restoreFont(name: name, data: fontData) {
                count += 1
            }
        }
        SoundHubLogger.shared.log("恢复配置备份：\(count) 项设置", level: .info)
        if count > 0 {
            SoundHubHaptics.success()
            backupMessage = "已恢复 \(count) 项设置，部分设置需重启应用后完全生效"
            ToastCenter.shared.show("已恢复 \(count) 项设置")
        } else {
            backupMessage = "备份中未找到可恢复的设置"
        }
    }

    private var legacyTabBarSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.soundhubAmber)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("低系统悬浮底栏")
                        .font(SoundHubFont.appFont(15))
                        .foregroundStyle(Color.soundhubLabel)
                    Text("仅 iOS 26 以下生效，用来模拟高系统悬浮底栏")
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                }
                Spacer()
                Button("默认") {
                    resetLegacyTabBar()
                    SoundHubHaptics.select()
                }
                .font(SoundHubFont.appFont(12, .semibold))
                .foregroundStyle(Color.soundhubAmber)
                .buttonStyle(.plain)
            }
            settingsSlider("圆润度", valueText: "\(Int(legacyTabCornerRadius))") {
                Slider(value: $legacyTabCornerRadius, in: 18...42, step: 1)
                    .tint(Color.soundhubAmber)
            }
            settingsSlider("长度", valueText: "\(Int(legacyTabWidth))") {
                Slider(value: $legacyTabWidth, in: 300...420, step: 1)
                    .tint(Color.soundhubAmber)
            }
            settingsSlider("X 位置", valueText: signedIntText(legacyTabOffsetX)) {
                Slider(value: $legacyTabOffsetX, in: -40...40, step: 1)
                    .tint(Color.soundhubAmber)
            }
            settingsSlider("Y 位置", valueText: signedIntText(legacyTabOffsetY)) {
                Slider(value: $legacyTabOffsetY, in: -36...36, step: 1)
                    .tint(Color.soundhubAmber)
            }
        }
        .padding(14)
        .background {
            SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func resetLegacyTabBar() {
        legacyTabCornerRadius = 32
        legacyTabWidth = 356
        legacyTabOffsetX = 0
        legacyTabOffsetY = 0
    }

    private func signedIntText(_ value: Double) -> String {
        let intValue = Int(value.rounded())
        if intValue == 0 { return "0" }
        return intValue > 0 ? "+\(intValue)" : "\(intValue)"
    }

    private func settingsSlider<Content: View>(_ title: String, valueText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(SoundHubFont.appFont(13))
                    .foregroundStyle(Color.soundhubLabel)
                Spacer()
                Text(valueText)
                    .font(SoundHubFont.appFont(12, .semibold))
                    .foregroundStyle(Color.soundhubAmber)
            }
            content()
                .transaction { transaction in transaction.animation = nil }
        }
    }

    /// 任意 UserDefaults 值 → JSON 可序列化（Data 转 base64、Date 转时间戳）
    private func backupJSONSafe(_ value: Any) -> Any {
        if let data = value as? Data {
            return ["__soundhubData__": data.base64EncodedString()]
        }
        if let date = value as? Date { return date.timeIntervalSince1970 }
        if let dict = value as? [String: Any] { return dict.mapValues { backupJSONSafe($0) } }
        if let array = value as? [Any] { return array.map { backupJSONSafe($0) } }
        if let dict = value as? [String: String] { return dict }
        if let array = value as? [String] { return array }
        return value
    }

    /// JSON 值 → UserDefaults 可存类型（只保留 plist 兼容类型）
    private func backupPlistSafe(_ value: Any) -> Any? {
        if let dict = value as? [String: Any], dict.count == 1,
           let b64 = dict["__soundhubData__"] as? String,
           let data = Data(base64Encoded: b64) {
            return data
        }
        if value is String || value is NSNumber { return value }
        if let array = value as? [Any] {
            let mapped = array.compactMap { backupPlistSafe($0) }
            return mapped.count == array.count ? mapped : nil
        }
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (k, v) in dict {
                guard let mv = backupPlistSafe(v) else { return nil }
                result[k] = mv
            }
            return result
        }
        return nil
    }

    /// 日志：查看 / 清空（导出入口放在日志查看器右上角）
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "日志")
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    logActionButton(icon: "doc.text.magnifyingglass", title: "查看日志") {
                        showLogViewer = true
                    }
                    logActionButton(icon: "trash", title: "清空日志") {
                        SoundHubLogger.shared.clear()
                        ToastCenter.shared.show("日志已清空")
                    }
                }
            }
            .padding(14)
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func infoSheet(title: String, body: String) -> some View {
        SoundHubNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    Text(body)
                        .font(SoundHubFont.appFont(13))
                        .foregroundStyle(Color.soundhubLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showFeedbackSheet = false
                        showDisclaimerSheet = false
                        showEnvironmentSheet = false
                    }
                }
            }
        }
    }

    private func logActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(LocalizedStringKey(title))
            }
            .font(SoundHubFont.appFont(13, .semibold))
            .foregroundStyle(Color.soundhubLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background {
                SoundHubGlass(shape: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.95))
    }

    private var footerNote: some View {
        VStack(spacing: 6) {
            Text("SoundHub · 仅供学习交流，纯 AI 实现此应用")
                .font(SoundHubFont.appFont(11))
                .foregroundStyle(Color.soundhubComment.opacity(0.7))
            Text("接入网易云音乐、QQ 音乐等公开接口")
                .font(SoundHubFont.appFont(11))
                .foregroundStyle(Color.soundhubComment.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// 壁纸格子：点击应用到所选外观；使用中的壁纸显示主题色边框+勾选；右上角删除
    private func wallpaperCell(path: String, appearance: SoundHubWallpaperAppearance) -> some View {
        let isActive = path == theme.backgroundImagePath(for: appearance.colorScheme)
        return ZStack(alignment: .topTrailing) {
            Button {
                SoundHubHaptics.tap()
                theme.applyWallpaper(at: path, for: appearance.colorScheme)
            } label: {
                Group {
                    if let img = SoundHubImageFileCache.image(at: path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.soundhubGlassFill
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.soundhubAmber)
                            .background { SoundHubSurface(shape: Circle()) }
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                SoundHubHaptics.medium()
                theme.deleteWallpaper(at: path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.soundhubComment)
                    .frame(width: 28, height: 28)
                    .background { SoundHubSurface(shape: Circle()) }
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .zIndex(2)
        }
    }
}

// MARK: - 均衡器

struct EqualizerSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var equalizer = SoundHubEqualizer.shared
    @State private var newPresetName = ""
    @State private var showPresetNamePrompt = false

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { equalizer.isEnabled },
            set: { equalizer.setEnabled($0) }
        )
    }

    private func gainBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { equalizer.bandGains.indices.contains(index) ? equalizer.bandGains[index] : 0 },
            set: { equalizer.setBandGain(at: index, to: $0) }
        )
    }

    private var preampBinding: Binding<Double> {
        Binding(
            get: { equalizer.preampGain },
            set: { equalizer.setPreampGain($0) }
        )
    }

    var body: some View {
        SoundHubNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        EqualizerResponseView(
                            gains: equalizer.bandGains,
                            preampGain: equalizer.preampGain
                        )
                        controlCard
                        presetCard
                        bandsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .soundhubScrollIndicatorsHidden()
            }
            .navigationTitle(soundhubLocalized("均衡器", "Equalizer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(soundhubLocalized("完成", "Done")) { dismiss() }
                }
            }
            .alert(
                soundhubLocalized("保存自定义预设", "Save custom preset"),
                isPresented: $showPresetNamePrompt
            ) {
                TextField(
                    soundhubLocalized("预设名称", "Preset name"),
                    text: $newPresetName
                )
                Button(soundhubLocalized("保存", "Save")) {
                    if equalizer.saveCustomPreset(name: newPresetName) {
                        SoundHubHaptics.select()
                    }
                    newPresetName = ""
                }
                Button(soundhubLocalized("取消", "Cancel"), role: .cancel) {
                    newPresetName = ""
                }
            } message: {
                Text(soundhubLocalized("保存当前频段和前级增益，之后可以一键恢复。", "Save the current bands and preamp for one-tap recall later."))
            }
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: enabledBinding) {
                HStack(spacing: 11) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(soundhubLocalized("启用均衡器", "Enable Equalizer"))
                            .font(SoundHubFont.appFont(15, .semibold))
                            .foregroundStyle(Color.soundhubLabel)
                        Text(soundhubLocalized("播放时实时应用当前调节", "Apply the current tuning while playing"))
                            .font(SoundHubFont.appFont(11))
                            .foregroundStyle(Color.soundhubComment)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(Color.soundhubAmber)

            Text(soundhubLocalized("均衡器仅处理 SoundHub 当前播放的音乐，不影响其他 App。", "The equalizer only processes music playing in SoundHub."))
                .font(SoundHubFont.appFont(11))
                .foregroundStyle(Color.soundhubComment)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.soundhubComment.opacity(0.14))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(soundhubLocalized("前级增益", "Preamp"))
                        .font(SoundHubFont.appFont(13, .medium))
                        .foregroundStyle(Color.soundhubLabel)
                    Spacer()
                    Text(String(format: "%+.1f dB", equalizer.preampGain))
                        .font(SoundHubFont.appFont(12, .semibold))
                        .foregroundStyle(abs(equalizer.preampGain) > 0.01 ? Color.soundhubAmber : Color.soundhubComment)
                        .monospacedDigit()
                }
                Slider(value: preampBinding, in: -SoundHubEqualizer.maximumGain...SoundHubEqualizer.maximumGain, step: 0.5)
                    .tint(Color.soundhubAmber)
                    .transaction { transaction in transaction.animation = nil }
                HStack {
                    Text("-12")
                    Spacer()
                    Text(soundhubLocalized("不增益", "Unity"))
                    Spacer()
                    Text("+12")
                }
                .font(SoundHubFont.appFont(10))
                .foregroundStyle(Color.soundhubComment.opacity(0.75))
            }
        }
        .padding(14)
        .background { SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(soundhubLocalized("预设", "Preset"))
                    .font(SoundHubFont.appFont(14, .semibold))
                    .foregroundStyle(Color.soundhubLabel)
                Spacer()
                Menu {
                    ForEach(SoundHubEqualizerPreset.allCases.filter { $0 != .custom }) { preset in
                        Button(preset.displayName) {
                            equalizer.applyPreset(preset)
                            SoundHubHaptics.select()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(equalizer.selectedCustomPresetName ?? equalizer.selectedPreset.displayName)
                            .font(SoundHubFont.appFont(13, .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.soundhubAmber)
                    .padding(.horizontal, 11)
                    .frame(height: 31)
                    .background { SoundHubSurface(shape: Capsule()) }
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(SoundHubEqualizerPreset.allCases.filter { $0 != .custom }) { preset in
                    let selected = equalizer.selectedPreset == preset
                    Button {
                        equalizer.applyPreset(preset)
                        SoundHubHaptics.select()
                    } label: {
                        Text(preset.displayName)
                            .font(SoundHubFont.appFont(11.5, selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.soundhubAmber : Color.soundhubLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background {
                                Capsule().fill(selected ? Color.soundhubAmber.opacity(0.14) : Color.primary.opacity(0.035))
                            }
                            .overlay {
                                Capsule().strokeBorder(selected ? Color.soundhubAmber.opacity(0.42) : Color.primary.opacity(0.06), lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !equalizer.customPresets.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(soundhubLocalized("我的预设", "My presets"))
                        .font(SoundHubFont.appFont(12, .semibold))
                        .foregroundStyle(Color.soundhubComment)
                    ForEach(equalizer.customPresets) { preset in
                        HStack(spacing: 8) {
                            Button {
                                equalizer.applyCustomPreset(preset)
                                SoundHubHaptics.select()
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: equalizer.selectedCustomPresetName == preset.name ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(equalizer.selectedCustomPresetName == preset.name ? Color.soundhubAmber : Color.soundhubComment)
                                    Text(preset.name)
                                        .font(SoundHubFont.appFont(12.5, .medium))
                                        .foregroundStyle(Color.soundhubLabel)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            Button {
                                equalizer.deleteCustomPreset(preset)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.soundhubComment)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    newPresetName = equalizer.selectedCustomPresetName ?? ""
                    showPresetNamePrompt = true
                } label: {
                    Label(soundhubLocalized("保存当前预设", "Save current preset"), systemImage: "square.and.arrow.down")
                        .font(SoundHubFont.appFont(12.5, .medium))
                        .foregroundStyle(Color.soundhubAmber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background { SoundHubSurface(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)) }
                }
                .buttonStyle(.plain)

                Button {
                    equalizer.reset()
                    SoundHubHaptics.select()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.soundhubComment)
                        .frame(width: 42, height: 34)
                        .background { SoundHubSurface(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(soundhubLocalized("重置调节", "Reset adjustments"))
            }
        }
        .padding(14)
        .background { SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private var bandsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(soundhubLocalized("自定义调节", "Custom tuning"))
                        .font(SoundHubFont.appFont(14, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Text(soundhubLocalized("范围 -12 dB 至 +12 dB", "Range: -12 dB to +12 dB"))
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                }
                Spacer()
            }

            ForEach(Array(SoundHubEqualizer.bandFrequencies.enumerated()), id: \.offset) { index, frequency in
                equalizerBandRow(index: index, frequency: frequency)
                if index < SoundHubEqualizer.bandFrequencies.count - 1 {
                    Divider().overlay(Color.soundhubComment.opacity(0.14))
                }
            }
        }
        .padding(14)
        .background { SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private func equalizerBandRow(index: Int, frequency: Double) -> some View {
        let gain = equalizer.bandGains.indices.contains(index) ? equalizer.bandGains[index] : 0
        return VStack(spacing: 6) {
            HStack {
                Text(frequencyLabel(frequency))
                    .font(SoundHubFont.appFont(13, .medium))
                    .foregroundStyle(Color.soundhubLabel)
                Spacer()
                Text(String(format: "%+.1f dB", gain))
                    .font(SoundHubFont.appFont(12, .semibold))
                    .foregroundStyle(abs(gain) > 0.01 ? Color.soundhubAmber : Color.soundhubComment)
                    .monospacedDigit()
            }
            Slider(value: gainBinding(index), in: -SoundHubEqualizer.maximumGain...SoundHubEqualizer.maximumGain, step: 0.5)
                .tint(Color.soundhubAmber)
                .transaction { transaction in transaction.animation = nil }
            HStack {
                Text("-12")
                Spacer()
                Text("0")
                Spacer()
                Text("+12")
            }
            .font(SoundHubFont.appFont(10))
            .foregroundStyle(Color.soundhubComment.opacity(0.75))
        }
    }

    private func frequencyLabel(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            let value = frequency / 1_000
            return value.rounded() == value ? "\(Int(value)) kHz" : String(format: "%.1f kHz", value)
        }
        return "\(Int(frequency)) Hz"
    }
}

private struct EqualizerResponseView: View {
    let gains: [Double]
    let preampGain: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(soundhubLocalized("频响预览", "Response preview"))
                        .font(SoundHubFont.appFont(14, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Text(soundhubLocalized("拖动下方频段，实时塑造声音", "Shape the sound in real time by tuning each band below"))
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                }
                Spacer()
                Image(systemName: "waveform.path")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.soundhubAmber)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let values = responseValues
                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in
                            Divider().overlay(Color.soundhubComment.opacity(0.12))
                            Spacer()
                        }
                    }
                    Path { path in
                        guard let first = values.first else { return }
                        path.move(to: CGPoint(x: 0, y: yPosition(first, height: height)))
                        for index in values.indices.dropFirst() {
                            let x = width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                            path.addLine(to: CGPoint(x: x, y: yPosition(values[index], height: height)))
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.soundhubAmber.opacity(0.65), Color.soundhubAmber, Color.soundhubHighlight],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
                    Path { path in
                        guard let first = values.first else { return }
                        path.move(to: CGPoint(x: 0, y: height))
                        path.addLine(to: CGPoint(x: 0, y: yPosition(first, height: height)))
                        for index in values.indices.dropFirst() {
                            let x = width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                            path.addLine(to: CGPoint(x: x, y: yPosition(values[index], height: height)))
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.soundhubAmber.opacity(0.22), Color.soundhubAmber.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
            }

            HStack {
                Text("31 Hz")
                Spacer()
                Text("1 kHz")
                Spacer()
                Text("16 kHz")
            }
            .font(SoundHubFont.appFont(10))
            .foregroundStyle(Color.soundhubComment)
        }
        .padding(14)
        .background { SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    }

    private var responseValues: [Double] {
        guard !gains.isEmpty else { return [preampGain] }
        return gains.map { min(max($0 + preampGain * 0.35, -12), 12) }
    }

    private func yPosition(_ value: Double, height: CGFloat) -> CGFloat {
        let normalized = (value + 12) / 24
        return height * CGFloat(1 - normalized)
    }
}

// MARK: - 壁纸照片选择器（PHPicker 封装：iOS 14+ 兼容，支持多选图片）

struct WallpaperPhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0 // 0 = 多选
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: WallpaperPhotoPicker
        init(_ parent: WallpaperPhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            for result in results {
                let provider = result.itemProvider
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        guard let data, !data.isEmpty else { return }
                        DispatchQueue.main.async {
                            self.parent.onPicked(data)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 字体文件选择器（UIDocumentPicker 包装，比 SwiftUI fileImporter 稳定：所有文件可选，系统 asCopy 复制到沙盒）

struct FontDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FontDocumentPicker
        init(_ parent: FontDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
// MARK: - 配置备份文档（SwiftUI 原生 fileExporter 导出，稳定可靠）

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
// MARK: - 配置备份文件选择器（UIDocumentPicker 封装：比 SwiftUI fileImporter 稳定，所有文件可选）

struct BackupDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText, .item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: BackupDocumentPicker
        init(_ parent: BackupDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
