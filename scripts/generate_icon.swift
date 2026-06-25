#!/usr/bin/env swift
// scripts/generate_icon.swift
// 生成 GiveMeABreak.app 图标：leaf.fill 叶子 + 渐变 squircle 背景（统一休息遮罩的「绿叶」视觉）。
// 用法: swift scripts/generate_icon.swift [variant]
//   variant: A（默认，teal 渐变背景 + 白叶，高对比、小尺寸清晰）
//            B（深色背景 + teal 叶，忠于遮罩原貌）
// 产出: Resources/AppIcon.iconset/icon_*.png（10 个标准尺寸），随后由 Makefile 调 iconutil 打包。
// 环境要求: 需在有图形会话的 Mac 上运行（NSImage(systemSymbolName:) 依赖系统符号字体）。
import AppKit
import Foundation

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "A"
let ICONSET_DIR = "Resources/AppIcon.iconset"

// MARK: - 配色方案

struct Palette { let top: NSColor; let bottom: NSColor; let leaf: NSColor }
let palette: Palette
switch variant {
case "B":  // 忠于遮罩：深色背景 + teal 叶
    palette = Palette(
        top:    NSColor(srgbRed: 0.04, green: 0.05, blue: 0.09, alpha: 1),
        bottom: NSColor(srgbRed: 0.09, green: 0.06, blue: 0.14, alpha: 1),
        leaf:   NSColor(srgbRed: 0.16, green: 0.80, blue: 0.74, alpha: 1))
default:   // 方案 A：teal 渐变背景 + 白叶（推荐）
    palette = Palette(
        top:    NSColor(srgbRed: 0.11, green: 0.62, blue: 0.60, alpha: 1),
        bottom: NSColor(srgbRed: 0.05, green: 0.45, blue: 0.52, alpha: 1),
        leaf:   .white)
}

// MARK: - squircle 超椭圆路径（n≈5 近似 Apple squircle 圆角超椭圆）

func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let a = rect.width / 2, b = rect.height / 2
    let n = 5.0
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        // 超椭圆参数方程：x = a·sgn(cos)·|cos|^(2/n)，y 同理
        let xs = ct >= 0 ? CGFloat(1) : CGFloat(-1)
        let ys = st >= 0 ? CGFloat(1) : CGFloat(-1)
        let x = cx + a * CGFloat(pow(abs(Double(ct)), 2.0 / n)) * xs
        let y = cy + b * CGFloat(pow(abs(Double(st)), 2.0 / n)) * ys
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

// MARK: - 渲染单张图标 PNG

func renderPNG(_ pt: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pt), pixelsHigh: Int(pt),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,   // squircle 外四角透明
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: pt, height: pt)

    // 1) squircle 裁剪
    ctx.addPath(squirclePath(in: rect))
    ctx.clip()

    // 2) 渐变背景（顶→底）
    let colors = [palette.top.cgColor, palette.bottom.cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])

    // 3) 居中叶子（染色：复制 alpha 形状后用目标色 sourceAtop 填充）
    guard let base = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Give me a break") else {
        fputs("错误：leaf.fill 不可用（需在有图形会话的 Mac 上运行）\n", stderr)
        exit(1)
    }
    let cfg = NSImage.SymbolConfiguration(pointSize: pt * 0.62, weight: .regular)
    let leaf = base.withSymbolConfiguration(cfg) ?? base
    let tinted = NSImage(size: leaf.size)
    tinted.lockFocus()
    leaf.draw(in: NSRect(origin: .zero, size: leaf.size))
    palette.leaf.setFill()
    NSRect(origin: .zero, size: leaf.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let ls = leaf.size.width
    let origin = NSPoint(x: rect.midX - ls / 2, y: rect.midY - ls / 2)
    tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - 导出 iconset 10 个标准尺寸

try? FileManager.default.removeItem(atPath: ICONSET_DIR)
try? FileManager.default.createDirectory(atPath: ICONSET_DIR, withIntermediateDirectories: true)

let sizes: [(name: String, pt: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for s in sizes {
    let data = renderPNG(s.pt)
    try! data.write(to: URL(fileURLWithPath: "\(ICONSET_DIR)/\(s.name).png"))
}
print("✓ iconset 生成完成（方案 \(variant)）：\(ICONSET_DIR)（10 张 PNG）")
print("  下一步：iconutil -c icns \(ICONSET_DIR) -o Resources/AppIcon.icns")
