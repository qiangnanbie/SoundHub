import SwiftUI

/// 下载页：歌曲 / 文件两个视图，展示已下载内容
struct DownloadView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var store = DownloadStore.shared
    @ObservedObject private var location = DownloadLocation.shared

    private enum Segment: String, CaseIterable { case songs = "歌曲", files = "文件" }

    @State private var segment: Segment = .songs
    @State private var searchText = ""
    @State private var editing = false
    @State private var sortByNewest = true
    @State private var scanResult = ""
    @State private var shareFile: ShareFileItem?
    @State private var showShareSheet = false
    @State private var showFolderPicker = false
    @State private var showLocationOptions = false

    private var filteredTracks: [DownloadedTrack] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = keyword.isEmpty ? store.tracks : store.tracks.filter {
            $0.name.lowercased().contains(keyword) || $0.artists.lowercased().contains(keyword)
        }
        return sortByNewest ? base : base.sorted { $0.name < $1.name }
    }

    private var filteredFiles: [URL] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let files = store.allFiles()
        guard !keyword.isEmpty else { return files }
        return files.filter { $0.lastPathComponent.lowercased().contains(keyword) }
    }

    var body: some View {
        SoundHubNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.customBackground)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        segmentPicker
                        infoCards
                        searchField
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 140)
                }
                .soundhubScrollIndicatorsHidden()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showShareSheet) {
                if let shareFile { ShareSheet(items: [shareFile.url]) }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { url in
                    guard let url else { return }
                    do {
                        try location.setCustomFolder(url)
                        ToastCenter.shared.show("下载位置已切换到「\(url.lastPathComponent)」")
                    } catch {
                        ToastCenter.shared.show("无法使用该目录：\(error.localizedDescription)")
                    }
                }
            }
            .confirmationDialog("下载位置", isPresented: $showLocationOptions, titleVisibility: .visible) {
                Button("选择自定义文件夹") { showFolderPicker = true }
                if location.isCustom {
                    Button("恢复为应用内目录", role: .destructive) {
                        location.resetToInternal()
                        ToastCenter.shared.show("下载位置已恢复为应用内")
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(location.isCustom
                     ? "当前：\(location.displayName)。已下载的文件不会自动搬迁。"
                     : "默认保存在应用内，卸载 App 会一起删除。可改为自定义文件夹。")
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center) {
            Text("下载")
                .font(SoundHubFont.appFont(32, .bold))
                .foregroundStyle(Color.soundhubLabel)
            Spacer()
            HStack(spacing: 8) {
                circleButton("plus") { segment = .songs }
                Button {
                    SoundHubHaptics.tap()
                    editing.toggle()
                } label: {
                    Text(editing ? "完成" : "编辑")
                        .font(SoundHubFont.appFont(14, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                circleButton("arrow.up.arrow.down") {
                    sortByNewest.toggle()
                    SoundHubHaptics.select()
                }
            }
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundHubHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.soundhubLabel)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var segmentPicker: some View {
        HStack(spacing: 0) {
            ForEach(Segment.allCases, id: \.self) { item in
                Button {
                    guard segment != item else { return }
                    SoundHubHaptics.select()
                    segment = item
                    searchText = ""
                } label: {
                    VStack(spacing: 7) {
                        Text(item.rawValue)
                            .font(SoundHubFont.appFont(16, .semibold))
                            .foregroundStyle(segment == item ? Color.primary : Color.primary.opacity(0.45))
                        Capsule()
                            .fill(segment == item ? Color.soundhubHighlight : Color.clear)
                            .frame(width: 28, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var infoCards: some View {
        HStack(spacing: 10) {
            Button {
                SoundHubHaptics.tap()
                showLocationOptions = true
            } label: {
                infoCard(
                    icon: "internaldrive",
                    title: "下载位置",
                    subtitle: location.displayName,
                    footer: location.isCustom ? "点按可更换目录" : "⚠️ 卸载 App 会删除"
                )
            }
            .buttonStyle(.plain)
            Button {
                SoundHubHaptics.tap()
                let report = store.duplicateReport()
                scanResult = report.groups == 0
                    ? "未发现重复"
                    : "发现 \(report.groups) 组重复，可清理 \(ByteCountFormatter.string(fromByteCount: report.wastedBytes, countStyle: .file))"
            } label: {
                infoCard(
                    icon: "doc.on.doc",
                    title: "重复扫描",
                    subtitle: scanResult.isEmpty ? "还未扫描" : scanResult,
                    footer: "支持重复和多版本识别"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func infoCard(icon: String, title: String, subtitle: String, footer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.soundhubHighlight)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.soundhubHighlight.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SoundHubFont.appFont(13, .semibold))
                        .foregroundStyle(Color.soundhubLabel)
                    Text(subtitle)
                        .font(SoundHubFont.appFont(11))
                        .foregroundStyle(Color.soundhubComment)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(footer)
                .font(SoundHubFont.appFont(10))
                .foregroundStyle(Color.soundhubComment.opacity(0.9))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.soundhubComment)
            TextField(segment == .songs ? "搜索歌曲/歌手" : "搜索文件名", text: $searchText)
                .font(SoundHubFont.appFont(13))
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.soundhubComment)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if segment == .songs {
            if filteredTracks.isEmpty {
                emptyState(
                    icon: "arrow.down.circle",
                    title: "暂无下载",
                    subtitle: "在播放页面点击「更多」下载喜欢的歌曲"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredTracks) { track in
                        trackRow(track)
                    }
                }
            }
        } else {
            if filteredFiles.isEmpty {
                emptyState(
                    icon: "folder",
                    title: "暂无文件",
                    subtitle: "下载目录目前是空的"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredFiles, id: \.self) { file in
                        fileRow(file)
                    }
                }
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 112, height: 112)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.soundhubComment.opacity(0.7))
            }
            .padding(.top, 60)
            Text(title)
                .font(SoundHubFont.appFont(17, .semibold))
                .foregroundStyle(Color.soundhubLabel)
            Text(subtitle)
                .font(SoundHubFont.appFont(13))
                .foregroundStyle(Color.soundhubComment)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func trackRow(_ track: DownloadedTrack) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: track.coverURL, size: 46, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(SoundHubFont.appFont(14, .semibold))
                    .foregroundStyle(Color.soundhubLabel)
                    .lineLimit(1)
                Text("\(track.artists) · \(track.qualityName) · \(ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file))")
                    .font(SoundHubFont.appFont(11))
                    .foregroundStyle(Color.soundhubComment)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(soundhubTimeString(track.duration))
                .font(SoundHubFont.appFont(11, .medium, .monospaced))
                .foregroundStyle(Color.soundhubComment)
            if editing {
                Button {
                    SoundHubHaptics.tap()
                    store.delete(track)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editing else { return }
            player.play(songs: [track.song], startAt: 0)
        }
        .contextMenu {
            Button {
                shareFile = ShareFileItem(url: store.fileURL(for: track))
                showShareSheet = true
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                store.delete(track)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func fileRow(_ file: URL) -> some View {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        return HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.soundhubHighlight)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.soundhubHighlight.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.lastPathComponent)
                    .font(SoundHubFont.appFont(13, .medium))
                    .foregroundStyle(Color.soundhubLabel)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(SoundHubFont.appFont(11))
                    .foregroundStyle(Color.soundhubComment)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .contextMenu {
            Button {
                shareFile = ShareFileItem(url: file)
                showShareSheet = true
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
            }
        }
    }
}
