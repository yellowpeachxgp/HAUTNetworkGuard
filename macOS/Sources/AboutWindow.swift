import Cocoa

/// 关于窗口控制器
class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于"
        window.center()
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        // 应用名称
        let nameLabel = NSTextField(labelWithString: AppConfig.appName)
        nameLabel.font = NSFont.boldSystemFont(ofSize: 20)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 0, y: 160, width: 300, height: 30)
        contentView.addSubview(nameLabel)

        // 版本号
        let versionLabel = NSTextField(labelWithString: "版本 \(AppConfig.version)")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 0, y: 135, width: 300, height: 20)
        contentView.addSubview(versionLabel)

        // 描述
        let descLabel = NSTextField(labelWithString: "河南工业大学校园网自动登录工具")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.alignment = .center
        descLabel.frame = NSRect(x: 0, y: 105, width: 300, height: 20)
        contentView.addSubview(descLabel)

        // 作者
        let authorLabel = NSTextField(labelWithString: "作者: \(AppConfig.author)")
        authorLabel.font = NSFont.systemFont(ofSize: 11)
        authorLabel.textColor = .secondaryLabelColor
        authorLabel.alignment = .center
        authorLabel.frame = NSRect(x: 0, y: 75, width: 300, height: 20)
        contentView.addSubview(authorLabel)

        // QQ群
        let qqLabel = NSTextField(labelWithString: "QQ群: \(AppConfig.qqGroup)")
        qqLabel.font = NSFont.systemFont(ofSize: 11)
        qqLabel.textColor = .secondaryLabelColor
        qqLabel.alignment = .center
        qqLabel.frame = NSRect(x: 0, y: 50, width: 300, height: 20)
        contentView.addSubview(qqLabel)

        // 网站
        let websiteLabel = NSTextField(labelWithString: AppConfig.website)
        websiteLabel.font = NSFont.systemFont(ofSize: 11)
        websiteLabel.textColor = .linkColor
        websiteLabel.alignment = .center
        websiteLabel.frame = NSRect(x: 0, y: 25, width: 300, height: 20)
        contentView.addSubview(websiteLabel)
    }
}
