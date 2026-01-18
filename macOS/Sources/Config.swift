import Foundation

/// 应用配置管理
class AppConfig {
    static let shared = AppConfig()

    // 应用信息
    static let appName = "HAUT Network Guard"
    static let version = "1.3.4"
    static let author = "YellowPeach"
    static let website = "https://github.com/yellowpeachxgp/HAUTNetworkGuard"
    static let qqGroup = "789860526"

    // UserDefaults 键
    private let usernameKey = "haut_username"
    private let passwordKey = "haut_password"
    private let autoSaveKey = "haut_auto_save"
    private let hasConfiguredKey = "haut_has_configured"
    private let checkIntervalKey = "haut_check_interval"
    private let autoLoginKey = "haut_auto_login"

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
    
    /// 检测间隔 (秒), 默认 30 秒
    var checkInterval: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: checkIntervalKey)
            return value > 0 ? max(5, min(300, value)) : 30
        }
        set {
            UserDefaults.standard.set(max(5, min(300, newValue)), forKey: checkIntervalKey)
        }
    }
    
    /// 自动登录 (断线重连)
    var autoLogin: Bool {
        get {
            // 默认开启
            if UserDefaults.standard.object(forKey: autoLoginKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoLoginKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoLoginKey) }
    }

    /// 保存配置
    func save(username: String, password: String, autoSave: Bool, checkInterval: Int = 30, autoLogin: Bool = true) {
        self.username = username
        self.password = password
        self.autoSave = autoSave
        self.checkInterval = checkInterval
        self.autoLogin = autoLogin
        self.hasConfigured = true
        Logger.log("配置已保存 (检测间隔: \(checkInterval)秒)")
    }

    /// 清除配置
    func clear() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
        UserDefaults.standard.removeObject(forKey: autoSaveKey)
        UserDefaults.standard.removeObject(forKey: hasConfiguredKey)
        UserDefaults.standard.removeObject(forKey: checkIntervalKey)
        UserDefaults.standard.removeObject(forKey: autoLoginKey)
        Logger.log("配置已清除")
    }
}
