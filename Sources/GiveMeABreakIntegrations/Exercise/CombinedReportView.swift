import SwiftUI
import AppKit
import GiveMeABreakEngine

/// 综合报告视图：周期切换（本周/本月/本季/本年）+ **原生层级化**呈现「工作回顾 + 运动概览」合成报告。
///
/// 消费 `buildCombinedReportModel(...)`（结构化模型，单一事实源），用原生 SwiftUI 渲染标题/元数据/
/// 工作回顾（Top + 周期分布，**只读**——详尽逐条编辑仍归「工作日志」窗，避免双编辑路径）/ 运动概览
/// （按类型表 + 明细行**支持编辑/删除**，对齐 WorkLogEntryRow 悬停显隐 + 右键菜单 + 二次确认）。
/// 复制/导出输出 `renderCombinedReport(...)` 的 Markdown（与模型同源）。
struct CombinedReportView: View {
    private let workStore: WorkLogStore
    private let exerciseStore: ExerciseStore
    /// 运动录入 Picker 数据源（v7 起来自 `DayPlanConfig.exerciseTypes`）。
    private let exerciseTypes: [String]
    /// 保存/更新回调经 AppRoot 落库（同步走「自定义类型自动记住 + config 持久化」）。
    private let onSaveExercise: (ExerciseEntry) -> Void
    private let onUpdateExercise: (ExerciseEntry) -> Void
    private let onClose: () -> Void

    @State private var scope: CombinedReportScope
    @State private var model: CombinedReportModel?
    @State private var reportMarkdown: String = ""
    @State private var workCount: Int = 0
    @State private var exerciseCount: Int = 0
    @State private var pendingDelete: ExerciseEntry?
    @State private var activeSheet: ActiveSheet?

    init(workStore: WorkLogStore,
         exerciseStore: ExerciseStore,
         exerciseTypes: [String],
         initialScope: CombinedReportScope = .week,
         onSaveExercise: @escaping (ExerciseEntry) -> Void,
         onUpdateExercise: @escaping (ExerciseEntry) -> Void,
         onClose: @escaping () -> Void) {
        self.workStore = workStore
        self.exerciseStore = exerciseStore
        self.exerciseTypes = exerciseTypes
        self.onSaveExercise = onSaveExercise
        self.onUpdateExercise = onUpdateExercise
        self.onClose = onClose
        _scope = State(initialValue: initialScope)
    }

    /// 编辑/新增运动记录弹窗来源（`.sheet(item:)` 需 Identifiable）。
    private enum ActiveSheet: Identifiable {
        case create
        case edit(ExerciseEntry)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let e): return "edit-\(e.id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 620, idealWidth: 740, minHeight: 480, idealHeight: 580)
        .onAppear { regenerate() }
        .sheet(item: $activeSheet) { sheet in sheetForm(sheet) }
    }

    // MARK: - 工具栏（周期 + 计数）

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("周期", selection: $scope) {
                Text("本周").tag(CombinedReportScope.week)
                Text("本月").tag(CombinedReportScope.month)
                Text("本季").tag(CombinedReportScope.quarter)
                Text("本年").tag(CombinedReportScope.year)
            }
            .pickerStyle(.segmented)
            .onChange(of: scope) { _, _ in regenerate() }
            Spacer()
            Text("工作 \(workCount) · 运动 \(exerciseCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    // MARK: - 内容（原生阅读器 / 空态）

    @ViewBuilder private var content: some View {
        if let model, !model.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header(model)
                    workSection(model.work)
                    exerciseSection(model)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .alert("删除这条运动记录？",
                   isPresented: Binding(get: { pendingDelete != nil },
                                        set: { if !$0 { pendingDelete = nil } }),
                   presenting: pendingDelete) { entry in
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    exerciseStore.delete(id: entry.id)
                    pendingDelete = nil
                    regenerate()
                }
            } message: { entry in
                Text("将删除「\(exerciseSetsText(entry))」，且不可恢复。")
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("（暂无记录）")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("点击「补录运动…」记录一段微运动。")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Button("补录运动…") { activeSheet = .create }
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 标题 / 章节

    private func header(_ model: CombinedReportModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.meta)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // 工作回顾：只读（详尽逐条编辑归「工作日志」窗）
    private func workSection(_ work: CombinedWorkSection) -> some View {
        section("工作回顾") {
            if work.isEmpty {
                Text("（暂无工作记录）").font(.system(size: 12)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("Top \(min(3, work.top.count))")
                        ForEach(Array(work.top.enumerated()), id: \.element.id) { idx, entry in
                            HStack(spacing: 10) {
                                rankBadge(idx + 1)
                                Text(entry.summary).font(.system(size: 13)).lineLimit(2)
                                Spacer(minLength: 8)
                                Text(humanizedDuration(entry.durationSeconds))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.teal)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader("周期分布")
                        ForEach(work.byPeriod, id: \.key) { r in
                            HStack(spacing: 8) {
                                Text(r.label).font(.system(size: 12, design: .monospaced))
                                Spacer(minLength: 8)
                                Text("\(r.count) 条 · \(humanizedDuration(r.totalSeconds))")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func exerciseSection(_ model: CombinedReportModel) -> some View {
        let exercise = model.exercise
        return section("运动概览") {
            if exercise.isEmpty {
                Text("（暂无运动记录）").font(.system(size: 12)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    typeGrid(exercise.byType)
                    if model.scope == .week || model.scope == .month {
                        VStack(alignment: .leading, spacing: 2) {
                            sectionHeader("明细")
                            ForEach(exercise.sessions, id: \.id) { e in
                                ExerciseEntryRow(
                                    entry: e,
                                    onEdit: { activeSheet = .edit(e) },
                                    onDelete: { pendingDelete = e },
                                    onCopy: { copyToClipboard(exerciseEntryMarkdown(e)) }
                                )
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            sectionHeader("按月")
                            monthGrid(exercise.byMonth)
                        }
                    }
                }
            }
        }
    }

    private func typeGrid(_ rows: [CombinedCountRepRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text("动作").gridColumnAlignment(.leading)
                Text("记录数").gridColumnAlignment(.trailing)
                Text("总数量").gridColumnAlignment(.trailing)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            Divider().gridCellColumns(3)
            ForEach(rows, id: \.key) { r in
                GridRow {
                    Text(r.key).font(.system(size: 13, design: .monospaced))
                    Text("\(r.sessions)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    Text("\(r.reps)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.teal)
                }
            }
        }
    }

    private func monthGrid(_ rows: [CombinedCountRepRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text("月份").gridColumnAlignment(.leading)
                Text("记录数").gridColumnAlignment(.trailing)
                Text("总数量").gridColumnAlignment(.trailing)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            Divider().gridCellColumns(3)
            ForEach(rows, id: \.key) { r in
                GridRow {
                    Text(r.key).font(.system(size: 13, design: .monospaced))
                    Text("\(r.sessions)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    Text("\(r.reps)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.teal)
                }
            }
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        let opacity = [1: 0.9, 2: 0.65, 3: 0.45][rank] ?? 0.35
        return Text("\(rank)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.teal.opacity(opacity)))
    }

    // MARK: - 底部操作

    private var footer: some View {
        HStack {
            Button("复制") { copyToClipboard(reportMarkdown) }
                .disabled(model?.isEmpty ?? true)
            Button("导出 .md…") { exportMarkdown() }
                .disabled(model?.isEmpty ?? true)
            Button("补录运动…") { activeSheet = .create }
            Spacer()
            Button("关闭") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - 编辑 / 新增弹窗

    @ViewBuilder private func sheetForm(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .create:
            let lastEnd = exerciseStore.loadEntries().last?.endedAt
            ExerciseEntryFormView(
                mode: .create(defaultStart: lastEnd ?? Date().addingTimeInterval(-10 * 60), defaultEnd: Date()),
                types: exerciseTypes,
                onSubmit: { entry in
                    onSaveExercise(entry)
                    activeSheet = nil
                    regenerate()
                },
                onCancel: { activeSheet = nil }
            )
        case .edit(let entry):
            ExerciseEntryFormView(
                mode: .edit(entry),
                types: exerciseTypes,
                onSubmit: { updated in
                    onUpdateExercise(updated)
                    activeSheet = nil
                    regenerate()
                },
                onCancel: { activeSheet = nil }
            )
        }
    }

    // MARK: - 渲染（重算模型 + Markdown）

    private func regenerate() {
        let now = Date()
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let work = workStore.loadEntries()
        let exercise = exerciseStore.loadEntries()
        let workScoped = filterWorkLogEntriesForCombined(work, scope: scope, now: now, calendar: cal, timeZone: cal.timeZone)
        let exerciseScoped = filterExerciseEntries(exercise, scope: scope, now: now, calendar: cal, timeZone: cal.timeZone)
        workCount = workScoped.count
        exerciseCount = exerciseScoped.count
        model = buildCombinedReportModel(workEntries: work, exerciseEntries: exercise,
                                         scope: scope, now: now, calendar: cal, timeZone: cal.timeZone)
        reportMarkdown = renderCombinedReport(workEntries: work, exerciseEntries: exercise,
                                              scope: scope, now: now, calendar: cal, timeZone: cal.timeZone)
    }

    // MARK: - 复制 / 导出

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exerciseEntryMarkdown(_ entry: ExerciseEntry) -> String {
        var s = "- **\(hhmmLocal(entry.startedAt))** · \(exerciseSetsText(entry))"
        if let note = entry.note { s += "\n  > 备注：\(note)" }
        return s
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultFilename()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try reportMarkdown.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            NSLog("[GiveMeABreak][combined] 导出失败：\(error)")
        }
    }

    private func defaultFilename() -> String {
        var c = Calendar.current
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        let now = Date()
        switch scope {
        case .week:
            return String(format: "%04d-W%02d",
                          c.component(.yearForWeekOfYear, from: now),
                          c.component(.weekOfYear, from: now)) + ".md"
        case .month:
            let p = c.dateComponents([.year, .month], from: now)
            return String(format: "%04d-%02d", p.year ?? 0, p.month ?? 0) + ".md"
        case .quarter:
            let p = c.dateComponents([.year, .month], from: now)
            return String(format: "%04d-Q%d", p.year ?? 0, ((p.month ?? 1) - 1) / 3 + 1) + ".md"
        case .year:
            let p = c.dateComponents([.year], from: now)
            return String(format: "%04d", p.year ?? 0) + ".md"
        }
    }

    // MARK: - 章节脚手架

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }
}

// MARK: - 运动明细行子视图（自持悬停态；右键菜单常驻 + 悬停显隐内联操作，对齐 WorkLogEntryRow）

private struct ExerciseEntryRow: View {
    let entry: ExerciseEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false

    private var clock: String { hhmmLocal(entry.startedAt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(clock)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(exerciseSetsText(entry))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if hovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("编辑")
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("删除")
                }
            }
            if let note = entry.note {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.teal.opacity(0.6)).frame(width: 2)
                    Text("备注：\(note)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
            Button { onCopy() } label: { Label("复制本条", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
        }
    }
}
