import Foundation
import GiveMeABreakEngine
import IOKit.pwr_mgt

/// 防止空闲睡眠/熄屏守护：IOKit 原生电源断言（`IOPMAssertionCreateWithName`，
/// 即 caffeinate / Amphetamine / KeepingYouAwake 的同一机制，非 spawn 子进程）。
/// 与引擎 FSM 完全正交：只消费 `PowerSettings`，不读写引擎任何状态。
/// 非沙盒 + Hardened Runtime 下无需任何 entitlement / TCC 权限；进程退出时内核自动回收断言
/// （App 崩溃亦不会遗留「永久唤醒」，优于 caffeinate 子进程的孤儿进程风险）。
/// 仅主线程调用（start / onApply / 菜单动作 / shutdown 均在主线程），无需加锁。
final class IdleSleepGuard {
    /// 持有的断言 ID；nil = 未持有。两种模式下 display 断言恒持有，模式差异仅体现在 system 断言——
    /// 故按断言维度 diff 增删，模式切换时 display 断言全程不落（零空窗，无 release-再-create 间隙）。
    private var displayAssertion: IOPMAssertionID?
    private var systemAssertion: IOPMAssertionID?

    /// 当前是否实际持有断言（可观测）。
    var isActive: Bool { displayAssertion != nil || systemAssertion != nil }

    /// 幂等应用电源配置（diff 实际持有 vs 期望状态；创建失败仅记日志、ID 保持 nil，
    /// 下次 apply 同配置即自愈重试——不缓存期望状态，故不会误判「已生效」）。
    func apply(_ power: PowerSettings) {
        let wantDisplay = power.preventIdleSleepEnabled
        let wantSystem = power.preventIdleSleepEnabled && power.mode == .displayAndSystem
        if wantDisplay, displayAssertion == nil {
            displayAssertion = createAssertion(type: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                               reason: "GiveMeABreak prevent display idle sleep")
        } else if !wantDisplay, let id = displayAssertion {
            displayAssertion = nil
            releaseAssertion(id, kind: "显示器")
        }
        if wantSystem, systemAssertion == nil {
            systemAssertion = createAssertion(type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                              reason: "GiveMeABreak prevent system idle sleep")
        } else if !wantSystem, let id = systemAssertion {
            systemAssertion = nil
            releaseAssertion(id, kind: "系统")
        }
    }

    /// 释放全部断言（AppRoot.shutdown 调用；进程退出内核亦会回收，此处为干净收尾与可观测）。
    func release() {
        apply(PowerSettings())
    }

    // MARK: - IOKit 封装

    /// 创建断言，失败返回 nil（kIOReturnSuccess 判定；reason ≤128 字符，`pmset -g assertions` 可见）。
    private func createAssertion(type: CFString, reason: String) -> IOPMAssertionID? {
        var id = IOPMAssertionID()
        let kr = IOPMAssertionCreateWithName(type,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             reason as CFString,
                                             &id)
        guard kr == kIOReturnSuccess else {
            NSLog("[GiveMeABreak][power] 电源断言创建失败 kr=\(kr)：\(reason)")
            return nil
        }
        NSLog("[GiveMeABreak][power] 电源断言已创建：\(reason)")
        return id
    }

    private func releaseAssertion(_ id: IOPMAssertionID, kind: String) {
        let kr = IOPMAssertionRelease(id)
        if kr != kIOReturnSuccess {
            NSLog("[GiveMeABreak][power] 电源断言释放失败 kr=\(kr)（\(kind)）")
        }
    }

    deinit {
        // 防御性兜底：正常路径 shutdown() 已释放；泄漏时进程退出内核亦回收。
        if let id = displayAssertion { IOPMAssertionRelease(id) }
        if let id = systemAssertion { IOPMAssertionRelease(id) }
    }
}
