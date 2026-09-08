import AppKit
import SwiftUI

/// 粒子文案层（源自 reactbits ParticleText）：文字经 CoreText 栅格化后按网格采样，
/// 每个不透明像素成为一枚光点，自目标位就近散开后聚拢，聚成后保持低频呼吸漂移。
///
/// **小字号粒子化的三条硬约束**（浏览器原型实测所得，偏离任一条字形即不可辨）：
/// 1. 采样步长须锚定「屏幕像素」而非字号——按字号缩放会使每字只剩十余个点；
/// 2. 光点半径须略小于采样步长——大于则糊成实心字，远小于则笔画断开；
/// 3. 散布与漂移幅度须以「字号」为基准且远小于笔画宽——按 DPR 缩放会把字抖散。
///
/// 透明层，叠加于任一背景特效之上（`MaskEffectBackground` 负责合成）。
struct ParticleTextView: View {
    let text: String
    /// 字号，与静态文案一致（呈现方式不同，字号不变）。
    let fontSize: CGFloat
    /// 系统「减弱动态效果」：true 时直接画出聚合完成的静帧（由调用方传入，单一来源）。
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            // 采样与模拟均在像素坐标系下进行（与浏览器原型一致），故须知设备像素比。
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            ParticleTextCanvas(text: text, fontSize: fontSize, size: geo.size,
                               pixelScale: scale, reduceMotion: reduceMotion)
        }
    }
}

private struct ParticleTextCanvas: View {
    let text: String
    let fontSize: CGFloat
    let size: CGSize
    let pixelScale: CGFloat
    let reduceMotion: Bool

    /// 目标点位（点坐标系，即 SwiftUI 逻辑坐标）。以 text/size 为键缓存，尺寸变化才重算。
    private var targets: [CGPoint] { ParticleTextSampler.shared.targets(text: text, fontSize: fontSize, size: size, pixelScale: pixelScale) }

    var body: some View {
        let pts = targets
        // 光点半径：略小于采样步长（步长见 ParticleTextSampler.stride），保证笔画连续不糊。
        let radius = ParticleTextSampler.stride(pixelScale: pixelScale) / pixelScale * 0.62
        // 动效幅度基准：一律以字号计（而非 DPR），保证小字号文案不被抖散。
        let unit = fontSize / 30

        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            // 减弱动态时取聚合完成时刻的静帧（入场 1.7s + 错峰 0.9s，取 8s 必已聚合）。
            let t = reduceMotion ? 8.0 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                ctx.blendMode = .plusLighter          // 笔画交叠自然提亮（同浏览器版 'lighter'）
                for (i, target) in pts.enumerated() {
                    let p = ParticleTextSampler.position(index: i, target: target, t: t, unit: unit)
                    let alpha = ParticleTextSampler.alpha(index: i, t: t)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(Color(red: 0.784, green: 0.957, blue: 1.0).opacity(alpha))
                    )
                }
            }
        }
    }
}

/// 文案采样与粒子运动（纯函数 + 单条缓存）。
///
/// 运动为「时间的纯函数」——与项目既有 `TimelineView` 动效约定一致：无状态、确定性、
/// 任意时刻可冻结为静帧。故不做逐帧积分（斥力等需要状态的交互留待后续按需引入）。
final class ParticleTextSampler {
    static let shared = ParticleTextSampler()

    private var cacheKey: String = ""
    private var cachePoints: [CGPoint] = []
    private let lock = NSLock()

    /// 采样步长（后备缓冲像素）：锚定屏幕像素而非字号 —— 取 1.5 个逻辑像素对应的物理像素。
    /// 过大则每字点数不足读不出字形，过小则粒子糊成实心字。
    static func stride(pixelScale: CGFloat) -> CGFloat {
        max(2, (pixelScale * 1.5).rounded())
    }

    /// 栅格化文案并采样出目标点位（点坐标系）。以 text+size+fontSize 为键缓存。
    func targets(text: String, fontSize: CGFloat, size: CGSize, pixelScale: CGFloat) -> [CGPoint] {
        let key = "\(text)|\(Int(size.width))x\(Int(size.height))|\(fontSize)|\(pixelScale)"
        lock.lock()
        defer { lock.unlock() }
        if key == cacheKey { return cachePoints }

        let points = Self.rasterize(text: text, fontSize: fontSize, size: size, pixelScale: pixelScale)
        cacheKey = key
        cachePoints = points
        return points
    }

    /// CoreText 栅格化 → 逐网格采样 alpha > 40 的像素为目标点。
    private static func rasterize(text: String, fontSize: CGFloat, size: CGSize, pixelScale: CGFloat) -> [CGPoint] {
        guard size.width > 1, size.height > 1 else { return [] }

        let pw = Int((size.width * pixelScale).rounded())
        let ph = Int((size.height * pixelScale).rounded())
        guard pw > 0, ph > 0 else { return [] }

        let bytesPerRow = pw * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * ph)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = pixels.withUnsafeMutableBytes({ raw -> CGContext? in
                  CGContext(data: raw.baseAddress, width: pw, height: ph,
                            bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
              })
        else { return [] }

        // 字号乘像素比：与浏览器原型的 fontPx = 30 × DPR 对齐。
        let px = fontSize * pixelScale
        let font = NSFont.systemFont(ofSize: px, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        // 坐标系约定（已离线逐行打印位图 alpha 验证）：以 premultipliedLast 建的
        // CGBitmapContext 下，CTLineDraw 的输出在缓冲中**已自上而下正立**——
        // 即行号 0 即画面顶部，与 SwiftUI Canvas 的 Y 向下同向。故既不做 CTM 翻转，
        // 采样时也不翻转行号；任一处多翻一次都会使文案上下镜像。
        ctx.textPosition = CGPoint(x: (CGFloat(pw) - bounds.width) / 2 - bounds.origin.x,
                                   y: (CGFloat(ph) - bounds.height) / 2 - bounds.origin.y)
        CTLineDraw(line, ctx)

        let step = Int(stride(pixelScale: pixelScale))
        var out: [CGPoint] = []
        out.reserveCapacity(16_000)
        for y in Swift.stride(from: 0, to: ph, by: step) {
            for x in Swift.stride(from: 0, to: pw, by: step) {
                if pixels[y * bytesPerRow + x * 4 + 3] > 40 {
                    out.append(CGPoint(x: CGFloat(x) / pixelScale,
                                       y: CGFloat(y) / pixelScale))
                }
            }
        }
        NSLog("[GiveMeABreak][maskFx] 粒子文案采样：\(out.count) 点（画布 \(pw)×\(ph)，字号 \(Int(px))px，步长 \(step)）")
        return out
    }

    // MARK: - 运动（时间的纯函数）

    /// 确定性伪随机（同 index 恒定，等价于浏览器原型的 Fx2D.rand）。
    private static func rand(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + 78.233) * 43758.5453123
        return x - floor(x)
    }

    /// 粒子在时刻 t 的位置：入场自目标位就近辐射（easeOutCubic），聚成后低频呼吸漂移。
    static func position(index: Int, target: CGPoint, t: TimeInterval, unit: CGFloat) -> CGPoint {
        let delay = rand(index + 11) * 0.9
        let k = min(1, max(0, (t - delay) / 1.7))
        let ease = 1 - pow(1 - k, 3)

        // 散布半径须以字号为基准且约等于笔画宽度，否则字形被淹没（浏览器原型实测）。
        let angle = rand(index + 3) * .pi * 2
        let r0 = (0.4 + 0.6 * rand(index + 77)) * Double(unit) * 30 * 0.055
        let from = CGPoint(x: target.x + CGFloat(cos(angle) * r0),
                           y: target.y + CGFloat(sin(angle) * r0))

        // 聚成后的呼吸漂移：幅度远小于笔画宽度。
        let ph = rand(index + 5) * .pi * 2
        let drift = CGPoint(x: CGFloat(sin(t * 0.55 + ph) * 0.22) * unit,
                            y: CGFloat(cos(t * 0.48 + ph) * 0.22) * unit)

        return CGPoint(x: from.x + (target.x + drift.x - from.x) * CGFloat(ease),
                       y: from.y + (target.y + drift.y - from.y) * CGFloat(ease))
    }

    /// 粒子不透明度：入场渐显，聚成后稳定。
    static func alpha(index: Int, t: TimeInterval) -> Double {
        let delay = rand(index + 11) * 0.9
        let k = min(1, max(0, (t - delay) / 1.7))
        let ease = 1 - pow(1 - k, 3)
        return 0.55 + 0.40 * ease
    }
}
