# CHANGELOG

本文件记录 Give me a break 的版本变更事件。

## Unreleased

新增「Coding Proxy 托管」：把本地命令行工具（如 `uv run coding-proxy start`）交给本应用托管——设置「Agentic AI」页配置工作目录与启动命令，开启后随应用自动启动并保持运行，退出应用时一并停止；菜单「Coding Proxy…」打开控制台查看彩色日志流并会话级启停。配置 schema 升至 v10（容错迁移，旧配置无感），123 单测全绿（+32），引擎 FSM 零改动。

### 核心改进

- **新增「Coding Proxy 托管」（全仓首个 `Foundation.Process` 子进程用例）**。托管生命周期语义：开启 = 随本应用启动并保持运行；**退出应用时同步有界停止**（SIGTERM → ≤2s 轮询 → SIGKILL → 回收，不留孤儿进程）；进程意外退出**不自动重启**（防无退避重启风暴），控制台可手动再启动。环境 PATH 自动增强（前置 `~/.local/bin` / `~/bin` / `/opt/homebrew/bin` / `/usr/local/bin`）——App 从 Finder 启动无 shell PATH 也能解析 `uv`；并注入 `PYTHONUNBUFFERED=1` 防 Python 子进程块缓冲导致日志迟滞。
- **控制台窗口（菜单「Coding Proxy…」）**：彩色等宽日志流（stdout 默认色 / stderr 橙色 / 生命周期蓝灰，时间戳灰色）、运行状态与 PID、会话级「启动 / 停止 / 重启 / 清空日志」、自动滚底开关与「回到底部」。日志为会话级环形缓冲（2000 行 / 单行 4000 字符截断），窗口关闭再开不丢失；stdout/stderr 双管道流式捕获（UTF-8 跨 chunk 安全拼行，汉字被劈开不产生乱码），UI 刷新 ≥250ms 合流。
- **设置「Agentic AI」页新增 Coding Proxy 分区**：「随应用自动启动」开关 + 工作目录（目录选择器 / 存在性校验警示）+ 启动命令（解析与可执行校验警示），全部随「应用」提交——运行中修改目录或命令**自动重启进程**，仅翻转开关不打扰运行中的进程；配置无效不阻断「应用」、不杀死正在运行的旧进程（仅行内橙叹号 + 控制台状态 + 日志警示）。与「防止睡眠」的即时通道语义刻意不同：开关与目录/命令同为草稿，避免「开关即时生效、目录还是旧草稿」组合下的静默启动失败。

### 工程

- 配置 schema 9→10：`AgentSettings` 内嵌正交子结构 `codingProxy: CodingProxySettings`（`autoStartEnabled: Bool` 默认 false / `workingDirectory: String` 默认空 / `launchCommand: String` 默认 `uv run coding-proxy start`），容错解码平滑迁移（旧 v9 缺 `codingProxy` 补默认），保持「Agentic AI 页签 ↔ agent 域」1:1 映射。纯逻辑全部下沉 Engine 层新文件 `CodingProxySupport.swift`（命令行解析含引号包夹与 `~` 展开 / PATH 增强与可执行解析 / 配置校验 / apply 决策纯函数 / 线程安全环形日志缓冲 / UTF-8 安全行拼装器），进程托管本体在集成层 `CodingProxy/` 三文件（`CodingProxyProcessController` 仅主线程控制 + epoch 机制作废同步停止后在途的 terminationHandler 回调，规避状态竞态；`CodingProxyConsoleView` + `CodingProxyConsoleWindowController` 仿 WorkLog 报告窗范式，尺寸位置经 `setFrameAutosaveName` 跨启动记忆）。apply 决策核心不变式：**配置未变绝不触碰进程**（用户在控制台手动停止的进程不会被无关「应用」复活）。单元测试 91→123（+32：命令解析各例 / PATH 去重 / 校验分支 / 决策表 / 缓冲裁剪与单行截断 / 汉字跨 chunk 拼合 / v9→v10 迁移与 round-trip），全绿。
- 已知边界（v1 不做，YAGNI）：停止契约 = 直接子进程（`uv run` 在 Unix 上 exec 子进程，SIGTERM 直达；若自定义命令自身再派生孙进程则不保证波及，后续可升级 posix_spawn 进程组击杀）；App 被强杀/崩溃可能遗留子进程（`applicationWillTerminate` 非强保证），下次启动若端口冲突会在控制台日志中自愈式暴露；不做端口占用/已在运行探测、日志不落盘（仅会话内缓冲）。

## v0.1.9 — 2026-09-07（patch · 页签条自绘等间距 + 签名脚本兼容修复）

继 v0.1.8 后的补丁版本：设置窗页签条自绘重构（等间距紧凑排布、不再随窗口拉伸）；`scripts/create-signing-cert.sh` p12 算法兼容修复（macOS `security import` 必现失败）。91 单测全绿，引擎 FSM 零改动。

### 核心改进

- **页签标题等间距排布（净间隙恒为 1.5 字宽），不再随窗口宽度拉伸铺满**。原生 `TabView` 在 macOS 26 会把页签均匀铺满整个工具栏、间隙随窗口变宽而拉大，且无任何样式 API 可控。改为**自绘页签条**（左对齐 `HStack` + 胶囊选中态 + VoiceOver `isSelected`）：相邻标题文字净间隙恒为 1.5 字宽（13pt 系统字体下 ≈ 19.5pt，以「标题两侧各留一半内边距」实现、条内零间距）；测量字体=渲染字体，页签条自然宽度闭式确定。窗口最小宽度相应改为「页签条自然宽度 ∨ 表单可读性下限 560」取大（运行期按页签文案测算，改名/增删页签自动重算）；`SettingsTabSpec` 移除 `icon` 字段（原生 26 样式本就不渲染图标，自绘后各 macOS 版本观感一致）。

### Bug 修复

- **`scripts/create-signing-cert.sh`：p12 打包改用 legacy 算法（3DES + SHA1 MAC）**。macOS `security import`（含 CI runner）不认新版默认 PBES2/SHA-256 MAC 的 p12，报「MAC verification failed during PKCS12 import (wrong password?)」——误导性文案，实为算法不支持；显式指定后导入成功。（v0.1.8 tag 切于该修复合入之前，故随本版本发布）

## v0.1.8 — 2026-09-07（GA · 稳定签名与一键安装）

继 v0.1.7 后的工程基建与体验版本：签名链路升级为稳定自签名证书（TCC 授权一次、跨版本持久，从 ad-hoc 版本升级需最后一次重新授权）并新增 `install.sh` 一键安装/升级；设置窗 7 页签恢复默认平铺、支持自由调节宽高与尺寸/位置跨启动记忆。91 单测全绿，引擎 FSM 零改动。

### 核心改进

- **稳定自签名：TCC 权限授权一次、跨版本持久**。根因修复「升级替换二进制后辅助功能 / 输入监控 / 日历反复要求重新授权」——ad-hoc 签名（`codesign -s -`）的 Designated Requirement 绑定 cdhash，每次构建都变，TCC 视为不同应用；改用稳定自签名代码签名证书（10 年期、codeSigning EKU）后 DR 跨构建稳定，TCC 授权持久。**从 ad-hoc 版本升级需最后一次重新授权**。配套：`scripts/create-signing-cert.sh`（一次性证书创建，OpenSSL/LibreSSL 双兼容 + sudo 信任 + 自动写入 `Makefile.local`）；`Makefile` 签名身份可插拔（`SIGNING_IDENTITY ?= -` + `sinclude Makefile.local`，默认行为不变）；`release.yml` 新增自签名重签步（`MACOS_SELFSIGN_P12` 等 secrets 门控、与 Developer ID 步互斥防双签，公证链路逐字保留）+ `signing.txt` 状态 marker（按产物实签判定）+ Release Note 三分支文案。
- **新增 `install.sh` 一键安装/升级**：下载 Release zip → 防御性去隔离 → 替换 `/Applications/GiveMeABreak.app` → 启动，一条命令完成；版本参数严格校验，`/Applications` 不可写时自动降级 sudo / `~/Applications`。
- **设置窗 7 页签恢复默认平铺（不再折叠进 `>>` 溢出菜单）**。根因：根视图硬编码 `.frame(width: 560)` 钉死内容宽度，第 7 个页签「Agentic AI」加入后图文页签固有宽度超出可用宽度，macOS 26（工具栏式页签条）将放不下的页签折叠为 `>>` 呼出按钮。修复：页签规格（页签 / 标题 / 图标）收敛为唯一事实源 `SettingsTabMetrics`，渲染与宽度测算同源——运行期以系统字体实测文案宽度推算「平铺所需最小内容宽度」，经窗口 `contentMinSize` 硬性锁底；新增 / 改名页签自动重算，同类问题不再复发。页签文案同步精简为双字（通用 / 电源 / 作息 / 音效 / 日志 / 运动 / Agentic AI），窗口更紧凑。
- **设置窗支持自由调节宽高（尺寸归用户所有）**。`styleMask` 增 `.resizable`；整体移除原「内容驱动尺寸」机制（`preferredContentSize` KVO、`didMove` 锚点、顶边锚定重排，净删约 60 行）——内容不再反向改写窗口尺寸，页签内容高于窗口时由 `Form`（grouped 即 ScrollView）内部滚动，与 macOS 系统设置行为一致。承载层由 `NSHostingController` 改为 `NSHostingView`（contentView 语义：视图适配窗口，而非窗口跟随内容 resize）。
- **设置窗尺寸 / 位置跨启动记忆**。经 `setFrameAutosaveName` 原生持久化（随移动 / 缩放自动落盘）；首次打开走「默认尺寸 + 显式居中主屏可见区」（沿用 issue #7 协议），其后恢复上次位置尺寸并做离屏收口（多屏 / 拔屏兜底）。

## v0.1.7 — 2026-09-07（GA · 防止空闲睡眠）

继 v0.1.6 后的功能版本：新增「防止空闲睡眠」——经 IOKit 原生电源断言（与 `caffeinate` 同机制，非子进程）阻止电脑因空闲而熄屏/睡眠，菜单栏勾选项与设置「电源」页双入口、总开关即时生效、状态持久化，**无需任何权限**。配置 schema 升至 v9（容错迁移，旧配置无感），91 单测全绿，引擎 FSM 零改动。

### 核心改进

- **新增「防止空闲睡眠」（等同 `caffeinate -d` / `-d -i`）**。经 IOKit 原生电源断言（`IOPMAssertionCreateWithName`，即 caffeinate / Amphetamine / KeepingYouAwake 的同一机制，**非 spawn 子进程**——App 崩溃时内核自动回收断言，无孤儿进程风险）阻止电脑因空闲而熄屏/睡眠，无需任何权限。两种防护模式：**仅显示器**（= `-d`，display 断言亦隐含阻止系统空闲睡眠）与**显示器 + 系统**（= `-d -i`，显式再叠加系统断言，`pmset -g assertions` 可观测两条）。入口双轨：菜单栏新增勾选项「防止睡眠」（咖啡杯图标，勾选态经 `menuWillOpen` 自愈同步）+ 设置窗口新增独立「电源」页签。**总开关两处均即时生效**（与「开机自启」同语义，共用一条即时通道），防护范围 segmented Picker 随「应用」提交。开关状态持久化（重启后自动恢复），默认关。**与休息 / 工作 / 遮罩模式完全正交**：引擎 FSM 零改动，不影响主动睡眠（合盖、Apple 菜单睡眠、低电量）。

### 工程

- 新增 `IdleSleepGuard`（集成层，按断言维度 diff 增删：模式切换时 display 断言全程不落，零空窗；创建失败记日志、下次 apply 自愈重试；仅主线程调用）。配置 schema 8→9：`DayPlanConfig` 新增正交子结构 `power: PowerSettings`（`preventIdleSleepEnabled: Bool` 默认 false / `mode: IdleSleepGuardMode` 默认 displayOnly），容错解码平滑迁移（旧 v8 缺 `power` 补默认；`mode` 经 String→rawValue 回退，**未知枚举值不炸整份配置**）。`StatusItemController` 继承 NSObject 以承载 `NSMenuDelegate`。总开关采用**单一即时通道**（`AppRoot.setPreventIdleSleep`，`engine.config` 为权威值）：设置窗「应用」时以 live 值覆盖草稿快照——否则设置窗开启期间从菜单栏所做的改动，会被 `show()` 时的旧草稿静默回滚（「开机自启」正是以同样的非 draft 语义规避此类冲突）。单元测试 87→91（+4：默认值 / round-trip / 部分字段与未知 mode 容错 / v8→v9 迁移），全绿。
- 已知后续项：「开机自启」菜单勾选态未纳入同款 `menuWillOpen` 自愈（`SMAppService.status` 为系统调用，超出本次边界）。

## v0.1.6 — 2026-09-04（GA · 遮罩冻结计时）

继 v0.1.5 后的行为语义版本：屏幕遮罩期间工作计时冻结——计划性休息及其小结窗不再打断遮罩，遮罩成为真正的「请勿打扰」。87 单测全绿，纯引擎 FSM 零改动。

### 核心改进

- **屏幕遮罩期间工作计时冻结**。进入遮罩即挂起心跳（复用小结窗的既有冻结机制）：工作累加器停止推进，计划性休息及其小结窗**不会在遮罩中触发**；双击 Esc 退出时先 rebase 对账基点（新增 `LiveGiveMeABreakEngine.handleScreenMaskEnded()`，语义同 `handleWake`）再恢复心跳——遮罩时长不计入工作累加、恢复后首秒不跳秒。「立即休息」（⌃⌥⌘R）仍可主动接管（显式动作优先，遮罩自动让位）；唤醒守卫同步扩展（遮罩中唤醒不抢恢复心跳，suspend/resume 严格配对）。

## v0.1.5 — 2026-09-04（GA · 全局快捷键）

继 v0.1.4 后的修复 + 效率版本：修复「所有快捷键全局按下无反应」，新增零权限全局快捷键 ⌃⌥⌘K（屏幕遮罩）/ ⌃⌥⌘R（立即休息）。87 单测全绿，零回归。

### 核心改进

- **新增全局快捷键 ⌃⌥⌘K（屏幕遮罩）/ ⌃⌥⌘R（立即休息）**。经系统 `RegisterEventHotKey`（Carbon HIToolbox）注册，任意应用前台即时生效、零权限、事件被系统消费不透传给前台应用；菜单项快捷键展示同步更新为真实组合键。选择 ⌃⌥⌘ 修饰以最小化与常见应用内快捷键的冲突面。
- **屏幕遮罩移除「双击 Esc 退出」画面提示**：退出方式不变（双击 Esc），仅移除画面上的提示文字以保持遮罩画面极简。

### Bug 修复

- **修复「所有快捷键全局按下无反应」**。根因有二：(1) 状态栏菜单项的裸字母快捷键为 macOS 原生「仅菜单展开时生效」行为，此前菜单展示易被误读为全局热键；(2) ⌃⌘Q 劫持经事件 tap 探针（`CGGetEventTapList`）证实**未安装**——输入监控权限未授予当前二进制身份，Ad-hoc 签名应用升级替换二进制后 TCC 授权失效。修复：即时动作改由零权限全局热键承载（见上）；锁屏劫持启动时输出权限预检日志提升可观测性；授权/重新授权与三层快捷键生效范围说明补入 README「快捷键」一节。

## v0.1.4 — 2026-09-04（GA · 屏幕遮罩体验焕新）

继 v0.1.3 后的体验打磨版本：手动屏幕遮罩文案与氛围动画焕新，与「给键盘买冰棍」的趣味叙事相互呼应。沿「最小干预」原则，纯前端视觉变更，无新依赖、零回归（87 单测全绿）。

### 核心改进

- **屏幕遮罩文案与氛围动画焕新**：主文案改为「键盘说它有点烫，我去给它买个冰棍，两分钟后见~」，并新增同调性的简约氛围动画——纯 Shape 绘制的冰棍轻浮动/微摆/光晕呼吸/融滴坠落 + 雪花缓升「凉意」，全部由单一 `TimelineView(.animation)` 以时间为纯函数驱动（确定性、零动画状态管理），系统开启「减弱动态效果」时整体暂停为静帧；文案保持静止保证可读性。

## v0.1.3 — 2026-09-04（GA · 主动屏幕遮罩 · Agentic AI 页签预留）

继 v0.1.2 后的特性版本：新增用户随时可手动触发的全屏遮罩（可占用系统锁屏快捷键），并为设置窗口新增 Agentic AI 配置页签（功能预留）。沿「最小干预、循证工程」原则，无新依赖、零回归（87 单测全绿）。

### 核心改进

- **新增主动屏幕遮罩（手动「屏幕遮罩」）**。在到点强制休息之外，新增用户随时可触发的全屏遮罩：菜单「屏幕遮罩」或占用系统锁屏快捷键 Control+Command+Q（拦截后不真正锁屏，改为进入本 App 遮罩）触发，电脑后台照常运行，仅阻断新的鼠标/键盘输入；双击 Esc 退出。与既有工作/休息调度引擎（FSM）**零耦合**——不读写引擎状态，仅在计划性休息触发时自动让位（休息优先）。快捷键拦截需「输入监控」权限，未授权时静默降级为仅菜单可用（不阻塞、日志可观测）。
- **设置窗口新增「Agentic AI」页签（Claude Code 配置 · 功能预留）**。为后续引入 Agentic AI 相关功能预留配置入口，与既有「每功能域一页签」结构一致：
  - **Claude Code 可执行文件路径**：可键入 / 浏览选择自定义路径，非可执行时行内橙色警示（非阻塞）；「使用系统 Claude Code」一键复位为**自动从系统 PATH 探测**（推荐）。
  - **Claude 设置快捷打开**：split-button「在 X 中打开」一键打开 `~/.claude/settings.json`，右侧下拉自动探测已安装编辑器（VS Code / Cursor / Zed / Sublime / Xcode 等，含图标）并**持久化所选编辑器**,另有「系统默认」与「其他应用…」;文件不存在时在访达中定位 `~/.claude`。
  - 事实性适配：本 App **不打包 Claude Code**,故文案采「PATH 自动探测」而非上游「bundled version」措辞;**当前仅落地 UI + 持久化,未接入任何 Claude Code 实际调用**。

### 工程

- 新增 `LockShortcutMonitor`（`CGEventTap` 于 HID 层拦截 Control+Command+Q，`.headInsertEventTap` + `.defaultTap`，权限经 `CGPreflightListenEventAccess`/`CGRequestListenEventAccess` 查询/申请）与 `ScreenMaskController`/`ScreenMaskContentView`（复用既有 `OverlayPanel`，独立实现、不修改 `LiveOverlayController`）。二者均为纯新增文件，零改动引擎/既有遮罩代码；`AppRoot`/`StatusItemController` 增量接线。Info.plist 新增 `NSInputMonitoringUsageDescription`。
- 配置 schema 7→8：`DayPlanConfig` 新增正交子结构 `agent: AgentSettings`（`claudeExecutablePath` / `claudeSettingsEditorBundleId`,默认全 `nil`）,容错解码平滑迁移（旧 v7 缺 `agent` 补默认、子字段缺失补 `nil`、显式值尊重）。子结构仅纯 Foundation 字段落于 Engine 层、引擎携带即忽略;AppKit 编辑器探测/打开逻辑正交隔离于集成层新 `ClaudeSettingsLauncher`。
- 单元测试 83→87（+4：v7→v8 迁移补默认 / `agent` 往返 / `AgentSettings` 部分字段容错 / 默认全 nil），全绿 < 1s。无新依赖、无回归。

### 文档

- LICENSE 版权人统一为 ThreeFish-AI（与 README 及代码仓库主体对齐）；README 页脚 License 区块精简为内联一行署名并直接跳转至 `./LICENSE`。

### 说明

- macOS 与 Windows 产物**均未做代码签名 / 公证**（与既往版本一致），首次启动需手动放行（详见 [README](./README.md)）；代码签名 / 公证将在后续版本补齐。

## v0.1.2 — 2026-07-04（GA · UI/UX 深度优化 · 菜单分组 / 运动类型注册表 / 跳过残留修复）

继 v0.1.1 后的体验打磨版本：状态栏菜单重排、运动类型可个性化持久、运动补录时间自动贴合休息区间，并修复一处「跳过看似复用上次记录」的 SwiftUI 状态残留 bug。沿「最小干预、循证工程」原则，无新依赖、零回归（83 单测全绿、复制 / 导出 Markdown 与 v0.1.1 逐字节一致）。

### 核心改进

- **状态栏菜单：文案统一 2~4 字 + 按动作分组**。过长文案精简（`补录工作日志`→`补录工作`、`补录运动记录`→`补录运动`），全菜单分 5 段（分隔线划分）：**立即休息** ┃ **查看**（工作日志·综合报告）┃ **录入**（补录工作·补录运动）┃ **偏好**（设置·开机自启）┃ **退出**。扫读更快、语义边界清晰。
- **运动类型注册表（可持久增删 + 自动记住）**。运动类型由硬编码升级为配置注册表——在设置「运动记录」页集中增删；录入时经「其他…」临时输入的自定义类型**保存即自动记住**（去重、保序），下次直接挑选，无需重输。
- **运动补录时间自动定位到休息区间**。「补录运动」默认时段由「上一条记录的结束时刻」改为 **`[现在 − 休息时长, 现在]`**——贴合「补刚才那段休息做的运动」的真实语义，不再停留在上次记录。
- **运动提示窗超时可配**。新增 `exercisePromptTimeoutSeconds`（默认 180s，可设「永久等待」），与工作日志小结窗对称；原硬编码 180s 兜底保留为默认值。

### Bug 修复

- **修复「跳过 / 重开窗复用上次输入」**：四个提示 / 补录窗 + 报告 / 设置窗控制器在稳定 `NSHostingController` 上反复替换 `rootView`，致 SwiftUI `@State` 跨弹窗残留——「输入文字 → 跳过」后下次弹窗文字仍在（视觉 = 复用，非数据复用，故持久层无可疑写入）。改为每次重建 hosting 控制器，`@State` 归零，跳过真正「忽略」。已记入 [issue #9](./.agents/issue.md)。

### 工程

- 配置 schema 6→7：`exerciseTypes`（默认 `["胯下击掌","提膝击掌","深蹲","俯卧撑"]`）/ `exercisePromptTimeoutSeconds`（默认 180s），容错解码平滑迁移（缺字段补默认、显式空数组尊重）。
- 抽纯函数 `exerciseBackfillDefaultRange`（`[now − restDuration, now]`，负值裁剪）与 `appendedExerciseTypes`（去重 / 保序 / 去空白，无新增返回 nil 跳过写盘）；落库侧据此「写 config + 热更新引擎」。
- 单元测试 77→83（+6：v6→v7 迁移 / exerciseTypes 往返 / 补录默认时段 / 类型追加纯函数），全绿 < 1s。

### 说明

- macOS 与 Windows 产物**均未做代码签名 / 公证**（与 v0.1.0 / v0.1.1 一致），首次启动需手动放行（详见 [README](./README.md)）；代码签名 / 公证将在后续版本补齐。

## v0.1.1 — 2026-06-30（GA · 运动记录 + 综合报告 · 工作日志可编辑 + 原生阅读器）

继 v0.1.0 MVP 正式发布后的首个特性版本，沿「认知闭合 × 身体留痕」双主线演进：休息自然结束时随手录入微运动，与工作日志一并汇入 周 / 月 / 季 / 年 综合报告；同时工作日志窗口由只读等宽 Markdown 升级为原生层级化阅读器，并支持逐条编辑 / 删除。两处改动均严守单一事实源，复制 / 导出 Markdown 与 v0.1.0 逐字节一致。

### 核心能力

- **运动记录（休息里的身体留痕）**：休息**自然结束**时弹轻量输入框，记录这段休息里做的微运动（胯下击掌 / 提膝击掌 / 深蹲 / 俯卧撑，或自定义），每条含「运动时段 + 若干（类型 × 数量）」。与进入休息前的工作日志小结窗对称：工作日志完成「认知闭合」，运动记录把休息里的微运动也留痕，日积月累汇入综合报告。永不阻塞引擎：回车「记录完成」/ Esc 或关窗跳过 / 到点自动放行（固定 180s 兜底）；连续 3 次跳过自动静默一轮；提前结束（Esc）与被会议、下班打断均不弹；可在设置整体关闭。
- **综合报告（周 / 月 / 季 / 年）**：运动记录与工作日志一并汇入新的「综合报告」窗口，按**周 / 月 / 季 / 年**原生层级呈现——工作回顾（Top N + 周期分布，只读，逐条编辑仍归「工作日志」窗）与运动概览（按类型聚合 + 明细，周 / 月支持编辑 / 删除，季 / 年按月汇总）。一键复制与导出 Markdown（`2026-W26.md` / `2026-06.md` / `2026-Q2.md` / `2026.md`）。
- **工作日志：原生阅读器 + 逐条编辑**：报告窗口由等宽 Markdown 原貌升级为原生 SwiftUI 层级渲染——标题 / 元数据、Top 3 排名（序号徽标 + 等宽时长）、完成清单 / 按日·按周分组、月度汇总（原生 `Grid`）、待续·下一步，深色优先、层级与可读性显著提升；明细行支持**编辑**（起止时段 / 专注时长 / 小结 / 下一步）与**删除**——悬停内联按钮 + 右键菜单常驻（含「复制本条」）+ 删除二次确认，报告随结构化记录自动重算。补录与编辑共用同一表单。

### 工程

- 引擎正交扩展「运动记录」域：`ExerciseEntry` / `ExerciseSet` 容错解码模型、`ExerciseStore`（原子写 + 容错读）、`CombinedReport`（纯函数聚合 周 / 月 / 季 / 年）；抽出 `ReportDateKeys`（day / week / month / quarter / year，SSOT，工作日志报告行为零回归）；引擎新增 `onPostBreak`，仅在休息自然结束（`.resting → .working`）触发。配置 schema 5→6（`exerciseLogEnabled`，缺省 true 平滑迁移）。
- 工作日志重构为「单一事实源」：抽出结构化 `WorkLogReportModel` + `buildWorkLogReportModel` 作为聚合唯一来源，由原生阅读器与导出 Markdown 两渲染器共用；`renderWorkLogReport` 降为序列化器，复制 / 导出与 v0.1.0 **逐字节一致**（golden 快照守护，零回归）；`WorkLogStore` 新增按 `id` 的 `update` / `delete`。
- 单元测试 54→77（含运动记录 / 综合报告 golden + `onPostBreak` 不变量），全绿 < 1s。

### 说明

- 菜单栏新增「综合报告…」「补录运动记录…」两项；设置新增「运动记录」页签（开关）。
- macOS 与 Windows 产物**均未做代码签名 / 公证**（与 v0.1.0 一致），首次启动需手动放行（详见 [README](./README.md)）；代码签名 / 公证将在后续版本补齐。

## v0.1.0 — 2026-06-27（GA · MVP 正式发布）

首个正式发布（GA）：一款功能完备的 macOS 菜单栏强制作息应用，整合作息节律、全屏遮罩、休息音效、Google 日历门控、工作日志与图形化设置。本版聚合了此前迭代的全部能力，作为 MVP 的正式基线。

### 核心能力

- **强制排版作息**：自定义工作时段（每日重复、可跨午夜）内累计工作 N 分钟（默认 50）即触发强制休息 M 分钟（默认 10）；AFK 阈值（默认 3 分钟）在离座时暂停累计，避免人不在时误触发。
- **全屏遮罩**：休息时遮罩所有显示器（`CGShieldingWindowLevel`，压过菜单栏 / Dock / 全屏），Esc 二次确认方可提前结束（软强制，留逃生阀）；多屏热插拔自适应。
- **休息音效（取代 / 回退链路）**：设置「休息音乐」后循环播放本地音频（mp3/m4a/aac/wav/flac 等）取代内置粉噪音，文件缺失或格式不支持时自动回退；音频仅以本地路径引用、不打包不分发。粉噪音由 AVAudioEngine 实时合成，零音频文件、可靠且不依赖外部播放器。可叠加联动 QQ 音乐（经系统媒体键控制，需辅助功能权限，不可用则静默跳过）。
- **Google 日历门控**：会议计为工作时间，休息推迟至会议结束（EventKit 复用 OS 登录态，无 OAuth 代码）。
- **工作日志（认知闭合）**：自然休息前花 30 秒写下「刚完成什么 + 下一步」，永不阻塞休息（回车提交 / Esc 或关窗跳过 / 到点自动放行，默认 3 分钟可调，或开启「永久等待」）；可整体关闭，「立即休息」不弹。记录落盘，菜单「工作日志…」生成今日 / 本周 / 本月报告（Markdown，可复制 / 导出）；并支持「补录工作日志」回填漏记时段。循证设计（Leroy 注意力残留 / Stubblebine 插值日记 / Fogg 行为模型 / JITAI）。
- **图形化设置（四页签）**：通用（开机自启 + 关于）/ 作息（工作时段 + 节律）/ 休息音效 / 工作日志；草稿—应用一次性提交、恢复默认二次确认、窗口按当前页签内容自适应（免滚动 / 留白）。即时保存 + 引擎热更新。
- **健壮性**：AFK / 睡眠暂停累加（不回灌）、崩溃恢复 fast-forward、状态持久化；配置 schema v5（含 `restMusicPath` / `workLogPromptTimeoutSeconds`），旧配置容错解码平滑迁移。

### 工程

- 三模块正交分解：`GiveMeABreakEngine`（纯 FSM + evaluate 纯函数）/ `GiveMeABreakIntegrations`（AppKit / EventKit / CGEvent）/ `GiveMeABreak`（@main 壳）；54 单测全绿（<1s，CLT 自建运行器）。
- 跨平台 SSOT：`shared/` 黄金 fixture + config / work-log schema；Windows 端 C#/.NET 8 WPF 平行移植，CI 多平台一次发布 macOS + Windows 双 asset。

### 说明

- 本 GA 标志 MVP 功能完备；macOS 与 Windows 产物**均未做代码签名 / 公证**，首次启动需手动放行（详见 [README](./README.md)）。代码签名 / 公证与 Windows 真机验收将在后续版本补齐。
