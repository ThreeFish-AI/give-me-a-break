import SwiftUI
import GiveMeABreakEngine

/// 手动屏幕遮罩内容：程序化高清背景特效（Metal）+ 趣味文案（可粒子化）。
/// 背景与休息遮罩共用 `MaskEffectBackground`（单一事实源），故两处视觉一致。
/// 系统开启「减弱动态效果」时特效与文案均暂停为静帧（`MaskEffectBackground` /
/// `ParticleTextView` 各自处理）。双击 Esc 直接退出，无中间确认态（故无需 ObservableObject）。
struct ScreenMaskContentView: View {
    /// 遮罩视觉配置（背景特效 / 粒子文案）；由 `ScreenMaskController` 在升起时快照传入。
    let settings: ScreenMaskSettings

    static let caption = "键盘说它有点烫，我去给它买个冰棍，两分钟后见~"

    var body: some View {
        ZStack {
            MaskEffectBackground(effect: settings.effect)
            MaskCaption(text: Self.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
