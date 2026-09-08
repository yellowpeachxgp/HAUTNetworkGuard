import Cocoa
import UserNotifications

/// 菜单栏控制器
class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var detailMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var logoutMenuItem: NSMenuItem!

    private let api: SrunService
    private let config: AppConfig
    private let now: () -> TimeInterval
    private var checkTimer: Timer?
    private var currentStatus: NetworkStatus = .checking
    private var lastStatusAt: Date?
    private var checkInterval: TimeInterval { TimeInterval(config.checkInterval) }
    private var session = SessionPolicy()
    private var monotonicNow: TimeInterval { now() }

    // 状态图标
    private let onlineIcon = "wifi"
    private let offlineIcon = "wifi.slash"
    private let checkingIcon = "arrow.triangle.2.circlepath"

    // 更新窗口引用
    private var updateWindowController: UpdateWindowController?
    // 需要持有设置窗口控制器，否则会被提前释放导致控件动作失效
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var utilityWindowObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    init(api: SrunService = SrunAPI(), config: AppConfig = .shared,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.api = api
        self.config = config
        self.now = now
        super.init()
        Logger.debug("初始化菜单栏控制器")
        setupStatusItem()
        setupMenu()
        if AppRuntime.isUISmokeTest {
            Logger.info("已启用 macOS UI smoke test 模式，跳过通知、网络轮询和自动更新后台任务")
            currentStatus = .offline
            updateUI()
        } else {
            requestNotificationPermission()
            startMonitoring()
            setupUpdateChecker()
        }
        setupNotifications()
    }

    deinit {
        checkTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        for observer in utilityWindowObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restartTimer),
            name: .checkIntervalChanged,
            object: nil
        )
    }
    
    @objc private func restartTimer() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkStatus(reason: "timer")
        }
        Logger.info("定时器已重启, 间隔: \(Int(checkInterval))秒")
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

// MARK: - 窗口展示
extension StatusBarController {
    private func presentUtilityWindow(_ controller: NSWindowController, kind: String) {
        DispatchQueue.main.async { [weak self, controller] in
            guard let self else {
                Logger.warn("展示 \(kind) 窗口失败：窗口控制器已释放")
                return
            }

            controller.showWindow(nil)
            guard let window = controller.window else {
                Logger.warn("展示 \(kind) 窗口失败：窗口尚未创建")
                return
            }

            self.registerUtilityWindowObserver(for: window, kind: kind)
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.collectionBehavior.insert(.fullScreenAuxiliary)

            let changed = NSApp.setActivationPolicy(.regular)
            Logger.debug("准备展示 \(kind) 窗口 (activationPolicyChanged=\(changed))")

            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            _ = NSRunningApplication.current.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
        }
    }

    private func registerUtilityWindowObserver(for window: NSWindow, kind: String) {
        let key = ObjectIdentifier(window)
        if let observer = utilityWindowObservers[key] {
            NotificationCenter.default.removeObserver(observer)
        }

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self else { return }
            Logger.debug("\(kind) 窗口已关闭")
            if let window {
                let key = ObjectIdentifier(window)
                if let observer = self.utilityWindowObservers.removeValue(forKey: key) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }

            switch kind {
            case "账号设置":
                self.settingsWindowController = nil
            case "关于":
                self.aboutWindowController = nil
            case "更新":
                self.updateWindowController = nil
            default:
                break
            }

            self.restoreAccessoryActivationIfPossible()
        }

        utilityWindowObservers[key] = observer
    }

    private func restoreAccessoryActivationIfPossible() {
        let hasVisibleUtilityWindow =
            (settingsWindowController?.window?.isVisible ?? false) ||
            (aboutWindowController?.window?.isVisible ?? false) ||
            (updateWindowController?.window?.isVisible ?? false)

        if hasVisibleUtilityWindow {
            Logger.debug("仍有可见窗口，保持 regular 激活策略")
            return
        }

        let changed = NSApp.setActivationPolicy(.accessory)
        Logger.debug("恢复菜单栏应用激活策略 (changed=\(changed))")
    }
}

// MARK: - UI Smoke Test
extension StatusBarController {
    func runUISmokeTest(completion: @escaping (Bool, String) -> Void) {
        Logger.info("开始执行 macOS UI smoke test")
        stepOpenSettingsForSmokeTest(completion: completion)
    }

    private func stepOpenSettingsForSmokeTest(completion: @escaping (Bool, String) -> Void) {
        settingsAction()
        waitForWindow(title: "账号设置", shouldBeVisible: true, timeout: 2.0) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                completion(false, "账号设置窗口未能成功打开")
                return
            }
            guard NSApp.activationPolicy() == .regular else {
                completion(false, "打开账号设置后激活策略未切换到 regular")
                return
            }
            self.closeWindow(title: "账号设置")
            self.waitForActivationPolicy(.accessory, timeout: 2.0) { restored in
                guard restored else {
                    completion(false, "关闭账号设置后未恢复到 accessory 激活策略")
                    return
                }
                self.stepReopenSettingsForSmokeTest(completion: completion)
            }
        }
    }

    private func stepReopenSettingsForSmokeTest(completion: @escaping (Bool, String) -> Void) {
        settingsAction()
        waitForWindow(title: "账号设置", shouldBeVisible: true, timeout: 2.0) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                completion(false, "账号设置窗口二次打开失败")
                return
            }
            self.closeWindow(title: "账号设置")
            self.waitForWindow(title: "账号设置", shouldBeVisible: false, timeout: 2.0) { closed in
                guard closed else {
                    completion(false, "账号设置窗口关闭状态异常")
                    return
                }
                self.stepOpenAboutForSmokeTest(completion: completion)
            }
        }
    }

    private func stepOpenAboutForSmokeTest(completion: @escaping (Bool, String) -> Void) {
        aboutAction()
        waitForWindow(title: "关于", shouldBeVisible: true, timeout: 2.0) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                completion(false, "关于窗口未能成功打开")
                return
            }
            self.closeWindow(title: "关于")
            self.waitForWindow(title: "关于", shouldBeVisible: false, timeout: 2.0) { closed in
                guard closed else {
                    completion(false, "关于窗口关闭状态异常")
                    return
                }
                self.stepOpenUpdateForSmokeTest(completion: completion)
            }
        }
    }

    private func stepOpenUpdateForSmokeTest(completion: @escaping (Bool, String) -> Void) {
        let releaseInfo = ReleaseInfo(
            version: AppConfig.version,
            htmlURL: AppConfig.website,
            downloadURL: nil,
            releaseNotes: "UI smoke test placeholder"
        )
        showUpdateWindow(result: .noUpdate(releaseInfo))
        waitForWindow(title: "检查更新", shouldBeVisible: true, timeout: 2.0) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                completion(false, "更新窗口未能成功打开")
                return
            }
            self.closeWindow(title: "检查更新")
            self.waitForWindow(title: "检查更新", shouldBeVisible: false, timeout: 2.0) { closed in
                guard closed else {
                    completion(false, "更新窗口关闭状态异常")
                    return
                }
                self.waitForActivationPolicy(.accessory, timeout: 2.0) { restored in
                    if restored {
                        completion(true, "macOS UI smoke test 通过")
                    } else {
                        completion(false, "关闭全部窗口后未恢复到 accessory 激活策略")
                    }
                }
            }
        }
    }

    private func waitForWindow(
        title: String,
        shouldBeVisible: Bool,
        timeout: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        func poll() {
            let visible = NSApp.windows.contains { window in
                window.title == title && window.isVisible
            }
            if visible == shouldBeVisible {
                completion(true)
                return
            }
            if Date() >= deadline {
                Logger.warn("UI smoke test 窗口检测超时 title=\(title) expected_visible=\(shouldBeVisible)")
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
    }

    private func waitForActivationPolicy(
        _ policy: NSApplication.ActivationPolicy,
        timeout: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        func poll() {
            if NSApp.activationPolicy() == policy {
                completion(true)
                return
            }
            if Date() >= deadline {
                Logger.warn("UI smoke test 激活策略检测超时 expected=\(policy.rawValue) actual=\(NSApp.activationPolicy().rawValue)")
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
    }

    private func closeWindow(title: String) {
        if let window =
            NSApp.windows.first(where: { $0.title == title && $0.isVisible }) ??
            NSApp.windows.first(where: { $0.title == title }) {
            window.close()
        } else {
            Logger.warn("尝试关闭窗口失败：未找到 title=\(title)")
        }
    }
}

// MARK: - 菜单设置
extension StatusBarController {
    private func setupMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

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
        loginMenuItem = NSMenuItem(
            title: "立即登录",
            action: #selector(loginAction),
            keyEquivalent: "l"
        )
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        // 注销登录
        logoutMenuItem = NSMenuItem(
            title: "注销登录",
            action: #selector(logoutAction),
            keyEquivalent: "o"
        )
        logoutMenuItem.target = self
        menu.addItem(logoutMenuItem)

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

        let diagnosticsItem = NSMenuItem(
            title: "复制诊断信息",
            action: #selector(copyDiagnosticsAction),
            keyEquivalent: "d"
        )
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

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

        // 检查更新
        let updateItem = NSMenuItem(
            title: "检查更新...",
            action: #selector(checkUpdateAction),
            keyEquivalent: "u"
        )
        updateItem.target = self
        menu.addItem(updateItem)

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
        Logger.info("开始网络监控，检测间隔: \(Int(checkInterval)) 秒")
        checkStatus(reason: "startup")
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkStatus(reason: "timer")
        }
    }

    func checkStatus(reason: String) {
        guard let token = session.beginStatus() else {
            Logger.debug("跳过状态检测 [\(reason)]：已有网络操作进行中")
            return
        }

        updateUI()
        Logger.debug("触发一次网络状态检测 [\(reason)]")
        api.checkStatus { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                let observation: SessionPolicy.Observation
                switch status {
                case .online: observation = .online
                case .offline: observation = .offline
                case .error, .checking: observation = .error
                }
                guard self.session.completeStatus(token, observation: observation) else { return }
                self.handleStatusChange(status, reason: reason)
            }
        }
    }
}

// MARK: - 状态处理
extension StatusBarController {
    private func handleStatusChange(_ newStatus: NetworkStatus, reason: String) {
        let previousStatus = currentStatus
        currentStatus = newStatus
        lastStatusAt = Date()
        Logger.info("状态迁移 [\(reason)]: \(previousStatus.kindLabel) -> \(newStatus.kindLabel)")

        updateUI()

        switch newStatus {
        case .offline:
            triggerAutoLoginIfNeeded(trigger: reason)
        case .error(let message):
            Logger.warn("状态检测错误，不触发自动登录: \(message)")
        case .checking, .online:
            break
        }
    }

    private func updateUI() {
        var iconName: String
        var statusText: String

        switch currentStatus {
        case .online:
            iconName = onlineIcon
            statusText = "状态: 已连接"
        case .offline:
            iconName = offlineIcon
            statusText = session.manualOfflineHold ? "状态: 已暂停自动重连" : "状态: 未连接"
        case .checking:
            iconName = checkingIcon
            statusText = "状态: 检测中..."
        case .error(let msg):
            iconName = offlineIcon
            statusText = "状态: 错误 - \(msg)"
        }

        if session.isBusy {
            iconName = checkingIcon
            switch session.operation {
            case .login: statusText = "状态: 正在登录..."
            case .logout: statusText = "状态: 正在注销..."
            case .status: statusText = "状态: 正在检测..."
            case .idle: break
            }
        }

        statusItem.button?.image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: statusText
        )
        statusMenuItem.title = statusText
        if session.manualOfflineHold {
            detailMenuItem.title = "自动重连已暂停；点击「立即登录」解除暂停"
        } else {
            let hint = automaticRetryHint()
            let checkedAt = lastStatusAt.map {
                "最近检测 \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium))"
            }
            detailMenuItem.title = [currentStatus.description, hint, checkedAt]
                .compactMap { $0 }.joined(separator: "；")
        }
        loginMenuItem.isEnabled = (!currentStatus.isOnline || session.manualOfflineHold) && !session.isBusy
        logoutMenuItem.isEnabled = currentStatus.isOnline && !session.isBusy
    }

    private func automaticRetryHint() -> String? {
        guard config.autoLogin else { return nil }
        let remaining = session.nextAutomaticAttempt - monotonicNow
        guard remaining > 0 else { return nil }
        return "自动重试约 \(Int(ceil(remaining))) 秒后"
    }

    private func triggerAutoLoginIfNeeded(trigger: String) {
        guard let token = session.beginLogin(
            manual: false, enabled: config.autoLogin,
            hasCredentials: !config.username.isEmpty && !config.password.isEmpty,
            now: monotonicNow, interval: checkInterval
        ) else { return }
        performLogin(token: token, manual: false, trigger: trigger)
    }

    private func performLogin(token: UInt64, manual: Bool, trigger: String) {
        updateUI()
        Logger.info("执行登录流程 [\(trigger)] (account: \(Logger.maskUsername(config.username)))")
        api.login { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let succeeded: Bool
                if case .failed = result { succeeded = false } else { succeeded = true }
                guard self.session.completeLogin(token, succeeded: succeeded, now: self.monotonicNow) else { return }
                switch result {
                case .success:
                    Logger.info("登录请求成功 [\(trigger)]，等待状态确认")
                    self.sendNotification(title: "登录请求成功", body: "正在确认校园网连接状态")
                case .alreadyOnline:
                    Logger.info("登录返回 already_online [\(trigger)]，等待状态确认")
                case .failed(let msg):
                    Logger.warn("登录失败 [\(trigger)]: \(msg)")
                    self.currentStatus = .error(msg)
                    self.sendNotification(title: "登录失败", body: msg)
                }
                self.updateUI()
                if succeeded || manual {
                    self.checkStatus(reason: "post_login")
                }
            }
        }
    }
}

// MARK: - 菜单操作
extension StatusBarController {
    @objc func loginAction() {
        guard !session.isBusy else { return }
        guard !config.username.isEmpty, !config.password.isEmpty else {
            settingsAction()
            return
        }
        guard let token = session.beginLogin(
            manual: true, enabled: config.autoLogin, hasCredentials: true,
            now: monotonicNow, interval: checkInterval
        ) else { return }
        performLogin(token: token, manual: true, trigger: "manual_login")
    }

    @objc func logoutAction() {
        guard let token = session.beginLogout() else { return }
        updateUI()
        Logger.info("手动注销")
        api.logout { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let succeeded: Bool
                if case .failed = result { succeeded = false } else { succeeded = true }
                guard self.session.completeLogout(token, succeeded: succeeded) else { return }
                switch result {
                case .success:
                    self.currentStatus = .offline
                    self.sendNotification(title: "注销成功", body: "已断开校园网，自动重连已暂停")
                case .alreadyOnline:
                    self.currentStatus = .offline
                    self.sendNotification(title: "提示", body: "当前未在线，自动重连已暂停")
                case .failed(let msg):
                    self.currentStatus = .error(msg)
                    self.sendNotification(title: "注销失败", body: msg + " 自动重连已暂停，可再次注销。")
                }
                self.updateUI()
                self.checkStatus(reason: "manual_logout")
            }
        }
    }

    @objc private func checkNowAction() {
        Logger.info("手动检测")
        checkStatus(reason: "manual_check")
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func settingsAction() {
        Logger.debug("打开账号设置窗口")
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        if let controller = settingsWindowController {
            presentUtilityWindow(controller, kind: "账号设置")
        }
    }

    @objc private func aboutAction() {
        Logger.debug("打开关于窗口")
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        if let controller = aboutWindowController {
            presentUtilityWindow(controller, kind: "关于")
        }
    }

    @objc private func checkUpdateAction() {
        Logger.info("手动检查更新")
        UpdateChecker.shared.checkForUpdate(isManual: true, force: true)
    }

    @objc func copyDiagnosticsAction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticText(), forType: .string)
        detailMenuItem.title = "诊断信息已复制；内容不含账号和密码"
        Logger.info("已复制脱敏诊断信息")
    }

    func diagnosticText() -> String {
        let checkedAt = lastStatusAt.map {
            DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium)
        } ?? "尚未检测"
        let retry = automaticRetryHint() ?? "无"
        return [
            "\(AppConfig.appName) v\(AppConfig.version)",
            "状态分类: \(currentStatus.kindLabel)",
            "最近检测: \(checkedAt)",
            "自动登录: \(config.autoLogin ? "开启" : "关闭")",
            "自动重试: \(retry)"
        ].joined(separator: "\n")
    }
}

// MARK: - 通知
extension StatusBarController {
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if granted {
                Logger.info("通知权限已授予")
            } else if let error = error {
                Logger.warn("通知权限请求失败: \(error.localizedDescription)")
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        guard !AppRuntime.isUISmokeTest else { return }
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

// MARK: - 更新检测
extension StatusBarController {
    private func setupUpdateChecker() {
        // 后台自动检测回调（只在有更新时触发）
        UpdateChecker.shared.onUpdateAvailable = { [weak self] releaseInfo in
            Logger.info("后台检测到新版本: \(releaseInfo.version)")
            self?.showUpdateWindow(result: .hasUpdate(releaseInfo))
        }

        // 手动检测完成回调（无论是否有更新都触发）
        UpdateChecker.shared.onCheckComplete = { [weak self] result in
            self?.showUpdateWindow(result: result)
        }

        UpdateChecker.shared.startPeriodicCheck()
    }

    private func showUpdateWindow(result: UpdateCheckResult) {
        // 关闭之前的更新窗口
        updateWindowController?.close()

        var onSkip: (() -> Void)? = nil
        if case .hasUpdate(let info) = result {
            onSkip = {
                UpdateChecker.shared.skipVersion(info.version)
            }
        }

        updateWindowController = UpdateWindowController(
            result: result,
            onSkip: onSkip
        )
        if let controller = updateWindowController {
            presentUtilityWindow(controller, kind: "更新")
        }
    }
}
