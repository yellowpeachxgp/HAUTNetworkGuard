import Cocoa
import Darwin

if SingleInstanceGuard.anotherInstanceExists() {
    fputs("HAUTNetworkGuard 已在运行，当前启动请求退出。\n", stderr)
    exit(EX_UNAVAILABLE)
}

// 创建应用实例
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 启动应用
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
