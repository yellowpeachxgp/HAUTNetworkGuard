import Cocoa

/// 设置窗口控制器
class SettingsWindowController: NSWindowController {
    var onSave: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "账号设置"
        window.center()
        self.init(window: window)
        setupUI()
    }

    private var usernameField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var autoSaveCheckbox: NSButton!
    private var autoLaunchCheckbox: NSButton!

    private func setupUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        // 标题
        let titleLabel = NSTextField(labelWithString: "HAUT Network Guard")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 20, y: 270, width: 360, height: 30)
        contentView.addSubview(titleLabel)

        // 副标题
        let subtitleLabel = NSTextField(labelWithString: "河南工业大学校园网自动登录工具")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 250, width: 360, height: 20)
        contentView.addSubview(subtitleLabel)

        // 分割线
        let separator1 = NSBox(frame: NSRect(x: 20, y: 235, width: 360, height: 1))
        separator1.boxType = .separator
        contentView.addSubview(separator1)

        // 学号标签
        let userLabel = NSTextField(labelWithString: "学号:")
        userLabel.frame = NSRect(x: 20, y: 195, width: 60, height: 20)
        contentView.addSubview(userLabel)

        // 学号输入框
        usernameField = NSTextField()
        usernameField.frame = NSRect(x: 80, y: 192, width: 300, height: 26)
        usernameField.placeholderString = "请输入学号"
        usernameField.stringValue = AppConfig.shared.username
        contentView.addSubview(usernameField)

        // 密码标签
        let passLabel = NSTextField(labelWithString: "密码:")
        passLabel.frame = NSRect(x: 20, y: 155, width: 60, height: 20)
        contentView.addSubview(passLabel)

        // 密码输入框
        passwordField = NSSecureTextField()
        passwordField.frame = NSRect(x: 80, y: 152, width: 300, height: 26)
        passwordField.placeholderString = "请输入密码"
        passwordField.stringValue = AppConfig.shared.password
        contentView.addSubview(passwordField)

        // 分割线
        let separator2 = NSBox(frame: NSRect(x: 20, y: 135, width: 360, height: 1))
        separator2.boxType = .separator
        contentView.addSubview(separator2)

        // 选项区域
        // 自动保存复选框
        autoSaveCheckbox = NSButton(checkboxWithTitle: "记住密码", target: nil, action: nil)
        autoSaveCheckbox.frame = NSRect(x: 80, y: 100, width: 120, height: 20)
        autoSaveCheckbox.state = AppConfig.shared.autoSave ? .on : .off
        contentView.addSubview(autoSaveCheckbox)

        // 开机自启动复选框
        autoLaunchCheckbox = NSButton(checkboxWithTitle: "开机自启动", target: nil, action: nil)
        autoLaunchCheckbox.frame = NSRect(x: 220, y: 100, width: 120, height: 20)
        autoLaunchCheckbox.state = LaunchManager.shared.isEnabled ? .on : .off
        contentView.addSubview(autoLaunchCheckbox)

        // 提示信息
        let hintLabel = NSTextField(labelWithString: "开启后，每次开机将自动启动并保持网络连接")
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.frame = NSRect(x: 80, y: 75, width: 300, height: 16)
        contentView.addSubview(hintLabel)

        // 保存按钮
        let saveButton = NSButton(title: "保存并启动", target: self, action: #selector(saveAction))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 280, y: 20, width: 100, height: 32)
        contentView.addSubview(saveButton)

        // 版本信息
        let versionLabel = NSTextField(labelWithString: "v\(AppConfig.version) by \(AppConfig.author)")
        versionLabel.font = NSFont.systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.frame = NSRect(x: 20, y: 20, width: 200, height: 16)
        contentView.addSubview(versionLabel)
    }

    @objc private func saveAction() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
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
        AppConfig.shared.save(username: username, password: password, autoSave: autoSave)

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

        window?.close()
        onSave?()
    }
}
