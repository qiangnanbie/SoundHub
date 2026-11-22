import SwiftUI
import UniformTypeIdentifiers

/// 下载位置：默认 App 内，也可让用户选择自定义目录（存安全作用域书签）
final class DownloadLocation: ObservableObject {
    static let shared = DownloadLocation()

    private let bookmarkKey = "soundhub.download.folderBookmark"
    private let nameKey = "soundhub.download.folderName"

    @Published private(set) var folderName: String = ""
    @Published private(set) var isCustom: Bool = false

    private init() {
        isCustom = UserDefaults.standard.data(forKey: bookmarkKey) != nil
        folderName = UserDefaults.standard.string(forKey: nameKey) ?? ""
    }

    /// App 内置目录
    var internalDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SoundHubDownloads", isDirectory: true)
    }

    /// 当前生效的下载目录
    var directory: URL {
        if let custom = resolvedCustomDirectory() { return custom }
        return internalDirectory
    }

    var displayName: String {
        isCustom && !folderName.isEmpty ? folderName : "应用内"
    }

    var subtitle: String {
        isCustom ? "自定义目录" : "应用内"
    }

    func setCustomFolder(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
        folderName = url.lastPathComponent
        isCustom = true
    }

    func resetToInternal() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        folderName = ""
        isCustom = false
    }

    /// 在安全作用域内执行文件操作
    @discardableResult
    func withDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
        let url = directory
        let scoped = isCustom ? url.startAccessingSecurityScopedResource() : false
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return try body(url)
    }

    private func resolvedCustomDirectory() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let refreshed = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }
}

/// 目录选择器（UIDocumentPicker，iOS 15 可用）
struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

/// 音频文件选择器（用于从文件 App 导入本地歌曲）
struct AudioFilePicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick([])
        }
    }
}
