import Cocoa
import UserNotifications

/// 菜单栏控制器
class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var detailMenuItem: NSMenuItem!

    private let api = SrunAPI()
    private var checkTimer: Timer?
    private var currentStatus: NetworkStatus = .checking
    private var checkInterval: TimeInterval = 3

    // 状态图标
    private let onlineIcon = "wifi"
    private let offlineIcon = "wifi.slash"
    private let checkingIcon = "arrow.triangle.2.circlepath"

    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
        requestNotificationPermission()
        startMonitoring()
    }
}

// MARK: - 设置
extension StatusBarController {
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: checkingIcon,
                accessibilityDescription: "网络状态"
            )
        }
    }
}

// MARK: - 菜单设置
extension StatusBarController {
    private func setupMenu() {
        menu = NSMenu()

        // 状态显示
        statusMenuItem = NSMenuItem(title: "状态: 检测中...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // 详细信息
        detailMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detailMenuItem.isEnabled = false
        menu.addItem(detailMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 立即登录
        let loginItem = NSMenuItem(
            title: "立即登录",
            action: #selector(loginAction),
            keyEquivalent: "l"
        )
        loginItem.target = self
        menu.addItem(loginItem)

        // 注销登录
        let logoutItem = NSMenuItem(
            title: "注销登录",
            action: #selector(logoutAction),
            keyEquivalent: "o"
        )
        logoutItem.target = self
        menu.addItem(logoutItem)

        menu.addItem(NSMenuItem.separator())

        // 立即检测
        let checkItem = NSMenuItem(
            title: "立即检测",
            action: #selector(checkNowAction),
            keyEquivalent: "r"
        )
        checkItem.target = self
        menu.addItem(checkItem)

        menu.addItem(NSMenuItem.separator())

        // 账号设置
        let settingsItem = NSMenuItem(
            title: "账号设置...",
            action: #selector(settingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 关于
        let aboutItem = NSMenuItem(
            title: "关于",
            action: #selector(aboutAction),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }
}

// MARK: - 监控逻辑
extension StatusBarController {
    private func startMonitoring() {
        checkStatus()
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkStatus()
        }
    }

    private func checkStatus() {
        api.checkStatus { [weak self] status in
            DispatchQueue.main.async {
                self?.handleStatusChange(status)
            }
        }
    }
}

// MARK: - 状态处理
extension StatusBarController {
    private func handleStatusChange(_ newStatus: NetworkStatus) {
        let wasOnline = currentStatus.isOnline
        currentStatus = newStatus

        updateUI()

        // 每次检测到离线状态都尝试自动登录
        if !newStatus.isOnline {
            // 只在首次检测到掉线时发送通知
            if wasOnline {
                Logger.log("检测到掉线，尝试自动重连...")
                sendNotification(title: "网络已断开", body: "正在尝试自动重连...")
            } else {
                Logger.log("仍处于离线状态，继续尝试登录...")
            }
            performAutoLogin()
        }
    }

    private func updateUI() {
        let iconName: String
        let statusText: String

        switch currentStatus {
        case .online:
            iconName = onlineIcon
            statusText = "状态: 已连接"
        case .offline:
            iconName = offlineIcon
            statusText = "状态: 未连接"
        case .checking:
            iconName = checkingIcon
            statusText = "状态: 检测中..."
        case .error(let msg):
            iconName = offlineIcon
            statusText = "状态: 错误 - \(msg)"
        }

        statusItem.button?.image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: statusText
        )
        statusMenuItem.title = statusText
        detailMenuItem.title = currentStatus.description
    }

    private func performAutoLogin() {
        api.login { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    Logger.log("自动登录成功")
                    self?.sendNotification(title: "登录成功", body: "已自动重新连接校园网")
                    self?.checkStatus()
                case .alreadyOnline:
                    Logger.log("已经在线")
                    self?.checkStatus()
                case .failed(let msg):
                    Logger.log("自动登录失败: \(msg)")
                    self?.sendNotification(title: "登录失败", body: msg)
                }
            }
        }
    }
}

// MARK: - 菜单操作
extension StatusBarController {
    @objc private func loginAction() {
        Logger.log("手动登录")
        api.login { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.sendNotification(title: "登录成功", body: "已连接校园网")
                case .alreadyOnline:
                    self?.sendNotification(title: "提示", body: "已经在线")
                case .failed(let msg):
                    self?.sendNotification(title: "登录失败", body: msg)
                }
                self?.checkStatus()
            }
        }
    }

    @objc private func logoutAction() {
        Logger.log("手动注销")
        api.logout { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.sendNotification(title: "注销成功", body: "已断开校园网")
                case .alreadyOnline, .failed:
                    self?.sendNotification(title: "注销失败", body: "请稍后重试")
                }
                self?.checkStatus()
            }
        }
    }

    @objc private func checkNowAction() {
        Logger.log("手动检测")
        checkStatus()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func settingsAction() {
        let controller = SettingsWindowController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func aboutAction() {
        let controller = AboutWindowController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 通知
extension StatusBarController {
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if granted {
                Logger.log("通知权限已授予")
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
