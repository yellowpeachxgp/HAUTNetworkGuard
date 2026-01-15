import Cocoa

/// 更新检测窗口控制器
/// 支持显示：有新版本、已是最新版本、检测出错三种状态
class UpdateWindowController: NSWindowController {
    private var checkResult: UpdateCheckResult
    private var onSkip: (() -> Void)?

    // UI 组件
    private var iconView: NSImageView!
    private var titleLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var currentVersionLabel: NSTextField!
    private var latestVersionLabel: NSTextField!
    private var releaseNotesTitle: NSTextField!
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var primaryButton: NSButton!
    private var secondaryButton: NSButton!
    private var skipButton: NSButton!

    init(result: UpdateCheckResult, onSkip: (() -> Void)? = nil) {
        self.checkResult = result
        self.onSkip = onSkip

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "检查更新"
        window.center()

        super.init(window: window)
        setupUI()
        updateContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true
        window.contentView = contentView

        // 顶部区域：图标 + 标题
        // 图标
        iconView = NSImageView(frame: NSRect(x: 20, y: 300, width: 48, height: 48))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)

        // 标题
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 80, y: 320, width: 350, height: 24)
        contentView.addSubview(titleLabel)

        // 状态
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.frame = NSRect(x: 80, y: 298, width: 350, height: 20)
        contentView.addSubview(statusLabel)

        // 分割线
        let separator1 = NSBox(frame: NSRect(x: 20, y: 285, width: 410, height: 1))
        separator1.boxType = .separator
        contentView.addSubview(separator1)

        // 版本信息区域
        currentVersionLabel = NSTextField(labelWithString: "")
        currentVersionLabel.font = NSFont.systemFont(ofSize: 13)
        currentVersionLabel.frame = NSRect(x: 20, y: 252, width: 200, height: 20)
        contentView.addSubview(currentVersionLabel)

        latestVersionLabel = NSTextField(labelWithString: "")
        latestVersionLabel.font = NSFont.systemFont(ofSize: 13)
        latestVersionLabel.frame = NSRect(x: 220, y: 252, width: 210, height: 20)
        contentView.addSubview(latestVersionLabel)

        // 更新日志标题
        releaseNotesTitle = NSTextField(labelWithString: "更新日志:")
        releaseNotesTitle.font = NSFont.boldSystemFont(ofSize: 12)
        releaseNotesTitle.frame = NSRect(x: 20, y: 218, width: 410, height: 20)
        contentView.addSubview(releaseNotesTitle)

        // 更新日志 ScrollView
        scrollView = NSScrollView(frame: NSRect(x: 20, y: 70, width: 410, height: 145))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 390, height: 145))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = NSColor.textBackgroundColor

        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        // 底部按钮区域
        // 主按钮（右侧）
        primaryButton = NSButton(title: "", target: self, action: #selector(primaryAction))
        primaryButton.bezelStyle = .rounded
        primaryButton.frame = NSRect(x: 330, y: 20, width: 100, height: 32)
        primaryButton.keyEquivalent = "\r"
        contentView.addSubview(primaryButton)

        // 次要按钮（中间）
        secondaryButton = NSButton(title: "", target: self, action: #selector(secondaryAction))
        secondaryButton.bezelStyle = .rounded
        secondaryButton.frame = NSRect(x: 220, y: 20, width: 100, height: 32)
        contentView.addSubview(secondaryButton)

        // 跳过按钮（左侧）- 仅在有更新时显示
        skipButton = NSButton(title: "跳过此版本", target: self, action: #selector(skipAction))
        skipButton.bezelStyle = .rounded
        skipButton.frame = NSRect(x: 20, y: 20, width: 100, height: 32)
        contentView.addSubview(skipButton)
    }

    private func updateContent() {
        switch checkResult {
        case .hasUpdate(let releaseInfo):
            configureForUpdate(releaseInfo)
        case .noUpdate(let releaseInfo):
            configureForNoUpdate(releaseInfo)
        case .error(let message):
            configureForError(message)
        }
    }

    /// 配置界面：有新版本
    private func configureForUpdate(_ info: ReleaseInfo) {
        // 图标 - 下载箭头
        iconView.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "更新")
        iconView.contentTintColor = .systemBlue

        // 标题
        titleLabel.stringValue = "发现新版本"
        titleLabel.textColor = .labelColor

        // 状态
        statusLabel.stringValue = "有新版本可供下载"
        statusLabel.textColor = .systemBlue

        // 版本信息
        currentVersionLabel.stringValue = "当前版本: v\(AppConfig.version)"
        currentVersionLabel.textColor = .secondaryLabelColor

        latestVersionLabel.stringValue = "最新版本: v\(info.version)"
        latestVersionLabel.textColor = .systemGreen

        // 更新日志
        textView.string = simplifyReleaseNotes(info.releaseNotes)

        // 按钮
        primaryButton.title = "立即更新"
        primaryButton.isHidden = false

        secondaryButton.title = "稍后提醒"
        secondaryButton.isHidden = false

        skipButton.isHidden = false
    }

    /// 配置界面：已是最新版本
    private func configureForNoUpdate(_ info: ReleaseInfo) {
        // 图标 - 勾选
        iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "最新")
        iconView.contentTintColor = .systemGreen

        // 标题
        titleLabel.stringValue = "已是最新版本"
        titleLabel.textColor = .labelColor

        // 状态
        statusLabel.stringValue = "当前版本已是最新，无需更新"
        statusLabel.textColor = .systemGreen

        // 版本信息
        currentVersionLabel.stringValue = "当前版本: v\(AppConfig.version)"
        currentVersionLabel.textColor = .labelColor

        latestVersionLabel.stringValue = "最新版本: v\(info.version)"
        latestVersionLabel.textColor = .secondaryLabelColor

        // 更新日志
        releaseNotesTitle.stringValue = "当前版本更新日志:"
        textView.string = simplifyReleaseNotes(info.releaseNotes)

        // 按钮
        primaryButton.title = "关闭"
        primaryButton.isHidden = false

        secondaryButton.isHidden = true
        skipButton.isHidden = true
    }

    /// 配置界面：检测出错
    private func configureForError(_ message: String) {
        // 图标 - 错误
        iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "错误")
        iconView.contentTintColor = .systemRed

        // 标题
        titleLabel.stringValue = "检测更新失败"
        titleLabel.textColor = .labelColor

        // 状态
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed

        // 版本信息
        currentVersionLabel.stringValue = "当前版本: v\(AppConfig.version)"
        currentVersionLabel.textColor = .labelColor

        latestVersionLabel.stringValue = ""

        // 更新日志
        releaseNotesTitle.stringValue = "错误信息:"
        textView.string = "无法连接到 GitHub 服务器获取版本信息。\n\n可能的原因:\n• 网络连接问题\n• GitHub 服务暂时不可用\n• 防火墙或代理设置\n\n请稍后重试，或访问项目主页手动检查更新:\nhttps://github.com/yellowpeachxgp/HAUTNetworkGuard/releases"

        // 按钮
        primaryButton.title = "关闭"
        primaryButton.isHidden = false

        secondaryButton.title = "重试"
        secondaryButton.isHidden = false

        skipButton.isHidden = true
    }

    /// 简化更新说明
    private func simplifyReleaseNotes(_ notes: String) -> String {
        var result = notes
        // 移除 markdown 标题符号
        result = result.replacingOccurrences(of: "### ", with: "▸ ")
        result = result.replacingOccurrences(of: "## ", with: "■ ")
        result = result.replacingOccurrences(of: "# ", with: "● ")
        // 处理列表
        result = result.replacingOccurrences(of: "- ", with: "  • ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Actions

    @objc private func primaryAction() {
        switch checkResult {
        case .hasUpdate(let info):
            Logger.log("用户选择立即更新")
            let urlString = info.downloadURL ?? info.htmlURL
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            window?.close()
        case .noUpdate, .error:
            window?.close()
        }
    }

    @objc private func secondaryAction() {
        switch checkResult {
        case .hasUpdate:
            Logger.log("用户选择稍后提醒")
            window?.close()
        case .error:
            Logger.log("用户选择重试")
            window?.close()
            // 触发重新检测
            UpdateChecker.shared.checkForUpdate(isManual: true)
        case .noUpdate:
            break
        }
    }

    @objc private func skipAction() {
        if case .hasUpdate(let info) = checkResult {
            Logger.log("用户选择跳过此版本: \(info.version)")
            onSkip?()
            window?.close()
        }
    }
}

/// 向后兼容：保留旧的初始化方法用于自动检测弹窗
extension UpdateWindowController {
    convenience init(releaseInfo: ReleaseInfo, onSkip: (() -> Void)? = nil) {
        self.init(result: .hasUpdate(releaseInfo), onSkip: onSkip)
    }
}
