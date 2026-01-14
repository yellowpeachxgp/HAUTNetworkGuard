import Cocoa

/// 更新提示窗口控制器
class UpdateWindowController: NSWindowController {
    private var releaseInfo: ReleaseInfo
    private var onSkip: (() -> Void)?

    init(releaseInfo: ReleaseInfo, onSkip: (() -> Void)? = nil) {
        self.releaseInfo = releaseInfo
        self.onSkip = onSkip

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "发现新版本"
        window.center()

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        // 图标
        let iconView = NSImageView(frame: NSRect(x: 20, y: 200, width: 64, height: 64))
        iconView.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "更新")
        iconView.contentTintColor = .systemBlue
        contentView.addSubview(iconView)

        // 标题
        let titleLabel = NSTextField(labelWithString: "发现新版本 v\(releaseInfo.version)")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 100, y: 225, width: 300, height: 24)
        contentView.addSubview(titleLabel)

        // 当前版本
        let currentLabel = NSTextField(labelWithString: "当前版本: v\(AppConfig.version)")
        currentLabel.font = NSFont.systemFont(ofSize: 12)
        currentLabel.textColor = .secondaryLabelColor
        currentLabel.frame = NSRect(x: 100, y: 200, width: 300, height: 20)
        contentView.addSubview(currentLabel)

        // 更新内容标题
        let notesTitle = NSTextField(labelWithString: "更新内容:")
        notesTitle.font = NSFont.boldSystemFont(ofSize: 12)
        notesTitle.frame = NSRect(x: 20, y: 165, width: 380, height: 20)
        contentView.addSubview(notesTitle)

        // 更新内容 (ScrollView)
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 80, width: 380, height: 80))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 80))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.string = simplifyReleaseNotes(releaseInfo.releaseNotes)
        textView.textContainerInset = NSSize(width: 5, height: 5)

        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        // 立即更新按钮
        let updateButton = NSButton(title: "立即更新", target: self, action: #selector(updateAction))
        updateButton.bezelStyle = .rounded
        updateButton.frame = NSRect(x: 300, y: 20, width: 100, height: 32)
        updateButton.keyEquivalent = "\r"
        contentView.addSubview(updateButton)

        // 稍后提醒按钮
        let laterButton = NSButton(title: "稍后提醒", target: self, action: #selector(laterAction))
        laterButton.bezelStyle = .rounded
        laterButton.frame = NSRect(x: 190, y: 20, width: 100, height: 32)
        contentView.addSubview(laterButton)

        // 跳过此版本按钮
        let skipButton = NSButton(title: "跳过此版本", target: self, action: #selector(skipAction))
        skipButton.bezelStyle = .rounded
        skipButton.frame = NSRect(x: 20, y: 20, width: 100, height: 32)
        contentView.addSubview(skipButton)
    }

    /// 简化更新说明
    private func simplifyReleaseNotes(_ notes: String) -> String {
        // 移除 markdown 标题符号，简化显示
        var result = notes
        result = result.replacingOccurrences(of: "### ", with: "")
        result = result.replacingOccurrences(of: "## ", with: "")
        result = result.replacingOccurrences(of: "# ", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func updateAction() {
        Logger.log("用户选择立即更新")

        // 优先使用 DMG 下载链接，否则打开 Release 页面
        let urlString = releaseInfo.downloadURL ?? releaseInfo.htmlURL

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }

        window?.close()
    }

    @objc private func laterAction() {
        Logger.log("用户选择稍后提醒")
        window?.close()
    }

    @objc private func skipAction() {
        Logger.log("用户选择跳过此版本")
        onSkip?()
        window?.close()
    }
}
