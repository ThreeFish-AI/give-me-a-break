import SwiftUI
import GiveMeABreakEngine

/// 休息前工作日志提示视图（认知闭合仪式：< 60s 写下「完成了什么 + 可选下一步」）。
///
/// 设计循证（Leroy 注意力残留 / Stubblebine 插值日记 / Fogg Facilitator 提示）：
/// - 持久标签（非 placeholder-as-label）+ 轮换占位示例抗疲劳；
/// - 软字符计数（不硬截断、不设最小长度——最小长度是已证实的完成杀手）；
/// - 永不阻塞：回车提交 / Esc 跳过 / 60s 自动放行；空内容提交 ≡ 跳过；
/// - 可选「下一步」次级字段（ready-to-resume plan），显式标注 optional。
struct WorkLogPromptView: View {
    /// 本周期累计专注时长（用于上下文行「工作 N 分钟」）。
    private let workDurationSeconds: TimeInterval
    /// 占位示例轮换池索引（由控制器跨会话轮换传入）。
    private let seedIndex: Int
    private let onSubmit: (String, String?) -> Void
    private let onSkip: () -> Void

    @State private var summary: String = ""
    @State private var nextAction: String = ""
    @State private var nextExpanded: Bool = false

    private let softLimit = 120

    /// 轮换占位示例池（对抗 JITAI 提示疲劳：跨会话轮换，不重复）。
    private static let placeholders = [
        "例：回了设计评审那封邮件",
        "例：调试登录 bug，定位到 token 过期",
        "例：写完周报第一稿",
        "例：和 PM 对齐了下周排期",
        "例：重构了缓存层，移除一处死锁",
        "例：读完那篇 FSM 论文并记了笔记",
    ]

    init(workDurationSeconds: TimeInterval,
         seedIndex: Int,
         onSubmit: @escaping (String, String?) -> Void,
         onSkip: @escaping () -> Void) {
        self.workDurationSeconds = workDurationSeconds
        self.seedIndex = seedIndex
        self.onSubmit = onSubmit
        self.onSkip = onSkip
    }

    private var placeholder: String {
        guard !Self.placeholders.isEmpty else { return "" }
        let idx = ((seedIndex % Self.placeholders.count) + Self.placeholders.count) % Self.placeholders.count
        return Self.placeholders[idx]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").foregroundStyle(.teal).font(.system(size: 20))
                Text("给这段时间留个注脚")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }

            Text("刚刚完成了什么？花 30 秒写下，让大脑真正放下、休息时不再惦记。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $summary)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(minHeight: 64, idealHeight: 72)
                    .overlay(alignment: .topLeading) {
                        if summary.isEmpty {
                            Text(placeholder)
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

            // 可选「下一步」（ready-to-resume plan），默认折叠
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
                Text("工作 \(humanizedDuration(workDurationSeconds))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("跳过") { submitOrSkip() }
                    .keyboardShortcut(.cancelAction)
                Button("记录并休息") { submitOrSkip() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 300)
    }

    /// 提交：空内容 ≡ 跳过（不写入日志）；非空则带上可选 nextAction。
    private func submitOrSkip() {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let na = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onSkip()
        } else {
            onSubmit(trimmed, na.isEmpty ? nil : na)
        }
    }
}
