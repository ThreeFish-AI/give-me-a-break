import Foundation
import GiveMeABreakEngine

// Coding Proxy 纯逻辑用例：命令解析 / 路径与 PATH / 校验 / apply 决策 / 日志缓冲与行拼装。
// 进程托管本体（CodingProxyProcessController）依赖 AppKit 侧 Foundation.Process，不属本测试 target。

func runCodingProxyCases() {
    print("▸ CodingProxy")

    let home = "/Users/tester"

    // MARK: parseCommandLine

    test("parseCommandLine：简单多参数命令") {
        let parsed = parseCommandLine("uv run coding-proxy start", home: home)
        expectEqual(parsed!.executable, "uv", "可执行段应为 uv")
        expectEqual(parsed!.arguments, ["run", "coding-proxy", "start"], "参数应按空白切分")
    }

    test("parseCommandLine：双引号包夹含空格参数") {
        let parsed = parseCommandLine("/bin/sh -c 'echo \"hello world\"'", home: home)
        expectEqual(parsed!.executable, "/bin/sh", "可执行段应为 /bin/sh")
        expectEqual(parsed!.arguments, ["-c", "echo \"hello world\""], "单引号内的双引号与空格应保持原样")
    }

    test("parseCommandLine：单引号包夹含空格路径") {
        let parsed = parseCommandLine("/bin/cat '/tmp/my file.txt'", home: home)
        expectEqual(parsed!.arguments, ["/tmp/my file.txt"], "单引号内空格不应切分")
    }

    test("parseCommandLine：多空白与 Tab 分隔") {
        let parsed = parseCommandLine("  uv \t run   coding-proxy  ", home: home)
        expectEqual(parsed!.arguments, ["run", "coding-proxy"], "多空白应规整为单分隔")
    }

    test("parseCommandLine：空串 / 纯空白 → nil") {
        expect(parseCommandLine("", home: home) == nil, "空串应返回 nil")
        expect(parseCommandLine("   \t  ", home: home) == nil, "纯空白应返回 nil")
    }

    test("parseCommandLine：引号不闭合 → nil") {
        expect(parseCommandLine("uv run 'coding-proxy", home: home) == nil, "未闭合单引号应返回 nil")
        expect(parseCommandLine("uv \"run start", home: home) == nil, "未闭合双引号应返回 nil")
    }

    test("parseCommandLine：空引号参数成独立 token") {
        let parsed = parseCommandLine("cmd \"\" x", home: home)
        expectEqual(parsed!.arguments, ["", "x"], "空引号应保留为空参数")
    }

    test("parseCommandLine：可执行段 ~ 前缀展开") {
        let parsed = parseCommandLine("~/bin/tool --flag", home: home)
        expectEqual(parsed!.executable, "\(home)/bin/tool", "~ 前缀应展开为 home")
        expectEqual(parsed!.arguments, ["--flag"], "参数不做 ~ 展开")
    }

    test("parseCommandLine：Unicode 路径") {
        let parsed = parseCommandLine("/bin/echo 你好 世界", home: home)
        expectEqual(parsed!.arguments, ["你好", "世界"], "Unicode token 应完整切分")
    }

    // MARK: expandLeadingTilde

    test("expandLeadingTilde：~ / ~/x 展开，其余原样") {
        expectEqual(expandLeadingTilde("~", home: home), home, "单独 ~ 应展开为 home")
        expectEqual(expandLeadingTilde("~/Documents/x", home: home), "\(home)/Documents/x", "~/ 前缀应展开")
        expectEqual(expandLeadingTilde("/abs/path", home: home), "/abs/path", "绝对路径应原样")
        expectEqual(expandLeadingTilde("/x~/y", home: home), "/x~/y", "非前缀 ~ 应原样")
    }

    // MARK: augmentedPathEnvironment

    test("augmentedPathEnvironment：前置用户级与 Homebrew bin，保序去重") {
        let current = "/usr/bin:/bin:/opt/homebrew/bin"
        let augmented = augmentedPathEnvironment(currentPath: current, home: home)
        let parts = augmented.split(separator: ":").map(String.init)
        expectEqual(parts.count, 6, "与原 PATH 重复的 /opt/homebrew/bin 应去重（4 增强 + 3 原有 − 1 重复）")
        expectEqual(parts[0], "\(home)/.local/bin", "首个应为用户 uv 安装位 ~/.local/bin")
        expectEqual(parts[1], "\(home)/bin", "次选应为 ~/bin")
        expectEqual(parts[2], "/opt/homebrew/bin", "Homebrew Apple Silicon 路径应前置")
        expectEqual(parts.last, "/bin", "原 PATH 顺序应追加在后")
    }

    test("augmentedPathEnvironment：currentPath 为 nil 也能产出") {
        let augmented = augmentedPathEnvironment(currentPath: nil, home: home)
        expect(!augmented.isEmpty, "无原 PATH 时也应至少包含四个增强目录")
    }

    // MARK: resolveExecutablePath

    test("resolveExecutablePath：裸名按 PATH 首个命中") {
        let parsed = ParsedCommandLine(executable: "uv", arguments: ["run"])
        let executables: Set<String> = ["/opt/homebrew/bin/uv"]
        let resolved = resolveExecutablePath(parsed, pathEnvironment: "/usr/bin:/opt/homebrew/bin") {
            executables.contains($0)
        }
        expectEqual(resolved, "/opt/homebrew/bin/uv", "应命中 PATH 中首个存在 uv 的目录")
    }

    test("resolveExecutablePath：全不命中 → nil") {
        let parsed = ParsedCommandLine(executable: "no-such-tool", arguments: [])
        expect(resolveExecutablePath(parsed, pathEnvironment: "/usr/bin:/bin") { _ in false } == nil,
               "PATH 无命中应返回 nil")
    }

    test("resolveExecutablePath：含 / 视为路径原样返回") {
        let parsed = ParsedCommandLine(executable: "./local/tool", arguments: [])
        expectEqual(resolveExecutablePath(parsed, pathEnvironment: "/usr/bin") { _ in false }, "./local/tool",
                    "相对路径应原样返回（存在性交由校验器）")
    }

    // MARK: validateCodingProxySettings

    // 内存文件系统：paths → (exists, isDirectory)；executables 集合单独判定。
    func makeFS(paths: [String: (exists: Bool, isDir: Bool)], executables: Set<String> = [])
        -> (fileExists: (String) -> Bool, isDirectory: (String) -> Bool, isExecutableFile: (String) -> Bool) {
        return (
            { paths[$0]?.exists == true },
            { paths[$0]?.isDir == true },
            { executables.contains($0) }
        )
    }
    let pathEnv = augmentedPathEnvironment(currentPath: "/usr/bin:/bin", home: home)

    func validate(_ s: CodingProxySettings,
                  paths: [String: (exists: Bool, isDir: Bool)],
                  executables: Set<String> = []) -> CodingProxyValidation {
        let fs = makeFS(paths: paths, executables: executables)
        return validateCodingProxySettings(s, home: home, pathEnvironment: pathEnv,
                                           fileExists: fs.fileExists,
                                           isDirectory: fs.isDirectory,
                                           isExecutableFile: fs.isExecutableFile)
    }

    test("validate：各失败分支") {
        expectEqual(validate(CodingProxySettings(), paths: [:]), .emptyWorkingDirectory, "空目录应报未配置")
        expectEqual(validate(CodingProxySettings(workingDirectory: "/nope"),
                             paths: ["/Users/tester/proj": (true, true)]),
                    .workingDirectoryNotFound, "目录不存在应报不存在")
        expectEqual(validate(CodingProxySettings(workingDirectory: "/Users/tester/file.txt"),
                             paths: ["/Users/tester/file.txt": (true, false)]),
                    .workingDirectoryNotDirectory, "路径是文件应报非文件夹")
        expectEqual(validate(CodingProxySettings(workingDirectory: "~/proj", launchCommand: "  "),
                             paths: ["/Users/tester/proj": (true, true)]),
                    .emptyCommand, "空命令应报未配置")
        expectEqual(validate(CodingProxySettings(workingDirectory: "~/proj", launchCommand: "uv 'run"),
                             paths: ["/Users/tester/proj": (true, true)]),
                    .commandUnparsable, "引号不闭合应报不可解析")
        expectEqual(validate(CodingProxySettings(workingDirectory: "~/proj", launchCommand: "no-such-tool x"),
                             paths: ["/Users/tester/proj": (true, true)]),
                    .executableNotFound, "可执行未命中应报未找到")
    }

    test("validate：完整有效配置（~ 目录展开 + PATH 命中）") {
        let s = CodingProxySettings(autoStartEnabled: true, workingDirectory: "~/proj")
        expectEqual(validate(s, paths: ["/Users/tester/proj": (true, true)],
                             executables: ["/opt/homebrew/bin/uv"]), .ok, "目录与命令均有效应返回 ok")
    }

    // MARK: codingProxyTransition

    test("transition：previous == new → none（无关 apply 不复活手动停止的进程）") {
        let s = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/p")
        expectEqual(codingProxyTransition(previous: s, new: s, newValidation: .ok, isRunning: false), .none,
                    "配置未变绝不触碰进程")
    }

    test("transition：App 启动首次 apply（previous == nil）") {
        let on = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/p")
        expectEqual(codingProxyTransition(previous: nil, new: on, newValidation: .ok, isRunning: false), .start,
                    "开启 + 有效 + 未运行 → 启动")
        let off = CodingProxySettings(autoStartEnabled: false, workingDirectory: "/p")
        expectEqual(codingProxyTransition(previous: nil, new: off, newValidation: .ok, isRunning: false), .none,
                    "未开启 → 不启动")
        expectEqual(codingProxyTransition(previous: nil, new: on, newValidation: .ok, isRunning: true), .none,
                    "已在运行（理论不发生）→ 不重启")
    }

    test("transition：关闭开关 → 停止运行中的进程") {
        let old = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/p")
        let new = CodingProxySettings(autoStartEnabled: false, workingDirectory: "/p")
        expectEqual(codingProxyTransition(previous: old, new: new, newValidation: .ok, isRunning: true), .stop,
                    "关开关且在运行 → 停止")
        expectEqual(codingProxyTransition(previous: old, new: new, newValidation: .ok, isRunning: false), .none,
                    "关开关且未运行 → 无动作")
    }

    test("transition：目录/命令变化且在运行 → restart；仅开关翻转不打扰") {
        let base = CodingProxySettings(autoStartEnabled: false, workingDirectory: "/p")
        let newDir = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/q")
        expectEqual(codingProxyTransition(previous: base, new: newDir, newValidation: .ok, isRunning: true), .restart,
                    "目录变化且运行中 → 重启")
        let newCmd = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/p", launchCommand: "uv run x")
        expectEqual(codingProxyTransition(previous: base, new: newCmd, newValidation: .ok, isRunning: true), .restart,
                    "命令变化且运行中 → 重启")
        let onlyToggle = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/p")
        expectEqual(codingProxyTransition(previous: base, new: onlyToggle, newValidation: .ok, isRunning: true), .none,
                    "仅开关翻转且运行中 → 不打扰")
    }

    test("transition：开启 + 有效 + 未运行 → start（含修复无效配置后的首次 apply）") {
        let prevInvalid = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/bad")
        let fixed = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/p")
        expectEqual(codingProxyTransition(previous: prevInvalid, new: fixed, newValidation: .ok, isRunning: false),
                    .start, "从无效配置修复为有效且开启 → 启动")
    }

    test("transition：新配置无效 → none（不杀正在运行的旧进程）") {
        let old = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/p")
        let broken = CodingProxySettings(autoStartEnabled: true, workingDirectory: "/nope")
        expectEqual(codingProxyTransition(previous: old, new: broken, newValidation: .workingDirectoryNotFound, isRunning: true),
                    .none, "新配置无效不应杀死旧进程")
    }

    // MARK: CodingProxyLogBuffer

    test("CodingProxyLogBuffer：超容量裁最旧，snapshot 为拷贝") {
        let buffer = CodingProxyLogBuffer(capacity: 3)
        for i in 1...5 { buffer.append(.stdout, "line\(i)") }
        let snap = buffer.snapshot
        expectEqual(snap.map(\.text), ["line3", "line4", "line5"], "超出容量应保留最新 3 行")
        expectEqual(buffer.count, 3, "count 应反映裁剪后行数")
        buffer.append(.stderr, "new")
        expectEqual(snap.count, 3, "先取的 snapshot 不应受后续 append 影响（深拷贝）")
        expectEqual(buffer.snapshot.last?.stream, .stderr, "新行流类型应正确")
    }

    test("CodingProxyLogBuffer：单行超长物理截断并标记") {
        let buffer = CodingProxyLogBuffer(capacity: 10, maxLineLength: 10)
        buffer.append(.stdout, String(repeating: "a", count: 500))
        let text = buffer.snapshot[0].text
        expect(text.hasSuffix("…（已截断）"), "超长行应带截断标记")
        expect(text.count <= 10 + " …（已截断）".count, "截断后不应超过上限 + 标记长度")
        buffer.clear()
        expectEqual(buffer.count, 0, "clear 后应为空")
    }

    // MARK: CodingProxyLogAssembler

    test("CodingProxyLogAssembler：\\n 切行 / CRLF 剥 \\r / 多行 chunk") {
        let asm = CodingProxyLogAssembler()
        expectEqual(asm.append(Data("a\nb\r\nc\n".utf8)), ["a", "b", "c"], "CRLF 行尾应剥 \\r")
        expect(asm.flushTail() == nil, "全部换行结束应无残留")
    }

    test("CodingProxyLogAssembler：无尾换行的半行经 flushTail 冲出") {
        let asm = CodingProxyLogAssembler()
        expectEqual(asm.append(Data("complete\npartial".utf8)), ["complete"], "半行不出")
        expectEqual(asm.flushTail(), "partial", "EOF 应冲出残留半行")
        expect(asm.flushTail() == nil, "二次 flush 应无残留")
    }

    test("CodingProxyLogAssembler：UTF-8 汉字跨 chunk 劈开再拼合（无替换字符）") {
        let asm = CodingProxyLogAssembler()
        let bytes = Array("启动完成：代理已就绪\n".utf8)
        // 劈在多字节序列中间：前 6 字节（含半个「成」字）+ 余下全部
        let first = Data(bytes[0..<6])
        let second = Data(bytes[6...])
        expectEqual(asm.append(first), [], "劈开的多字节序列不应产出残行")
        let lines = asm.append(second)
        expectEqual(lines, ["启动完成：代理已就绪"], "跨 chunk 汉字应完整拼合，不出现 U+FFFD")
    }

    test("CodingProxyLogAssembler：空 chunk 无副作用") {
        let asm = CodingProxyLogAssembler()
        expectEqual(asm.append(Data()), [], "空 Data 不产出行")
        expectEqual(asm.append(Data("x\n".utf8)), ["x"], "后续正常切行")
    }
}
