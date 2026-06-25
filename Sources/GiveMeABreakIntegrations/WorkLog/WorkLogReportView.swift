import SwiftUI
import AppKit
import GiveMeABreakEngine

/// 工作日志报告查看视图：周期切换（今日/本周/本月/全部）+ Markdown 预览 + 复制/导出/清空。
///
/// 渲染采用等宽原貌 Markdown（含表格）——比 AttributedString(markdown:) 更诚实（后者不支持表格）。
/// 导出/复制用同一份渲染产物；清空走 NSAlert 二次确认（普通窗口上下文，NSAlert 安全）。
struct WorkLogReportView: View {
    private let store: WorkLogStore
    private let onClose: () -> Void

    @State private var scope: WorkLogReportScope = .today
    @State private var reportMarkdown: String = ""
    @State private var entryCount: Int = 0
    @State private var showClearConfirm: Bool = false
    @State private var clearAlertMessage: String = ""

    init(store: WorkLogStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // 等宽原貌预览，忠实展示表格与层级
            ScrollView {
                Text(reportMarkdown.isEmpty ? "_（暂无记录）_" : reportMarkdown)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            Divider()
            footer
        }
        .frame(minWidth: 600, idealWidth: 720, minHeight: 460, idealHeight: 560)
        .onAppear { regenerate() }
        .alert("清空全部工作日志？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                store.replaceAll([])
                regenerate()
            }
        } message: {
            Text(clearAlertMessage)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("周期", selection: $scope) {
                Text("今日").tag(WorkLogReportScope.today)
                Text("本周").tag(WorkLogReportScope.week)
                Text("本月").tag(WorkLogReportScope.month)
                Text("全部").tag(WorkLogReportScope.all)
            }
            .pickerStyle(.segmented)
            .onChange(of: scope) { _, _ in regenerate() }
            Spacer()
            Text("\(entryCount) 条")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button("复制") { copyToClipboard(reportMarkdown) }
            Button("导出 .md…") { exportMarkdown() }
            Spacer()
            Button("清空…", role: .destructive) { confirmClear() }
                .disabled(entryCount == 0)
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - 渲染

    private func regenerate() {
        let now = Date()
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let entries = store.loadEntries()
        let scoped = filterWorkLogEntries(entries, scope: scope, now: now, calendar: cal, timeZone: cal.timeZone)
        entryCount = scoped.count
        reportMarkdown = renderWorkLogReport(
            entries: entries, scope: scope, now: now, calendar: cal, timeZone: cal.timeZone
        )
    }

    // MARK: - 复制 / 导出 / 清空

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultFilename()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try reportMarkdown.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            NSLog("[GiveMeABreak][worklog] 导出失败：\(error)")
        }
    }

    private func defaultFilename() -> String {
        let cal = Calendar.current
        let now = Date()
        switch scope {
        case .today:
            return "\(dayKeyPublic(now, cal: cal)).md"
        case .week:
            return "\(weekKeyPublic(now, cal: cal)).md"
        case .month:
            return "\(monthKeyPublic(now, cal: cal)).md"
        case .all:
            return "work-log-all.md"
        }
    }

    private func confirmClear() {
        // 提示先导出再清空（AGENTS.md 数据谨慎）
        clearAlertMessage = "将永久删除 \(entryCount) 条记录，且不可恢复。建议先「导出 .md」备份后再清空。"
        showClearConfirm = true
    }
}

// MARK: - 日期键（导出文件名用，对齐 WorkLogReport 内部格式）

private func dayKeyPublic(_ date: Date, cal: Calendar) -> String {
    let p = cal.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
}
private func monthKeyPublic(_ date: Date, cal: Calendar) -> String {
    let p = cal.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", p.year ?? 0, p.month ?? 0)
}
private func weekKeyPublic(_ date: Date, cal: Calendar) -> String {
    var c = cal
    c.firstWeekday = 2
    c.minimumDaysInFirstWeek = 4
    let y = c.component(.yearForWeekOfYear, from: date)
    let w = c.component(.weekOfYear, from: date)
    return String(format: "%04d-W%02d", y, w)
}
