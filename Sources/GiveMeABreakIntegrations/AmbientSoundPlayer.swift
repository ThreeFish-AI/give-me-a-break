import AVFoundation

/// 休息氛围音播放器：用 AVAudioPlayerNode 循环播放预生成的**粉噪音**（Paul Kellet 算法）。
///
/// 设计要点：
/// - **零音频文件**：粉噪音样本在初始化时合成进 `AVAudioPCMBuffer`，无版权/体积问题；
/// - **零第三方依赖**：仅 AVFoundation，CLT 兼容；
/// - **默认与其他音频混合**：macOS 经 CoreAudio 自动混音，可与 QQ 音乐叠加播放；
/// - 粉噪音频率分布最接近自然雨声，适合休息/专注/助眠。
final class AmbientSoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let buffer: AVAudioPCMBuffer
    private(set) var isPlaying = false

    init() {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: 44_100, channels: 1, interleaved: false)!
        buffer = AmbientSoundPlayer.makePinkNoise(seconds: 8, format: format)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.4   // 舒适响度
    }

    func start() {
        guard !isPlaying else { return }
        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: [.loops])  // 无缝循环
            player.play()
            isPlaying = true
            NSLog("[GiveMeABreak][ambient] 粉噪音已启动")
        } catch {
            NSLog("[GiveMeABreak][ambient] AVAudioEngine 启动失败：\(error.localizedDescription)")
        }
    }

    func stop() {
        guard isPlaying else { return }
        player.stop()      // 停止调度并清空已调度 buffer（便于下次重新 schedule）
        engine.pause()     // 暂停而非 stop+reset，便于快速重启
        isPlaying = false
        NSLog("[GiveMeABreak][ambient] 粉噪音已停止")
    }

    func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, volume))
    }

    // MARK: - Private

    /// Paul Kellet 粉噪音滤波器，合成 `seconds` 秒单声道 Float32 buffer。
    /// 首尾各做 ~50ms 线性淡入淡出，消除循环边界点击声。
    private static func makePinkNoise(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buf.frameLength = frameCount
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
        let data = buf.floatChannelData![0]
        let n = Int(frameCount)
        let fade = Int(format.sampleRate * 0.05)   // ~50ms
        for i in 0..<n {
            let white = Float.random(in: -1...1)
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            var sample = pink * 0.11
            // 首尾淡入淡出
            if i < fade { sample *= Float(i) / Float(fade) }
            else if i > n - fade { sample *= Float(n - i) / Float(fade) }
            data[i] = sample
        }
        return buf
    }
}
