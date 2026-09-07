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

// MARK: - 页签规格与尺寸契约（SSOT：渲染与宽度测算同源）

/// 设置页签（七页签分类：通用 / 电源 / 作息 / 休息音效 / 工作日志 / 运动记录 / Agentic AI）。
private enum SettingsTab: Hashable { case general, power, schedule, sound, workLog, exercise, agenticAI }

/// 页签规格：页签条渲染与宽度测算共用同一份标题，防「文案改了、测算没跟上」漂移。
private struct SettingsTabSpec {
    let tab: SettingsTab
    let title: String
}

/// 自绘页签条的宽度模型（自绘后测量字体=渲染字体，宽度闭式确定；Apple 不公布原生页签条度量，
/// 且原生样式在 macOS 26 会把页签均匀铺满工具栏、间隙不可控）。
private enum SettingsTabMetrics {
    static let tabs: [SettingsTabSpec] = [
        .init(tab: .general,   title: "通用"),
        .init(tab: .power,     title: "电源"),
        .init(tab: .schedule,  title: "作息"),
        .init(tab: .sound,     title: "音效"),
        .init(tab: .workLog,   title: "日志"),
        .init(tab: .exercise,  title: "运动"),
        .init(tab: .agenticAI, title: "Agentic AI"),
    ]

    static let labelFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)  // 13pt，页签标题字体
    /// 相邻页签标题文字的净间隙：1.5 个字宽（13pt 下 ≈ 19.5pt），恒定不随窗口宽度拉伸。
    /// 以「标题两侧各留一半内边距」实现（条内零间距），文字间隙恰为 1.5 字宽。
    static let interTitleGap: CGFloat = NSFont.systemFontSize * 1.5
    /// 页签条与窗口左右边缘的留白（与 Form(.grouped) 内容边距对齐）。
    static let stripHorizontalPadding: CGFloat = 16
    /// 表单可读性下限（历史验证值 560：两组 Section 首屏可见，长期使用的固定宽度）。
    static let formMinWidth: CGFloat = 560

    /// 页签条自然宽度（含左右留白）；窗口最小宽度须容纳它，杜绝标题截断。
    static var stripNaturalWidth: CGFloat {
        let text = tabs.reduce(CGFloat(0)) {
            $0 + ceil(($1.title as NSString).size(withAttributes: [.font: labelFont]).width)
        }
        return text + CGFloat(tabs.count) * interTitleGap + 2 * stripHorizontalPadding
    }
}

/// 设置视图：七页签分类（通用 / 电源 / 作息 / 音效 / 日志 / 运动 / Agentic AI），draft-apply 模式。
/// 「开机自启」与「防止睡眠」总开关即时生效（非 draft）——二者同为菜单栏快捷开关，走 draft 会让
/// 设置窗开启期间菜单侧的改动被旧草稿静默回滚；其余随底部「应用」一次性提交所有页签的草稿。
struct SettingsView: View {
    @State private var draft: DayPlanConfig
    @State private var loginEnabled: Bool
    /// 「防止睡眠」总开关（即时通道的本地镜像，非 draft 字段；权威值在 `engine.config`）。
    @State private var preventIdleSleepEnabled: Bool
    @State private var selectedTab: SettingsTab = .general
    @State private var showingResetConfirm: Bool = false
    /// 已安装的候选编辑器（Agentic AI 页「在…中打开」下拉数据源）；视图出现时探测一次。
    @State private var installedEditors: [ClaudeSettingsLauncher.InstalledEditor] = []
    private let onApply: (DayPlanConfig) -> Void
    private let onCancel: () -> Void
    private let onToggleLogin: (Bool) -> Void
    private let onTogglePreventIdleSleep: (Bool) -> Void

    // MARK: - 窗口尺寸契约（供 SettingsWindowController：contentMinSize 锁底 + 首开默认值）

    /// 窗口最小内容宽度：页签条自然宽度与表单可读性下限取大（运行期按页签文案测算）。
    static var minimumContentWidth: CGFloat {
        max(SettingsTabMetrics.formMinWidth, SettingsTabMetrics.stripNaturalWidth).rounded(.up)
    }
    static let minimumContentHeight: CGFloat = 440   // 页签条(~40)+footer(~56)+至少两组 Section
    /// 首次打开默认尺寸：宽度 = 平铺下限 + 呼吸余量；高度盖住最高常用页签（作息）。
    /// 不按首签内容适配——「通用」页很矮，按它开窗过小、切页签即滚动。
    static var defaultContentSize: NSSize {
        NSSize(width: minimumContentWidth + 40, height: 640)
    }

    init(initial: DayPlanConfig,
         loginEnabled: Bool,
         onApply: @escaping (DayPlanConfig) -> Void,
         onCancel: @escaping () -> Void,
         onToggleLogin: @escaping (Bool) -> Void,
         onTogglePreventIdleSleep: @escaping (Bool) -> Void) {
        _draft = State(initialValue: initial)
        _loginEnabled = State(initialValue: loginEnabled)
        _preventIdleSleepEnabled = State(initialValue: initial.power.preventIdleSleepEnabled)
        self.onApply = onApply
        self.onCancel = onCancel
        self.onToggleLogin = onToggleLogin
        self.onTogglePreventIdleSleep = onTogglePreventIdleSleep
    }

    /// 工作时段校验：非跨午夜且 end ≤ start 视为非法（禁用「应用」+ 行内警示）。
    private var hasInvalidWindow: Bool {
        draft.workWindows.contains { !$0.crossesMidnight && $0.end.rawValue <= $0.start.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()
            content(for: selectedTab)
                .formStyle(.grouped)

            Divider()
            footerButtons
        }
        .onAppear { installedEditors = ClaudeSettingsLauncher.availableEditors() }
        // 尺寸契约：不加任何 frame 修饰符——窗口尺寸归用户（控制器经 contentMinSize 锁
        // 「页签条自然宽度 ∨ 表单可读性」下限）；窗口偏小时由 Form（grouped 即 ScrollView）
        // 内部滚动，不压坏布局。
        .confirmationDialog("确定恢复全部设置为默认值？",
                            isPresented: $showingResetConfirm,
                            titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) { draft = .defaultConfig }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将重置工作时段、节律、休息音效、工作日志、运动记录、电源防护范围与 Agentic AI 设置为初始值（不影响开机自启与「防止睡眠」总开关，二者即时生效）。")
        }
    }

    // MARK: - 页签条与页签内容（规格与宽度测算同源于 SettingsTabMetrics.tabs）

    /// 自绘页签条：左对齐、相邻标题净间隙恒为 1.5 字宽，不随窗口宽度拉伸——原生 TabView 在
    /// macOS 26 将页签均匀铺满工具栏、间隙不可控，故弃用改自绘；窗口 contentMinSize ≥
    /// 页签条自然宽度，任何宽度下都不会截断或折叠。
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTabMetrics.tabs, id: \.tab) { spec in
                tabButton(for: spec)
            }
            Spacer()
        }
        .padding(.horizontal, SettingsTabMetrics.stripHorizontalPadding)
        .padding(.vertical, 8)
    }

    /// 单个页签：标题两侧各留 1.5 字宽的一半（间隙由 item 内边距构成，条内零间距）；
    /// 选中态胶囊底色（对齐系统分段控件观感），VoiceOver isSelected 标记选中页签。
    private func tabButton(for spec: SettingsTabSpec) -> some View {
        let isSelected = selectedTab == spec.tab
        return Button {
            selectedTab = spec.tab
        } label: {
            Text(spec.title)
                .font(.system(size: NSFont.systemFontSize))
                .padding(.horizontal, SettingsTabMetrics.interTitleGap / 2)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(isSelected ? 0.08 : 0), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .accessibilityLabel(spec.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 各页签内容：Form 与 Section 原样承载。
    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:   Form { generalSection; aboutSection }       // 通用：开机自启 + 关于
        case .power:     Form { powerSection }                       // 电源：防止空闲睡眠/熄屏（IOKit 断言，与休息/工作/遮罩引擎零耦合）
        case .schedule:  Form { workWindowsSection; rhythmSection }  // 作息：工作时段 + 节律（何时工作、工作多久休息一次）
        case .sound:     Form { soundSection }                       // 休息音效：休息时听什么（自定义音频 / 白噪音 / QQ 音乐）
        case .workLog:   Form { workLogSection }                     // 工作日志：休息前的小结书写（开关 / 永久等待 / 等待时长）
        case .exercise:  Form { exerciseSection }                    // 运动记录：休息结束后的微运动录入（开关）
        case .agenticAI: Form { agenticAISection }                   // Agentic AI：Claude Code 相关配置（为后续功能预留的 groundwork）
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

    // MARK: - 电源（防止空闲睡眠/熄屏）

    private var powerSection: some View {
        Section {
            Toggle("防止空闲睡眠熄屏", isOn: Binding(
                get: { preventIdleSleepEnabled },
                set: { newValue in
                    preventIdleSleepEnabled = newValue
                    onTogglePreventIdleSleep(newValue)   // 即时生效，与菜单栏勾选项同一通道（不走 draft）
                }
            ))
            .accessibilityHint("开启后阻止显示器与系统因空闲而熄屏/睡眠；可在菜单栏「防止睡眠」快速开关")
            if preventIdleSleepEnabled {
                Picker("防护范围", selection: $draft.power.mode) {
                    Text("仅显示器").tag(IdleSleepGuardMode.displayOnly)
                    Text("显示器 + 系统").tag(IdleSleepGuardMode.displayAndSystem)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("防护范围")
            }
        } header: {
            Text("防止空闲睡眠")
        } footer: {
            Text("开启后本应用持有系统电源断言（与 caffeinate 同机制）。「仅显示器」等同 caffeinate -d：显示器保持常亮，系统亦不会因空闲而睡眠；「显示器 + 系统」等同 caffeinate -d -i：在此之上显式阻止系统空闲睡眠。均不影响主动睡眠（合盖、Apple 菜单睡眠、低电量）。总开关即时生效（同菜单栏「防止睡眠」），防护范围随「应用」提交；状态持久化，重启后自动恢复。本功能与休息 / 工作 / 遮罩模式完全独立。")
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

    // MARK: - 运动记录（休息自然结束后记录）

    private var exerciseSection: some View {
        Group {
            Section {
                Toggle("休息结束后记录运动", isOn: $draft.exerciseLogEnabled)
                    .accessibilityHint("休息倒计时自然走完时弹出输入框，记录这段休息里做的微运动（如深蹲、俯卧撑）")
                if draft.exerciseLogEnabled {
                    Toggle("永久等待（不自动跳过）", isOn: exerciseWaitForeverBinding)
                        .accessibilityHint("开启后运动提示窗不自动消失，需手动「记录完成」「跳过」或关窗")
                    if draft.exercisePromptTimeoutSeconds > 0 {
                        inlineStepper("自动放行等待时长", value: minutesBinding(\.exercisePromptTimeoutSeconds),
                                      range: 1...30, step: 1, hint: "运动提示窗弹出后超过此时长未操作，自动跳过")
                    }
                }
            } header: {
                Text("运动记录")
            } footer: {
                Text("休息自然结束时花几秒记下做了哪些微运动（如胯下击掌 / 提膝击掌 / 深蹲 / 俯卧撑）与数量，日积月累。永不阻塞：回车「记录完成」/ Esc 或关窗跳过 / 到点自动放行；提前结束（Esc）与被会议、下班打断均不弹。运动记录与工作日志一并汇入菜单「综合报告…」，按 周 / 月 / 季 / 年 合成并导出。")
            }

            // 运动类型注册表：录入 Picker 的备选项，可增删；录入时「其他…」输入的自定义类型保存后自动加入。
            Section {
                if draft.exerciseTypes.isEmpty {
                    Text("尚无运动类型，点下方「+」添加").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(draft.exerciseTypes.indices, id: \.self) { i in
                    exerciseTypeRow(i)
                }
                Button {
                    draft.exerciseTypes.append("新运动")
                } label: {
                    Label("添加运动项", systemImage: "plus")
                }
            } header: {
                Text("运动类型")
            } footer: {
                Text("录入运动时的备选清单。点「+」添加并在行内命名（2~4 字最佳）；「−」移除（至少保留 1 项）。录入时通过「其他…」临时输入的自定义类型保存后会自动加入此处，下次可直接挑选。")
            }
        }
    }

    @ViewBuilder
    private func exerciseTypeRow(_ i: Int) -> some View {
        let canDelete = draft.exerciseTypes.count > 1
        HStack(spacing: 10) {
            TextField("运动名称", text: $draft.exerciseTypes[i])
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 8)
            Button {
                draft.exerciseTypes.remove(at: i)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .help(canDelete ? "删除该运动项" : "至少保留一项运动")
            .accessibilityLabel("删除第 \(i + 1) 个运动项")
        }
    }

    // MARK: - Agentic AI（Claude Code 配置 · 为后续 Agentic AI 功能预留）

    private var agenticAISection: some View {
        Group {
            // Claude Code 可执行文件路径：可编辑文本框 + 浏览 + 「使用系统 Claude Code」复位。
            Section {
                claudeExecutableRow
            } header: {
                Text("Claude Code 可执行文件路径")
            } footer: {
                Text("自定义 Claude Code 可执行文件路径。留空则自动从系统 PATH 探测（推荐）。此为 Agentic AI 功能预留配置，当前尚未接入实际调用。")
            }

            // Claude 设置：快捷在选定编辑器中打开 ~/.claude/settings.json。
            Section {
                claudeSettingsRow
            } header: {
                Text("Claude 设置")
            } footer: {
                Text("在选定编辑器中快捷打开 Claude Code 用户配置文件 ~/.claude/settings.json；点「在…中打开」右侧箭头可切换编辑器（自动探测已安装的 VS Code / Cursor 等，另有「系统默认」与「其他应用…」）。文件不存在时在访达中定位 ~/.claude 目录。")
            }
        }
    }

    /// 可执行路径行：TextField（可键入）+ 非阻塞无效提示 + 浏览按钮 + 复位为系统探测。
    private var claudeExecutableRow: some View {
        let trimmed = (draft.agent.claudeExecutablePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = !trimmed.isEmpty && !FileManager.default.isExecutableFile(atPath: trimmed)
        return HStack(spacing: 8) {
            TextField("Claude Code 可执行文件路径", text: Binding(
                get: { draft.agent.claudeExecutablePath ?? "" },
                set: { draft.agent.claudeExecutablePath = $0.isEmpty ? nil : $0 }
            ), prompt: Text(verbatim: "/opt/homebrew/bin/claude"))
            .labelsHidden()                                  // 隐藏前导标签，占位符落入框内（同 DatePicker 范式）
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Claude Code 可执行文件路径")
            if invalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("该路径不存在或不可执行；留空则自动从系统 PATH 探测")
                    .accessibilityLabel("路径无效：文件不存在或不可执行")
            }
            Button { pickClaudeExecutable() } label: {
                Image(systemName: "folder")
            }
            .help("浏览选择 Claude Code 可执行文件")
            .accessibilityLabel("浏览选择可执行文件")
            Button("使用系统 Claude Code") { draft.agent.claudeExecutablePath = nil }
                .disabled(trimmed.isEmpty)
                .help("清除自定义路径，改为自动从系统 PATH 探测（推荐）")
                .accessibilityHint("清除自定义 Claude Code 路径，回退系统 PATH 探测")
        }
    }

    /// Claude 设置行：显示 ~/.claude/settings.json + split-button「在 X 中打开」（下拉切换编辑器）。
    private var claudeSettingsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("~/.claude/settings.json")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            openInMenu
        }
    }

    /// split-button：主操作用当前所选编辑器打开；下拉切换编辑器（含系统默认 / 其他应用…）。
    private var openInMenu: some View {
        Menu {
            if installedEditors.isEmpty {
                Text("未探测到已安装编辑器")
            }
            ForEach(installedEditors) { ed in
                Button {
                    draft.agent.claudeSettingsEditorBundleId = ed.bundleId
                } label: {
                    Label {
                        Text(ed.name)
                    } icon: {
                        Image(nsImage: ClaudeSettingsLauncher.icon(for: ed))
                    }
                }
            }
            Divider()
            Button("系统默认打开") { draft.agent.claudeSettingsEditorBundleId = nil }
            Button("其他应用…") { pickEditorApp() }
        } label: {
            Label("在 \(currentEditorLabel) 中打开", systemImage: "arrow.up.forward.app")
        } primaryAction: {
            ClaudeSettingsLauncher.openClaudeSettings(editorBundleId: draft.agent.claudeSettingsEditorBundleId)
        }
        .fixedSize()
        .help("在「\(currentEditorLabel)」中打开 ~/.claude/settings.json（点右侧箭头切换编辑器）")
        .accessibilityLabel("打开 Claude 设置，当前编辑器 \(currentEditorLabel)")
    }

    /// 当前选定编辑器的展示名；未选（nil/空）时为「系统默认」。
    private var currentEditorLabel: String {
        if let id = draft.agent.claudeSettingsEditorBundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty {
            return ClaudeSettingsLauncher.displayName(forBundleId: id)
        }
        return "系统默认"
    }

    /// NSOpenPanel 选 Claude Code 可执行文件（默认定位 Homebrew bin 目录，可见隐藏文件）。
    private func pickClaudeExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 Claude Code 可执行文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true                       // 可执行常在 /usr/local/bin、/opt/homebrew/bin
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.agent.claudeExecutablePath = url.path
    }

    /// NSOpenPanel 选任意编辑器 .app，取其 bundle id 持久化（下拉「其他应用…」入口）。
    private func pickEditorApp() {
        let panel = NSOpenPanel()
        panel.title = "选择编辑器应用"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleId = Bundle(url: url)?.bundleIdentifier else { return }
        draft.agent.claudeSettingsEditorBundleId = bundleId
    }

    // MARK: - 底部按钮栏

    private var footerButtons: some View {
        HStack {
            Button("恢复默认") { showingResetConfirm = true }
                .help("将工作时段、节律、休息音效、工作日志、运动记录、电源防护范围与 Agentic AI 恢复为初始值（不影响开机自启与「防止睡眠」总开关）")
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

    /// 运动提示窗「永久等待」开关 ↔ exercisePromptTimeoutSeconds 哨兵 0（对称工作日志）。
    private var exerciseWaitForeverBinding: Binding<Bool> {
        Binding(
            get: { draft.exercisePromptTimeoutSeconds <= 0 },
            set: { draft.exercisePromptTimeoutSeconds = $0 ? 0 : 180 }
        )
    }
}
