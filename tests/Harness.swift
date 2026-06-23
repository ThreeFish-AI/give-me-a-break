import Foundation

// MARK: - 轻量测试运行器（CLT 无 XCTest/Swift Testing，自建极简断言）

/// 注：Command Line Tools 不含 XCTest / Swift Testing 宏插件，故采用自建运行器。
/// 语义对齐 XCTest：test(name) 分组，expect/expectEqual 断言，退出码反映成败。

var testPassed = 0
var testFailed = 0
private var currentTest = "(未命名)"

func test(_ name: String, _ body: () -> Void) {
    currentTest = name
    let before = testFailed
    body()
    if testFailed == before {
        testPassed += 1
        print("  ✓ \(name)")
    } else {
        print("  ↑ 失败用例：\(name)")
    }
}

@discardableResult
func expect(_ cond: @autoclosure () -> Bool, _ msg: String = "",
            file: String = #fileID, line: Int = #line) -> Bool {
    if cond() { return true }
    testFailed += 1
    print("  ✗ FAIL [\(currentTest)] \(msg)  (\(file):\(line))")
    return false
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "",
                               file: String = #fileID, line: Int = #line) {
    if a != b {
        testFailed += 1
        print("  ✗ FAIL [\(currentTest)] \(msg): 期望 \(b)，实际 \(a)  (\(file):\(line))")
    }
}

func approx(_ a: TimeInterval, _ b: TimeInterval, _ eps: TimeInterval = 2) -> Bool {
    abs(a - b) < eps
}
