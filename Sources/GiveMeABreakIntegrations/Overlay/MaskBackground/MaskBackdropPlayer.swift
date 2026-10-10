import AppKit
import AVFoundation
import GiveMeABreakEngine

/// 遮罩航拍背景的共享播放器：单实例由 AppRoot 注入两处遮罩控制器（同 `MaskInputGuard` 范式），仅主线程使用。
///
/// 一个 `AVPlayer` 同时驱动各屏的 `AVPlayerLayer` → 多屏也只有一路硬件解码。刻意不用：
/// - AVKit / `AVPlayerView`：会接管系统「正在播放」，抢走 QQ 音乐的媒体键；
/// - `AVPlayerLooper`：双 item 预载，内存尖峰——改为到尾手动 seek 回零。
final class MaskBackdropPlayer: ObservableObject {
    let player = AVPlayer()
    /// 视频加载失败：视图据此回退静帧。
    @Published private(set) var failed = false

    private var active = false
    private var reduceMotion = false
    private var currentURL: URL?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// 延迟释放的代际令牌：begin 递增即作废尚未执行的释放（手动遮罩 → 立即休息的无缝交接）。
    private var generation = 0

    init() {
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false  // 显示器断言唯一归属 IdleSleepGuard
        player.automaticallyWaitsToMinimizeStalling = false     // 本地文件，无需缓冲等待
        player.actionAtItemEnd = .none
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            // 熄屏期间画面不可见，停解码省电；亮屏后续播
            nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.active else { return }
                self.player.pause()
            },
            nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.playIfAllowed()
            },
        ]
    }

    // MARK: - 生命周期（与两处 show/dismiss 对称成对）

    /// 遮罩升起：先于面板构建调用，首帧尽早就绪。
    func begin(source: SystemWallpaperSource, reduceMotion: Bool) {
        active = true
        self.reduceMotion = reduceMotion
        generation += 1
        guard case .video(let url) = source else {
            release()  // 静帧：无需解码
            return
        }
        if url != currentURL || failed { load(url) }  // 同一视频则直接续播，画面不跳变
        playIfAllowed()  // 减弱动态效果：不播放，暂停的播放器停在首帧，零持续解码
    }

    /// 遮罩收起：立即暂停（0.3s 淡出期间定格），稍后释放解码资源。
    /// 释放不挂在淡出完成回调或 ARC 上——二者均不可靠，代际令牌兜住期间的再次升起。
    func end() {
        guard active else { return }
        active = false
        player.pause()
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.active, self.generation == token else { return }
            self.release()
        }
    }

    /// 唤醒钩子：遮罩跨睡眠存活时核实播放状态（未激活时 no-op）。
    func recheckHealth() {
        guard active, let item = player.currentItem else { return }
        if item.status == .failed {
            markFailed(item.error)
        } else if !reduceMotion, item.status == .readyToPlay, player.rate == 0 {
            player.play()
        }
    }

    // MARK: - 内部

    private func playIfAllowed() {
        guard active, !reduceMotion, player.currentItem != nil else { return }
        player.play()
    }

    private func load(_ url: URL) {
        detachItem()
        currentURL = url
        if failed { failed = false }
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async {
                guard let self, self.player.currentItem === item else { return }
                self.markFailed(item.error)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player.seek(to: .zero)  // 手动循环
            self.playIfAllowed()
        }
        player.replaceCurrentItem(with: item)
    }

    private func markFailed(_ error: Error?) {
        guard !failed else { return }
        failed = true
        NSLog("[GiveMeABreak][maskBackdrop] 航拍视频加载失败，回退静帧：\(currentURL?.lastPathComponent ?? "-") \(error.map { "\($0)" } ?? "")")
    }

    private func release() {
        detachItem()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        if failed { failed = false }
    }

    private func detachItem() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    deinit {
        detachItem()
        for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }
}
