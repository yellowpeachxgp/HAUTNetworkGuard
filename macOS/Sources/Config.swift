import Foundation

/// 应用配置管理
class AppConfig {
    static let shared = AppConfig()

    // 应用信息
    static let appName = "HAUT Network Guard"
    static let version = "1.3.2"
    static let author = "YellowPeach"
    static let website = "https://github.com/yellowpeachxgp/HAUTNetworkGuard"
    static let qqGroup = "789860526"

    // UserDefaults 键
    private let usernameKey = "haut_username"
    private let passwordKey = "haut_password"
    private let autoSaveKey = "haut_auto_save"
    private let hasConfiguredKey = "haut_has_configured"

    private init() {}

    /// 是否已配置
    var hasConfigured: Bool {
        get { UserDefaults.standard.bool(forKey: hasConfiguredKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasConfiguredKey) }
    }

    /// 是否自动保存
    var autoSave: Bool {
        get { UserDefaults.standard.bool(forKey: autoSaveKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoSaveKey) }
    }

    /// 用户名
    var username: String {
        get { UserDefaults.standard.string(forKey: usernameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }

    /// 密码
    var password: String {
        get { UserDefaults.standard.string(forKey: passwordKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: passwordKey) }
    }

    /// 保存配置
    func save(username: String, password: String, autoSave: Bool) {
        self.username = username
        self.password = password
        self.autoSave = autoSave
        self.hasConfigured = true
        Logger.log("配置已保存")
    }

    /// 清除配置
    func clear() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
        UserDefaults.standard.removeObject(forKey: autoSaveKey)
        UserDefaults.standard.removeObject(forKey: hasConfiguredKey)
        Logger.log("配置已清除")
    }
}
