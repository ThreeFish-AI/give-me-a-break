import Foundation
import Metal
import GiveMeABreakEngine

/// Metal 设备与着色器库的进程级单例：运行时编译一次，全特效共用。
///
/// 编译失败或设备不可用时全部返回 nil，由 `MaskEffectBackground` 回退到纯 SwiftUI 渐变——
/// **绝不出现黑屏/空遮罩**（遮罩是强制性 UI，渲染失败不能削弱其遮蔽作用）。
final class MaskShaderLibrary {
    static let shared = MaskShaderLibrary()

    /// Metal 设备；nil 表示本机不支持（极旧机型 / 部分虚拟机）。
    let device: MTLDevice?
    /// 编译后的着色器库；nil 表示编译失败。
    private let library: MTLLibrary?
    /// 每特效的渲染管线缓存（首次使用时惰性构建）。
    private var pipelines: [MaskEffect: MTLRenderPipelineState] = [:]
    private let lock = NSLock()

    var isAvailable: Bool { device != nil && library != nil }

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            NSLog("[GiveMeABreak][maskFx] Metal 设备不可用，遮罩特效回退为渐变")
            device = nil
            library = nil
            return
        }
        device = dev

        let started = Date()
        do {
            library = try dev.makeLibrary(source: MaskShaderSources.source, options: nil)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            NSLog("[GiveMeABreak][maskFx] 着色器编译成功（\(ms)ms，设备 \(dev.name)）")
        } catch {
            NSLog("[GiveMeABreak][maskFx] 着色器编译失败，回退为渐变：\(error)")
            library = nil
        }
    }

    /// 取（或惰性构建）指定特效的渲染管线。返回 nil 时调用方须回退。
    func pipeline(for effect: MaskEffect, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = pipelines[effect] { return cached }
        guard let device, let library else { return nil }

        let spec = MaskShaderSources.spec(for: effect)
        guard let vfn = library.makeFunction(name: "fx_vertex"),
              let ffn = library.makeFunction(name: spec.fragment) else {
            NSLog("[GiveMeABreak][maskFx] 缺少入口函数 \(spec.fragment)，回退为渐变")
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat
        do {
            let state = try device.makeRenderPipelineState(descriptor: desc)
            pipelines[effect] = state
            return state
        } catch {
            NSLog("[GiveMeABreak][maskFx] 管线构建失败（\(spec.fragment)）：\(error)")
            return nil
        }
    }
}
