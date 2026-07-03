import SwiftUI
import GiveMeABreakEngine

/// 一组运动的草稿（UI 态）：类型经 Picker 选预设或「其他…」自定义，数量直接输入 + Stepper 微调。
/// 由录入提示窗与编辑表单共用，提交时转换为 `ExerciseSet`（单一事实源，避免两处重复）。
struct ExerciseSetDraft: Identifiable, Equatable {
    let id = UUID()
    var selection: String      // 预设类型 或 customSentinel
    var customText: String     // selection == customSentinel 时生效
    var reps: Int

    static let customSentinel = "__custom__"

    /// 新建草稿：`selection` 默认空串（Picker 无匹配项时回落到首项）；调用方可显式传入 `types.first`。
    init(selection: String = "", customText: String = "", reps: Int = 20) {
        self.selection = selection
        self.customText = customText
        self.reps = reps
    }

    /// 由已有 `ExerciseSet` 还原草稿（编辑模式）：类型在给定类型列表内则选中之，否则归为自定义。
    /// `types` 为当前配置注册表（v7 起来自 `DayPlanConfig.exerciseTypes`），决定「预设 vs 自定义」归属。
    init(from set: ExerciseSet, types: [String]) {
        if types.contains(set.type) {
            self.selection = set.type
            self.customText = ""
        } else {
            self.selection = ExerciseSetDraft.customSentinel
            self.customText = set.type
        }
        self.reps = set.reps
    }

    /// 规范化后的类型名（自定义时取去空白文本）。
    var effectiveType: String {
        let t = (selection == ExerciseSetDraft.customSentinel) ? customText : selection
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 是否有效（类型非空且数量 > 0）。
    var isValid: Bool { !effectiveType.isEmpty && reps > 0 }
}

/// 草稿数组 → 入库的 `ExerciseSet` 列表（过滤无效项；类型去空白）。
func materializeSets(_ drafts: [ExerciseSetDraft]) -> [ExerciseSet] {
    drafts.filter { $0.isValid }.map { ExerciseSet(type: $0.effectiveType, reps: $0.reps) }
}

/// 可复用的「运动组」编辑器：动态行（类型 Picker + 数量输入/Stepper），支持 +增 / −删。
/// 录入提示窗与编辑表单共用同一视觉与交互（SSOT）。Picker 数据源为 `types`（配置注册表，可持久增删）。
struct ExerciseSetsEditor: View {
    /// Picker 数据源：来自 `DayPlanConfig.exerciseTypes`（用户可在设置增删；自定义项保存即自动记住）。
    private let types: [String]
    @Binding var drafts: [ExerciseSetDraft]

    init(types: [String], drafts: Binding<[ExerciseSetDraft]>) {
        self.types = types
        self._drafts = drafts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($drafts) { $draft in
                row($draft)
            }
            Button {
                drafts.append(ExerciseSetDraft(selection: types.first ?? defaultExerciseTypes.first ?? ""))
            } label: {
                Label("再加一组", systemImage: "plus.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.teal)
        }
    }

    @ViewBuilder
    private func row(_ draft: Binding<ExerciseSetDraft>) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: draft.selection) {
                ForEach(types, id: \.self) { Text($0).tag($0) }
                Divider()
                Text("其他…").tag(ExerciseSetDraft.customSentinel)
            }
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel("运动类型")

            if draft.wrappedValue.selection == ExerciseSetDraft.customSentinel {
                TextField("自定义动作", text: draft.customText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .accessibilityLabel("自定义运动类型")
            }

            Spacer(minLength: 4)

            TextField("数量", value: draft.reps, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("运动数量")
            Stepper("", value: draft.reps, in: 0...9999)
                .labelsHidden()
                .accessibilityLabel("数量增减")

            Button {
                drafts.removeAll { $0.id == draft.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .disabled(drafts.count <= 1)              // 至少保留一行
            .help(drafts.count > 1 ? "删除该组" : "至少保留一组")
            .accessibilityLabel("删除该组")
        }
    }
}
