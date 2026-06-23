import SwiftUI
import TimeoutEngine

// MARK: - TimeOfDay ↔ Date 桥接（DatePicker hourAndMinute 需要 Date）

private extension TimeOfDay {
    /// 用固定基准日期承载 HH:mm:ss。
    var asDate: Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.hour = hourComponent; c.minute = minuteComponent; c.second = secondComponent
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }
    init?(hourMinute date: Date) {
        let comps = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
        guard let h = comps.hour, let m = comps.minute else { return nil }
        self.init(hours: h, minutes: m)
    }
}

/// 设置视图：图形化编辑工作时段、工作/休息时长、AFK 阈值。
struct SettingsView: View {
    @State private var draft: DayPlanConfig
    private let onApply: (DayPlanConfig) -> Void
    private let onCancel: () -> Void

    init(initial: DayPlanConfig, onApply: @escaping (DayPlanConfig) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: initial)
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("工作时段（每日重复）") {
                    ForEach(draft.workWindows.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            DatePicker("开始", selection: timeBinding(at: i, \.start), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .help("开始时间")
                            Text("→").foregroundStyle(.secondary)
                            DatePicker("结束", selection: timeBinding(at: i, \.end), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .help("结束时间")
                            Spacer()
                            Button {
                                guard draft.workWindows.count > 1 else { return }
                                draft.workWindows.remove(at: i)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("删除该时段")
                        }
                    }
                    Button {
                        draft.workWindows.append(WorkWindow(start: TimeOfDay(hours: 14), end: TimeOfDay(hours: 18)))
                    } label: {
                        Label("添加时段", systemImage: "plus.circle.fill")
                    }
                }

                Section("节律") {
                    stepperRow("工作时长", value: minutesBinding(\.workIntervalSeconds), range: 5...240, step: 5)
                    stepperRow("休息时长", value: minutesBinding(\.restDurationSeconds), range: 1...60, step: 1)
                    stepperRow("离开判定（AFK 阈值）", value: minutesBinding(\.afkThresholdSeconds), range: 1...60, step: 1)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("应用") { onApply(draft) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 380)
    }

    // MARK: - 行视图

    @ViewBuilder
    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value.wrappedValue) 分钟").foregroundStyle(.secondary).monospacedDigit()
        }
        Stepper("\(title)", value: value, in: range, step: step)
            .labelsHidden()
    }

    // MARK: - Bindings

    private func timeBinding(at index: Int, _ keyPath: WritableKeyPath<WorkWindow, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { draft.workWindows[index][keyPath: keyPath].asDate },
            set: { newDate in
                if let td = TimeOfDay(hourMinute: newDate) {
                    draft.workWindows[index][keyPath: keyPath] = td
                }
            }
        )
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<DayPlanConfig, TimeInterval>) -> Binding<Int> {
        Binding(
            get: { Int(draft[keyPath: keyPath] / 60) },
            set: { draft[keyPath: keyPath] = TimeInterval($0) * 60 }
        )
    }
}
