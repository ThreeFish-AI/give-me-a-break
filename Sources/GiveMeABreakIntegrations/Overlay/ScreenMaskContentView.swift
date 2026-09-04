import SwiftUI

/// 手动屏幕遮罩内容：与休息遮罩同款深色渐变背景，纯静态展示（无中间确认态，
/// 双击 Esc 直接退出，故无需 ObservableObject 驱动响应式切换，比 OverlayContentView 更简单）。
struct ScreenMaskContentView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.09),
                         Color(red: 0.09, green: 0.06, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(0.97)

            VStack(spacing: 28) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.teal)

                Text("屏幕已遮罩")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                Text("双击 Esc 退出")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
