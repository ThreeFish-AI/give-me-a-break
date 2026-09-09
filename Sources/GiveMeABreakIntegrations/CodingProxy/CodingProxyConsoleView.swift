import SwiftUI
import GiveMeABreakEngine

/// Coding Proxy 控制台：状态条 + 会话级启停控制 + 等宽日志流（stdout 默认 / stderr 橙 / 生命周期蓝灰）。
/// 日志本体在 `CodingProxyProcessController.log`（会话级环形缓冲），窗口关闭再开不丢日志；
/// 视图仅持 snapshot，经 onLogAppended 合流回调（≥250ms）拉取，窗口关闭即退订零开销。
struct CodingProxyConsoleView: View {
    @ObservedObject var controller: CodingProxyProcessController
    @State private var lines: [CodingProxyLogLine] = []
    @State private var autoScroll = true

    /// 等宽日志行时间戳（HH:mm:ss）。
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                headerBar
                Divider()
                logArea(proxy: proxy)
                Divider()
                footerBar(proxy: proxy)
            }
            .onAppear {
                lines = controller.log.snapshot
                controller.onLogAppended = { [weak controller] in
                    lines = controller?.log.snapshot ?? []
                }
            }
            .onDisappear {
                controller.onLogAppended = nil
            }
        }
    }

    // MARK: - 头部状态条

    private var statusText: String {
        switch controller.runState {
        case .idle:
            return controller.lastValidation != .ok ? "已停止 · 配置无效" : "已停止"
        case .running(let pid):
            return "运行中 · PID \(pid)"
        case .stopping:
            return "正在停止…"
        case .failedToStart(let reason):
            return "启动失败：\(reason)"
        case .exited(let code, let unexpected):
            return unexpected ? "已意外退出 · 退出码 \(code)（不自动重启）" : "已退出 · 退出码 \(code)"
        }
    }

    private var statusColor: Color {
        switch controller.runState {
        case .running: return .green
        case .stopping: return .orange
        case .failedToStart, .exited(_, true): return .red
        case .idle, .exited: return .secondary
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(verbatim: statusText)
                .font(.callout.weight(.medium))
                .foregroundStyle(statusColor == .secondary ? Color.secondary : statusColor)
                .lineLimit(1)
                .truncationMode(.tail)
            if controller.lastValidation != .ok {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("当前配置无效：\(controller.lastValidation.localizedDescription)")
                    .accessibilityLabel("配置无效：\(controller.lastValidation.localizedDescription)")
            }
            Spacer(minLength: 12)
            Button("启动") { controller.start() }
                .disabled(isRunning || isStopping)
                .help("以当前设置启动 Coding Proxy 子进程（会话级操作，不写入设置）")
            Button("停止") { controller.stop() }
                .disabled(!isRunning)
                .help("停止子进程（SIGTERM，5 秒宽限后 SIGKILL 兜底）")
            Button("重启") { controller.restart() }
                .disabled(!isRunning)
                .help("停止后立即以当前设置重新启动")
            Button("清空日志") { controller.clearLog() }
                .disabled(lines.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var isRunning: Bool {
        if case .running = controller.runState { return true }
        return false
    }

    private var isStopping: Bool {
        if case .stopping = controller.runState { return true }
        return false
    }

    // MARK: - 日志流

    private func logArea(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(lines) { line in
                    logRow(line)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onChange(of: lines) { _, _ in
            guard autoScroll, let last = lines.last else { return }
            proxy.scrollTo(last.id, anchor: .bottom)
        }
        .onChange(of: autoScroll) { enabled, _ in
            guard enabled, let last = lines.last else { return }
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    /// 单行日志：时间戳灰 + 正文按流着色。`Text(verbatim:)` 防日志内容被当本地化 key。
    private func logRow(_ line: CodingProxyLogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: Self.timestampFormatter.string(from: line.date))
                .foregroundStyle(.tertiary)
            Text(verbatim: line.text)
                .foregroundStyle(textColor(for: line.stream))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
        .id(line.id)
        .accessibilityLabel("\(line.stream.rawValue)：\(line.text)")
    }

    private func textColor(for stream: CodingProxyLogStream) -> Color {
        switch stream {
        case .stdout: return .primary
        case .stderr: return .orange
        case .system: return .blue.opacity(0.75)
        }
    }

    // MARK: - 底部工具条

    private func footerBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Text("共 \(lines.count) 行 · 缓冲上限 \(controller.log.capacity) 行")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("stdout 默认色 · stderr 橙色 · 生命周期蓝色")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 12)
            Toggle("自动滚动", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("新日志到达时自动滚动到底部；上翻查阅时可关闭")
            Button("回到底部") {
                guard let last = lines.last else { return }
                autoScroll = true
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .disabled(lines.isEmpty)
            .help("跳转到底部并恢复自动滚动")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
