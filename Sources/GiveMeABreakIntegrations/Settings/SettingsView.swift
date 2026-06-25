import SwiftUI
import GiveMeABreakEngine

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

/// 设置视图：一般 / 工作时段 / 节律 / 休息音效 四 Section（draft-apply 模式）。
/// 「开机自启」即时生效（非 draft，符合登录项语义）；其余随「应用」提交。
struct SettingsView: View {
    @State private var draft: DayPlanConfig
    @State private var loginEnabled: Bool
    private let onApply: (DayPlanConfig) -> Void
    private let onCancel: () -> Void
    private let onToggleLogin: (Bool) -> Void

    init(initial: DayPlanConfig,
         loginEnabled: Bool,
         onApply: @escaping (DayPlanConfig) -> Void,
         onCancel: @escaping () -> Void,
         onToggleLogin: @escaping (Bool) -> Void) {
        _draft = State(initialValue: initial)
        _loginEnabled = State(initialValue: loginEnabled)
        self.onApply = onApply
        self.onCancel = onCancel
        self.onToggleLogin = onToggleLogin
    }

    /// 工作时段校验：非跨午夜且 end ≤ start 视为非法（禁用「应用」+ 行内警示）。
    private var hasInvalidWindow: Bool {
        draft.workWindows.contains { !$0.crossesMidnight && $0.end.rawValue <= $0.start.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                generalSection
                workWindowsSection
                rhythmSection
                soundSection
            }
            .formStyle(.grouped)

            Divider()
            footerButtons
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 460, idealHeight: 580)
    }

    // MARK: - 一般（开机自启：即时生效）

    private var generalSection: some View {
        Section {
            Toggle("开机时自动启动 Give me a break", isOn: Binding(
                get: { loginEnabled },
                set: { newValue in
                    loginEnabled = newValue
                    onToggleLogin(newValue)   // 即时生效，不走 draft（符合登录项语义）
                }
            ))
            .accessibilityHint("登录后自动在后台运行 Give me a break")
        } header: {
            Text("一般")
        } footer: {
            Text("也可在「系统设置 → 通用 → 登录项」管理。")
        }
    }

    // MARK: - 工作时段

    private var workWindowsSection: some View {
        Section {
            ForEach(draft.workWindows.indices, id: \.self) { i in
                workWindowRow(i)
            }
            Button {
                draft.workWindows.append(WorkWindow(start: TimeOfDay(hours: 14), end: TimeOfDay(hours: 18)))
            } label: {
                Label("添加时段", systemImage: "plus")
            }
        } header: {
            Text("工作时段（每日重复）")
        } footer: {
            Text("这些时间段每天都会生效，期间累计工作时间。时段可跨午夜（如 22:00–02:00）。")
        }
    }

    @ViewBuilder
    private func workWindowRow(_ i: Int) -> some View {
        let window = draft.workWindows[i]
        let invalid = !window.crossesMidnight && window.end.rawValue <= window.start.rawValue
        let canDelete = draft.workWindows.count > 1

        HStack(spacing: 10) {
            DatePicker("开始", selection: timeBinding(at: i, \.start), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityLabel("第 \(i + 1) 个时段的开始时间")
            Text("→").foregroundStyle(.secondary)
            DatePicker("结束", selection: timeBinding(at: i, \.end), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityLabel("第 \(i + 1) 个时段的结束时间")
            Spacer(minLength: 8)
            if invalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("结束时间需晚于开始时间，或设为跨午夜时段")
                    .accessibilityLabel("该时段无效：结束需晚于开始")
            }
            Button {
                draft.workWindows.remove(at: i)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)                      // 灰显替代静默 guard
            .help(canDelete ? "删除该时段" : "至少保留一个工作时段")
            .accessibilityLabel("删除第 \(i + 1) 个时段")
        }
    }

    // MARK: - 节律（Stepper 标题左对齐 + 数值/控件右对齐同一行）

    private var rhythmSection: some View {
        Section {
            inlineStepper("工作时长", value: minutesBinding(\.workIntervalSeconds),
                          range: 5...240, step: 5, hint: "每累计工作这么久，就触发一次休息")
            inlineStepper("休息时长", value: minutesBinding(\.restDurationSeconds),
                          range: 1...60, step: 1, hint: "每次休息的持续时长")
            inlineStepper("离开判定（AFK 阈值）", value: minutesBinding(\.afkThresholdSeconds),
                          range: 1...60, step: 1, hint: "连续无键鼠操作超过此值，视为已离开座位，暂停工作计时")
        } header: {
            Text("节律")
        } footer: {
            Text("AFK = Away From Keyboard。离开判定在你短暂离座时暂停累计工作时间，避免误触发休息。")
        }
    }

    /// 标题左、Stepper（label 闭包显示当前值）右，同一行对齐。
    @ViewBuilder
    private func inlineStepper(_ title: String, value: Binding<Int>,
                               range: ClosedRange<Int>, step: Int, hint: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue) 分钟")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("\(title)，当前 \(value.wrappedValue) 分钟")
            .accessibilityHint(hint)
        }
    }

    // MARK: - 休息音效

    private var soundSection: some View {
        Section {
            Toggle("休息时播放舒缓白噪音", isOn: $draft.ambientSoundEnabled)
                .accessibilityHint("内置粉噪音，无需安装任何播放器")
            Toggle("联动 QQ 音乐", isOn: $draft.controlQQMusic)
                .accessibilityHint("需安装 QQ 音乐并授予辅助功能权限")
        } header: {
            Text("休息音效")
        } footer: {
            Text("白噪音由应用内置合成，可靠且不依赖外部播放器；QQ 音乐联动经系统媒体键控制，需安装并授权辅助功能。")
        }
    }

    // MARK: - 底部按钮栏

    private var footerButtons: some View {
        HStack {
            Button("恢复默认") { draft = .defaultConfig }
                .help("将工作时段、节律与音效恢复为初始值（不影响开机自启）")
            Spacer()
            Button("取消") { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button("应用") { onApply(draft) }
                .keyboardShortcut(.defaultAction)
                .disabled(hasInvalidWindow)
        }
        .padding(16)
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
