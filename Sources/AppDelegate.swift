import Cocoa

/// 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("\(AppConfig.appName) v\(AppConfig.version) 启动")

        // 检查是否首次运行或未配置
        if !AppConfig.shared.hasConfigured {
            showFirstRunSettings()
        } else {
            startApp()
        }
    }

    private func showFirstRunSettings() {
        settingsWindow = SettingsWindowController()
        settingsWindow?.onSave = { [weak self] in
            self?.startApp()
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startApp() {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("\(AppConfig.appName) 退出")
    }
}
