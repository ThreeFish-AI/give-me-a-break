import Foundation
import GiveMeABreakEngine

/// 遮罩背景特效的 Metal 着色器源码（运行时经 `device.makeLibrary(source:)` 编译）。
///
/// **为何是源码字符串而非 .metal 文件**：Command Line Tools 不含 `xcrun metal` 编译器
/// （需完整 Xcode），且 `swift build` 不编译 .metal、Makefile 装配的 .app 不含 SPM 资源
/// bundle（`Bundle.module` 会断）。运行时编译一次约 50–150ms，被遮罩 0.4s 淡入完全掩盖，
/// 且与项目「零打包资产」哲学一致（同 `AmbientSoundPlayer` 合成粉噪音、不打包音频文件）。
///
/// **GLSL → MSL 移植检查单**（浏览器原型见 `.temp/mask-fx-preview/effects.js`）：
/// - `mod(x, y)`：GLSL 对负数返回非负，MSL `fmod` 保留符号 → 统一用 `pmod()` 自实现；
/// - `atan(y, x)` → `atan2(y, x)`（本组特效已全部规避角向采样，无奇点，故实际未用到）；
/// - `gl_FragCoord` → `[[position]]`，两者原点均在左上，Y 向下，无需翻转；
/// - `fract/mix/smoothstep/clamp` 语义一致；float 字面量统一带小数点（MSL 类型推断更严）；
/// - `texture2D` 一律不用：噪声全部程序生成（零纹理资产）。
///
/// **清晰度三要素**（与浏览器版一致）：① 取满原生 backingScaleFactor；② SSAA 超采样后
/// 由合成器下采样（见 `MaskEffectSpec.ssaa`）；③ `detail()` 高频细节层补颗粒级纹理。
enum MaskShaderSources {

    /// 每个特效的渲染规格：入口函数名、超采样倍率、帧率上限。
    struct Spec {
        let fragment: String
        /// 超采样倍率：>1 时后备缓冲放大渲染再由合成器下采样，消除细线/球缘锯齿。
        /// 字形类特效（字雨微光）刻意取 1——直绘更锐，下采样反而使字形变软。
        let ssaa: CGFloat
        /// 帧率上限（0 = 跟随刷新率）。重特效降至 30 以护住 Intel 核显与电池。
        let fps: Int
    }

    static func spec(for effect: MaskEffect) -> Spec {
        switch effect {
        case .orb:        return Spec(fragment: "fx_orb",       ssaa: 1.5, fps: 0)
        case .fibers:     return Spec(fragment: "fx_fibers",    ssaa: 1.5, fps: 0)
        case .letterRain: return Spec(fragment: "fx_letterRain", ssaa: 1.0, fps: 30)
        case .caustics:   return Spec(fragment: "fx_caustics",  ssaa: 1.5, fps: 0)
        case .silk:       return Spec(fragment: "fx_silk",      ssaa: 1.4, fps: 0)
        }
    }

    /// 完整着色器源：公共前奏 + 全部特效片元函数。
    /// 一次编译得到含全部入口的 library，切换特效无需重编译（缓存于 `MaskShaderLibrary`）。
    static let source = common + orb + fibers + letterRain + caustics + silk

    // MARK: - 公共前奏（顶点着色器 + 噪声工具 + 色调映射）

    private static let common = """
    #include <metal_stdlib>
    using namespace metal;

    constant float PI  = 3.14159265359;
    constant float TAU = 6.28318530718;

    /// 逐帧 uniform。与浏览器原型的 u_resolution / u_time / u_mouse / u_seed 一一对应。
    struct FxUniforms {
        float2 res;      // 后备缓冲像素尺寸（含 SSAA）
        float  time;     // 秒；进程级单一纪元 → 多屏同相位
        float2 mouse;    // 像素坐标，左上原点；无鼠标时为 (-1, -1)
        float  seed;
    };

    struct FxVertex {
        float4 position [[position]];
    };

    /// 全屏三角形：覆盖 NDC 全域，省去两三角形的对角线插值。
    vertex FxVertex fx_vertex(uint vid [[vertex_id]]) {
        const float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        FxVertex out;
        out.position = float4(pos[vid], 0.0, 1.0);
        return out;
    }

    /// 负数安全取模（GLSL mod 对负数返回非负，MSL fmod 保留符号）。
    static inline float pmod(float x, float y) { return x - y * floor(x / y); }

    static inline float hash11(float p) { return fract(sin(p * 127.1) * 43758.5453123); }
    static inline float hash12(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
    }

    /// 二维值噪声（quintic 缓动，避免格点方向性伪影）。
    static inline float vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        float a = hash12(i), b = hash12(i + float2(1.0, 0.0));
        float c = hash12(i + float2(0.0, 1.0)), d = hash12(i + float2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    /// 三维值噪声（时间作为第三维 → 无缝流动，而非平移贴图）。
    static inline float vnoise3(float3 p) {
        float3 i = floor(p), f = fract(p);
        float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        float n = i.x + i.y * 57.0 + i.z * 113.0;
        float a = hash11(n),          b = hash11(n + 1.0);
        float c = hash11(n + 57.0),   d = hash11(n + 58.0);
        float e = hash11(n + 113.0),  g = hash11(n + 114.0);
        float h = hash11(n + 170.0),  k = hash11(n + 171.0);
        return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
                   mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
    }

    /// 高频细节项（2 阶）：以极低成本为高光/脊线补上「颗粒级」清晰度。
    /// 比给所有 fbm 加阶数便宜得多——后者会让每片元的哈希调用数翻倍。
    static inline float detail(float2 p) {
        return vnoise(p * 7.0) * 0.65 + vnoise(p * 15.0) * 0.35;
    }

    static inline float fbm2(float2 p) {
        float v = 0.0, a = 0.5;
        for (int i = 0; i < 5; i++) { v += a * vnoise(p); p *= 2.02; a *= 0.5; }
        return v;
    }

    static inline float fbm3(float3 p) {
        float v = 0.0, a = 0.5;
        for (int i = 0; i < 5; i++) { v += a * vnoise3(p); p *= 2.03; a *= 0.5; }
        return v;
    }

    /// 屏幕比例归一化坐标：短边为 1，居中原点（分辨率无关 → 4K/8K 构图一致）。
    static inline float2 aspectUV(float2 fragCoord, float2 res) {
        return (fragCoord - 0.5 * res) / min(res.x, res.y);
    }

    /// 屏幕暗角（清爽感的收边，避免四角发灰）。
    static inline float vignetteAt(float2 fragCoord, float2 res, float strength) {
        float2 q = fragCoord / res;
        float v = 16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y);
        return mix(1.0, pow(clamp(v, 0.0, 1.0), 0.22), strength);
    }

    /// filmic 色调映射 + 轻微抖动（消除大面积柔光渐变的 8bit 色带）。
    static inline float3 tonemap(float3 c, float2 fragCoord, float time) {
        c = 1.0 - exp(-c);
        c += (hash12(fragCoord + fract(time)) - 0.5) / 255.0;
        return clamp(c, 0.0, 1.0);
    }

    """

    // MARK: - 03 涟漪光球（reactbits Orb · 球面流纹重构）

    private static let orb = """
    fragment float4 fx_orb(FxVertex in [[stage_in]],
                           constant FxUniforms &u [[buffer(0)]]) {
        float2 fc = in.position.xy;
        float2 uv = aspectUV(fc, u.res);
        float t = u.time * 0.5;

        float r = length(uv);

        // 球廓扰动：笛卡尔域采样（无 uv/r 归一化 → 中心无奇点），幅度随 r 收缩，
        // 仅作用于球缘；球缘处 uv 已远离原点，噪声在角向自然连续。
        float edge = (fbm3(float3(uv * 4.2, t * 0.30)) - 0.5) * smoothstep(0.06, 0.28, r);
        float R = 0.42 + edge * 0.034 + 0.013 * sin(t * 1.1);      // 呼吸（全屏下 0.42 短边半径观感最匀）

        // 球缘过渡带按像素尺度自适应：SSAA 下自动收窄 → 边缘更锐但仍无锯齿。
        float aa = 1.6 / min(u.res.x, u.res.y);
        float body = smoothstep(R + aa, R - aa, r);
        float z = sqrt(max(0.0, 1.0 - pow(min(r / R, 1.0), 2.0)));  // 半球高度

        // 球面流纹：以「球面坐标（含 z 分量）」做三维 fbm —— 无同心环、无辐条，
        // 读作水面波光在球体表面缓缓流转（波光流转的核心表达）。
        float f1 = fbm3(float3(uv * 5.2, z * 2.2 - t * 0.95));
        float f2 = fbm3(float3(uv * 2.1 + 7.7, z * 1.1 - t * 0.55));
        // 高频细节：为流纹补上颗粒级纹理（清晰度的主要来源，成本仅 2 次噪声）。
        float fd = detail(uv * 2.2 + float2(t * 0.10, -t * 0.07)) - 0.5;
        float flow = pow(clamp(f1 * 1.35 + fd * 0.20, 0.0, 1.0), 1.6) * (0.45 + 0.55 * f2 * 1.6);
        // 亮纹尖峰：流纹的窄带 → 水面波光的高光丝（波光流转的点睛）。
        float crest = pow(clamp(1.0 - abs(f1 + fd * 0.14 - 0.52) * 8.5, 0.0, 1.0), 2.2);

        float fres = pow(1.0 - z, 2.4);                            // 菲涅尔边缘增亮

        float3 inner = float3(0.560, 0.968, 0.890);                // 冰青
        float3 outer = float3(0.878, 0.984, 0.988);                // 白青
        float3 deep  = float3(0.014, 0.036, 0.052);                // 墨青底

        float3 col = deep;
        col += inner * body * (0.05 + 0.95 * flow * (0.35 + 0.65 * z));
        col += outer * body * crest * (0.30 + 0.35 * z) * 0.85;    // 波光高光丝
        col += outer * body * fres * 0.26;                         // 球缘亮唇
        col += mix(inner, outer, 0.4) * exp(-max(r - R, 0.0) * 13.0) * 0.15;   // 外晕

        // 环绕热点：沿球缘公转的高光，赋予方向感。
        float2 hot = float2(cos(-t * 0.7), sin(-t * 0.7)) * (R * 0.90);
        col += outer * 0.008 / (0.010 + dot(uv - hot, uv - hot) * 44.0);

        // 球体左上的镜面反光（赋予「光泽」，脱离灰扑扑的塑料感）。
        float2 spec = uv - float2(-0.14, 0.15);                    // 随半径等比外移，保持相对构图
        col += outer * body * exp(-dot(spec, spec) * 24.0) * 0.34;

        col *= vignetteAt(fc, u.res, 0.58);
        return float4(tonemap(col, fc, u.time), 1.0);
    }

    """

    // MARK: - 05 冷雾纤丝（reactbits GhostFibers）

    private static let fibers = """
    fragment float4 fx_fibers(FxVertex in [[stage_in]],
                              constant FxUniforms &u [[buffer(0)]]) {
        float2 fc = in.position.xy;
        float2 uv0 = aspectUV(fc, u.res) * 1.25;
        float t = u.time * 0.20;

        // 整体极缓自转：让纤丝方向持续变化，避免长时间静态构图。
        float ca = cos(t * 0.25), sa = sin(t * 0.25);
        uv0 = float2x2(float2(ca, sa), float2(-sa, ca)) * uv0;

        float3 line  = float3(0.130, 0.180, 0.245);                // 雾蓝暗线
        float3 glowC = float3(0.300, 0.420, 0.560);                // 银蓝辉
        float3 col = float3(0.0);

        for (int i = 0; i < 4; i++) {
            float fi = float(i) + 1.0;
            float2 p = uv0;
            // 域扭曲：以自身 yx 分量驱动位移 → 纤丝的柔性弯折。
            p += 0.06 * sin(p.yx * fi * 2.4 + t * 1.3 + fi);
            // 极坐标扭转：赋予绕心的螺旋倾向。
            float rr = length(p), aa2 = atan2(p.y, p.x);
            aa2 += sin(rr * 2.6 - t * 1.1 + fi) * 0.16;
            p = float2(cos(aa2), sin(aa2)) * rr;

            // 高频细节仅轻微扰动相位：目标是「丝缕质感」而非硬边——
            // 过强的扰动 + 过高的次幂会把柔雾纤丝变成硬朗闪电，反丢清爽舒雅。
            float fd = detail(p * 0.9 + float2(t * 0.05, fi)) - 0.5;
            float ridge = abs(sin(p.x * (2.2 + fi * 0.9) + sin(p.y * 2.0 + t) + fd * 0.30));
            ridge = pow(max(0.0, 1.0 - ridge), 8.0);               // 柔脊（清晰度交由 SSAA 与细节层承担）
            // 宽幅辉光带：与脊线同相位但衰减慢，撑起体积雾感。
            float glow = exp(-8.0 * abs(sin(p.x * 2.4 + t * 0.8 + fi)));

            col += (line * ridge * 2.2 + glowC * glow * 0.34) / fi;
        }

        col = 1.0 - exp(-col * 1.75);                              // filmic（收敛以免脊线过曝成白）
        col *= float3(0.90, 0.99, 1.10);                           // 冷调偏移（蓝提亮）
        col += float3(0.014, 0.024, 0.036);                        // 抬黑，避免死黑
        col += (hash12(fc + fract(u.time) * 91.7) - 0.5) * 0.020;  // 胶片颗粒（减淡以不糊细节）
        col *= vignetteAt(fc, u.res, 0.50);
        return float4(clamp(col, 0.0, 1.0), 1.0);
    }

    """

    // MARK: - 06 字雨微光（reactbits LetterGlitch · 着色器化）

    /// 浏览器版为 Canvas 2D 字形网格；此处以「程序化字形」在着色器内合成——
    /// 每个网格单元用 hash 选一个 5×7 点阵位图（内置字模），随时间换字换亮度。
    /// 如此免去 CoreText 图集与 CPU 逐帧绘制，且天然分辨率无关。
    private static let letterRain = """
    /// 5×7 点阵字模：以 35bit 掩码存于 uint（低位为左上）。取 24 个「技术感」字符。
    constant uint GLYPHS[24] = {
        0x1F8C63EU, 0x0E8C610U, 0x1F0F87FU, 0x1F0F86FU, 0x118FC21U, 0x1F87C3FU,
        0x0E87C3EU, 0x1F11084U, 0x0E8BA2EU, 0x0E8FA1CU, 0x0421080U, 0x1084210U,
        0x0044400U, 0x0E8C62EU, 0x04213E0U, 0x1F0842FU, 0x11151151U, 0x0A8A28AU,
        0x1151151U, 0x08A2A88U, 0x0004000U, 0x1084218U, 0x0421084U, 0x1F0000FU
    };

    /// 采样字模第 (gx, gy) 个像素（gx∈[0,5), gy∈[0,7)）。
    static inline float glyphBit(uint code, int gx, int gy) {
        if (gx < 0 || gx >= 5 || gy < 0 || gy >= 7) { return 0.0; }
        uint bit = uint(gy * 5 + gx);
        return float((code >> bit) & 1u);
    }

    fragment float4 fx_letterRain(FxVertex in [[stage_in]],
                                  constant FxUniforms &u [[buffer(0)]]) {
        float2 fc = in.position.xy;

        // 网格随分辨率缩放：4K 下字号与密度等比放大，观感与 1080p 一致。
        float scale = max(1.0, min(u.res.x, u.res.y) / 900.0);
        float2 cell = float2(17.0, 27.0) * scale;
        float2 gid = floor(fc / cell);                             // 网格索引
        float2 gf = (fc - gid * cell) / cell;                      // 单元内归一化坐标

        // 每 55ms 换一批字（同浏览器版的 glitch 节拍）；每格的换字时刻由 hash 错开。
        float tick = floor(u.time / 0.055);
        float cellSeed = hash12(gid + u.seed);
        float phase = floor(tick * 0.04 + cellSeed * 97.0);        // 约 4% 的格子每拍换字
        uint code = GLYPHS[uint(hash12(gid + phase * 3.71) * 24.0) % 24u];

        // 字形：5×7 点阵，单元内留边（0.62 宽 / 0.74 高）以形成字间距。
        float2 inner = (gf - float2(0.19, 0.13)) / float2(0.62, 0.74);
        float lit = 0.0;
        if (inner.x >= 0.0 && inner.x < 1.0 && inner.y >= 0.0 && inner.y < 1.0) {
            int gx = int(inner.x * 5.0);
            int gy = int(inner.y * 7.0);
            lit = glyphBit(code, gx, gy);
        }

        // 亮带自上而下巡回：范围 [-0.35, 1.35] 覆盖全屏并含进出淡入淡出余量。
        float waveY = pmod(u.time * 0.075, 1.7) - 0.35;
        float yn = fc.y / u.res.y;
        float wave = exp(-pow((yn - waveY) / 0.30, 2.0));
        // 亮带内更亮、带外更暗 → 对比度提升，字形边缘更锐利可辨。
        float base = 0.040 + 0.42 * wave;

        // 三色随机换色（青白 / 冷灰 / 青碧），与浏览器版调色一致。
        float ci = hash12(gid + phase * 7.13);
        float3 tint = ci < 0.34 ? float3(0.38, 0.83, 0.78)
                    : ci < 0.67 ? float3(0.55, 0.72, 0.75)
                                : float3(0.82, 0.94, 0.92);

        float3 col = float3(0.031, 0.051, 0.063);                   // 墨黑底
        col += tint * lit * base;

        // 暗角：四周压暗，视线收拢至画面中部。
        float2 q = fc / u.res - 0.5;
        col *= 1.0 - clamp(pow(length(q) * 1.45, 2.2), 0.0, 0.88);
        return float4(clamp(col, 0.0, 1.0), 1.0);
    }

    """

    // MARK: - 08 水波光斑（原创 · 迭代折叠焦散）

    private static let caustics = """
    /// 经典 "seascape caustics"：反复以正弦扭曲坐标，取尖峰倒数累加成网纹。
    static inline float causticAt(float2 uv, float t) {
        float2 p = uv * TAU - 250.0;                               // 抬到远离原点的相位区，避免中心奇点
        float2 i = p;
        float c = 1.0, inten = 0.0055;
        for (int n = 0; n < 5; n++) {
            float ti = t * (1.0 - (3.5 / float(n + 1)));
            i = p + float2(cos(ti - i.x) + sin(ti + i.y),
                           sin(ti - i.y) + cos(ti + i.x));
            c += 1.0 / length(float2(p.x / (sin(i.x + ti) / inten),
                                     p.y / (cos(i.y + ti) / inten)));
        }
        c /= 5.0;
        c = 1.17 - pow(c, 1.4);
        return clamp(pow(abs(c), 8.0), 0.0, 1.4);
    }

    fragment float4 fx_caustics(FxVertex in [[stage_in]],
                                constant FxUniforms &u [[buffer(0)]]) {
        float2 fc = in.position.xy;
        float2 uv = aspectUV(fc, u.res) * 1.15 + 0.5;
        float t = u.time * 0.34 + 22.0;                            // 起始偏移：t=0 即成图

        float c1 = causticAt(uv, t);
        float c2 = causticAt(uv * 0.62 + 3.1, t * 0.71);           // 二层错频，破解规律感
        // 高频细节：为焦散亮纹补上水面细波的颗粒感（清晰度的主要来源）。
        float fd = detail(uv * 1.8 + float2(t * 0.09, -t * 0.06)) - 0.5;
        c1 *= 1.0 + fd * 0.45;
        c2 *= 1.0 + fd * 0.30;

        // 水体渐变底：上浅下深，模拟自上而下的入射光衰减。
        float2 q = fc / u.res;
        float3 shallow = float3(0.055, 0.180, 0.190);
        float3 deep    = float3(0.012, 0.062, 0.078);
        float3 col = mix(shallow, deep, clamp(q.y * 1.15 - 0.1, 0.0, 1.0));

        float3 lightA = float3(0.686, 0.953, 0.882);               // 青绿亮纹
        float3 lightB = float3(0.388, 0.780, 0.698);               // 水青次纹
        col += lightA * c1 * 0.66;
        col += lightB * c2 * 0.42;
        // 亮纹尖顶提白：网纹交汇处的高光结节，读作阳光聚焦点。
        col += float3(0.92, 1.00, 0.98) * pow(clamp(c1, 0.0, 1.0), 3.0) * 0.22;

        // 缓慢横移的体积光柱（水面波峰的聚光），强化「流转」。
        float shaft = exp(-pow((q.x - (0.5 + 0.34 * sin(u.time * 0.11))) / 0.30, 2.0));
        col += lightA * shaft * 0.055;

        col *= vignetteAt(fc, u.res, 0.52);
        return float4(tonemap(col, fc, u.time), 1.0);
    }

    """

    // MARK: - 09 丝绸流光（原创 · fbm 域扭曲缎光）

    private static let silk = """
    fragment float4 fx_silk(FxVertex in [[stage_in]],
                            constant FxUniforms &u [[buffer(0)]]) {
        float2 fc = in.position.xy;
        float2 uv = aspectUV(fc, u.res) * 0.80;
        float t = u.time * 0.16;

        // 二次域扭曲（Inigo Quilez warp）：先用 fbm 位移坐标，再对位移后的场再取 fbm。
        float2 q = float2(fbm3(float3(uv * 0.9, t * 0.5)),
                          fbm3(float3(uv * 0.9 + 5.2, t * 0.5)));
        float2 rr = float2(fbm3(float3(uv * 1.1 + 2.2 * q + float2(1.7, 9.2), t * 0.35)),
                           fbm3(float3(uv * 1.1 + 2.2 * q + float2(8.3, 2.8), t * 0.35)));
        float f = fbm3(float3(uv + 1.8 * rr, t * 0.25));

        // 高频细节：缎面的织纹（丝绸清晰度的本体特征，无此则只是一团雾）。
        float fd = detail(uv * 3.0 + rr * 0.8 + float2(t * 0.06, 0.0)) - 0.5;
        // 褶皱高光：沿扭曲后的等值线取窄带（|sin| 高次幂），得到各向异性丝光。
        float fold = abs(sin((f * 2.4 + rr.x * 1.0 - t * 1.0) * PI + fd * 0.55));
        float sheen = pow(1.0 - fold, 3.0);                        // 高次幂 → 高光带更窄更亮
        float wide  = pow(1.0 - fold, 0.9) * 0.50;                 // 宽幅底光，垫出缎面体感

        float3 deep  = float3(0.014, 0.044, 0.058);
        float3 mint  = float3(0.400, 1.000, 0.880);                // 薄荷（强饱和）
        float3 lilac = float3(0.620, 0.560, 1.000);                // 冰紫（强饱和）

        // 色相须与亮度场解耦：若沿用 f 驱动色相，则「亮处」与「某一色」恒定绑定，
        // 画面只剩单一色调。改用独立的低频噪声决定色相分区，
        // 使薄荷区与冰紫区各自跨越明暗，两色都能出现在高光上。
        float hueField = fbm3(float3(uv * 0.55 + 21.7, t * 0.16));
        float hue = smoothstep(0.44, 0.56, hueField + 0.05 * sin(t * 0.5));
        float3 tint = mix(mint, lilac, hue);

        // 强度须留在 tonemap 的线性区（≲0.6），否则 1-exp(-c) 把三通道压向 1 而褪成灰白。
        float3 col = deep + tint * (sheen * 0.46 + wide * 0.30);
        col += mix(mint, float3(1.0), 0.3) * pow(sheen, 3.0) * 0.10; // 高光尖顶提白（收敛）
        // 中央柔光：缎面受光最盛处，兼填补构图中心的空洞。
        col += tint * exp(-dot(uv, uv) * 1.6) * 0.07;

        col *= vignetteAt(fc, u.res, 0.46);
        return float4(tonemap(col, fc, u.time), 1.0);
    }

    """
}
