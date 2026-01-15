import Foundation

/// 开机自启动管理器
class LaunchManager {
    static let shared = LaunchManager()

    private let launchAgentLabel = "cn.ehaut.networkguard"
    private let launchAgentsPath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        launchAgentsPath = "\(home)/Library/LaunchAgents"
    }

    private var plistPath: String {
        return "\(launchAgentsPath)/\(launchAgentLabel).plist"
    }

    /// 是否已启用开机自启动
    var isEnabled: Bool {
        return FileManager.default.fileExists(atPath: plistPath)
    }

    /// 启用开机自启动
    func enable() -> Bool {
        // 确保 LaunchAgents 目录存在
        if !FileManager.default.fileExists(atPath: launchAgentsPath) {
            do {
                try FileManager.default.createDirectory(atPath: launchAgentsPath, withIntermediateDirectories: true)
            } catch {
                Logger.log("创建 LaunchAgents 目录失败: \(error.localizedDescription)")
                return false
            }
        }

        // 获取当前应用路径
        let appPath = Bundle.main.bundlePath
        let executablePath = "\(appPath)/Contents/MacOS/HAUTNetworkGuard"

        // 创建 plist 内容
        let plistContent: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": "/tmp/HAUTNetworkGuard.log",
            "StandardErrorPath": "/tmp/HAUTNetworkGuard.error.log"
        ]

        // 写入 plist 文件
        let plistData = try? PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
        guard let data = plistData else {
            Logger.log("生成 plist 数据失败")
            return false
        }

        do {
            try data.write(to: URL(fileURLWithPath: plistPath))
            Logger.log("开机自启动已启用")

            // 加载 LaunchAgent
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["load", plistPath]
            try? process.run()
            process.waitUntilExit()

            return true
        } catch {
            Logger.log("写入 plist 文件失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 禁用开机自启动
    func disable() -> Bool {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            Logger.log("LaunchAgent 文件不存在")
            return true
        }

        // 先卸载 LaunchAgent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistPath]
        try? process.run()
        process.waitUntilExit()

        // 删除 plist 文件
        do {
            try FileManager.default.removeItem(atPath: plistPath)
            Logger.log("开机自启动已禁用")
            return true
        } catch {
            Logger.log("删除 plist 文件失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 设置开机自启动状态
    func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            return enable()
        } else {
            return disable()
        }
    }
}
