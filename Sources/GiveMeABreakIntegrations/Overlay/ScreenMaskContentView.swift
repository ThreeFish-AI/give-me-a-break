import SwiftUI

/// 手动屏幕遮罩内容：与休息遮罩同款深色渐变背景 + 趣味文案与氛围动画
/// （纯 Shape 冰棍轻浮动/摇摆/光晕呼吸/融滴坠落 + 雪花缓升「凉意」）。
/// 所有动效由单一 `TimelineView(.animation)` 以时间 t 的纯函数驱动（确定性、零动画状态管理），
/// 系统开启「减弱动态效果」时整体暂停为静帧；文案保持静止以保证可读性（简约清晰）。
/// 双击 Esc 直接退出，无中间确认态（故无需 ObservableObject）。
struct ScreenMaskContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.09),
                         Color(red: 0.09, green: 0.06, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(0.97)

            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    CoolDrift(t: t)
                    VStack(spacing: 30) {
                        Popsicle(t: t)
                        Text("键盘说它有点烫，我去给它买个冰棍，两分钟后见~")
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 冰棍（SF Symbols 无冰棍图形，纯 Shape 绘制）：随 t 浮动/微摆/光晕呼吸/融滴周期坠落。
private struct Popsicle: View {
    let t: TimeInterval

    var body: some View {
        let bob = sin(t * 1.4) * 9                                    // 上下浮动
        let sway = sin(t * 0.9) * 2.5                                 // 左右微摆（角度）
        let glow = 0.18 + 0.10 * sin(t * 1.1)                         // 光晕呼吸
        let drip = t.truncatingRemainder(dividingBy: 3.2) / 3.2       // 融滴周期 0..1
        VStack(spacing: 5) {
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 14,
                                       bottomTrailingRadius: 14, topTrailingRadius: 40,
                                       style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.90, blue: 0.84),
                                                  Color(red: 0.16, green: 0.62, blue: 0.58)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 86, height: 132)
                Capsule()                                             // 高光
                    .fill(.white.opacity(0.32))
                    .frame(width: 10, height: 78)
                    .offset(x: -22, y: -14)
                Capsule()                                             // 融滴
                    .fill(Color(red: 0.42, green: 0.90, blue: 0.84).opacity(0.85 * (1 - drip)))
                    .frame(width: 6, height: 14)
                    .offset(x: 26, y: 60 + drip * 52)
            }
            .shadow(color: Color(red: 0.20, green: 0.85, blue: 0.78).opacity(glow), radius: 32)
            Capsule()                                                 // 木棍
                .fill(Color(red: 0.80, green: 0.66, blue: 0.47))
                .frame(width: 13, height: 36)
        }
        .offset(y: bob)
        .rotationEffect(.degrees(sway))
    }
}

/// 缓缓上飘的雪花（「买冰棍」的凉意氛围）：位置/大小/透明度均为 t 的纯函数，确定性无跳变；
/// 底部出生、顶部消隐均做边缘淡出，循环重置不可见。
private struct CoolDrift: View {
    let t: TimeInterval

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<Self.flakeCount, id: \.self) { i in
                let f = flake(i, in: geo.size)
                Image(systemName: "snowflake")
                    .font(.system(size: f.size, weight: .light))
                    .foregroundStyle(.white.opacity(f.opacity))
                    .position(x: f.x, y: f.y)
            }
        }
    }

    private static let flakeCount = 8

    private func flake(_ i: Int, in size: CGSize) -> (x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double) {
        let seed = Double(i) + 1
        let speed = 12 + seed.truncatingRemainder(dividingBy: 3) * 7   // 12~26 pt/s
        let xBase = size.width * (0.10 + 0.80 * abs(sin(seed * 12.9898)))
        let sway = sin(t * (0.25 + seed * 0.06)) * 20                  // 水平缓摆
        let span = size.height + 120
        let y = span - 60 - (t * speed + seed * 173).truncatingRemainder(dividingBy: span)
        let fade = min(min(max(y / 60, 0), 1), min(max((size.height - y) / 60, 0), 1))
        return (xBase + sway, y, 9 + seed.truncatingRemainder(dividingBy: 3) * 5, 0.30 * fade)
    }
}
