import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import GiveMeABreakEngine

/// 遮罩背景的单一事实源：手动屏幕遮罩（`ScreenMaskContentView`）与休息遮罩
/// （`OverlayContentView`）共用本视图，跟随系统壁纸，保证两处视觉一致。
///
/// 组合三层（自底向上）：
/// 1. 兜底渐变——视频 / 静帧未就绪或不可得时的可见层，保证遮罩绝不透明失效；
/// 2. 壁纸层——航拍视频（共享播放器，失败回退静帧）或本屏桌面静帧；
/// 3. 可读性暗纱——实拍画面明亮，无此层白色文案会在亮区糊掉。
struct MaskBackground: View {
    let source: SystemWallpaperSource
    /// 本屏桌面静帧（`NSWorkspace.desktopImageURL(for:)`）。
    let stillURL: URL?
    /// 静帧解码长边上限（本屏物理像素），免得整张解码 6K 原图。
    let maxPixelSize: Int
    @ObservedObject var backdrop: MaskBackdropPlayer

    var body: some View {
        ZStack {
            // 兜底渐变：与旧版遮罩同款深色。
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.09),
                         Color(red: 0.09, green: 0.06, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )

            Group {
                if case .video = source, !backdrop.failed {
                    AerialLayerView(player: backdrop.player)
                } else if let stillURL {
                    StillWallpaperView(url: stillURL, maxPixelSize: maxPixelSize)
                }
            }
            .ignoresSafeArea()

            // 可读性暗纱：中心略重、四周略轻——文案与倒计时均居中。
            RadialGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.25)],
                center: .center, startRadius: 0, endRadius: 1000
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension MaskBackground {
    /// 按屏构造：静帧取该屏桌面图，解码上限取该屏物理像素长边。
    init(screen: NSScreen, source: SystemWallpaperSource, backdrop: MaskBackdropPlayer) {
        self.init(
            source: source,
            stillURL: NSWorkspace.shared.desktopImageURL(for: screen),
            maxPixelSize: Int(max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor),
            backdrop: backdrop
        )
    }
}

// MARK: - 航拍视频层

/// 挂到共享播放器上的 `AVPlayerLayer`（多屏多层、一路解码）。
struct AerialLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerHostView { PlayerLayerHostView(player: player) }
    func updateNSView(_ view: PlayerLayerHostView, context: Context) {}
    static func dismantleNSView(_ view: PlayerLayerHostView, coordinator: ()) { view.detach() }
}

final class PlayerLayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var readyObservation: NSKeyValueObservation?

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.opacity = 0  // 首帧就绪前透出兜底渐变，避免黑帧闪烁
        playerLayer.player = player
        layer?.addSublayer(playerLayer)
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.fadeIn() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现（本视图仅代码构造）") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    /// 渲染服务端动画淡入，无逐帧主线程开销。
    private func fadeIn() {
        guard playerLayer.opacity == 0 else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.6
        playerLayer.opacity = 1
        playerLayer.add(fade, forKey: "fadeIn")
    }

    func detach() {
        readyObservation?.invalidate()
        readyObservation = nil
        playerLayer.player = nil
    }
}

// MARK: - 桌面静帧层

/// 后台按本屏像素缩略解码，就绪后短淡入；绝不阻塞遮罩升起（保双击 Esc 的主线程响应）。
struct StillWallpaperView: NSViewRepresentable {
    let url: URL
    let maxPixelSize: Int

    func makeNSView(context: Context) -> StillImageHostView {
        let view = StillImageHostView()
        view.load(url: url, maxPixelSize: maxPixelSize)
        return view
    }

    func updateNSView(_ view: StillImageHostView, context: Context) {}
}

final class StillImageHostView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现（本视图仅代码构造）") }

    // contents 由 load 直接写入：声明走 updateLayer 且不实现，防 AppKit 重绘覆盖。
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}

    func load(url: URL, maxPixelSize: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else {
                NSLog("[GiveMeABreak][maskBackdrop] 桌面静帧解码失败，保留兜底渐变：\(url.lastPathComponent)")
                return
            }
            DispatchQueue.main.async { self?.show(image) }
        }
    }

    private func show(_ image: CGImage) {
        guard let layer else { return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.4
        layer.add(fade, forKey: kCATransition)
        layer.contents = image
    }
}

// MARK: - 文案

extension View {
    /// 遮罩文案阴影：明亮实拍画面上托住白字（暗纱之外的第二道可读性保障）。
    func maskTextShadow() -> some View {
        shadow(color: .black.opacity(0.55), radius: 6, y: 1)
    }
}

/// 遮罩文案：简约清晰的普通文本（保持静止以保证可读性）。
/// 曾试过粒子聚字（reactbits ParticleText 移植），但 30pt 小字号下粒子必须细到
/// 亚像素才不糊笔画，可读性与观感均不及普通文本，故移除——遮罩文案的第一要务是「读得清」。
struct MaskCaption: View {
    let text: String
    var fontSize: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .light, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .maskTextShadow()
    }
}
