import Foundation

// 测试入口（top-level main.swift）。make test → swift run GiveMeABreakTests

print("⏱  GiveMeABreakEngine 单元测试\n")

runEvaluateCases()
print("")
runEngineTransitionCases()
print("")
runEngineWiringCases()
print("")
runConfigStoreCases()

print("\n──────────────────────────────")
print("结果：\(testPassed) 通过，\(testFailed) 失败")
print("──────────────────────────────")

if testFailed > 0 {
    exit(1)
}
