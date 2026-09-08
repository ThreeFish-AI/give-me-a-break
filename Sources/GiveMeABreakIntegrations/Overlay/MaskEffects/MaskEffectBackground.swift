import SwiftUI
import GiveMeABreakEngine

/// 遮罩背景的单一事实源：手动屏幕遮罩（`ScreenMaskContentView`）与休息遮罩
/// （`OverlayContentView`）共用本视图，保证两处视觉一致。
///
/// 组合三层（自底向上）：
/// 1. 兜底渐变——Metal 不可用时的唯一可见层，保证遮罩绝不透明失效；
/// 2. Metal 背景特效——`MaskEffectView`，仅在着色器可用时插入；
/// 3. 可读性暗纱——压住特效高光，保证叠加于其上的文案/倒计时始终清晰。
struct MaskEffectBackground: View {
    let effect: MaskEffect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // 兜底渐变：与旧版遮罩同款深色，Metal 失效时即为最终画面。
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.09),
                         Color(red: 0.09, green: 0.06, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )

            if MaskShaderLibrary.shared.isAvailable {
                MaskEffectView(effect: effect, reduceMotion: reduceMotion)
                    .ignoresSafeArea()
            }

            // 可读性暗纱：特效高光可达近白，无此层白色文案会在亮区糊掉。
            // 中心略重、四周略轻——文案与倒计时均居中。
            RadialGradient(
                colors: [Color.black.opacity(0.42), Color.black.opacity(0.16)],
                center: .center, startRadius: 0, endRadius: 900
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 遮罩文案：按配置以粒子聚成或普通文本呈现。字号一致，仅呈现方式不同。
struct MaskCaption: View {
    let text: String
    let particle: Bool
    var fontSize: CGFloat = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if particle {
            ParticleTextView(text: text, fontSize: fontSize, reduceMotion: reduceMotion)
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: .light, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// 特效的中文显示名与副标题（设置页选择器的单一事实源）。
enum MaskEffectCatalog {
    static func displayName(_ effect: MaskEffect) -> String {
        switch effect {
        case .orb:        return "涟漪光球"
        case .fibers:     return "冷雾纤丝"
        case .letterRain: return "字雨微光"
        case .caustics:   return "水波光斑"
        case .silk:       return "丝绸流光"
        }
    }

    static func summary(_ effect: MaskEffect) -> String {
        switch effect {
        case .orb:        return "半透明光球缓缓呼吸，球面流纹如水面波光徐徐流转"
        case .fibers:     return "雾蓝纤丝在低频呼吸中缓缓摆动，层层脊线漂出银白微光"
        case .letterRain: return "全屏字符点阵极淡闪烁，亮带自上而下巡回"
        case .caustics:   return "阳光穿过水面在池底投下的焦散网纹，光斑明暗流转"
        case .silk:       return "缎面在无风中缓缓起伏，高光带沿褶皱流淌，泛薄荷与冰紫"
        }
    }
}
