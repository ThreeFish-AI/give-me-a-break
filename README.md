<div align="center">

# Give me a break 🍅

**macOS 菜单栏强制作息应用**

在自定义工作时段内执行「工作 / 强制休息」节律，休息时**遮罩全部显示器**并**播放舒缓音效**（内置粉噪音 + 可选 QQ 音乐联动）；接入 **Google 日历**会议，会议计为工作时间但**休息自然后延**。

![macOS](https://img.shields.io/badge/macOS-14%2B-000000) ![Swift](https://img.shields.io/badge/Swift-SPM-F05138) ![License](https://img.shields.io/badge/license-MIT-blue)

</div>

## 设计哲学

熵减：用「上下文驱动、最小干预、循证工程」原则，对抗每天作息的无序。完整设计与循证调研见 [设计文档](./docs/give-me-a-break-design.md)，协作规约沉淀于 [ThreeFish-AI/agents.md](https://github.com/ThreeFish-AI/agents.md)（本仓不设项目级副本）。

## 核心能力

- **强制排版作息**：工作窗口内每累计 N 分钟（默认 50）→ 强制休息 M 分钟（默认 10）。
- **全屏遮罩**：休息时遮罩所有显示器（`CGShieldingWindowLevel`，压过菜单栏/Dock/全屏）；单击 Esc 唤出遮罩内嵌确认（继续休息 / 直接退出），**0.4s 内双击 Esc 直接退出**（软强制，留逃生阀）。
- **遮罩背景跟随系统壁纸**：手动遮罩与休息遮罩共用同一背景，与桌面所见一致——当前壁纸为系统航拍（Aerial）时，静音循环播放本机同一段 4K 视频（Media Engine 硬件解码，多屏共用一路，实测整机功耗与空闲持平）；其余壁纸按屏显示桌面静帧；任一步不可得即逐级回退，遮罩绝不失效（只读取本机已有文件，不下载、不打包）。解析链与回退细节见[设计文档 §8](./docs/give-me-a-break-design.md#8-遮罩背景跟随系统壁纸)。
- **屏幕遮罩（手动）**：全局快捷键 **⌃⌥⌘K**、菜单「屏幕遮罩」或系统锁屏快捷键 Control+Command+Q（拦截后不真正锁屏，改为进入本 App 遮罩；需「输入监控」授权）随时手动进入同款全屏遮罩，电脑后台照常运行。遮罩期间在 HID 层**白名单拦截键盘**：除裸 Esc（双击退出）与裸 Return（休息确认框默认按钮）外全部吞掉——含 ⌘Tab / ⌘\` / ⌃←→ / Mission Control / ⌘空格 / ⌘⇧345 / ⌘⌥Esc 等系统组合键（需「输入监控」授权，未授权时降级为面板级阻断，仅系统组合键放行）；媒体键/亮度不受影响。退出路径：双击 Esc、看门狗（30min 核实遮罩仍在屏则续期，不在则自动解除拦截）、`GIVEMEABREAK_DISABLE_INPUT_GUARD` 应急短路、ssh/他机 kill、电源键硬关机。遮罩期间**工作计时冻结**（计划性休息及其小结窗不会打断遮罩，遮罩时长也不计入工作累加）；「立即休息」（⌃⌥⌘R）仍可主动接管（遮罩自动让位）。
- **休息音效**：进入休息播放**自定义音频**（在设置选择本地 mp3/m4a/aac/wav/flac 等文件，循环播放，取代内置粉噪音；文件不打包不分发，仅以本地路径引用，缺失/不可用自动回退粉噪音）或内置**粉噪音**（启动时预合成 8s 缓冲、AVAudioEngine 无缝循环，零音频文件、可靠）；可选叠加联动 QQ 音乐（经系统 Now Playing 路由的 CGEvent 媒体键）。结束休息自动停止。均可在设置中配置。
- **Google 日历门控**：会议计为工作时间，但休息推迟到会议结束。例：工作 30min 后接 30min 会议 → 连续工作 60min，会议结束才开始 10min 休息。
- **工作日志（认知闭合仪式）**：自然休息前弹一个轻量输入框，花 30 秒写下「刚刚完成了什么 + 可选下一步」，让大脑真正放下再休息（循证：Leroy 注意力残留 / Stubblebine 插值日记）。记录按时间段落盘，菜单「工作日志…」一键生成今日/本周/月报 Markdown，支持复制与导出。永不阻塞休息：回车提交 / Esc 跳过 / 关窗放行 / 到点自动放行（等待时长可在设置调整，默认 3 分钟）；亦可设「永久等待」让窗口停留至手动操作，或在设置关闭整个环节；「立即休息」不弹。
- **运动记录 + 综合报告**：与工作日志对称——**休息自然结束时**弹轻量输入框，记录这段休息里做的微运动（如胯下击掌 / 提膝击掌 / 深蹲 / 俯卧撑），每条含「运动时段 + 若干（类型 × 数量）」；提前结束（Esc）与被会议、下班打断均不弹。运动记录与工作日志一并汇入菜单「综合报告…」，按**周 / 月 / 季 / 年**合成原生层级报告（工作 Top N + 周期分布、运动按类型聚合 + 明细），支持复制与导出 Markdown。
- **防止空闲睡眠**：菜单「防止睡眠」勾选项或设置「电源」页一键开启（两处**即时生效**，同「开机自启」语义）——经 IOKit 原生电源断言（与 `caffeinate -d` / `-d -i` 同机制，非子进程）阻止电脑因空闲而熄屏/睡眠，**无需任何权限**；防护范围（仅显示器 / 显示器 + 系统）在设置「电源」页配置、随「应用」提交，状态持久化、重启后自动恢复，`pmset -g assertions` 可观测。与休息 / 工作 / 遮罩模式完全独立，不影响主动睡眠（合盖、Apple 菜单睡眠、低电量）。
- **Coding Proxy 托管**：把本地命令行工具（如 `uv run coding-proxy start`）交给本应用托管——在设置「Agentic AI」页配置**工作目录 + 启动命令**并开启后，随本应用自动启动并保持运行，退出本应用时一并停止（SIGTERM → SIGKILL 兜底，不留孤儿进程）；环境 PATH 自动补充 Homebrew 与用户 bin 目录（Finder 启动的 App 无 shell PATH 也能找到 `uv`）。菜单「Coding Proxy…」打开控制台：彩色等宽日志流（stdout / 橙色 stderr / 蓝色生命周期）、状态与 PID、会话级启动/停止/重启。配置改动随「应用」提交，运行中修改目录或命令自动重启；进程意外退出不自动重启（防重启风暴）。
- **健壮性**：AFK/睡眠暂停累加（不回灌）、崩溃恢复（fast-forward）、多屏热插拔、状态持久化。

## 架构总览

![应用架构总览](docs/diagrams/app-architecture/app-architecture.svg)

**正交分解**（[详细 FSM](./docs/give-me-a-break-design.md#2-调度引擎)）：`evaluate` 是零时间依赖纯函数（注入虚拟时钟可测）；`LiveGiveMeABreakEngine` 仅汇聚输入 + 调用纯函数 + 幂等分发；三大 Controller 各封装系统 API 与权限。三模块：`GiveMeABreakEngine`（纯核心）、`GiveMeABreakIntegrations`（AppKit/EventKit/CGEvent）、`GiveMeABreak`（@main 壳）。

## 下载与安装（Release 资产）

从 [Releases](https://github.com/ThreeFish-AI/give-me-a-break/releases) 下载对应平台 zip。macOS 产物为**稳定自签名**（10 年期 codeSigning 证书，未公证）：**TCC 权限（辅助功能 / 输入监控 / 日历）授权一次、跨版本升级持久**；Gatekeeper 对「未知开发者」应用仍会拦截**首次**打开（彻底消除需 Apple 公证，$99/年，演进链路已预留，见[签名与 TCC 授权](#签名与-tcc-授权一次授权跨版本持久)）。

**macOS 一键安装（推荐，安装/升级通用）**：

```bash
curl -fsSL https://raw.githubusercontent.com/ThreeFish-AI/give-me-a-break/feature/1.x.x/install.sh -o install.sh
bash install.sh              # 最新正式版；指定版本：bash install.sh v0.1.8
```

脚本自动完成：下载 Release zip → 去隔离 → 替换安装目录中的 `GiveMeABreak.app` → 启动。安装目标优先 `/Applications`：目录不可写时经 `sudo` 提权写入，`sudo` 不可用则回退 `~/Applications`；环境变量 `GIVEMEABREAK_INSTALL_DIR` 可覆盖安装目录（测试/自定义，此时不退出运行中实例、不自动启动）。

**macOS 手动安装**：解压后将 `GiveMeABreak.app` 拖入 `/Applications`，执行一次去隔离再启动（macOS 15 起已无右键「打开」旁路）：

```bash
xattr -dr com.apple.quarantine /Applications/GiveMeABreak.app
```

**Windows 10/11 x64**（`give-me-a-break-*-win64.zip`）：自包含、未签名。SmartScreen 提示时点「更多信息 → 仍要运行」；因低级键盘钩子（`WH_KEYBOARD_LL`）+ `SendInput` 媒体键，可能被 Defender / 360 / 火绒**误报**，需手动放行。解压后运行 `GiveMeABreakShell.exe`。

## 环境要求

- **macOS 14+**（Sonoma 及以上，本机实测 macOS 26.5.1）。
- **Swift 工具链**：Command Line Tools 即可（`swift --version` ≥ 6.0）。**无需安装完整 Xcode**——本工程用 Swift Package Manager + `Makefile` 手工装配 `.app`。
- `codesign` / `xcrun notarytool` 随 Command Line Tools 附带。

## 构建与运行

```bash
# 装配 GiveMeABreak.app（默认 ad-hoc 签名；配置 Makefile.local 后为稳定自签名）并运行
make run

# 或分步
make build      # swift build -c release
make app        # 装配 .app + codesign + 清 quarantine（签名身份见「签名与 TCC 授权」）
open GiveMeABreak.app

# 单元测试（自建运行器，CLT 无 XCTest）
make test
```

**快速验证遮罩/音乐/工作日志**（⚠️ 会遮罩你的屏幕约 15 秒）：

```bash
GIVEMEABREAK_DEBUG=1 .build/release/GiveMeABreak
# → 8s 工作 → 工作日志输入框（DEBUG 旁路 15min 门控）→ 回车/跳过 → 全屏遮罩 + 拉起 QQ 音乐 → 15s 后自动退出遮罩 + 暂停音乐
```

## 权限授予（首次运行，全部由你在系统设置手动完成）

Give me a break 是**非沙盒**应用（沙盒会阻断媒体键与日历自动化）。运行后请在「系统设置 → 隐私与安全性」依次授予：

| 权限                             | 用途                                                     | 触发时机                                             |
| -------------------------------- | --------------------------------------------------------- | ------------------------------------------------------ |
| **辅助功能 (Accessibility)**     | CGEvent 合成媒体键控制 QQ 音乐                             | 首次启动弹引导窗                                        |
| **完全日历访问**                 | EventKit 读取 Google 日历会议                              | 首次启动请求                                            |
| **输入监控 (Input Monitoring)**  | `CGEventTap` 拦截系统锁屏快捷键（Control+Command+Q），触发「屏幕遮罩」而非真正锁屏 | 首次启动尝试接管快捷键时；未授权时自动降级，仅菜单「屏幕遮罩」可用（**授权后需重启 App 才生效**，非热更新） |
| **自动化 (Automation)**          | plist / entitlements 已预置 `NSAppleEventsUsageDescription` 与 `com.apple.security.automation.apple-events`，当前无 AppleScript 代码（预置未用） | 无（预置未用） |

> Agent 不得代用户完成任何认证 / 授权，凭证不进 chat；上述权限授予全部由你在系统设置手动完成。

## 签名与 TCC 授权（一次授权，跨版本持久）

TCC 权限是否在升级后保留，取决于**代码签名身份是否稳定**：ad-hoc 签名（`codesign -s -`）的 Designated Requirement 绑定 cdhash，每次构建都变，TCC 视为不同应用 → 授权失效；稳定证书签名的 DR 绑定证书 CN → 跨构建不变 → 授权持久（见 [issue #5](./.agents/issue.md)）。

**本机一次性配置**（开发者，此后 `make app` 稳定签名、TCC 不再反复弹）：

```bash
bash scripts/create-signing-cert.sh   # 创建 10 年期自签名 codeSigning 证书（含一步 sudo 信任）
                                       # 并自动写入仓库根 Makefile.local（gitignored）
```

**CI 配置 · 当前生效（稳定自签名，下载用户 TCC 同样一次授权）**：

| GitHub 设置项                     | 类型     | 值                                                        |
| --------------------------------- | -------- | ---------------------------------------------------------- |
| `MACOS_SELFSIGN_P12`              | Secret   | `base64 -i .temp/signing/selfsign.p12 \| pbcopy` 的结果     |
| `MACOS_SELFSIGN_P12_PWD`          | Secret   | 创建证书时输入的 p12 密码                                   |
| `KEYCHAIN_PASSWORD`               | Secret   | 任意强密码（CI 临时 keychain 用）                           |
| `SELFSIGN_IDENTITY`               | Variable | `GiveMeABreak Release`                                      |
| `ALLOW_ADHOC_RELEASE`             | Variable | 逃生门：默认拒绝 ad-hoc 产物流出，确需内测发布时临时设 `true`（当前链路即生效） |

**CI 配置 · 购证后启用（Developer ID + 公证，链路已在 release.yml 预留）**：

| GitHub 设置项                     | 类型     | 值                                                        |
| --------------------------------- | -------- | ---------------------------------------------------------- |
| `ENABLE_DEVELOPER_ID_SIGNING`     | Variable | `true` 启用 Developer ID 签名链（优先于稳定自签名）          |
| `MACOS_CERTIFICATE` / `MACOS_CERTIFICATE_PWD` | Secret | Developer ID 证书 p12（base64）与密码                     |
| `SIGNING_IDENTITY`                | Secret   | 证书 CN（如 `Developer ID Application: …`）                 |
| `APPLE_ID` / `APPLE_APP_SPECIFIC_PASSWORD` / `APPLE_TEAM_ID` | Secret | 公证（`notarytool submit`）账号三件套        |

自签 secrets 未配置或导入失败时，发布被**硬门禁阻断**——ad-hoc 产物禁止流出（`ALLOW_ADHOC_RELEASE` 为临时内测逃生门）。购证并配置 Developer ID secrets 后，[release.yml](./.github/workflows/release.yml) 自动改走 Developer ID 签名 + 公证链。签名链演进与 v0.1.10 ad-hoc 事故的取证史见 [issue #5](./.agents/issue.md) 与 [CHANGELOG](./CHANGELOG.md)。

> **迁移提示**：从 ad-hoc 版本升级到稳定签名版本时，TCC 权限需**最后一次**重新授权，此后跨版本持久；旧 ad-hoc 的孤儿授权记录可在系统设置手动移除，或经 `tccutil reset` 按权限整体重置。

## 快捷键

| 快捷键 | 动作 | 生效范围 | 前置条件 |
| --- | --- | --- | --- |
| **⌃⌥⌘K** | 屏幕遮罩 | 全局（任意应用前台） | 无（零权限） |
| **⌃⌥⌘R** | 立即休息 | 全局（任意应用前台） | 无（零权限） |
| **⌃⌘Q** | 进入屏幕遮罩（接管系统锁屏快捷键） | 全局 | 「输入监控」权限 + 授权后重启 App |
| 菜单项裸字母（L/,/Q） | 对应菜单项 | 仅状态栏菜单展开时 | 无 |

- ⌃⌥⌘K/⌃⌥⌘R 经系统 `RegisterEventHotKey`（Carbon HIToolbox）注册，事件被系统消费、**不会透传给前台应用**，也无需任何权限。
- ⌃⌘Q 劫持依赖 `CGEventTap`：未授权「输入监控」时该组合键保持系统原生锁屏（预期降级，⌃⌥⌘K 不受影响）；授权后需重启 App 才生效。Release 产物与本机构建（配置 `Makefile.local` 后）均为**稳定自签名，TCC 授权跨版本持久**；从旧 ad-hoc 构建升级而来时需重新授权一次（见[签名与 TCC 授权](#签名与-tcc-授权一次授权跨版本持久)）。
- 菜单项裸字母快捷键（工作日志 L / 设置 , / 退出 Q）为 macOS 状态栏菜单的原生行为：仅在菜单展开时可选中所选项，**并非全局热键**；「立即休息 / 屏幕遮罩」在菜单中即展示 ⌃⌥⌘R / ⌃⌥⌘K 全局快捷键。

## QQ 音乐与 Google 日历准备

- **休息音效（默认开）**：内置**粉噪音**无需任何准备，开箱即用。可选联动 **QQ 音乐**：安装至 `/Applications/QQMusic.app` 并授予辅助功能权限（其注册为系统 Now Playing 应用，故媒体键可路由控制；**不可** AppleScript 脚本化，已二进制验证）。两者均可在设置中开关。
- **应用图标**：装配自动生成（`leaf.fill` 绿叶 + teal 渐变 squircle，方案 A）。
- **Google 日历**：在「系统设置 → Internet 账户」添加 Google 账户并启用日历 → 经 CalDAV 同步至 macOS 日历 → EventKit 自动可见（**无 OAuth 代码**，复用 OS 登录态）。

## 配置

配置文件：`~/Library/Application Support/com.aurelius.givemeabreak/config.json`（缺失则用默认；旧版配置自动平滑迁移）。默认即用户所述作息：

```json
{
  "schemaVersion": 10,
  "workWindows": [
    { "start": { "hours": 9 }, "end": { "hours": 12 } },
    { "start": { "hours": 13, "minutes": 40 }, "end": { "hours": 18 } }
  ],
  "workIntervalSeconds": 3000,
  "restDurationSeconds": 600,
  "afkThresholdSeconds": 180,
  "ambientSoundEnabled": true,
  "controlQQMusic": true,
  "workLogEnabled": true,
  "restMusicPath": null,
  "workLogPromptTimeoutSeconds": 180,
  "exerciseLogEnabled": true,
  "exercisePromptTimeoutSeconds": 180,
  "exerciseTypes": ["胯下击掌", "提膝击掌", "深蹲", "俯卧撑"],
  "agent": {
    "claudeExecutablePath": null,
    "claudeSettingsEditorBundleId": null,
    "codingProxy": {
      "autoStartEnabled": false,
      "workingDirectory": "",
      "launchCommand": "uv run coding-proxy start"
    }
  },
  "power": { "preventIdleSleepEnabled": false, "mode": "displayOnly" }
}
```

> **Agentic AI**：`agent.codingProxy`（v10 新增）为**已落地**的 Coding Proxy 托管配置（见上文「核心能力」）；`claudeExecutablePath` 与 `claudeSettingsEditorBundleId`（v8 新增）为后续 Agentic AI 功能预留——前者覆盖 Claude Code 可执行文件路径（`null`/空即自动从系统 `PATH` 探测，推荐），后者记住「Claude 设置」快捷打开所用编辑器的 bundle id（`null` 即系统默认关联应用）。二者仅持久化 + 设置界面可视化编辑，**当前尚未接入任何 Claude Code 调用**。
>
> **遮罩背景（无配置项）**：背景跟随系统壁纸；旧版 `screenMask` 子块已废弃——旧配置携带时解码忽略、下次落盘即丢弃，`schemaVersion` 保持 10（删字段对新旧版本双向兼容）。
>
> **电源（v9 新增）**：`power` 子块为「防止空闲睡眠」的配置——`preventIdleSleepEnabled` 总开关（默认 `false`，重启后自动恢复）；`mode` 防护范围（`displayOnly` = 仅显示器断言，等同 `caffeinate -d`；`displayAndSystem` = 显示器 + 系统双断言，等同 `caffeinate -d -i`）。引擎不消费本子块（与休息 / 工作 / 遮罩调度完全正交），仅集成层 `IdleSleepGuard` 消费。

工作日志单独持久化为 `work-log.json`（同目录），schema 见 [shared/work-log.schema.json](./shared/work-log.schema.json)；报告生成（今日/本周/月报 Markdown）见菜单「工作日志…」。运动记录单独持久化为 `exercise-log.json`（同目录）；与工作日志合成的综合报告（周/月/季/年 Markdown）见菜单「综合报告…」。

可在**设置窗口**图形化编辑，采用**草稿-应用**模式（改完点「应用」才提交并热更新引擎，无需手动改 JSON；仅「开机自启」与「防止睡眠」总开关为即时生效项）。设置窗口按功能域分 **7 个页签**：**通用 · 电源 · 作息 · 音效 · 日志 · 运动 · Agentic AI**；「通用」页含「开机自启」、遮罩背景状态（只读显示跟随系统壁纸与当前解析结果，可「打开墙纸设置…」直达系统设置）与「关于」版本卡；「Agentic AI」页配置 Claude Code 可执行文件路径覆盖（可在自动探测到的 VS Code / Cursor 等编辑器中一键打开 `~/.claude/settings.json`）与 Coding Proxy 托管；「电源」页配置「防止空闲睡眠」。菜单栏为**按状态着色的叶子图标**，中文状态与倒计时显示在图标 Tooltip 与菜单顶部状态行（如「工作中 · 距下次休息 23 分钟」）；下拉菜单按动作分组：**立即休息 · 屏幕遮罩**（即时动作）┃ **工作日志 · 综合报告 · Coding Proxy**（查看）┃ **补录工作 · 补录运动**（录入）┃ **设置 · 防止睡眠 · 开机自启**（偏好）┃ **退出**（打开窗口类菜单项带「…」尾缀）。

## 验证

- **单元测试**：`make test`（<1s）覆盖 FSM 谓词优先级、工作示例（30+30→60→10）、AFK 冻结、睡眠不回灌、fast-forward、区间合并、工作日志记录/报告/补录、运动记录/综合报告（周/月/季/年）、运动类型注册表与补录默认时段纯函数、Coding Proxy 配置解析与命令决策、系统壁纸解析回退链、onPostBreak 触发不变量、配置迁移（v3→v10，含 v9→v10 codingProxy 与 v10 screenMask 废弃容错）等。详见[设计文档 §10](./docs/give-me-a-break-design.md#10-测试矩阵)。
- **端到端**（真机，三权限 + QQ 音乐 + Google 账户）：`GIVEMEABREAK_DEBUG=1` 观察遮罩/音乐周期；正常时段等待 50min 触发；日历建会议验证推迟。

## 已知限制（透明披露）

- **强制休息与遮罩期间 Cmd-Opt-Esc 被 HID 层拦截**（白名单外一律吞）；`kill`（含 ssh / 他机）始终可终止——这是 macOS 设计，非恶意软件。软强制提供摩擦而非硬锁：键盘侧的唯一即时出口是双击 Esc，另有 30 分钟看门狗自动核实（防僵尸拦截吞键）。
- **QQ 音乐联动依赖外部条件**：需已安装 QQ 音乐、已授辅助功能权限、且 QQ 音乐注册为系统 Now Playing 应用，任一不满足即静默失败（toggle 语义还可能在播放中误暂停）——**故默认叠加内置粉噪音**保证任何情况下有声；失败条件明细与取证见 [issue #3](./.agents/issue.md)。
- **日历过滤近似**：「仅 Google」靠 `.calDAV` 源过滤；若有其他 CalDAV 账户（Yahoo/Fastmail）会被纳入。
- **macOS 26 `canBecomeKey`**：遮罩面板设为可成为 key 以收 Esc（Esc 双保险之一）；beta 期崩溃报告已经 macOS 26.5.1 实机回归证实 release 已消失（遮罩期间进程存活、面板位于 `CGShieldingWindowLevel`），见 [issue #4](./.agents/issue.md)。
- **「屏幕遮罩」非真正锁屏，且仅拦截默认快捷键**：与强制休息同为「软强制」；锁屏快捷键拦截固定为 macOS 默认的 Control+Command+Q，若你在「系统设置」自定义过锁屏快捷键，拦截不会跟随生效（仍可用菜单「屏幕遮罩」手动触发）；遮罩期间 Cmd-Opt-Esc 已被键盘白名单拦截（须「输入监控」授权，授权前该组合键仍可绕过）；任意 App 持有 Secure Input（如密码框、Terminal「安全键盘输入」）时全机 `CGEventTap` 被系统静默禁用，此刻 ⌃⌘Q 仍触发真正锁屏——均为 macOS 设计，非本 App 缺陷。**如需真正锁屏，请用 Apple 菜单 →「锁定屏幕」**。快捷键边界细节见[设计文档 §7](./docs/give-me-a-break-design.md#7-主动屏幕遮罩手动遮罩)。
- **遮罩背景依赖系统私有布局**：航拍经解析 `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`（非公开格式）定位，系统升级若变更布局则降级桌面静帧（遮罩不受影响）；仅读「全部显示器」的壁纸选择，分屏 / 分 Space 单独设置的航拍不区分；航拍须先在「系统设置 → 墙纸」下载过。详见[设计文档 §8](./docs/give-me-a-break-design.md#8-遮罩背景跟随系统壁纸)。

## 项目结构

```
├── Package.swift                  # SPM 四目标：Engine / Integrations 两 library + GiveMeABreak 可执行壳 + GiveMeABreakTests 测试运行器
├── Sources/
│   ├── GiveMeABreakEngine/             # 纯 Foundation：FSM + evaluate 纯函数 + 模型 + 持久化
│   ├── GiveMeABreakIntegrations/       # AppKit/EventKit/CGEvent：遮罩 + 音乐 + 日历 + 心跳 + 装配
│   └── GiveMeABreak/                   # @main 壳 + AppDelegate
├── tests/                         # Swift 自建测试运行器（Harness + Cases + main + 报告黄金快照）
├── shared/                        # 跨端契约：config.schema.json / work-log.schema.json / FSM 黄金 fixture（C# 端消费）
├── windows/                       # Windows 版 C#/.NET 8 工程（Engine / Win32 / Graph / Shell + 3 测试工程，2 sln）
├── scripts/                       # create-signing-cert.sh / generate_icon.swift / check_knowledge_map.sh
├── install.sh                     # macOS 一键安装 / 升级脚本
├── docs/                          # 设计文档 + Windows 版设计文档 + diagrams/（架构图）
├── Makefile / Resources/          # .app 装配 + Info.plist + entitlements
├── .github/                       # workflows（ci / lint / release）+ markdownlint / lychee 配置
└── .agents/                       # 协作文档（knowledge-map / issue）
```

## Windows 版

macOS 为主版本；Windows 10/11 x64 版已与 macOS 同节奏发布——[release.yml](./.github/workflows/release.yml) 以 **3 个具名 job**（macOS 构建 / Windows 构建 / Release 汇总）在打 tag 时同时挂出双平台 asset。集成层 38 个 Swift 文件中仅 `Heartbeat.swift` 可跨平台（其余绑定 AppKit / EventKit / CGEvent 等 Apple 专有框架或 POSIX 信号，Windows 物理不存在），故 Windows 版为 **C#/.NET 8 WPF 平行重写**（非 Swift 直编）：托盘常驻形态，入口 `GiveMeABreakShell.exe`；粉噪音经 NAudio（自写 Kellet 滤波，NAudio 仅 WASAPI 出声）、媒体键经 `SendInput`、全屏遮罩经 `WS_EX_TOPMOST` + `WH_KEYBOARD_LL` 软强制（仅拦 Alt+Tab 与 Win 键）、日历经 Microsoft Graph（MSAL 设备码登录）。架构、Esc 交互状态机、CI 与真机验收现状详见 [windows-port-design.md](./docs/windows-port-design.md)。

双端语义靠测试锚定：Swift 端为原始用例（期望值内联，不读 fixture）；C# 端由 `shared/test-fixtures/` 黄金 fixture 锁纯函数决策，时序场景逐条镜像 Swift 用例（计数见 [windows-port-design.md §10](./docs/windows-port-design.md#10-实施现状)）。

**Windows 构建**（需 Windows + .NET 8 SDK，macOS 无法编译 WPF 工程）：

```powershell
dotnet build windows/GiveMeABreakShell/GiveMeABreakShell.csproj -c Release
dotnet publish windows/GiveMeABreakShell/GiveMeABreakShell.csproj -c Release -r win-x64 --self-contained -o ./publish
.\publish\GiveMeABreakShell.exe
```

**配置差异（如实披露）**：配置文件位于 `%APPDATA%\com.aurelius.givemeabreak\`，C# 端实现 schema **v2 子集**并新增 `graphClientId` 字段（Graph 客户端 id，macOS 端无此字段）；**macOS 的 v10 配置带到 Windows 会因 schemaVersion 高于 2 而在内存中整体回退默认**（配置文件本身不被改写）——两端配置当前不互通，补齐 C# 端 schema 至 v10 为后续演进项。真机验收限制（托盘图标、粉噪音出声、QQ 音乐联动、遮罩覆盖 / 键盘拦截需 Windows 真机，CI 无 explorer shell / 音频设备 / 桌面会话）详见 [windows-port-design.md](./docs/windows-port-design.md)。

---

<div align="center">
  <sub>Built with 🧠, ❤️, and an absurd amount of coffee by <a href="https://github.com/ThreeFish-AI">ThreeFish-AI</a> · Released under the <a href="./LICENSE">MIT License</a>.</sub>
</div>
