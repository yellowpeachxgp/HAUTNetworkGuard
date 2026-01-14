import Cocoa

// 创建应用实例
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 启动应用
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
