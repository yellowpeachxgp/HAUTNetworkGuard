import Cocoa

/// 设置窗口控制器
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onSave: (() -> Void)?
    var onCloseWithoutSave: (() -> Void)?

    private var requiresInitialConfiguration = false
    private var didPersistSettings = false

    convenience init() {
        self.init(isInitialSetup: false)
    }

    convenience init(isInitialSetup: Bool) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "账号设置"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.init(window: window)
        requiresInitialConfiguration = isInitialSetup
        window.delegate = self
        setupUI()
    }

    private var usernameField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var autoSaveCheckbox: NSButton!
    private var autoLaunchCheckbox: NSButton!
    private var autoLoginCheckbox: NSButton!
    private var intervalSlider: NSSlider!
    private var intervalLabel: NSTextField!
    private var optionHintLabel: NSTextField!
    private var saveButton: NSButton!

    private func setupUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        // 标题
        let titleLabel = NSTextField(labelWithString: "HAUT Network Guard")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 20)
        titleLabel.frame = NSRect(x: 20, y: 442, width: 420, height: 28)
        contentView.addSubview(titleLabel)

        // 副标题
        let subtitleLabel = NSTextField(
            labelWithString: requiresInitialConfiguration
                ? "首次启动需要先完成账号配置"
                : "河南工业大学校园网自动登录工具"
        )
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 418, width: 420, height: 20)
        contentView.addSubview(subtitleLabel)

        let introLabel = NSTextField(
            labelWithString: requiresInitialConfiguration
                ? "建议同时开启“记住密码 + 自动登录”，这样重启后也能自动恢复网络连接。"
                : "修改后会立即更新检测间隔、自启动和自动登录策略。"
        )
        introLabel.font = NSFont.systemFont(ofSize: 11)
        introLabel.textColor = .tertiaryLabelColor
        introLabel.frame = NSRect(x: 20, y: 396, width: 420, height: 20)
        contentView.addSubview(introLabel)

        // 分割线
        let separator1 = NSBox(frame: NSRect(x: 20, y: 382, width: 420, height: 1))
        separator1.boxType = .separator
        contentView.addSubview(separator1)

        // 学号标签
        let userLabel = NSTextField(labelWithString: "学号:")
        userLabel.frame = NSRect(x: 20, y: 340, width: 60, height: 20)
        contentView.addSubview(userLabel)

        // 学号输入框
        usernameField = NSTextField()
        usernameField.frame = NSRect(x: 92, y: 336, width: 348, height: 28)
        usernameField.placeholderString = "请输入学号"
        usernameField.stringValue = AppConfig.shared.username
        usernameField.toolTip = "校园网登录学号"
        usernameField.setAccessibilityLabel("学号")
        contentView.addSubview(usernameField)

        // 密码标签
        let passLabel = NSTextField(labelWithString: "密码:")
        passLabel.frame = NSRect(x: 20, y: 294, width: 60, height: 20)
        contentView.addSubview(passLabel)

        // 密码输入框
        passwordField = NSSecureTextField()
        passwordField.frame = NSRect(x: 92, y: 290, width: 348, height: 28)
        passwordField.placeholderString = "请输入密码"
        passwordField.stringValue = AppConfig.shared.password
        passwordField.toolTip = "不会在界面明文显示"
        passwordField.setAccessibilityLabel("密码")
        contentView.addSubview(passwordField)

        // 分割线
        let separator2 = NSBox(frame: NSRect(x: 20, y: 270, width: 420, height: 1))
        separator2.boxType = .separator
        contentView.addSubview(separator2)

        // 检测间隔设置
        let intervalTitleLabel = NSTextField(labelWithString: "检测间隔:")
        intervalTitleLabel.frame = NSRect(x: 20, y: 236, width: 70, height: 20)
        contentView.addSubview(intervalTitleLabel)
        
        intervalSlider = NSSlider(value: Double(AppConfig.shared.checkInterval),
                                   minValue: 30, maxValue: 300,
                                   target: self, action: #selector(intervalChanged))
        intervalSlider.frame = NSRect(x: 92, y: 236, width: 250, height: 20)
        intervalSlider.altIncrementValue = 15
        intervalSlider.toolTip = "建议 30-60 秒，兼顾响应速度和请求频率"
        intervalSlider.setAccessibilityLabel("检测间隔（秒）")
        contentView.addSubview(intervalSlider)
        
        intervalLabel = NSTextField(labelWithString: "\(AppConfig.shared.checkInterval) 秒")
        intervalLabel.frame = NSRect(x: 350, y: 236, width: 90, height: 20)
        intervalLabel.alignment = .right
        contentView.addSubview(intervalLabel)

        let intervalHintLabel = NSTextField(labelWithString: "检测频率越高，离线恢复越快；默认建议保持在 30-60 秒。")
        intervalHintLabel.font = NSFont.systemFont(ofSize: 10)
        intervalHintLabel.textColor = .tertiaryLabelColor
        intervalHintLabel.frame = NSRect(x: 92, y: 214, width: 348, height: 16)
        contentView.addSubview(intervalHintLabel)

        // 选项区域
        // 自动保存复选框
        autoSaveCheckbox = NSButton(checkboxWithTitle: "记住密码", target: self, action: #selector(optionStateChanged))
        autoSaveCheckbox.frame = NSRect(x: 92, y: 176, width: 130, height: 20)
        autoSaveCheckbox.state = AppConfig.shared.autoSave ? .on : .off
        autoSaveCheckbox.toolTip = "勾选后会保存密码，便于系统重启后自动恢复登录"
        autoSaveCheckbox.setAccessibilityLabel("记住密码")
        contentView.addSubview(autoSaveCheckbox)

        // 开机自启动复选框
        autoLaunchCheckbox = NSButton(checkboxWithTitle: "开机自启动", target: self, action: #selector(optionStateChanged))
        autoLaunchCheckbox.frame = NSRect(x: 240, y: 176, width: 130, height: 20)
        autoLaunchCheckbox.state = LaunchManager.shared.isEnabled ? .on : .off
        autoLaunchCheckbox.toolTip = "登录系统后自动拉起应用并在菜单栏保持守护"
        autoLaunchCheckbox.setAccessibilityLabel("开机自启动")
        contentView.addSubview(autoLaunchCheckbox)
        
        // 自动登录复选框
        autoLoginCheckbox = NSButton(checkboxWithTitle: "自动登录 (断线重连)", target: self, action: #selector(optionStateChanged))
        autoLoginCheckbox.frame = NSRect(x: 92, y: 146, width: 220, height: 20)
        autoLoginCheckbox.state = AppConfig.shared.autoLogin ? .on : .off
        autoLoginCheckbox.toolTip = "检测到离线后自动尝试恢复网络连接"
        autoLoginCheckbox.setAccessibilityLabel("自动登录和断线重连")
        contentView.addSubview(autoLoginCheckbox)

        // 提示信息
        let hintLabel = NSTextField(labelWithString: "开启后，程序将自动检测并保持网络连接")
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.frame = NSRect(x: 92, y: 122, width: 320, height: 16)
        contentView.addSubview(hintLabel)

        optionHintLabel = NSTextField(frame: NSRect(x: 20, y: 68, width: 420, height: 44))
        optionHintLabel.isEditable = false
        optionHintLabel.isBordered = false
        optionHintLabel.drawsBackground = true
        optionHintLabel.backgroundColor = NSColor(calibratedRed: 0.93, green: 0.96, blue: 1.0, alpha: 1.0)
        optionHintLabel.font = NSFont.systemFont(ofSize: 11)
        if let cell = optionHintLabel.cell as? NSTextFieldCell {
            cell.wraps = true
            cell.isScrollable = false
            cell.lineBreakMode = .byWordWrapping
            cell.usesSingleLineMode = false
        }
        contentView.addSubview(optionHintLabel)

        // 保存按钮
        saveButton = NSButton(
            title: requiresInitialConfiguration ? "保存并启动" : "保存设置",
            target: self,
            action: #selector(saveAction)
        )
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.setAccessibilityLabel(requiresInitialConfiguration ? "保存并启动" : "保存设置")
        saveButton.frame = NSRect(x: 330, y: 20, width: 110, height: 32)
        contentView.addSubview(saveButton)

        if !requiresInitialConfiguration {
            let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeAction))
            closeButton.bezelStyle = .rounded
            closeButton.frame = NSRect(x: 240, y: 20, width: 80, height: 32)
            contentView.addSubview(closeButton)
        }

        // 版本信息
        let versionLabel = NSTextField(labelWithString: "v\(AppConfig.version) by \(AppConfig.author)")
        versionLabel.font = NSFont.systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.frame = NSRect(x: 20, y: 20, width: 200, height: 16)
        contentView.addSubview(versionLabel)

        // 明确键盘焦点顺序，首次配置无需鼠标即可完成。
        usernameField.nextKeyView = passwordField
        passwordField.nextKeyView = intervalSlider
        intervalSlider.nextKeyView = autoSaveCheckbox
        autoSaveCheckbox.nextKeyView = autoLaunchCheckbox
        autoLaunchCheckbox.nextKeyView = autoLoginCheckbox
        autoLoginCheckbox.nextKeyView = saveButton
        saveButton.nextKeyView = usernameField
        window.initialFirstResponder = usernameField

        updateOptionHint()
    }
    
    @objc private func intervalChanged() {
        let value = Int(intervalSlider.doubleValue)
        intervalLabel.stringValue = "\(value) 秒"
    }

    @objc private func optionStateChanged() {
        updateOptionHint()
    }

    @objc private func closeAction() {
        window?.close()
    }

    private func updateOptionHint() {
        let autoSave = autoSaveCheckbox.state == .on
        let autoLogin = autoLoginCheckbox.state == .on
        let autoLaunch = autoLaunchCheckbox.state == .on

        var message: String
        var textColor = NSColor(calibratedRed: 0.22, green: 0.33, blue: 0.48, alpha: 1.0)
        var backgroundColor = NSColor(calibratedRed: 0.93, green: 0.96, blue: 1.0, alpha: 1.0)

        if autoLogin && autoSave {
            message = "当前配置适合长期托管：启动后和掉线后都可以自动恢复连接。"
        } else if autoLogin {
            message = "已开启自动登录，但未记住密码。当前会话可重连，重启应用或系统后需要重新输入密码。"
            textColor = NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.0, alpha: 1.0)
            backgroundColor = NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.90, alpha: 1.0)
        } else {
            message = "已关闭自动登录。程序会继续检测网络状态，但离线后需要手动登录。"
        }

        message += autoLaunch ? " 已启用开机自启动。" : " 当前未启用开机自启动。"
        if let warning = AppConfig.shared.credentialWarning {
            message = warning
            textColor = .systemRed
        }

        optionHintLabel.stringValue = message
        optionHintLabel.textColor = textColor
        optionHintLabel.backgroundColor = backgroundColor
    }

    @objc private func saveAction() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue

        if username.isEmpty || password.isEmpty {
            let alert = NSAlert()
            alert.messageText = "请填写完整"
            alert.informativeText = "学号和密码不能为空"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }

        let autoSave = autoSaveCheckbox.state == .on
        let autoLogin = autoLoginCheckbox.state == .on
        let checkInterval = Int(intervalSlider.doubleValue)
        
        let credentialsSaved = AppConfig.shared.save(
            username: username,
            password: password,
            autoSave: autoSave,
            checkInterval: checkInterval,
            autoLogin: autoLogin
        )

        guard credentialsSaved else {
            let alert = NSAlert()
            alert.messageText = "密码保存未完成"
            alert.informativeText = AppConfig.shared.credentialWarning ?? "请稍后重试。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "返回设置")
            alert.runModal()
            return
        }

        // 处理开机自启动
        let autoLaunch = autoLaunchCheckbox.state == .on
        let success = LaunchManager.shared.setEnabled(autoLaunch)
        if !success {
            let alert = NSAlert()
            alert.messageText = "设置开机自启动失败"
            alert.informativeText = "请检查应用权限设置"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }

        didPersistSettings = true
        window?.close()
        onSave?()
        
        // 通知重启定时器
        NotificationCenter.default.post(name: .checkIntervalChanged, object: nil)
    }

    func windowWillClose(_ notification: Notification) {
        if requiresInitialConfiguration && !didPersistSettings {
            onCloseWithoutSave?()
        }
    }
}

// 通知名称扩展
extension Notification.Name {
    static let checkIntervalChanged = Notification.Name("checkIntervalChanged")
}
