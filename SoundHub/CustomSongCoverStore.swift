import SwiftUI
import UIKit

/// 自定义歌曲封面：按「原封面地址」索引，替换后所有使用该封面的列表自动生效。
final class CustomSongCoverStore: ObservableObject {
    static let shared = CustomSongCoverStore()

    /// 变更计数：视图可据此刷新
    @Published private(set) var revision = 0

    private let directory: URL
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("SoundHubCustomCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache.countLimit = 160
    }

    func hasCover(for url: URL?) -> Bool {
        guard let key = Self.key(for: url) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(key).path)
    }

    func image(for url: URL?) -> UIImage? {
        guard let key = Self.key(for: url) else { return nil }
        if let hit = cache.object(forKey: key as NSString) { return hit }
        let file = directory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: file.path),
              let image = UIImage(contentsOfFile: file.path) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    func setCover(_ image: UIImage, for url: URL?) throws {
        guard let key = Self.key(for: url) else { throw CustomCoverError.invalidTarget }
        let side = min(max(max(image.size.width, image.size.height), 320), 1200)
        let normalized = Self.squareImage(image, side: side)
        guard let data = normalized.jpegData(compressionQuality: 0.92) else {
            throw CustomCoverError.encodeFailed
        }
        let file = directory.appendingPathComponent(key)
        try data.write(to: file, options: .atomic)
        cache.setObject(normalized, forKey: key as NSString)
        revision += 1
    }

    func removeCover(for url: URL?) {
        guard let key = Self.key(for: url) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(key))
        cache.removeObject(forKey: key as NSString)
        revision += 1
    }

    private static func squareImage(_ image: UIImage, side: CGFloat) -> UIImage {
        let target = CGSize(width: side, height: side)
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    /// 用原始封面地址生成稳定文件名
    private static func key(for url: URL?) -> String? {
        guard let raw = url?.absoluteString, !raw.isEmpty else { return nil }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "cover-\(String(hash, radix: 16)).jpg"
    }
}

enum CustomCoverError: LocalizedError {
    case invalidTarget
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidTarget: return "这首歌没有封面地址，无法设置自定义封面"
        case .encodeFailed: return "图片编码失败"
        }
    }
}
