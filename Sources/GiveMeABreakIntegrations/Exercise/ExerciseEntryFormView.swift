import SwiftUI
import GiveMeABreakEngine

/// 运动记录「条目表单」：补录（新增）与编辑（改已有）共用同一视觉与交互（镜像 `WorkLogEntryFormView`）。
///
/// 语义为「用户自选时段、无超时、保存/取消、不触发休息」。两模式差异：
/// - `.create`：标题「补录运动记录」、字段空（默认一组深蹲）、保存生成新 `id`；
/// - `.edit`：标题「编辑运动记录」、字段预填、保存**保留原 `id` 与 `modelVersion`**。
enum ExerciseEntryFormMode {
    case create(defaultStart: Date, defaultEnd: Date)
    case edit(ExerciseEntry)
}

struct ExerciseEntryFormView: View {
    private let mode: ExerciseEntryFormMode
    /// Picker 数据源（配置注册表，v7 起来自 `DayPlanConfig.exerciseTypes`）。
    private let types: [String]
    private let onSubmit: (ExerciseEntry) -> Void
    private let onCancel: () -> Void

    @State private var start: Date
    @State private var end: Date
    @State private var drafts: [ExerciseSetDraft]
    @State private var note: String
    @State private var noteExpanded: Bool

    init(mode: ExerciseEntryFormMode,
         types: [String],
         onSubmit: @escaping (ExerciseEntry) -> Void,
         onCancel: @escaping () -> Void) {
        self.mode = mode
        self.types = types
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        switch mode {
        case .create(let defaultStart, let defaultEnd):
            let safeStart = defaultStart < defaultEnd ? defaultStart : defaultEnd.addingTimeInterval(-60)
            _start = State(initialValue: safeStart)
            _end = State(initialValue: defaultEnd)
            _drafts = State(initialValue: [ExerciseSetDraft(selection: types.first ?? defaultExerciseTypes.first ?? "")])
            _note = State(initialValue: "")
            _noteExpanded = State(initialValue: false)
        case .edit(let entry):
            let safeStart = entry.startedAt < entry.endedAt ? entry.startedAt : entry.endedAt.addingTimeInterval(-60)
            _start = State(initialValue: safeStart)
            _end = State(initialValue: entry.endedAt)
            let restored = entry.sets.map { ExerciseSetDraft(from: $0, types: types) }
            _drafts = State(initialValue: restored.isEmpty
                ? [ExerciseSetDraft(selection: types.first ?? defaultExerciseTypes.first ?? "")]
                : restored)
            _note = State(initialValue: entry.note ?? "")
            _noteExpanded = State(initialValue: entry.note?.isEmpty == false)
        }
    }

    private var isEdit: Bool { if case .edit = mode { return true } else { return false } }
    private var titleText: String { isEdit ? "编辑运动记录" : "补录运动记录" }
    private var iconName: String { isEdit ? "figure.run" : "figure.run.square.stack" }
    private var descText: String {
        isEdit
            ? "调整这条运动记录的时段、动作或备注，保存后报告自动重算。"
            : "为漏掉的某段运动补一条记录。选择时段、填动作与数量，保存后并入综合报告。"
    }

    private var hasValidSet: Bool { drafts.contains { $0.isValid } }
    private var canSave: Bool { hasValidSet && end > start }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: iconName).foregroundStyle(.teal).font(.system(size: 20))
                Text(titleText).font(.system(size: 18, weight: .semibold))
                Spacer()
            }

            Text(descText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 时段（DatePicker 互相约束：start ≤ end）
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("开始").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                    DatePicker("", selection: $start, in: ...end, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .accessibilityLabel("运动时段的开始时间")
                    Spacer()
                }
                HStack(spacing: 10) {
                    Text("结束").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                    DatePicker("", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .accessibilityLabel("运动时段的结束时间")
                    Spacer()
                }
            }

            // 运动组编辑器（与录入提示窗共用）
            ExerciseSetsEditor(types: types, drafts: $drafts)

            // 可选备注
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
                Text(isEdit ? "改这一条" : "新增一条")
                    .font(.system(size: 12))
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
        .frame(width: 460, height: 460)
    }

    private func save() {
        let sets = materializeSets(drafts)
        guard !sets.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry: ExerciseEntry
        switch mode {
        case .create:
            entry = ExerciseEntry(startedAt: start, endedAt: end, sets: sets,
                                  note: trimmedNote.isEmpty ? nil : trimmedNote)
        case .edit(let original):
            entry = ExerciseEntry(id: original.id, startedAt: start, endedAt: end, sets: sets,
                                  note: trimmedNote.isEmpty ? nil : trimmedNote,
                                  modelVersion: original.modelVersion)
        }
        onSubmit(entry)
    }
}
