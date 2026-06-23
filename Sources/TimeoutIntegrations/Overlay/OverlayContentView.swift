import SwiftUI

/// 休息遮罩内容：舒缓渐变背景 + 大字倒计时（TimelineView 每秒自更新）+ Esc 提示。
struct OverlayContentView: View {
    let deadline: Date

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.09),
                         Color(red: 0.09, green: 0.06, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(0.97)

            VStack(spacing: 28) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.teal)

                Text("休息一下")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remain = max(0, deadline.timeIntervalSince(context.date))
                    Text(format(remain))
                        .font(.system(size: 130, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }

                Text("按 Esc 可提前结束")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
