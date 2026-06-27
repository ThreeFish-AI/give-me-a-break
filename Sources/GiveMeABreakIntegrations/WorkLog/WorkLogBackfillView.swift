import SwiftUI
import GiveMeABreakEngine

/// 补录工作日志视图：为指定时段补写一段工作小结（用户主动补录漏掉的周期）。
///
/// 与 `WorkLogPromptView` 同源视觉语言（leaf 标题 / summary TextEditor + 软字符计数 / 可选下一步），
/// 但语义不同：用户**自选起止时段**、无超时、保存/取消（无「跳过」、不触发休息）。
/// 起始默认取上一条日志的 `endedAt`（填补最近缺口），结束默认当前时刻；两者经 DatePicker 互相约束保证 start ≤ end。
struct WorkLogBackfillView: View {
    private let onSubmit: (WorkLogEntry) -> Void
    private let onCancel: () -> Void

    @State private var start: Date
    @State private var end: Date
    @State private var summary: String = ""
    @State private var nextAction: String = ""
    @State private var nextExpanded: Bool = false

    private let softLimit = 120

    init(defaultStart: Date,
         defaultEnd: Date,
         onSubmit: @escaping (WorkLogEntry) -> Void,
         onCancel: @escaping () -> Void) {
        // 防御：起始不得晚于结束，否则回退到结束前 1 分钟。
        let safeStart = defaultStart < defaultEnd ? defaultStart : defaultEnd.addingTimeInterval(-60)
        _start = State(initialValue: safeStart)
        _end = State(initialValue: defaultEnd)
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    private var trimmedSummary: String { summary.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var durationSeconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
    private var canSave: Bool { !trimmedSummary.isEmpty && end > start }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil").foregroundStyle(.teal).font(.system(size: 20))
                Text("补录工作日志").font(.system(size: 18, weight: .semibold))
                Spacer()
            }

            Text("为漏掉的某段时间补一段工作小结。选择时段、写下完成了什么，保存后并入工作日志报告。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 时段选择（DatePicker 互相约束：start ≤ end）
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("开始").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                    DatePicker("", selection: $start, in: ...end, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .accessibilityLabel("补录时段的开始时间")
                    Spacer()
                }
                HStack(spacing: 10) {
                    Text("结束").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                    DatePicker("", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .accessibilityLabel("补录时段的结束时间")
                    Spacer()
                }
            }

            // summary（同 WorkLogPromptView 风格：TextEditor + 软字符计数 + 占位）
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $summary)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(minHeight: 64, idealHeight: 72)
                    .overlay(alignment: .topLeading) {
                        if summary.isEmpty {
                            Text("例：调试登录 bug，定位到 token 过期")
                                .foregroundStyle(Color(nsColor: .placeholderTextColor))
                                .font(.system(size: 14))
                                .padding(.horizontal, 5).padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                HStack {
                    Spacer()
                    Text("\(summary.count)/\(softLimit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(summary.count > softLimit ? .orange : .secondary)
                }
            }

            // 可选「下一步」（默认折叠）
            if nextExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下一步的第一个动作（可选）")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("例：打开 LoginViewModel 补单测", text: $nextAction)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { nextExpanded = true }
                } label: {
                    Label("加一条「下一步」", systemImage: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            HStack {
                Text("时长 \(humanizedDuration(durationSeconds))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 440, height: 420)
    }

    private func save() {
        let na = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = WorkLogEntry(
            startedAt: start,
            endedAt: end,
            summary: trimmedSummary,
            nextAction: na.isEmpty ? nil : na,
            durationSeconds: durationSeconds
        )
        onSubmit(entry)
    }
}
