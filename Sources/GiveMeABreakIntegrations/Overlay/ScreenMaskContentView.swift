import SwiftUI
import GiveMeABreakEngine

/// 手动屏幕遮罩内容：系统壁纸背景（航拍视频或桌面静帧）+ 趣味文案。
/// 背景与休息遮罩共用 `MaskBackground`（单一事实源），故两处视觉一致；
/// 系统开启「减弱动态效果」时航拍定格为首帧（`MaskBackdropPlayer` 处理）。
/// 双击 Esc 直接退出，无中间确认态（故无需 ObservableObject）。
struct ScreenMaskContentView: View {
    /// 本屏背景；由 `ScreenMaskController` 按屏构造传入。
    let background: MaskBackground

    static let caption = "键盘说它有点烫，我去给它买个冰棍，两分钟后见~"

    var body: some View {
        ZStack {
            background
            MaskCaption(text: Self.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
