import Foundation
import GiveMeABreakEngine

/// 子进程运行态（控制台头部状态与按钮启停依据）。
enum CodingProxyRunState: Equatable {
    case idle                            // 从未启动
    case running(pid: Int32)
    case stopping
    /// 启动失败原因（run() 抛错 / 前置校验失败）。
    case failedToStart(String)
    /// 已退出（unexpected = 非我方 stop 流程触发，如崩溃/被外部信号杀死）。
    case exited(code: Int32, unexpected: Bool)
}

/// Coding Proxy 子进程托管（集成层第一个 `Foundation.Process` 用例）。
///
/// - 线程模型：控制方法（apply/start/stop/restart/stopForQuit/clearLog）仅主线程调用
///   （AppRoot.start / onApply / 菜单与控制台按钮 / shutdown 均在主线程，同 `IdleSleepGuard` 约定）；
///   日志管道经 readabilityHandler 在后台队列写入（缓冲自带 NSLock），UI 刷新合流回主线程。
/// - 停止契约 = 直接子进程：`uv run` 在 Unix 上 exec 子进程（PID 即目标），SIGTERM 直达；
///   若自定义命令自身再派生孙进程，SIGTERM 不保证波及（控制台 footer 已明示此边界）。
/// - 不做崩溃自动重启（防无退避重启风暴）：意外退出仅记状态与日志，由控制台手动再启动。
final class CodingProxyProcessController: ObservableObject {
    /// 日志 UI 刷新合流间隔（高频输出不对 SwiftUI 逐行刷新）。
    private static let logFlushInterval: TimeInterval = 0.25
    /// 运行期停止的 SIGKILL 宽限（子进程无视 SIGTERM 时兜底）。
    private static let asyncStopGrace: TimeInterval = 5
    /// App 退出路径的同步停止上限（阻塞主线程的最坏值）。
    private static let syncStopTimeout: TimeInterval = 2

    @Published private(set) var runState: CodingProxyRunState = .idle
    /// 最近一次 apply 的配置校验结果（配置无效不杀旧进程，仅经此明示）。
    @Published private(set) var lastValidation: CodingProxyValidation = .ok
    let log = CodingProxyLogBuffer()
    /// 日志合流回调（主线程，≥250ms trailing）：控制台窗口订阅后拉 snapshot；窗口关闭时置 nil 退订。
    var onLogAppended: (() -> Void)?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    /// 我方 stop 流程标志（区分意外退出）；generation 用于作废同步停止后在途的 terminationHandler。
    private var stopping = false
    private var generation: UInt = 0
    private var lastApplied: CodingProxySettings?
    private var logFlushPending = false
    /// 日志写入与合流标志的串行队列（stdout/stderr 双管道可能并发回调）。
    private let ingestQueue = DispatchQueue(label: "com.aurelius.givemeabreak.codingproxy.ingest")

    // MARK: - 配置应用（AppRoot：启动恢复 + 设置「应用」）

    /// 幂等应用 Coding Proxy 配置：`codingProxyTransition` 纯函数决策 start/stop/restart/none。
    /// 配置未变绝不触碰进程（保留控制台手动启停的会话态）；新配置无效不动旧进程仅警示。
    func apply(_ settings: CodingProxySettings) {
        let validation = Self.liveValidation(of: settings)
        lastValidation = validation
        let action = codingProxyTransition(previous: lastApplied,
                                           new: settings,
                                           newValidation: validation,
                                           isRunning: process?.isRunning == true)
        lastApplied = settings
        if validation != .ok {
            let message = "配置无效：\(validation.localizedDescription)（不触碰当前进程）"
            log.append(.system, message)
            NSLog("[GiveMeABreak][codingProxy] \(message)")
            scheduleLogFlush()
        }
        switch action {
        case .none: break
        case .start: start()
        case .stop: stop()
        case .restart: restart()
        }
        NSLog("[GiveMeABreak][codingProxy] apply：autoStart=\(settings.autoStartEnabled) → \(action)")
    }

    // MARK: - 手动控制（控制台按钮，会话级操作、不写 config）

    /// 启动子进程（以最近一次 apply 的设置为准；未 apply 过配置则无操作）。
    func start() {
        guard process?.isRunning != true, runState != .stopping else { return }   // 幂等
        guard let settings = lastApplied else { return }

        let validation = Self.liveValidation(of: settings)
        lastValidation = validation
        guard validation == .ok else {
            runState = .failedToStart(validation.localizedDescription)
            log.append(.system, "启动失败：\(validation.localizedDescription)")
            NSLog("[GiveMeABreak][codingProxy] 启动失败：\(validation.localizedDescription)")
            scheduleLogFlush()
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let trimmedDir = settings.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = expandLeadingTilde(trimmedDir, home: home)
        let augmentedPATH = augmentedPathEnvironment(currentPath: ProcessInfo.processInfo.environment["PATH"],
                                                     home: home)
        // validation 已保证可解析与可执行命中，此处强解包安全。
        let parsed = parseCommandLine(settings.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines),
                                      home: home)!
        let executable = resolveExecutablePath(parsed, pathEnvironment: augmentedPATH,
                                               isExecutableFile: { FileManager.default.isExecutableFile(atPath: $0) })!

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = augmentedPATH
        environment["PYTHONUNBUFFERED"] = "1"   // 防 Python 子进程块缓冲导致日志迟滞（对非 Python 命令无害）

        // 先递增 generation 并在 run 前挂好 terminationHandler（捕获 spawn 时刻的 epoch），
        // 规避「快退出进程在 handler 挂接前死亡」的竞态。
        generation += 1
        let spawnGeneration = generation
        stopping = false

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = parsed.arguments
        p.currentDirectoryURL = URL(fileURLWithPath: directory)
        p.environment = environment

        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        attachPipeHandlers(outPipe: outPipe, errPipe: errPipe)
        p.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            let bySignal = process.terminationReason == .uncaughtSignal
            DispatchQueue.main.async { [weak self] in
                self?.handleProcessTerminated(code: code, bySignal: bySignal, for: spawnGeneration)
            }
        }

        do {
            try p.run()
        } catch {
            runState = .failedToStart(error.localizedDescription)
            log.append(.system, "启动失败：\(error.localizedDescription)")
            NSLog("[GiveMeABreak][codingProxy] 启动失败：\(error.localizedDescription)")
            scheduleLogFlush()
            return
        }

        process = p
        stdoutPipe = outPipe
        stderrPipe = errPipe
        runState = .running(pid: p.processIdentifier)
        log.append(.system, "已启动（PID \(p.processIdentifier)）：\(parsed.executable) \(parsed.arguments.joined(separator: " "))，工作目录 \(directory)")
        NSLog("[GiveMeABreak][codingProxy] 已启动 PID=\(p.processIdentifier) dir=\(directory) cmd=\(parsed.executable)")
        scheduleLogFlush()
    }

    /// 停止子进程（SIGTERM → 5s 宽限 SIGKILL 兜底；终态经 terminationHandler 回主线程）。
    func stop() {
        guard let p = process, p.isRunning else { return }   // 对未运行 Process 调 terminate 会抛异常
        stopping = true
        runState = .stopping
        let pid = p.processIdentifier
        p.terminate()   // SIGTERM（uv run exec ⇒ PID 即目标进程，直达）
        log.append(.system, "正在停止（SIGTERM → PID \(pid)）…")
        NSLog("[GiveMeABreak][codingProxy] 正在停止 PID=\(pid)")
        scheduleLogFlush()
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.asyncStopGrace) {
            guard p.isRunning else { return }
            // 宽限到点仍未退出：SIGKILL 兜底。p 尚未 reap ⇒ pid 未被复用，kill 无竞态；
            // 击杀后由 terminationHandler 走正常收尾。
            NSLog("[GiveMeABreak][codingProxy] SIGTERM 宽限超时，SIGKILL 兜底 PID=\(pid)")
            kill(pid, SIGKILL)
        }
    }

    /// 重启 = 同步有界停止后立刻启动（确保旧进程死透再拉新，避免端口争用）。
    func restart() {
        guard process?.isRunning == true else { start(); return }
        stopForQuit()
        start()
    }

    /// App 退出路径：同步有界停止（SIGTERM → ≤2s 轮询 → SIGKILL → waitUntilExit 回收）。
    /// 主线程短阻塞仅发生在退出期，通常 <100ms。
    func stopForQuit() {
        guard let p = process else { return }
        guard p.isRunning else {
            finalizeSynchronousStop(code: p.terminationStatus)
            return
        }
        stopping = true
        runState = .stopping
        let pid = p.processIdentifier
        p.terminate()
        let deadline = Date().addingTimeInterval(Self.syncStopTimeout)
        while p.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if p.isRunning {
            NSLog("[GiveMeABreak][codingProxy] 退出停止 SIGTERM 超时，SIGKILL 兜底 PID=\(pid)")
            kill(pid, SIGKILL)
            p.waitUntilExit()   // SIGKILL 即刻生效；此调用回收子进程，避免僵尸
        }
        finalizeSynchronousStop(code: p.terminationStatus)
    }

    /// 清空控制台日志缓冲。
    func clearLog() {
        log.clear()
        onLogAppended?()
    }

    // MARK: - 管道与终态处理

    /// 挂接 stdout/stderr readabilityHandler：chunk 经 Assembler 拼行后入缓冲；
    /// EOF（availableData 为空）必须摘除 handler（否则可能被空调用甚至空转）。
    private func attachPipeHandlers(outPipe: Pipe, errPipe: Pipe) {
        let outAssembler = CodingProxyLogAssembler()
        let errAssembler = CodingProxyLogAssembler()
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                if let tail = outAssembler.flushTail() { self?.ingest(lines: [tail], stream: .stdout) }
                return
            }
            let lines = outAssembler.append(data)
            self?.ingest(lines: lines, stream: .stdout)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                if let tail = errAssembler.flushTail() { self?.ingest(lines: [tail], stream: .stderr) }
                return
            }
            let lines = errAssembler.append(data)
            self?.ingest(lines: lines, stream: .stderr)
        }
    }

    /// terminationHandler 收尾（主线程）：stopping 区分意外退出；epoch 一致才生效
    /// （同步停止路径已就地落终态并递增 generation，在途回调到此作废）。
    private func handleProcessTerminated(code: Int32, bySignal: Bool, for generation: UInt) {
        guard generation == self.generation else { return }
        detachPipes()
        let unexpected = !stopping
        runState = .exited(code: code, unexpected: unexpected)
        process = nil
        stopping = false
        let detail = unexpected
            ? "进程意外退出（\(bySignal ? "信号 \(code)" : "退出码 \(code)")），不会自动重启，可在控制台手动启动"
            : "进程已停止（\(bySignal ? "信号 \(code)" : "退出码 \(code)")）"
        log.append(.system, detail)
        NSLog("[GiveMeABreak][codingProxy] \(detail)")
        scheduleLogFlush()
    }

    /// 同步停止收尾（主线程，stopForQuit/restart）：就地落终态并作废在途 terminationHandler。
    private func finalizeSynchronousStop(code: Int32) {
        generation += 1   // 作废仍排队中的 terminationHandler（其回主线程后 epoch 不匹配即忽略）
        detachPipes()
        runState = .exited(code: code, unexpected: false)
        process = nil
        stopping = false
        log.append(.system, "进程已停止（退出码 \(code)）")
        scheduleLogFlush()
        NSLog("[GiveMeABreak][codingProxy] 同步停止完成 code=\(code)")
    }

    private func detachPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    // MARK: - 日志合流（≥250ms trailing，主线程回调）

    private func ingest(lines: [String], stream: CodingProxyLogStream) {
        guard !lines.isEmpty else { return }
        ingestQueue.async { [weak self] in
            guard let self else { return }
            for line in lines { self.log.append(stream, line) }
            guard !self.logFlushPending else { return }
            self.logFlushPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.logFlushInterval) { [weak self] in
                guard let self else { return }
                self.onLogAppended?()
                self.ingestQueue.async { self.logFlushPending = false }
            }
        }
    }

    /// 控制方法内的主线程直排（生命周期 system 行无需合流等待，但仍走统一入口保序）。
    private func scheduleLogFlush() {
        DispatchQueue.main.async { [weak self] in self?.onLogAppended?() }
    }
}

// MARK: - 真实环境校验（设置页 Tooltip 与控制器共用的单一事实源）

extension CodingProxyProcessController {
    /// 以真实文件系统与当前进程环境校验 Coding Proxy 配置。
    static func liveValidation(of settings: CodingProxySettings) -> CodingProxyValidation {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let pathEnv = augmentedPathEnvironment(currentPath: ProcessInfo.processInfo.environment["PATH"], home: home)
        return validateCodingProxySettings(settings, home: home, pathEnvironment: pathEnv,
                                           fileExists: { fm.fileExists(atPath: $0) },
                                           isDirectory: { path in
                                               var isDir: ObjCBool = false
                                               return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
                                           },
                                           isExecutableFile: { fm.isExecutableFile(atPath: $0) })
    }

    /// 工作目录行警示文案（nil = 无警示；空串不警示——未配置不算错，由设置页 footer 说明）。
    static func liveWorkingDirectoryWarning(_ directory: String) -> String? {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fm = FileManager.default
        let expanded = expandLeadingTilde(trimmed, home: fm.homeDirectoryForCurrentUser.path)
        guard fm.fileExists(atPath: expanded) else { return "该目录不存在" }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: expanded, isDirectory: &isDir)
        return isDir.boolValue ? nil : "该路径不是文件夹"
    }

    /// 启动命令行警示文案（nil = 无警示；空串不警示）。
    static func liveLaunchCommandWarning(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = parseCommandLine(trimmed, home: FileManager.default.homeDirectoryForCurrentUser.path) else {
            return "命令无法解析（引号不闭合？）"
        }
        let pathEnv = augmentedPathEnvironment(currentPath: ProcessInfo.processInfo.environment["PATH"],
                                               home: FileManager.default.homeDirectoryForCurrentUser.path)
        guard resolveExecutablePath(parsed, pathEnvironment: pathEnv,
                                    isExecutableFile: FileManager.default.isExecutableFile(atPath:)) != nil else {
            return "可执行文件未在系统 PATH 与常见安装位（Homebrew / ~/.local/bin）中找到"
        }
        return nil
    }
}
