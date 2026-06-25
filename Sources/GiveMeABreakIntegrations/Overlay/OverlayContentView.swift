import SwiftUI

/// 遮罩共享状态：确认 UI 内嵌于遮罩面板内部，与遮罩同处 CGShieldingWindowLevel，
/// 从根上消除「确认对话框被遮罩遮挡」的层级问题（替代 NSAlert.runModal 默认低层级模态窗，
/// 后者默认 level=NSModalPanelWindowLevel 远低于遮罩，对话框会渲染在遮罩之下不可见）。
final class OverlayViewModel: ObservableObject {
    /// 是否处于「提前结束确认」态（false=倒计时态）。
    @Published var isConfirming = false
    /// 休息截止时刻（常量；倒计时由 TimelineView 每秒自更新）。
    let deadline: Date
    /// 用户点击「直接退出」回调（由控制器桥接到引擎 requestEarlyRestExit）。
    let onConfirmExit: () -> Void

    init(deadline: Date, onConfirmExit: @escaping () -> Void) {
        self.deadline = deadline
        self.onConfirmExit = onConfirmExit
    }
}

/// 休息遮罩内容：舒缓渐变背景 + 大字倒计时 + Esc 确认双态。
/// 倒计时态显示剩余时间与 Esc 提示；确认态显示「继续休息 / 直接退出」按钮。
struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.09),
                         Color(red: 0.09, green: 0.06, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(0.97)

            if viewModel.isConfirming {
                confirmView
            } else {
                countdownView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isConfirming)
    }

    private var countdownView: some View {
        VStack(spacing: 28) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 56))
                .foregroundStyle(.teal)

            Text("Give me a break")
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remain = max(0, viewModel.deadline.timeIntervalSince(context.date))
                Text(format(remain))
                    .font(.system(size: 130, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            Text("双击 Esc 直接结束休息")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var confirmView: some View {
        VStack(spacing: 22) {
            Text("提前结束休息？")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("休息尚未到时，提前结束将重置计时器。")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                // 「继续休息」绑回车默认动作（软强制倾向保留休息）
                Button("继续休息") { viewModel.isConfirming = false }
                    .keyboardShortcut(.defaultAction)
                // 「直接退出」不绑 .cancelAction：Esc 已被遮罩本地事件监听消费，
                // 双语义为「取消确认、返回休息」，若绑 cancelAction 会成为不可达死代码。
                Button("直接退出") { viewModel.onConfirmExit() }
            }
            .font(.system(size: 18, weight: .medium))

            Text("按 Esc 取消，返回休息")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
