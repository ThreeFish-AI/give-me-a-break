import AppKit
import Metal
import MetalKit
import SwiftUI
import GiveMeABreakEngine

/// 遮罩背景特效的 Metal 渲染视图（MTKView 包装为 SwiftUI 视图）。
///
/// **为何选 MTKView 而非 SwiftUI `Shader`/`colorEffect`**：
/// - `isPaused` 提供真正的暂停（系统「减弱动态效果」下保留末帧静帧，零 CPU/GPU 开销）；
/// - `preferredFramesPerSecond` 可按特效降帧（护住 Intel 核显与电池）；
/// - drawableSize 可显式钳制（4K/8K 外接屏的填充率护栏）；
/// - 每帧主线程成本仅「写 4 个 uniform + 1 次 draw」，双击 Esc 退出延迟零回归。
struct MaskEffectView: NSViewRepresentable {
    let effect: MaskEffect
    /// 系统「减弱动态效果」：true 时暂停动画并保留静帧。
    let reduceMotion: Bool

    func makeNSView(context: Context) -> MaskMTKView {
        MaskMTKView(effect: effect, reduceMotion: reduceMotion)
    }

    func updateNSView(_ view: MaskMTKView, context: Context) {
        view.apply(effect: effect, reduceMotion: reduceMotion)
    }
}

/// 与着色器 `FxUniforms` 严格对齐的 uniform 结构（float2 需 8 字节对齐，故顺序不可随意调整）。
private struct FxUniforms {
    var res: SIMD2<Float>
    var time: Float
    var mouse: SIMD2<Float>
    var seed: Float
}

final class MaskMTKView: MTKView {
    /// 进程级单一时间纪元：多屏各自持有独立 MTKView，共用同一纪元 → 相位一致，
    /// 且屏幕热插拔重建视图后时间轴连续（不跳变）。
    private static let epoch = CACurrentMediaTime()

    /// 后备缓冲总像素上限：超出则等比降采样。宁降分辨率也不掉帧
    /// （5K 全屏 × SSAA 1.5 ≈ 3300 万像素，远超核显填充率预算）。
    private static let maxPixels: CGFloat = 10_000_000

    private var effect: MaskEffect
    private var pipeline: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    private var mouse = SIMD2<Float>(-1, -1)
    private var trackingArea: NSTrackingArea?
    /// 减弱动态效果下的固定静帧时刻（特效创作约束：任意 t 均为成图）。
    private static let stillTime: Float = 8.0
    private var isStill = false

    init(effect: MaskEffect, reduceMotion: Bool) {
        self.effect = effect
        let device = MaskShaderLibrary.shared.device
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        // 背景特效满覆盖且 alpha 恒为 1 → 不透明图层可省一次合成混合。
        // 遮罩面板整体的淡入淡出由 NSWindow.alphaValue 承担，与此无关。
        layer?.isOpaque = true
        // 连续渲染（非 setNeedsDisplay 驱动）：特效是时间的纯函数，逐帧重绘。
        enableSetNeedsDisplay = false
        autoResizeDrawable = false          // drawableSize 由 resize 显式钳制
        delegate = self

        commandQueue = device?.makeCommandQueue()
        rebuildPipeline()
        apply(effect: effect, reduceMotion: reduceMotion)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) 未实现（本视图仅代码构造）") }

    /// 应用特效与减弱动态设置（SwiftUI 更新时调用；幂等）。
    func apply(effect newEffect: MaskEffect, reduceMotion: Bool) {
        if newEffect != effect {
            effect = newEffect
            rebuildPipeline()
        }
        let spec = MaskShaderSources.spec(for: effect)
        preferredFramesPerSecond = spec.fps > 0 ? spec.fps : 60

        // 减弱动态：画一帧静帧后暂停（MTKView 暂停即保留末帧 drawable，零开销）。
        if reduceMotion {
            isStill = true
            isPaused = false                 // 先放行一帧
            draw()
            isPaused = true
        } else {
            isStill = false
            isPaused = false
        }
        updateDrawableSize()
    }

    private func rebuildPipeline() {
        pipeline = MaskShaderLibrary.shared.pipeline(for: effect, pixelFormat: colorPixelFormat)
    }

    // MARK: - 尺寸（原生 DPR × SSAA，再按总像素上限钳制）

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
        installTrackingArea()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
        installTrackingArea()
    }

    private func updateDrawableSize() {
        let pointSize = bounds.size
        guard pointSize.width > 0, pointSize.height > 0 else { return }

        let native = window?.backingScaleFactor ?? 2.0
        var scale = native * MaskShaderSources.spec(for: effect).ssaa
        // 总像素钳制：超预算时等比降采样。
        let pixels = pointSize.width * pointSize.height * scale * scale
        if pixels > Self.maxPixels { scale *= sqrt(Self.maxPixels / pixels) }

        let target = CGSize(width: max(1, (pointSize.width * scale).rounded()),
                            height: max(1, (pointSize.height * scale).rounded()))
        if drawableSize != target { drawableSize = target }
    }

    // MARK: - 鼠标（喂给着色器的 u_mouse；当前入选特效均未使用，保留以支持交互型特效）

    private func installTrackingArea() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // 转为后备缓冲像素坐标，左上原点（与着色器 [[position]] 同系）。
        let sx = drawableSize.width / max(bounds.width, 1)
        let sy = drawableSize.height / max(bounds.height, 1)
        mouse = SIMD2<Float>(Float(p.x * sx), Float((bounds.height - p.y) * sy))
    }

    override func mouseExited(with event: NSEvent) {
        mouse = SIMD2<Float>(-1, -1)          // 着色器据此回落到「无鼠标」构图
    }
}

// MARK: - 渲染

extension MaskMTKView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline,
              let commandQueue,
              let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        var uniforms = FxUniforms(
            res: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            time: isStill ? Self.stillTime : Float(CACurrentMediaTime() - Self.epoch),
            mouse: mouse,
            seed: 3.7
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FxUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
