import EventKit
import Foundation
import TimeoutEngine

/// 日历提供者：EventKit 读取 Google（CalDAV）日历的忙碌事件，合并为时间线。
/// 缓存 + 限流（≥60s）+ EKEventStoreChanged 推送（debounce），避免引擎 1Hz tick 频繁查询。
/// 仅授权后才工作；未授权返回空时间线（会议功能降级为无会议，不阻断引擎）。
final class LiveCalendarProvider: CalendarProvider {
    private let store = EKEventStore()
    private let lock = NSLock()
    private var cached = MeetingTimeline.empty
    private var lastRefresh = Date.distantPast
    private var accessGranted = false
    private var refreshInFlight = false

    private let minRefreshInterval: TimeInterval = 60     // 显式刷新最低间隔
    private let lazyRefreshInterval: TimeInterval = 180   // 引擎 tick 触发的惰性刷新间隔

    func bootstrap() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.accessGranted = granted
                if granted {
                    NotificationCenter.default.addObserver(self, selector: #selector(self.storeChanged),
                                                            name: .EKEventStoreChanged, object: self.store)
                    self.triggerRefresh()
                    NSLog("[Timeout][calendar] 已获得日历完全访问权限")
                } else {
                    NSLog("[Timeout][calendar] 日历访问未授权（\(error?.localizedDescription ?? "用户拒绝")）；会议推迟降级为无会议")
                }
            }
        }
    }

    func currentTimeline() -> MeetingTimeline {
        if accessGranted, Date().timeIntervalSince(lastRefresh) >= lazyRefreshInterval {
            triggerRefresh()
        }
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    @objc private func storeChanged() {
        triggerRefresh()  // 内部 debounce + 限流
    }

    private func triggerRefresh() {
        guard accessGranted, !refreshInFlight,
              Date().timeIntervalSince(lastRefresh) >= minRefreshInterval else { return }
        refreshInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.refresh()
            self?.refreshInFlight = false
        }
    }

    private func refresh() {
        let now = Date()
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)  // 同步，已在后台队列

        let busy = events
            .filter { $0.calendar?.source?.sourceType == .calDAV }          // 仅 Google（CalDAV）
            .filter { $0.availability == .busy || $0.availability == .tentative }  // 排除「空闲」/未知
            .map { DateRange(start: $0.startDate, end: $0.endDate) }
        let merged = mergeBusyIntervals(busy)

        lock.lock()
        cached = MeetingTimeline(busyIntervals: merged, generatedAt: now)
        lastRefresh = now
        lock.unlock()

        NSLog("[Timeout][calendar] 刷新：\(events.count) 事件 → \(busy.count) Google 忙碌 → \(merged.count) 合并区间")
    }
}
