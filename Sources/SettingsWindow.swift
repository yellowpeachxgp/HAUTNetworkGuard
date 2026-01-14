import Cocoa

/// 设置窗口控制器
class SettingsWindowController: NSWindowController {
    var onSave: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
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

    private func setupUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        // 标题
        let titleLabel = NSTextField(labelWithString: "HAUT Network Guard")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 20, y: 230, width: 360, height: 30)
        contentView.addSubview(titleLabel)

        // 副标题
        let subtitleLabel = NSTextField(labelWithString: "河南工业大学校园网自动登录工具")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 210, width: 360, height: 20)
        contentView.addSubview(subtitleLabel)

        // 学号标签
        let userLabel = NSTextField(labelWithString: "学号:")
        userLabel.frame = NSRect(x: 20, y: 165, width: 60, height: 20)
        contentView.addSubview(userLabel)

        // 学号输入框
        usernameField = NSTextField()
        usernameField.frame = NSRect(x: 80, y: 162, width: 300, height: 26)
        usernameField.placeholderString = "请输入学号"
        usernameField.stringValue = AppConfig.shared.username
        contentView.addSubview(usernameField)

        // 密码标签
        let passLabel = NSTextField(labelWithString: "密码:")
        passLabel.frame = NSRect(x: 20, y: 125, width: 60, height: 20)
        contentView.addSubview(passLabel)

        // 密码输入框
        passwordField = NSSecureTextField()
        passwordField.frame = NSRect(x: 80, y: 122, width: 300, height: 26)
        passwordField.placeholderString = "请输入密码"
        passwordField.stringValue = AppConfig.shared.password
        contentView.addSubview(passwordField)

        // 自动保存复选框
        autoSaveCheckbox = NSButton(checkboxWithTitle: "记住密码", target: nil, action: nil)
        autoSaveCheckbox.frame = NSRect(x: 80, y: 85, width: 120, height: 20)
        autoSaveCheckbox.state = AppConfig.shared.autoSave ? .on : .off
        contentView.addSubview(autoSaveCheckbox)

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

        window?.close()
        onSave?()
    }
}
