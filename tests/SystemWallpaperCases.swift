import Foundation
import GiveMeABreakEngine

// 跟随系统壁纸纯逻辑用例：Index.plist 解析 / assetID 白名单 / 航拍视频定位 / 默认航拍 / resolve 优先级。
// 夹具在内存中构造（二进制 plist），文件系统谓词全部注入，不触真实磁盘。

private let assetID = "4207734D-74FE-4F92-B5E1-6EC8DEE24A15"
private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
private let videoDirs = SystemWallpaper.liveAerialVideoDirectories(home: home)
private let defaultDir = SystemWallpaper.defaultWallpaperDirectory
private let defaultVideo = defaultDir.appendingPathComponent("Golden Gate.mov")

private func bplist(_ obj: Any) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: obj, format: .binary, options: 0)
}

/// 航拍 choice 的 `Configuration`：内嵌二进制 plist `{assetID}`。
private func aerialConfig(_ id: String) -> Data { bplist(["assetID": id]) }

/// 构造 `Index.plist`：`AllSpacesAndDisplays.<slot>.Content.Choices[0]`。
private func indexPlist(provider: String, configuration: Data = Data(), slot: String = "Linked") -> Data {
    let choice: [String: Any] = ["Provider": provider, "Configuration": configuration, "Files": [Any]()]
    return bplist(["AllSpacesAndDisplays": ["Type": "linked", slot: ["Content": ["Choices": [choice]]]]])
}

private func exists(_ urls: [URL]) -> (URL) -> Bool {
    let paths = Set(urls.map(\.path))
    return { paths.contains($0.path) }
}

private func videoPath(_ source: SystemWallpaperSource) -> String? {
    if case .video(let url) = source { return url.path }
    return nil
}

func runSystemWallpaperCases() {
    print("▸ SystemWallpaper")

    let aerials = SystemWallpaper.aerialsProvider
    let newVideo = videoDirs[0].appendingPathComponent("\(assetID).mov")
    let legacyVideo = videoDirs[1].appendingPathComponent("\(assetID).mov")

    // MARK: choice(fromIndexPlist:)

    test("choice：航拍经 Linked → 解出 assetID") {
        let c = SystemWallpaper.choice(fromIndexPlist: indexPlist(provider: aerials, configuration: aerialConfig(assetID)))
        expectEqual(c, SystemWallpaper.Choice(provider: aerials, assetID: assetID), "Linked 槽位应解出航拍 assetID")
    }

    test("choice：航拍经 Desktop → 解出 assetID") {
        let data = indexPlist(provider: aerials, configuration: aerialConfig(assetID), slot: "Desktop")
        expectEqual(SystemWallpaper.choice(fromIndexPlist: data),
                    SystemWallpaper.Choice(provider: aerials, assetID: assetID), "Desktop 槽位应解出航拍 assetID")
    }

    test("choice：系统默认（空 Configuration）→ provider default、assetID nil") {
        let c = SystemWallpaper.choice(fromIndexPlist: indexPlist(provider: SystemWallpaper.defaultProvider))
        expectEqual(c, SystemWallpaper.Choice(provider: "default", assetID: nil), "默认壁纸应无 assetID")
    }

    test("choice：非航拍 provider 即使带 assetID 也不解出") {
        let provider = "com.apple.wallpaper.choice.image"
        let c = SystemWallpaper.choice(fromIndexPlist: indexPlist(provider: provider, configuration: aerialConfig(assetID)))
        expectEqual(c, SystemWallpaper.Choice(provider: provider, assetID: nil), "仅航拍 provider 才读 assetID")
    }

    test("choice：nil / 垃圾数据 / 缺键 → nil") {
        expect(SystemWallpaper.choice(fromIndexPlist: nil) == nil, "nil 数据应返回 nil")
        expect(SystemWallpaper.choice(fromIndexPlist: Data("garbage".utf8)) == nil, "非 plist 应返回 nil")
        expect(SystemWallpaper.choice(fromIndexPlist: bplist(["Other": 1])) == nil, "缺 AllSpacesAndDisplays 应返回 nil")
        expect(SystemWallpaper.choice(fromIndexPlist: bplist(["AllSpacesAndDisplays": ["Type": "linked"]])) == nil,
               "缺 Linked/Desktop 应返回 nil")
        let emptyChoices = bplist(["AllSpacesAndDisplays": ["Linked": ["Content": ["Choices": [Any]()]]]])
        expect(SystemWallpaper.choice(fromIndexPlist: emptyChoices) == nil, "Choices 为空应返回 nil")
        let noProvider = bplist(["AllSpacesAndDisplays": ["Linked": ["Content": ["Choices": [["Files": [Any]()]]]]]])
        expect(SystemWallpaper.choice(fromIndexPlist: noProvider) == nil, "缺 Provider 应返回 nil")
    }

    test("choice：恶意 assetID → assetID nil（防路径穿越）") {
        for bad in ["../../evil", "", "/etc/passwd", "\(assetID)/../x", "{\(assetID)}"] {
            let c = SystemWallpaper.choice(fromIndexPlist: indexPlist(provider: aerials, configuration: aerialConfig(bad)))
            expectEqual(c, SystemWallpaper.Choice(provider: aerials, assetID: nil), "非法 assetID「\(bad)」应被拒")
        }
    }

    // MARK: isValidAssetID

    test("isValidAssetID：标准 UUID（大小写）通过，其余拒绝") {
        expect(SystemWallpaper.isValidAssetID(assetID), "大写 UUID 应通过")
        expect(SystemWallpaper.isValidAssetID(assetID.lowercased()), "小写 UUID 应通过")
        for bad in ["", "../../evil", "/etc/passwd", "{\(assetID)}", "\(assetID)/../x",
                    assetID.replacingOccurrences(of: "-", with: ""), "\(assetID).mov",
                    String(assetID.dropLast()) + "G", " \(assetID)"] {
            expect(!SystemWallpaper.isValidAssetID(bad), "「\(bad)」应拒绝")
        }
    }

    // MARK: aerialVideo(assetID:in:fileExists:)

    test("aerialVideo：新旧目录均存在 → 取首个（新目录）") {
        let url = SystemWallpaper.aerialVideo(assetID: assetID, in: videoDirs, fileExists: exists([newVideo, legacyVideo]))
        expectEqual(url?.path, newVideo.path, "应优先新目录")
    }

    test("aerialVideo：新目录缺失 → 回落旧版 idleassetsd 目录") {
        let url = SystemWallpaper.aerialVideo(assetID: assetID, in: videoDirs, fileExists: exists([legacyVideo]))
        expectEqual(url?.path, legacyVideo.path, "应回落旧目录")
    }

    test("aerialVideo：均不存在 → nil") {
        expect(SystemWallpaper.aerialVideo(assetID: assetID, in: videoDirs, fileExists: exists([])) == nil, "未下载应返回 nil")
    }

    test("aerialVideo：非法 assetID 即使谓词恒真也返回 nil") {
        for bad in ["../../evil", "", "/etc/passwd", "\(assetID)/../x"] {
            expect(SystemWallpaper.aerialVideo(assetID: bad, in: videoDirs, fileExists: { _ in true }) == nil,
                   "非法 assetID「\(bad)」不应拼出路径")
        }
    }

    // MARK: defaultAerialVideo(resolvedDefaultDesktop:contentsOf:)

    test("defaultAerialVideo：默认壁纸位于 .default 目录 → 取同目录 .mov") {
        var listed: String?
        let url = SystemWallpaper.defaultAerialVideo(
            resolvedDefaultDesktop: defaultDir.appendingPathComponent("Golden Gate.heic"),
            contentsOf: { dir in
                listed = dir.path
                return [dir.appendingPathComponent("Golden Gate.heic"), dir.appendingPathComponent("Golden Gate.mov")]
            })
        expectEqual(url?.path, defaultVideo.path, "应取同目录的 Golden Gate.mov")
        expectEqual(listed, defaultDir.path, "应仅列举 .default 目录")
    }

    test("defaultAerialVideo：默认壁纸在别处（如 Sonoma 静帧）→ nil") {
        let url = SystemWallpaper.defaultAerialVideo(
            resolvedDefaultDesktop: URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic"),
            contentsOf: { [$0.appendingPathComponent("x.mov")] })
        expect(url == nil, "不在 .default 目录不应误判为航拍")
    }

    test("defaultAerialVideo：nil 输入 → nil") {
        expect(SystemWallpaper.defaultAerialVideo(resolvedDefaultDesktop: nil,
                                                  contentsOf: { [$0.appendingPathComponent("x.mov")] }) == nil,
               "无解析路径应返回 nil")
    }

    test("defaultAerialVideo：目录内无 .mov → nil") {
        let url = SystemWallpaper.defaultAerialVideo(
            resolvedDefaultDesktop: defaultDir.appendingPathComponent("Golden Gate.heic"),
            contentsOf: { [$0.appendingPathComponent("Golden Gate.heic"), $0.appendingPathComponent("thumb.jpg")] })
        expect(url == nil, "无 .mov 应返回 nil")
    }

    test("defaultAerialVideo：混杂 .heic/.jpg 时只取 .mov") {
        let url = SystemWallpaper.defaultAerialVideo(
            resolvedDefaultDesktop: defaultDir.appendingPathComponent("Golden Gate.heic"),
            contentsOf: { [$0.appendingPathComponent("a.heic"), $0.appendingPathComponent("b.jpg"),
                           $0.appendingPathComponent("Golden Gate.mov")] })
        expectEqual(url?.path, defaultVideo.path, "应忽略非 .mov 文件")
    }

    // MARK: isBuiltinDefault

    test("isBuiltinDefault：内置默认航拍 → true；用户 / 旧版目录航拍、仅前缀相同的他处文件 → false") {
        expect(SystemWallpaper.isBuiltinDefault(defaultVideo), "位于 .default 目录的 .mov 应判为内置默认")
        expect(!SystemWallpaper.isBuiltinDefault(newVideo), "用户目录下的航拍不是内置默认")
        expect(!SystemWallpaper.isBuiltinDefault(legacyVideo), "idleassetsd 目录下的航拍不是内置默认")
        expect(!SystemWallpaper.isBuiltinDefault(URL(fileURLWithPath: "/System/Library/Wallpapers/Other.mov")),
               "仅 /System/Library/Wallpapers/ 前缀相同、目录不同，不应判为内置默认")
    }

    // MARK: resolve 优先级

    let aerialChoice = SystemWallpaper.Choice(provider: aerials, assetID: assetID)
    let defaultChoice = SystemWallpaper.Choice(provider: SystemWallpaper.defaultProvider, assetID: nil)

    test("resolve：选中航拍且已下载 → 播放该视频") {
        let r = SystemWallpaper.resolve(choice: aerialChoice, aerialVideoDirectories: videoDirs,
                                        defaultAerialVideo: defaultVideo, fileExists: exists([newVideo, defaultVideo]))
        expectEqual(videoPath(r), newVideo.path, "应播放选中的航拍视频（优先于默认航拍）")
    }

    test("resolve：选中航拍但未下载 → 静帧（不回落默认航拍）") {
        let r = SystemWallpaper.resolve(choice: aerialChoice, aerialVideoDirectories: videoDirs,
                                        defaultAerialVideo: defaultVideo, fileExists: exists([defaultVideo]))
        expectEqual(r, .still, "未下载应显示静帧")
    }

    test("resolve：系统默认 + 内置航拍存在 → 播放默认航拍") {
        let r = SystemWallpaper.resolve(choice: defaultChoice, aerialVideoDirectories: videoDirs,
                                        defaultAerialVideo: defaultVideo, fileExists: exists([defaultVideo]))
        expectEqual(videoPath(r), defaultVideo.path, "默认壁纸为航拍时应播放内置视频")
    }

    test("resolve：系统默认 + 无内置航拍 → 静帧") {
        let r = SystemWallpaper.resolve(choice: defaultChoice, aerialVideoDirectories: videoDirs,
                                        defaultAerialVideo: nil, fileExists: { _ in true })
        expectEqual(r, .still, "无内置航拍应显示静帧")
    }

    test("resolve：Index.plist 缺失/损坏（choice nil）→ 静帧，不臆断为默认航拍（即使内置航拍存在）") {
        let r = SystemWallpaper.resolve(choice: nil, aerialVideoDirectories: videoDirs,
                                        defaultAerialVideo: defaultVideo, fileExists: exists([defaultVideo]))
        expectEqual(r, .still, "读不到选择应沿用系统当前壁纸图，而非默认航拍")
    }

    test("resolve：非航拍 provider → 静帧（即使内置航拍存在）") {
        let image = SystemWallpaper.Choice(provider: "com.apple.wallpaper.choice.image", assetID: nil)
        let r = SystemWallpaper.resolve(choice: image, aerialVideoDirectories: videoDirs,
                                        defaultAerialVideo: defaultVideo, fileExists: { _ in true })
        expectEqual(r, .still, "用户选了静态壁纸应显示静帧")
    }

    test("resolve：选中航拍但 assetID 非法（nil）→ 静帧") {
        let invalid = SystemWallpaper.Choice(provider: aerials, assetID: nil)
        let r = SystemWallpaper.resolve(choice: invalid, aerialVideoDirectories: videoDirs,
                                        defaultAerialVideo: defaultVideo, fileExists: { _ in true })
        expectEqual(r, .still, "assetID 非法应显示静帧，不回落默认航拍")
    }
}
