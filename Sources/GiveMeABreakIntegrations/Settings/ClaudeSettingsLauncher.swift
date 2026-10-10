import AppKit
import Foundation

/// 「Agentic AI」设置页 Claude 设置行的编辑器探测与打开助手（集成层，AppKit 依赖）。
///
/// 与 Engine 层 `AgentSettings`（纯 Foundation 的持久化字段）正交：此处只负责
/// (a) 探测系统已安装的候选编辑器、(b) 取应用图标、(c) 以选定编辑器打开
/// `~/.claude/settings.json`（缺失时在访达中定位 `~/.claude` 兜底，不静默创建文件）。
/// 无状态命名空间，全部静态方法；错误经 `NSLog` 记录，语义对齐 `LiveMusicController`。
enum ClaudeSettingsLauncher {

    // MARK: - 候选与探测

    /// 一个可选编辑器候选（展示名 + bundle id）。
    struct EditorCandidate: Identifiable, Hashable {
        let name: String
        let bundleId: String
        var id: String { bundleId }
    }

    /// 一个已安装的编辑器（候选 + 解析出的 app URL，用于取图标 / 打开）。
    struct InstalledEditor: Identifiable, Hashable {
        let candidate: EditorCandidate
        let appURL: URL
        var id: String { candidate.bundleId }
        var name: String { candidate.name }
        var bundleId: String { candidate.bundleId }
    }

    /// 策展的常见 macOS 代码编辑器候选清单（保序）。
    /// 探测时经 `urlForApplication(withBundleIdentifier:)` 校验，未安装 / bundle id 不符者
    /// 自动过滤——故即便个别 id 有出入也无害（仅表现为该项不出现在下拉中）。
    static let knownEditors: [EditorCandidate] = [
        .init(name: "Visual Studio Code", bundleId: "com.microsoft.VSCode"),
        .init(name: "VS Code Insiders", bundleId: "com.microsoft.VSCodeInsiders"),
        .init(name: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92"),
        .init(name: "Zed", bundleId: "dev.zed.Zed"),
        .init(name: "Sublime Text", bundleId: "com.sublimetext.4"),
        .init(name: "Nova", bundleId: "com.panic.Nova"),
        .init(name: "BBEdit", bundleId: "com.barebones.bbedit"),
        .init(name: "Xcode", bundleId: "com.apple.dt.Xcode"),
    ]

    /// 探测系统中已安装的候选编辑器（保序）。
    static func availableEditors() -> [InstalledEditor] {
        knownEditors.compactMap { cand in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cand.bundleId) else { return nil }
            return InstalledEditor(candidate: cand, appURL: url)
        }
    }

    /// bundle id 的展示名：先查候选表，再回退系统解析（app 本地化名，去 `.app` 后缀），
    /// 都失败则返回 bundle id 本身。用于「其他应用…」选中非候选表编辑器时的标签展示。
    static func displayName(forBundleId bundleId: String) -> String {
        if let known = knownEditors.first(where: { $0.bundleId == bundleId })?.name { return known }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        return bundleId
    }

    /// 取应用图标并缩放为菜单项尺寸（下拉项左侧小图标）。
    /// `icon(forFile:)` 返回大尺寸多表示图标，设 logical size 为 16pt 以适配菜单行高。
    static func icon(for editor: InstalledEditor) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: editor.appURL.path)
        img.size = NSSize(width: 16, height: 16)
        return img
    }

    // MARK: - 路径

    /// `~/.claude/settings.json` 的 URL。
    static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    /// `~/.claude` 目录 URL（文件缺失时访达定位兜底用）。
    static var claudeDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    // MARK: - 打开

    /// 以选定编辑器打开 `~/.claude/settings.json`。
    /// - Parameter editorBundleId: 目标编辑器 bundle id；`nil` 或未安装 → 系统默认关联应用打开。
    /// - Note: 文件不存在时不创建，改为在访达中定位 `~/.claude`（不存在则定位到 home），
    ///         提示用户 Claude Code 尚未初始化该配置。
    static func openClaudeSettings(editorBundleId: String?) {
        let fileURL = claudeSettingsURL
        let fm = FileManager.default

        guard fm.fileExists(atPath: fileURL.path) else {
            let dir = claudeDirectoryURL
            let target = fm.fileExists(atPath: dir.path) ? dir : fm.homeDirectoryForCurrentUser
            NSWorkspace.shared.activateFileViewerSelecting([target])
            NSLog("[GiveMeABreak][agent] ~/.claude/settings.json 不存在，已在访达定位 \(target.lastPathComponent)")
            return
        }

        let cfg = NSWorkspace.OpenConfiguration()
        if let bundleId = editorBundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: cfg) { _, error in
                if let error {
                    NSLog("[GiveMeABreak][agent] 以 \(bundleId) 打开 settings.json 失败，回退系统默认：\(error.localizedDescription)")
                    NSWorkspace.shared.open(fileURL, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        } else {
            NSWorkspace.shared.open(fileURL, configuration: cfg)
        }
    }
}
