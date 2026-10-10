import Foundation

// MARK: - 命令行解析与路径

/// 解析后的启动命令（可执行 + 参数列表）。
public struct ParsedCommandLine: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

/// 解析启动命令字符串：按空白（空格/Tab）切分，支持单/双引号包夹含空格参数；
/// 可执行段做 `~` 前缀展开。空串 / 纯空白 / 引号不闭合 → nil（不猜测，交由校验器明示）。
public func parseCommandLine(_ command: String, home: String) -> ParsedCommandLine? {
    var tokens: [String] = []
    var current = ""
    var quote: Character? = nil   // 当前处于何种引号内（nil = 引号外）
    var hasToken = false          // 当前 token 是否已积累字符（区分「空引号参数」与未开始）

    func pushToken() {
        tokens.append(current)
        current = ""
        hasToken = false
    }

    for ch in command {
        if let q = quote {
            if ch == q {
                quote = nil          // 引号闭合：空引号参数（""）也视为一个 token
            } else {
                current.append(ch)
                hasToken = true
            }
        } else if ch == "\"" || ch == "'" {
            quote = ch
            hasToken = true          // 引号开启即视为 token 开始（空引号参数场景）
        } else if ch == " " || ch == "\t" {
            if hasToken { pushToken() }
        } else {
            current.append(ch)
            hasToken = true
        }
    }
    guard quote == nil else { return nil }   // 引号不闭合：整体不可解析
    if hasToken { pushToken() }
    guard let first = tokens.first else { return nil }

    let executable = first == "~" ? home : expandLeadingTilde(first, home: home)
    return ParsedCommandLine(executable: executable, arguments: Array(tokens.dropFirst()))
}

/// `~` / `~/x` 前缀展开为 home 绝对路径；其余（绝对路径 / 非前缀 `~`）原样返回。
public func expandLeadingTilde(_ path: String, home: String) -> String {
    if path == "~" { return home }
    if path.hasPrefix("~/") { return home + String(path.dropFirst()) }
    return path
}

/// 增强 PATH：前置用户级与 Homebrew bin 目录（App 从 Finder 启动时无 shell PATH，
/// `uv` 常装于 `~/.local/bin` 或 `/opt/homebrew/bin`），追加原 PATH 并按目录去重（保首个）。
public func augmentedPathEnvironment(currentPath: String?, home: String) -> String {
    var seen = Set<String>()
    var components: [String] = []
    for dir in ["\(home)/.local/bin", "\(home)/bin", "/opt/homebrew/bin", "/usr/local/bin"] {
        if seen.insert(dir).inserted { components.append(dir) }
    }
    for dir in (currentPath ?? "").split(separator: ":") where !dir.isEmpty {
        if seen.insert(String(dir)).inserted { components.append(String(dir)) }
    }
    return components.joined(separator: ":")
}

/// 可执行解析：裸名按 PATH 顺序取首个可执行命中（绝对路径）；含 `/` 视为显式路径，
/// 就地判定可执行性（不可执行 → nil，令校验器统一以 `.executableNotFound` 明示，
/// 而非留到 `Process.run()` 抛英文 NSError）。全不命中 → nil。
public func resolveExecutablePath(_ parsed: ParsedCommandLine,
                                  pathEnvironment: String,
                                  isExecutableFile: (String) -> Bool) -> String? {
    let name = parsed.executable
    if name.contains("/") {
        return isExecutableFile(name) ? name : nil
    }
    for dir in pathEnvironment.split(separator: ":") where !dir.isEmpty {
        let candidate = "\(dir)/\(name)"
        if isExecutableFile(candidate) { return candidate }
    }
    return nil
}

// MARK: - 配置校验

/// Coding Proxy 配置校验结果（localizedDescription 供设置页 Tooltip 与控制台状态直接展示）。
public enum CodingProxyValidation: Equatable, Sendable {
    case ok
    case emptyWorkingDirectory
    case workingDirectoryNotFound
    case workingDirectoryNotDirectory
    case emptyCommand
    case commandUnparsable
    case executableNotFound

    /// 简体中文描述（引擎层持中文文案有 renderWorkLogReport 先例）。
    public var localizedDescription: String {
        switch self {
        case .ok: return "配置有效"
        case .emptyWorkingDirectory: return "未配置工作目录"
        case .workingDirectoryNotFound: return "工作目录不存在"
        case .workingDirectoryNotDirectory: return "工作目录不是文件夹"
        case .emptyCommand: return "未配置启动命令"
        case .commandUnparsable: return "启动命令无法解析（引号不闭合？）"
        case .executableNotFound: return "启动命令中的可执行文件未找到"
        }
    }
}

/// 校验 Coding Proxy 配置是否具备启动条件（不关心 autoStartEnabled——开关语义由调用方决定）。
/// 文件系统谓词全部注入：Engine 保持零真实 FS 依赖，测试可用内存字典驱动。
public func validateCodingProxySettings(_ settings: CodingProxySettings,
                                        home: String,
                                        pathEnvironment: String,
                                        fileExists: (String) -> Bool,
                                        isDirectory: (String) -> Bool,
                                        isExecutableFile: (String) -> Bool) -> CodingProxyValidation {
    let trimmedDir = settings.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedDir.isEmpty else { return .emptyWorkingDirectory }
    let dir = expandLeadingTilde(trimmedDir, home: home)
    guard fileExists(dir) else { return .workingDirectoryNotFound }
    guard isDirectory(dir) else { return .workingDirectoryNotDirectory }

    let trimmedCmd = settings.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedCmd.isEmpty else { return .emptyCommand }
    guard let parsed = parseCommandLine(trimmedCmd, home: home) else { return .commandUnparsable }
    guard resolveExecutablePath(parsed, pathEnvironment: pathEnvironment,
                                isExecutableFile: isExecutableFile) != nil else { return .executableNotFound }
    return .ok
}

// MARK: - apply 决策

/// apply 决策结果。
public enum CodingProxyAction: Equatable, Sendable {
    case none, start, stop, restart
}

/// apply 决策（纯函数，`CodingProxyProcessController.apply` 的策略核心）：
/// - `previous == new` → `.none`：配置未变绝不触碰进程——用户在控制台手动停止的进程，
///   不会被一次无关的「应用」复活（保留会话级手动状态）。
/// - 新配置无效 → `.none`：不动正在运行的旧进程（仅警示；一次手滑不该打死正常进程）。
/// - `previous == nil`（App 启动首次 apply）：enabled && 有效 && 未运行 → start。
/// - enabled 且已运行：目录/命令变化 → restart；仅开关翻转不打扰运行中的进程。
/// - 未 enabled 且已运行 → stop（开关即「保持运行」的期望态）。
public func codingProxyTransition(previous: CodingProxySettings?,
                                  new: CodingProxySettings,
                                  newValidation: CodingProxyValidation,
                                  isRunning: Bool) -> CodingProxyAction {
    if let previous, previous == new { return .none }
    guard newValidation == .ok else { return .none }
    if new.autoStartEnabled {
        guard isRunning else { return .start }
        if let previous,
           previous.workingDirectory != new.workingDirectory || previous.launchCommand != new.launchCommand {
            return .restart
        }
        return .none
    }
    return isRunning ? .stop : .none
}

// MARK: - 日志（环形缓冲 + 流式行拼装）

/// 日志流来源：子进程 stdout / stderr / 系统事件（启动、退出等生命周期）。
public enum CodingProxyLogStream: String, Equatable, Sendable {
    case stdout, stderr, system
}

/// 一行控制台日志。`id` 在入队时分配，跨 snapshot 拉取保持稳定（SwiftUI ForEach diff 不整列刷新）。
public struct CodingProxyLogLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let stream: CodingProxyLogStream
    public let text: String

    public init(id: UUID = UUID(), date: Date = Date(), stream: CodingProxyLogStream, text: String) {
        self.id = id
        self.date = date
        self.stream = stream
        self.text = text
    }
}

/// 线程安全日志环形缓冲：行数容量 + 单行长度双上限（代理类工具常整行打印 minified JSON，
/// 超长单行会拖死 SwiftUI 渲染，超限物理截断并标记）。
/// 写入来自 readabilityHandler 后台队列，读取来自主线程（snapshot 为深拷贝）。
public final class CodingProxyLogBuffer: @unchecked Sendable {
    public let capacity: Int
    public let maxLineLength: Int
    private let lock = NSLock()
    private var lines: [CodingProxyLogLine] = []
    private var appendedTotal: UInt64 = 0

    public init(capacity: Int = 2000, maxLineLength: Int = 4000) {
        self.capacity = capacity
        self.maxLineLength = maxLineLength
    }

    /// 追加一行（超长截断 + 标记；超出容量裁最旧）。
    public func append(_ stream: CodingProxyLogStream, _ text: String, date: Date = Date()) {
        let truncated = text.count > maxLineLength
            ? String(text.prefix(maxLineLength)) + " …（已截断）"
            : text
        lock.lock()
        lines.append(CodingProxyLogLine(date: date, stream: stream, text: truncated))
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        appendedTotal &+= 1
        lock.unlock()
    }

    /// 历史累计入队行数（单调，不受容量裁剪与 clear 影响）。
    /// 用途：UI 合流刷新据此判定「快照拉取后是否又有新行」——满容量时 `count` 恒等于
    /// capacity，无法充当该判据。
    public var totalAppended: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return appendedTotal
    }

    /// 当前缓冲快照（深拷贝，主线程安全读取）。
    public var snapshot: [CodingProxyLogLine] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return lines.count
    }

    public func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }
}

/// 流式行拼装器：feed 字节块 → 拼装完成的整行（`readabilityHandler` 的 chunk 不对齐行边界，
/// 且 UTF-8 多字节序列可能被劈在两个 chunk；半行与不完整尾字节缓存在实例内直到补全）。
/// 线程模型：每条管道流各持一个实例，仅在该管道的 readabilityHandler 上串行访问。
public final class CodingProxyLogAssembler: @unchecked Sendable {
    private var pending = Data()   // 半行缓冲（原始字节；可能含被劈开的 UTF-8 序列）

    public init() {}

    /// 喂入一个 chunk，返回其中已拼装完成的完整行（`\n` 切分、剥 `\r`）。
    /// 注：`\n`(0x0A) 不会出现在 UTF-8 多字节序列中，故按 `\n` 切分的行必然是完整 UTF-8 边界。
    public func append(_ data: Data) -> [String] {
        pending.append(data)
        var result: [String] = []
        while let nlIndex = pending.firstIndex(of: 0x0A) {
            var lineData = pending[0..<nlIndex]
            if lineData.last == 0x0D { lineData = lineData.dropLast() }   // 剥 \r（CRLF）
            result.append(String(decoding: lineData, as: UTF8.self))
            pending.removeSubrange(0...nlIndex)
        }
        return result
    }

    /// 流关闭（EOF）时冲出残留半行；无残留返回 nil。
    /// 尾部可能是被劈开的 UTF-8 序列，走有损解码（替换字符）兜底。
    public func flushTail() -> String? {
        guard !pending.isEmpty else { return nil }
        let tail = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return tail.isEmpty ? nil : tail
    }
}
