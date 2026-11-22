import SwiftUI

/// 账号登录页：列出三个平台的登录状态，可直接登录 / 退出
struct AccountCenterView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var qqAuth = QQMusicAuth.shared
    @ObservedObject private var kugouAuth = KugouMusicAuth.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showNeteaseLogin = false
    @State private var showQQLogin = false
    @State private var showKugouLogin = false
    @State private var confirmNeteaseLogout = false

    private struct PlatformRow {
        let provider: SearchProvider
        let title: String
        let loggedIn: Bool
        let detail: String
        let badge: String?
    }

    private var rows: [PlatformRow] {
        var list: [PlatformRow] = []
        list.append(PlatformRow(
            provider: .netease,
            title: "网易云音乐",
            loggedIn: auth.isLoggedIn,
            detail: auth.isLoggedIn ? (auth.user?.nickname ?? "已登录") : "未登录",
            badge: auth.user?.vipBadge
        ))
        list.append(PlatformRow(
            provider: .qq,
            title: "QQ 音乐",
            loggedIn: qqAuth.isLoggedIn,
            detail: qqAuth.isLoggedIn ? (qqAuth.nickname.isEmpty ? "已登录" : qqAuth.nickname) : "未登录",
            badge: qqAuth.vipBadge
        ))
        list.append(PlatformRow(
            provider: .kugou,
            title: "酷狗音乐",
            loggedIn: kugouAuth.isLoggedIn,
            detail: kugouAuth.isLoggedIn ? (kugouAuth.nickname.isEmpty ? "已登录" : kugouAuth.nickname) : "未登录",
            badge: kugouAuth.vipBadge
        ))
        return list
    }

    var body: some View {
        SoundHubNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.customBackground)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("账号")
                            .font(SoundHubFont.appFont(17, .semibold))
                            .foregroundStyle(Color.soundhubLabel)
                            .padding(.horizontal, 4)
                        ForEach(rows, id: \.title) { row in
                            platformCard(row)
                        }
                        Text("登录后可同步歌单、播放会员曲目。账号信息仅保存在本机。")
                            .font(SoundHubFont.appFont(11))
                            .foregroundStyle(Color.soundhubComment)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
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
            LoginView().environmentObject(auth).environmentObject(theme)
        }
        .sheet(isPresented: $showQQLogin) {
            QQLoginSheet().environmentObject(theme)
        }
        .sheet(isPresented: $showKugouLogin) {
            KugouLoginSheet().environmentObject(theme)
        }
        .confirmationDialog("退出网易云登录？", isPresented: $confirmNeteaseLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                auth.logout()
                WebLoginDataCleaner.clearNetEase()
                ToastCenter.shared.show("已退出网易云账号")
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func platformCard(_ row: PlatformRow) -> some View {
        HStack(spacing: 12) {
            brandIcon(row.provider)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(SoundHubFont.appFont(15, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    if let badge = row.badge, !badge.isEmpty {
                        Text(badge)
                            .font(SoundHubFont.appFont(9, .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color(red: 0.95, green: 0.75, blue: 0.25)))
                    }
                }
                Text(row.detail)
                    .font(SoundHubFont.appFont(11))
                    .foregroundStyle(Color.soundhubComment)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                SoundHubHaptics.tap()
                switch row.provider {
                case .netease:
                    if auth.isLoggedIn { confirmNeteaseLogout = true } else { showNeteaseLogin = true }
                case .qq:
                    if qqAuth.isLoggedIn {
                        qqAuth.logout()
                        ToastCenter.shared.show("已退出 QQ 音乐")
                    } else { showQQLogin = true }
                case .kugou:
                    if kugouAuth.isLoggedIn {
                        kugouAuth.logout()
                        ToastCenter.shared.show("已退出酷狗音乐")
                    } else { showKugouLogin = true }
                }
            } label: {
                Text(row.loggedIn ? "退出" : "登录")
                    .font(SoundHubFont.appFont(12, .semibold))
                    .foregroundStyle(row.loggedIn ? Color.soundhubComment : Color.soundhubHighlight)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(Color.primary.opacity(0.07))
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background {
            SoundHubGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func brandIcon(_ provider: SearchProvider) -> some View {
        Group {
            if let name = provider.brandImageName {
                Image(name).resizable().scaledToFit()
            } else {
                Image(systemName: provider.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
