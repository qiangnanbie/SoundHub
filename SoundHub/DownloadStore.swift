import SwiftUI

/// 已下载歌曲的元数据
struct DownloadedTrack: Identifiable, Codable, Hashable {
    let id: String
    let songID: Int
    let sourceRaw: String
    let name: String
    let artists: String
    let album: String
    let coverURLString: String?
    let duration: TimeInterval
    let fileName: String
    let fileSize: Int64
    let qualityName: String
    let addedAt: Date

    var source: SongSource { SongSource(rawValue: sourceRaw) ?? .netease }
    var coverURL: URL? { coverURLString.flatMap(URL.init(string:)) }

    /// 还原成可播放的 Song
    var song: Song {
        Song(
            id: songID,
            name: name,
            artists: artists,
            album: album,
            coverURL: coverURL,
            duration: duration,
            source: source
        )
    }
}

/// 下载库：文件落盘 + 索引持久化，供「下载」Tab 展示
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published private(set) var tracks: [DownloadedTrack] = []

    /// 索引始终放在 App 内，避免用户换目录后丢失下载记录
    private let indexURL: URL
    private let fileManager = FileManager.default

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let indexDirectory = base.appendingPathComponent("SoundHubDownloads", isDirectory: true)
        try? fileManager.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        indexURL = indexDirectory.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        loadIndex()
        pruneMissingFiles()
    }

    // MARK: - 读写

    var directory: URL { DownloadLocation.shared.directory }

    func fileURL(for track: DownloadedTrack) -> URL {
        directory.appendingPathComponent(track.fileName)
    }

    func contains(song: Song) -> Bool {
        tracks.contains { $0.id == Self.identifier(for: song) }
    }

    @discardableResult
    func importFile(from source: URL, song: Song, qualityName: String, ext: String) -> DownloadedTrack? {
        let trackID = Self.identifier(for: song)
        if let existing = tracks.first(where: { $0.id == trackID }) {
            try? fileManager.removeItem(at: fileURL(for: existing))
        }
        let safe = "\(song.name) - \(song.artists)"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let unique = String(UUID().uuidString.prefix(4))
        let fileName = "\(safe.isEmpty ? "track" : safe)-\(unique).\(ext)"
        var dest = directory.appendingPathComponent(fileName)
        var copied = false
        DownloadLocation.shared.withDirectory { dir in
            dest = dir.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: dest)
            if (try? fileManager.copyItem(at: source, to: dest)) != nil { copied = true }
        }
        guard copied else { return nil }
        let size = (try? fileManager.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
        let track = DownloadedTrack(
            id: trackID,
            songID: song.id,
            sourceRaw: song.source.rawValue,
            name: song.name,
            artists: song.artists,
            album: song.album,
            coverURLString: song.coverURL?.absoluteString,
            duration: song.duration,
            fileName: fileName,
            fileSize: size,
            qualityName: qualityName,
            addedAt: Date()
        )
        tracks.removeAll { $0.id == trackID }
        tracks.insert(track, at: 0)
        saveIndex()
        return track
    }

    func delete(_ track: DownloadedTrack) {
        try? fileManager.removeItem(at: fileURL(for: track))
        tracks.removeAll { $0.id == track.id }
        saveIndex()
    }

    func deleteAll() {
        for track in tracks {
            try? fileManager.removeItem(at: fileURL(for: track))
        }
        tracks = []
        saveIndex()
    }

    /// 下载目录里的全部文件（含未入库的散落文件）
    func allFiles() -> [URL] {
        var result: [URL] = []
        DownloadLocation.shared.withDirectory { dir in
            let items = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
            result = items
                .filter { $0.lastPathComponent != "index.json" }
                .filter { !$0.hasDirectoryPath }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return result
    }

    var totalBytes: Int64 {
        tracks.reduce(0) { $0 + $1.fileSize }
    }

    /// 重复扫描：同名同大小视为同一份的多版本
    func duplicateReport() -> (groups: Int, wastedBytes: Int64) {
        var buckets: [String: [DownloadedTrack]] = [:]
        for track in tracks {
            let key = "\(track.name)|\(track.artists)"
            buckets[key, default: []].append(track)
        }
        var groups = 0
        var wasted: Int64 = 0
        for (_, list) in buckets where list.count > 1 {
            groups += 1
            wasted += list.dropFirst().reduce(0) { $0 + $1.fileSize }
        }
        return (groups, wasted)
    }

    // MARK: - 内部

    private static func identifier(for song: Song) -> String {
        "\(song.source.rawValue)-\(song.id)"
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([DownloadedTrack].self, from: data) else { return }
        tracks = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func pruneMissingFiles() {
        let kept = tracks.filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
        if kept.count != tracks.count {
            tracks = kept
            saveIndex()
        }
    }
}
