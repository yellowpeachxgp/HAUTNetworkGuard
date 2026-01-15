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
                try FileManager.default.createDirectory(
                    atPath: launchAgentsPath,
                    withIntermediateDirectories: true
                )
            } catch {
                Logger.log("创建 LaunchAgents 目录失败: \(error)")
                return false
            }
        }

        // 使用固定的 Applications 路径
        let executablePath = "/Applications/HAUTNetworkGuard.app/Contents/MacOS/HAUTNetworkGuard"

        // 创建 plist 内容
        let plistContent: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        // 序列化 plist
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plistContent,
            format: .xml,
            options: 0
        ) else {
            Logger.log("生成 plist 数据失败")
            return false
        }

        // 写入文件
        do {
            try data.write(to: URL(fileURLWithPath: plistPath))
            Logger.log("开机自启动已启用: \(plistPath)")
            return true
        } catch {
            Logger.log("写入 plist 文件失败: \(error)")
            return false
        }
    }

    /// 禁用开机自启动
    func disable() -> Bool {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            return true
        }

        do {
            try FileManager.default.removeItem(atPath: plistPath)
            Logger.log("开机自启动已禁用")
            return true
        } catch {
            Logger.log("删除 plist 文件失败: \(error)")
            return false
        }
    }

    /// 设置开机自启动状态
    func setEnabled(_ enabled: Bool) -> Bool {
        return enabled ? enable() : disable()
    }
}
