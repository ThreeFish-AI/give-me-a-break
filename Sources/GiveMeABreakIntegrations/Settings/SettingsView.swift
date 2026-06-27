import AppKit
import SwiftUI
import UniformTypeIdentifiers
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

/// 设置视图：三页签分类（通用 / 作息 / 休息），draft-apply 模式。
/// 「开机自启」即时生效（非 draft）；其余随底部「应用」一次性提交所有页签的草稿。
struct SettingsView: View {
    @State private var draft: DayPlanConfig
    @State private var loginEnabled: Bool
    @State private var selectedTab: SettingsTab = .general
    @State private var showingResetConfirm: Bool = false
    private let onApply: (DayPlanConfig) -> Void
    private let onCancel: () -> Void
    private let onToggleLogin: (Bool) -> Void

    private enum SettingsTab: Hashable { case general, schedule, rest }

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
            TabView(selection: $selectedTab) {
                // 通用：开机自启 + 关于
                Form {
                    generalSection
                    aboutSection
                }
                .formStyle(.grouped)
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)

                // 作息：工作时段 + 节律（何时工作、工作多久休息一次）
                Form {
                    workWindowsSection
                    rhythmSection
                }
                .formStyle(.grouped)
                .tabItem { Label("作息", systemImage: "clock") }
                .tag(SettingsTab.schedule)

                // 休息：休息音效 + 工作日志（休息前后发生什么）
                Form {
                    soundSection
                    workLogSection
                }
                .formStyle(.grouped)
                .tabItem { Label("休息", systemImage: "moon.stars") }
                .tag(SettingsTab.rest)
            }

            Divider()
            footerButtons
        }
        .frame(minWidth: 500, idealWidth: 560, minHeight: 420, idealHeight: 540)
        .confirmationDialog("确定恢复全部设置为默认值？",
                            isPresented: $showingResetConfirm,
                            titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) { draft = .defaultConfig }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将重置工作时段、节律、休息音效与工作日志为初始值（不影响开机自启）。")
        }
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

    // MARK: - 关于（版本信息，平衡「通用」页签）

    private var aboutSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Give me a break").font(.headline)
                    Text("v\(appVersion) · 菜单栏强制作息守护")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        } header: {
            Text("关于")
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
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
            restMusicRow
            Toggle("休息时播放舒缓白噪音", isOn: $draft.ambientSoundEnabled)
                .accessibilityHint("内置粉噪音，无需安装任何播放器；当上方设置了休息音乐时将被取代")
            Toggle("联动 QQ 音乐", isOn: $draft.controlQQMusic)
                .accessibilityHint("需安装 QQ 音乐并授予辅助功能权限")
        } header: {
            Text("休息音效")
        } footer: {
            Text("设置「休息音乐」后，休息时将循环播放你选择的本地音频文件（mp3/m4a/aac/wav/flac 等），取代内置白噪音；若文件不存在或格式不支持，会回退到白噪音。文件不被打包或分发，仅以本地路径引用——移动或删除该文件会导致回退。白噪音由应用内置合成，可靠且不依赖外部播放器；QQ 音乐联动经系统媒体键控制，需安装并授权辅助功能。")
        }
    }

    /// 自定义休息音频选择行：NSOpenPanel 选本地音频文件，存绝对路径到 draft.restMusicPath；可清除。
    /// App 非沙盒，故直接以路径字符串引用（无需安全作用域书签）。
    private var restMusicRow: some View {
        HStack(spacing: 10) {
            Text("休息音乐")
            Spacer(minLength: 8)
            if let p = draft.restMusicPath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                Text((p as NSString).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("当前休息音乐：\((p as NSString).lastPathComponent)")
                Button("清除") { draft.restMusicPath = nil }
                    .buttonStyle(.borderless)
                    .accessibilityHint("清除自定义休息音乐，回退到内置白噪音")
            }
            Button(draft.restMusicPath?.isEmpty ?? true ? "选择文件…" : "更换…") { pickRestMusicFile() }
                .accessibilityHint("选择本地音频文件（mp3/m4a/aac/wav/flac）作为休息音乐，取代白噪音")
        }
    }

    private func pickRestMusicFile() {
        let panel = NSOpenPanel()
        panel.title = "选择休息音乐"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // 以扩展名解析 UTType，覆盖 mp3/m4a/aac/wav/flac/aiff/caf 等（FLAC 无稳定系统常量，故走 filenameExtension）。
        var types: Set<UTType> = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]
        for ext in ["mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "caf"] {
            if let t = UTType(filenameExtension: ext) { types.insert(t) }
        }
        panel.allowedContentTypes = Array(types)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.restMusicPath = url.path
    }

    // MARK: - 工作日志（休息前记录）

    private var workLogSection: some View {
        Section {
            Toggle("休息前记录工作日志", isOn: $draft.workLogEnabled)
                .accessibilityHint("自然休息前弹出输入框，记录这段时间的工作内容与成果")
            if draft.workLogEnabled {
                Toggle("永久等待（不自动跳过、不自动进入休息）", isOn: waitForeverBinding)
                    .accessibilityHint("开启后小结窗不会自动消失，需手动「记录并休息」「跳过」或关闭窗口")
                if draft.workLogPromptTimeoutSeconds > 0 {
                    inlineStepper("自动放行等待时长", value: minutesBinding(\.workLogPromptTimeoutSeconds),
                                  range: 1...30, step: 1, hint: "小结窗弹出后，超过此时长未操作即自动跳过进入休息")
                }
            }
        } header: {
            Text("工作日志")
        } footer: {
            Text("累满工作时长的自然休息前，会弹出输入框让你花 30 秒写下刚完成的与下一步，让大脑真正放下。可设定等待时长后自动放行（默认 3 分钟），或开启「永久等待」让窗口停留至手动操作，或在上方关闭整个环节。「立即休息」不弹。记录可在菜单「工作日志…」查看，生成今日/本周/本月报告。")
        }
    }

    // MARK: - 底部按钮栏

    private var footerButtons: some View {
        HStack {
            Button("恢复默认") { showingResetConfirm = true }
                .help("将工作时段、节律、休息音效与工作日志恢复为初始值（不影响开机自启）")
            Spacer()
            Button("取消") { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button("应用") { onApply(draft) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)   // 唯一主操作（primary-action），全局提交所有页签草稿
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

    /// 「永久等待」开关 ↔ workLogPromptTimeoutSeconds 哨兵 0。关永久即回默认 3 分钟。
    private var waitForeverBinding: Binding<Bool> {
        Binding(
            get: { draft.workLogPromptTimeoutSeconds <= 0 },
            set: { draft.workLogPromptTimeoutSeconds = $0 ? 0 : 180 }
        )
    }
}
