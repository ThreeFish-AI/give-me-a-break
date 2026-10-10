import SwiftUI
import GiveMeABreakEngine

/// 退出休息（自然结束）后弹出的运动记录提示视图（与 `WorkLogPromptView` 对称：工作日志在休息前、运动记录在休息后）。
///
/// - 顶部只读上下文行展示「运动时段」（默认取这段休息的起止）；
/// - 主体为可复用的 `ExerciseSetsEditor`（默认一组，预设深蹲），可加多组；
/// - 永不阻塞：回车「记录完成」/ Esc 跳过 / 关窗放行 / 到点自动放行；无有效组提交 ≡ 跳过；
/// - 可选「备注」次级字段，默认折叠。
struct ExercisePromptView: View {
    private let restStartedAt: Date
    private let restEndedAt: Date
    /// Picker 数据源（配置注册表，v7 起来自 `DayPlanConfig.exerciseTypes`）。
    private let types: [String]
    private let onSubmit: ([ExerciseSet], String?) -> Void
    private let onSkip: () -> Void

    @State private var drafts: [ExerciseSetDraft]
    @State private var note: String = ""
    @State private var noteExpanded: Bool = false

    init(restStartedAt: Date,
         restEndedAt: Date,
         types: [String],
         onSubmit: @escaping ([ExerciseSet], String?) -> Void,
         onSkip: @escaping () -> Void) {
        self.restStartedAt = restStartedAt
        self.restEndedAt = restEndedAt
        self.types = types
        self.onSubmit = onSubmit
        self.onSkip = onSkip
        _drafts = State(initialValue: [ExerciseSetDraft(selection: types.first ?? defaultExerciseTypes.first ?? "")])
    }

    private var windowText: String {
        "运动时段 \(hhmmLocal(restStartedAt))–\(hhmmLocal(restEndedAt))（休息时段）"
    }

    private var hasValidSet: Bool { drafts.contains { $0.isValid } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run").foregroundStyle(.teal).font(.system(size: 20))
                Text("动一动，给身体也记一笔")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }

            Text("休息结束了。刚才做了哪些微运动？记录下来，日积月累汇入周 / 月 / 季 / 年报。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(windowText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            ExerciseSetsEditor(types: types, drafts: $drafts)

            // 可选「备注」，默认折叠
            if noteExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("备注（可选）")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("例：热身后做的", text: $note)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { noteExpanded = true }
                } label: {
                    Label("加一条备注", systemImage: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            HStack {
                Text(hasValidSet ? "共 \(materializeSets(drafts).reduce(0) { $0 + $1.reps }) 个" : "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("跳过") { submitOrSkip() }
                    .keyboardShortcut(.cancelAction)
                Button("记录完成") { submitOrSkip() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }

    /// 提交：无有效组 ≡ 跳过（不写入）；否则带上可选备注。
    private func submitOrSkip() {
        let sets = materializeSets(drafts)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if sets.isEmpty {
            onSkip()
        } else {
            onSubmit(sets, trimmedNote.isEmpty ? nil : trimmedNote)
        }
    }
}

/// 本地时区 HH:mm（UI 展示用；报告分桶仍走引擎层零 locale 依赖的日期键）。
func hhmmLocal(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}
