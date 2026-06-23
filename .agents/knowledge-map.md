# Knowledge Map（知识索引）

> 项目内文档与关键能力索引；按主题正交分组，链接为相对路径以便跨上下文跳转。
> 新增/变更文档时应即时同步本表。

## 应用入口与规约

| 文档 | 说明 |
|---|---|
| [README.md](../README.md) | Timeout 应用主文档：构建/运行/权限/配置/架构 |
| [docs/timeout-design.md](../docs/timeout-design.md) | 设计文档：FSM 状态机 + 数据模型 + 测试矩阵 + IEEE 引用 |
| [docs/windows-port-design.md](../docs/windows-port-design.md) | Windows 移植技术方案：跨平台不可行性循证 + C#/.NET WPF 架构 + 全屏遮罩妥协设计 |
| [AGENTS.md](../AGENTS.md) | AI Agent 协作规约（工程行为准则） |

## 协作支撑

| 文档 | 说明 |
|---|---|
| [.agents/issue.md](./issue.md) | 跨上下文问题经验沉淀 |
| [.agents/reference-specifications.md](./reference-specifications.md) | IEEE 标准引用格式 |
| [.agents/browser-validation.md](./browser-validation.md) | 浏览器验证协议（OAuth/登录态红线，同构适用于系统 TCC） |

## 关键代码位置

| 能力 | 文件 |
|---|---|
| 调度核心（FSM + evaluate 纯函数） | `Sources/TimeoutEngine/Engine.swift` |
| 引擎接线 + sleep/wake + fast-forward | `Sources/TimeoutEngine/LiveTimeoutEngine.swift` |
| 多屏遮罩 + 软强制 Esc | `Sources/TimeoutIntegrations/Overlay/LiveOverlayController.swift` |
| 休息音效（粉噪音 + QQ 音乐联动） | `Sources/TimeoutIntegrations/LiveMusicController.swift` + `AmbientSoundPlayer.swift` |
| 内置粉噪音合成（AVAudioEngine） | `Sources/TimeoutIntegrations/AmbientSoundPlayer.swift` |
| 设置界面（一般/工作时段/节律/休息音效） | `Sources/TimeoutIntegrations/Settings/SettingsView.swift` |
| 应用图标生成脚本（leaf.fill + squircle） | `scripts/generate_icon.swift` |
| 配置 schema 迁移（容错解码） | `Sources/TimeoutEngine/Models.swift` + `ConfigStore.swift` |
| Google 日历 EventKit 门控 | `Sources/TimeoutIntegrations/LiveCalendarProvider.swift` |
| .app 装配 + 图标生成 + 签名 | `Makefile` |
| CI/CD 工作流（测试 / 文档门禁 / 发布） | `.github/workflows/` |
