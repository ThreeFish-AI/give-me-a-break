// swift-tools-version: 5.10
import PackageDescription

/// Give me a break — macOS 菜单栏强制作息应用
///
/// 三目标正交分解（遵循 AGENTS.md「Orthogonal Decomposition」）：
/// - `GiveMeABreakEngine`：纯 Foundation 调度核心（FSM + evaluate 纯函数），零 AppKit 依赖，可单元测试。
/// - `GiveMeABreakIntegrations`：AppKit/EventKit/CGEvent 集成层（三大 controller + 心跳 + 持久化 + 菜单栏）。
/// - `GiveMeABreak`：可执行壳（@main + AppDelegate 生命周期），薄层，仅装配。
let package = Package(
    name: "GiveMeABreak",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GiveMeABreakEngine",
            path: "Sources/GiveMeABreakEngine"
        ),
        .target(
            name: "GiveMeABreakIntegrations",
            dependencies: ["GiveMeABreakEngine"],
            path: "Sources/GiveMeABreakIntegrations"
        ),
        .executableTarget(
            name: "GiveMeABreak",
            dependencies: ["GiveMeABreakIntegrations"],
            path: "Sources/GiveMeABreak"
        ),
        // 测试运行器（可执行目标）。注：Command Line Tools 不含 XCTest/Swift Testing，
        // 故采用 tests/ 下自建的极简断言运行器（expect/test + 退出码），make test 经 swift run 驱动。
        .executableTarget(
            name: "GiveMeABreakTests",
            dependencies: ["GiveMeABreakEngine"],
            path: "tests"
        ),
    ]
)
