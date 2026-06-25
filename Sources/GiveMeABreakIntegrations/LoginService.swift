import ServiceManagement

/// 开机自启：SMAppService.mainApp（macOS 13+）。状态实时读取（用户可在系统设置切换，勿缓存）。
/// 需以正式 .app bundle 运行（Makefile 产物）；原始二进制下 SMAppService 不可用。
enum LoginService {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            NSLog("[GiveMeABreak] 开机自启：\(enabled ? "已启用" : "已关闭")")
        } catch {
            NSLog("[GiveMeABreak] 开机自启设置失败：\(error.localizedDescription)")
        }
    }
}
