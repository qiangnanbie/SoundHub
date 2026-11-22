import SwiftUI
import UIKit

@main
struct SoundHubApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthStore()
    @StateObject private var player = PlayerManager()
    @StateObject private var theme = ThemeStore.shared
    @StateObject private var favorites = FavoritesStore.shared
    /// 免责声明确认状态：未确认前主界面在模糊层下方可见，确认后移除门禁
    @AppStorage("soundhub.disclaimerAccepted") private var disclaimerAccepted = false
    @AppStorage("soundhub.language") private var languageRaw = AppLanguage.chinese.rawValue

    init() {
        // 闪退检测：优先初始化，检测上次异常退出并安装崩溃捕获
        _ = CrashReporter.shared
        // 主页暂停只应在设置页打开期间生效，避免异常退出后把暂停状态永久写入本地。
        UserDefaults.standard.set(false, forKey: "soundhub.pauseHomeRendering")
        // 新安装默认开启高刷新率；老用户保留自己手动关闭的选择。
        HighRefreshKeeper.registerDefaults()
        HighRefreshKeeper.shared.configureFromDefaults()
        UserDefaults.standard.register(defaults: [
            "soundhub.uiStyle": SoundHubUIStyle.nativeClean.rawValue,
            "soundhub.coverPlayerStyle": SoundHubCoverPlayerStyle.appleMusic.rawValue,
            "soundhub.appleMusic.showVolume": false,
            "soundhub.homeHideUsername": true,
            "soundhub.homeHeaderHideSort": true,
            "soundhub.homeHeaderHideRefresh": true,
            PlatformPreferenceStore.hidePickerKey: true,
            "soundhub.homeWallpaperBlur": 0.0,
            "soundhub.haptics.enabled": true,
            "soundhub.playback.autoResumeLast": false,
            "soundhub.playback.autoSkipOnFailure": true
        ])
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(auth)
                    .environmentObject(player)
                    .environmentObject(theme)
                    .environmentObject(favorites)
                // 未确认前展示首次使用引导页（分页引导 + 免责确认）
                if !disclaimerAccepted {
                    OnboardingView { disclaimerAccepted = true }
                }
            }
            .environment(\.locale, Locale(identifier: languageRaw))
            .task {
                // 先让系统完成首帧，再恢复仅影响已安装用户的数据与媒体偏好。
                await Task.yield()
                player.restorePersistedPlayMode()
                player.resumePersistedPlaybackIfEnabled()
                FontManager.reinstallIfNeeded()
                theme.restoreWallpapersIfNeeded()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
            }
        }
    }
}
