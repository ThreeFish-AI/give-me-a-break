import Foundation

// MARK: - 遮罩背景：跟随系统壁纸

/// 遮罩背景的解析结果。
public enum SystemWallpaperSource: Equatable, Sendable {
    /// 系统航拍视频：遮罩静音循环播放（Media Engine 硬件解码，近乎零 GPU 开销）。
    case video(URL)
    /// 非航拍壁纸，或航拍视频不可得：遮罩按屏显示桌面静帧（`NSWorkspace.desktopImageURL(for:)`）。
    case still
}

/// 「跟随系统壁纸」解析核心：纯函数，文件系统谓词全部注入（同 `validateCodingProxySettings` 范式），可单测。
///
/// 依据的均为 macOS **未公开的私有布局**，故每一步失败都降级为静帧，绝不让遮罩失效：
/// - 当前选择：`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` →
///   `AllSpacesAndDisplays.{Linked|Desktop}.Content.Choices[0]`；`Provider` 为航拍时，
///   `Configuration`（二进制 plist）内含 `assetID`（先例：sorkila/lockpaw PR #21）。
/// - 航拍视频：macOS 26+ 位于 `~/Library/Application Support/com.apple.wallpaper/aerials/videos/<assetID>.mov`；
///   macOS 14/15 位于 `/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/<assetID>.mov`。
/// - 系统默认壁纸即航拍时（macOS 27：`DefaultDesktop.heic` → `/System/Library/Wallpapers/.default/`），
///   同目录内置一段免下载的 `.mov`。
///
/// 只读取用户本机已有的文件，不下载、不打包、不分发（版权归 Apple）。
public enum SystemWallpaper {
    public static let aerialsProvider = "com.apple.wallpaper.choice.aerials"
    public static let defaultProvider = "default"

    /// 系统默认壁纸的入口（符号链接，指向当期默认壁纸）。
    public static let defaultDesktopImage = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
    /// 系统默认航拍所在目录（macOS 27 起，SIP 只读）。
    public static let defaultWallpaperDirectory = URL(fileURLWithPath: "/System/Library/Wallpapers/.default", isDirectory: true)

    /// 当前壁纸选择（`Index.plist` 中「全部显示器」的首个 choice）。
    public struct Choice: Equatable, Sendable {
        public let provider: String
        /// 仅航拍且通过 `isValidAssetID` 时非 nil。
        public let assetID: String?

        public init(provider: String, assetID: String?) {
            self.provider = provider
            self.assetID = assetID
        }
    }

    // MARK: - 路径

    public static func indexPlistURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// 航拍视频目录，按新→旧探测顺序。
    public static func liveAerialVideoDirectories(home: URL) -> [URL] {
        [
            home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS", isDirectory: true),
        ]
    }

    // MARK: - 解析

    /// 解析 `Index.plist`。结构不符 / 数据缺失 → nil（调用方按「未知」处理）。
    /// 只读「全部显示器」的选择：分屏、分 Space 的单独壁纸不区分（已知限制）。
    public static func choice(fromIndexPlist data: Data?) -> Choice? {
        guard let data,
              let root = plist(data),
              let all = root["AllSpacesAndDisplays"] as? [String: Any],
              let entry = (all["Linked"] ?? all["Desktop"]) as? [String: Any],
              let content = entry["Content"] as? [String: Any],
              let first = (content["Choices"] as? [[String: Any]])?.first,
              let provider = first["Provider"] as? String
        else { return nil }

        var assetID: String?
        if provider == aerialsProvider,
           let config = first["Configuration"] as? Data,
           let id = plist(config)?["assetID"] as? String,
           isValidAssetID(id) {
            assetID = id
        }
        return Choice(provider: provider, assetID: assetID)
    }

    /// assetID 白名单：必须是标准 UUID（8-4-4-4-12 十六进制）。
    /// 由此杜绝 `../`、绝对路径、空串等拼接注入（防路径穿越第一道关）。
    public static func isValidAssetID(_ id: String) -> Bool {
        id.count == 36 && UUID(uuidString: id) != nil
    }

    /// 选中航拍在本机的视频文件：按目录顺序取首个存在者。
    /// 拼接结果须仍直属该目录（防路径穿越第二道关，与白名单互为冗余）。
    public static func aerialVideo(assetID: String, in directories: [URL],
                                   fileExists: (URL) -> Bool) -> URL? {
        guard isValidAssetID(assetID) else { return nil }
        for dir in directories {
            let base = dir.standardizedFileURL
            let candidate = base.appendingPathComponent("\(assetID).mov").standardizedFileURL
            guard candidate.deletingLastPathComponent().path == base.path else { continue }
            if fileExists(candidate) { return candidate }
        }
        return nil
    }

    /// 系统默认壁纸为航拍时的内置视频。
    /// - Parameter resolvedDefaultDesktop: `DefaultDesktop.heic` 解析符号链接后的真实路径。
    /// 仅当它落在 `/System/Library/Wallpapers/.default/` 时才取同目录的 `.mov`——
    /// 不写死文件名，且默认壁纸不是航拍的系统版本（如 macOS 14 Sonoma）不会误判。
    public static func defaultAerialVideo(resolvedDefaultDesktop: URL?,
                                          contentsOf: (URL) -> [URL]) -> URL? {
        guard let image = resolvedDefaultDesktop?.standardizedFileURL else { return nil }
        let dir = image.deletingLastPathComponent()
        guard dir.path == defaultWallpaperDirectory.standardizedFileURL.path else { return nil }
        return contentsOf(dir)
            .filter { $0.pathExtension.lowercased() == "mov" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// 决定遮罩背景：航拍视频，或桌面静帧。
    /// - Parameters:
    ///   - choice: 当前壁纸选择；nil 表示 `Index.plist` 缺失或无法解析。
    ///   - aerialVideoDirectories: 航拍视频目录（`liveAerialVideoDirectories`）。
    ///   - defaultAerialVideo: 系统默认航拍的内置视频（`defaultAerialVideo(...)`）；nil 表示本系统无。
    ///   - fileExists: 文件存在性谓词。
    public static func resolve(choice: Choice?,
                               aerialVideoDirectories: [URL],
                               defaultAerialVideo: URL?,
                               fileExists: (URL) -> Bool) -> SystemWallpaperSource {
        switch choice?.provider {
        case aerialsProvider?:
            // 选中航拍：只认本机已下载的那一段；未下载退静帧（与桌面所见一致），不串到默认航拍
            guard let id = choice?.assetID,
                  let url = aerialVideo(assetID: id, in: aerialVideoDirectories, fileExists: fileExists)
            else { return .still }
            return .video(url)
        case defaultProvider?, nil:
            // 系统默认，或 Index.plist 缺失/损坏：默认壁纸是航拍且内置视频可读时播放
            guard let url = defaultAerialVideo, fileExists(url) else { return .still }
            return .video(url)
        default:
            return .still  // 图片 / 动态 / 纯色等非航拍壁纸
        }
    }

    // MARK: - Live（真实文件系统）

    /// 读取本机当前状态并解析（一个约 0.4KB 的 plist + 几次 stat，微秒级，可在主线程调用）。
    public static func current(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> SystemWallpaperSource {
        let fm = FileManager.default
        let builtin = defaultAerialVideo(
            resolvedDefaultDesktop: defaultDesktopImage.resolvingSymlinksInPath(),
            contentsOf: { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        )
        return resolve(
            choice: choice(fromIndexPlist: try? Data(contentsOf: indexPlistURL(home: home))),
            aerialVideoDirectories: liveAerialVideoDirectories(home: home),
            defaultAerialVideo: builtin,
            fileExists: { fm.isReadableFile(atPath: $0.path) }
        )
    }

    private static func plist(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
