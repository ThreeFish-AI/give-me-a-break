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

/// 设置视图：四页签分类（通用 / 作息 / 休息音效 / 工作日志），draft-apply 模式。
/// 「开机自启」即时生效（非 draft）；其余随底部「应用」一次性提交所有页签的草稿。
struct SettingsView: View {
    @State private var draft: DayPlanConfig
    @State private var loginEnabled: Bool
    @State private var selectedTab: SettingsTab = .general
    @State private var showingResetConfirm: Bool = false
    private let onApply: (DayPlanConfig) -> Void
    private let onCancel: () -> Void
    private let onToggleLogin: (Bool) -> Void

    private enum SettingsTab: Hashable { case general, schedule, sound, workLog }

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

                // 休息音效：休息时听什么（自定义音频 / 白噪音 / QQ 音乐）
                Form {
                    soundSection
                }
                .formStyle(.grouped)
                .tabItem { Label("休息音效", systemImage: "music.note") }
                .tag(SettingsTab.sound)

                // 工作日志：休息前的小结书写（开关 / 永久等待 / 等待时长）
                Form {
                    workLogSection
                }
                .formStyle(.grouped)
                .tabItem { Label("工作日志", systemImage: "note.text") }
                .tag(SettingsTab.workLog)
            }

            Divider()
            footerButtons
        }
        // 宽度固定、高度随当前页签内容自适应（窗口侧以 preferredContentSize 跟随，免滚动条/多余留白）。
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
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
            Toggle("开机时自动启动", isOn: Binding(
                get: { loginEnabled },
                set: { newValue in
                    loginEnabled = newValue
                    onToggleLogin(newValue)   // 即时生效，不走 draft（符合登录项语义）
                }
            ))
            .accessibilityHint("登录系统后在后台自动启动并守护作息")
        } header: {
            Text("一般")
        } footer: {
            Text("如需关闭，也可在「系统设置 → 通用 → 登录项」中管理。")
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
                    Text("v\(appVersion) · 菜单栏强制作息守护 · macOS 14+")
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
            Text("仅在这些时段内累计工作时间并触发休息；每天自动重复。时段可跨午夜（如 22:00–02:00）。")
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
                          range: 5...240, step: 5, hint: "累计工作达到此时长，触发一次强制休息")
            inlineStepper("休息时长", value: minutesBinding(\.restDurationSeconds),
                          range: 1...60, step: 1, hint: "每次强制休息的持续时长")
            inlineStepper("离开判定（AFK 阈值）", value: minutesBinding(\.afkThresholdSeconds),
                          range: 1...60, step: 1, hint: "无键鼠操作超过此时长即判定离座，暂停累计工作时间")
        } header: {
            Text("节律")
        } footer: {
            Text("AFK（Away From Keyboard）即离座判定：人不在时暂停计时，避免误触发休息。")
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
            Toggle("休息时播放柔和粉噪音", isOn: $draft.ambientSoundEnabled)
                .accessibilityHint("应用实时合成、开箱即用；设置上方休息音乐后由其取代，音乐加载失败时回退至此")
            Toggle("联动 QQ 音乐", isOn: $draft.controlQQMusic)
                .accessibilityHint("需已安装 QQ 音乐并授予辅助功能权限")
        } header: {
            Text("休息音效")
        } footer: {
            Text("休息时声音优先级：休息音乐 → 柔和粉噪音。设置「休息音乐」后循环播放所选本地音频（mp3/m4a/aac/wav/flac 等）取代粉噪音；文件缺失、格式不支持或被移动删除时，若已开启「柔和粉噪音」则回退之，否则静默。音频仅以本地路径引用、不打包不分发。\n粉噪音由应用实时合成，可靠且不依赖外部播放器；QQ 音乐为可叠加联动，经系统媒体键控制，需安装并授予辅助功能权限。")
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
                    .accessibilityHint("清除自定义休息音乐，回退到内置粉噪音")
            }
            Button(draft.restMusicPath?.isEmpty ?? true ? "选择文件…" : "更换…") { pickRestMusicFile() }
                .accessibilityHint("选择本地音频文件（mp3/m4a/aac/wav/flac）作为休息音乐，取代粉噪音")
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
                .accessibilityHint("自然休息前弹出输入框，记录刚完成的工作与成果，让大脑真正放下")
            if draft.workLogEnabled {
                Toggle("永久等待（不自动跳过、不自动进入休息）", isOn: waitForeverBinding)
                    .accessibilityHint("开启后小结窗不自动消失，需手动「记录并休息」「跳过」或关窗")
                if draft.workLogPromptTimeoutSeconds > 0 {
                    inlineStepper("自动放行等待时长", value: minutesBinding(\.workLogPromptTimeoutSeconds),
                                  range: 1...30, step: 1, hint: "小结窗弹出后超过此时长未操作，自动跳过并进入休息")
                }
            }
        } header: {
            Text("工作日志")
        } footer: {
            Text("自然休息前花 30 秒写下「刚完成什么 + 下一步」，完成认知闭合再休息。永不阻塞：回车提交 / Esc 或关窗跳过 / 到点自动放行（默认 3 分钟，可调，或设「永久等待」），也可在上方整体关闭；「立即休息」不弹。记录落盘，可在菜单「工作日志…」生成今日 / 本周 / 本月报告。")
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
