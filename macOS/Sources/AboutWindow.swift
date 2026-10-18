import Cocoa

/// 关于窗口控制器
class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        // 应用图标
        let iconView = NSImageView(frame: NSRect(x: 142, y: 208, width: 96, height: 96))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = NSApp.applicationIconImage
            ?? NSImage(named: NSImage.applicationIconName)
        iconView.setAccessibilityLabel("应用图标")
        contentView.addSubview(iconView)

        // 应用名称
        let nameLabel = NSTextField(labelWithString: AppConfig.appName)
        nameLabel.font = NSFont.boldSystemFont(ofSize: 20)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 20, y: 174, width: 340, height: 28)
        contentView.addSubview(nameLabel)

        // 版本号
        let versionLabel = NSTextField(labelWithString: "版本 \(AppConfig.version)")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 20, y: 150, width: 340, height: 18)
        contentView.addSubview(versionLabel)

        // 描述
        let descLabel = NSTextField(labelWithString: "河南工业大学校园网自动登录工具")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.alignment = .center
        descLabel.frame = NSRect(x: 20, y: 124, width: 340, height: 18)
        contentView.addSubview(descLabel)

        // 分割线
        let separator = NSBox(frame: NSRect(x: 30, y: 110, width: 320, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)

        // 作者
        let authorLabel = NSTextField(labelWithString: "作者: \(AppConfig.author)")
        authorLabel.font = NSFont.systemFont(ofSize: 11)
        authorLabel.textColor = .secondaryLabelColor
        authorLabel.alignment = .center
        authorLabel.frame = NSRect(x: 20, y: 86, width: 340, height: 18)
        contentView.addSubview(authorLabel)

        // QQ群
        let qqLabel = NSTextField(labelWithString: "QQ群: \(AppConfig.qqGroup)")
        qqLabel.font = NSFont.systemFont(ofSize: 11)
        qqLabel.textColor = .secondaryLabelColor
        qqLabel.alignment = .center
        qqLabel.frame = NSRect(x: 20, y: 64, width: 340, height: 18)
        contentView.addSubview(qqLabel)

        let supportLabel = NSTextField(labelWithString: "遇到问题可前往 GitHub 提交 issue，或加入 QQ 群反馈。")
        supportLabel.font = NSFont.systemFont(ofSize: 10)
        supportLabel.textColor = .tertiaryLabelColor
        supportLabel.alignment = .center
        supportLabel.frame = NSRect(x: 10, y: 40, width: 360, height: 18)
        contentView.addSubview(supportLabel)

        // 网站
        let websiteLabel = NSTextField(frame: NSRect(x: 20, y: 14, width: 340, height: 20))
        websiteLabel.isEditable = false
        websiteLabel.isBordered = false
        websiteLabel.drawsBackground = false
        websiteLabel.isSelectable = true
        websiteLabel.alignment = .center
        websiteLabel.allowsEditingTextAttributes = true
        websiteLabel.setAccessibilityLabel("项目主页")
        websiteLabel.attributedStringValue = NSAttributedString(
            string: AppConfig.website,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: URL(string: AppConfig.website) as Any
            ]
        )
        contentView.addSubview(websiteLabel)
    }
}
