import Foundation
import Security
import LocalAuthentication

/// 存储边界可注入，行为测试不访问正式应用的配置域或钥匙串条目。
protocol PasswordStore {
    func read() throws -> String?
    func write(_ value: String) throws
    func delete() throws
}

enum PasswordStoreError: Error {
    case operationFailed(OSStatus)
    case verificationFailed
}

struct KeychainPasswordStore: PasswordStore {
    let service: String
    var account = "default"

    private var query: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // 后台重连不能弹出阻塞式钥匙串认证窗口。
            kSecUseAuthenticationContext as String: context
        ]
    }

    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw PasswordStoreError.operationFailed(status)
        }
        guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw PasswordStoreError.verificationFailed
        }
        return password
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        var status = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            status = SecItemAdd(request as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw PasswordStoreError.operationFailed(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasswordStoreError.operationFailed(status)
        }
    }
}

/// 配置提交必须报告凭据失败；旧明文仅在安全写入并回读后清理。
class AppConfig {
    static let shared: AppConfig = {
        if ProcessInfo.processInfo.arguments.contains("--ui-smoke-test") {
            let namespace = "cn.ehaut.networkguard.tests.ui." + UUID().uuidString
            return AppConfig(
                defaults: UserDefaults(suiteName: namespace)!,
                credentialStore: KeychainPasswordStore(service: namespace)
            )
        }
        return AppConfig(
            defaults: .standard,
            credentialStore: KeychainPasswordStore(service: "cn.ehaut.networkguard")
        )
    }()

    static let appName = "HAUT Network Guard"
    static let version = BuildVersion.value
    static let author = "YellowPeach"
    static let website = "https://github.com/yellowpeachxgp/HAUTNetworkGuard"
    static let qqGroup = "789860526"

    private let defaults: UserDefaults
    private let credentialStore: PasswordStore
    private let usernameKey = "haut_username"
    private let passwordKey = "haut_password"
    private let autoSaveKey = "haut_auto_save"
    private let hasConfiguredKey = "haut_has_configured"
    private let checkIntervalKey = "haut_check_interval"
    private let autoLoginKey = "haut_auto_login"
    private var sessionPassword: String?
    private(set) var credentialWarning: String?

    init(defaults: UserDefaults, credentialStore: PasswordStore) {
        self.defaults = defaults
        self.credentialStore = credentialStore
    }

    var hasConfigured: Bool {
        get { defaults.bool(forKey: hasConfiguredKey) }
        set { defaults.set(newValue, forKey: hasConfiguredKey) }
    }

    var autoSave: Bool {
        get { defaults.bool(forKey: autoSaveKey) }
        set {
            if !newValue {
                let currentPassword = password
                defaults.set(false, forKey: autoSaveKey)
                sessionPassword = currentPassword
                _ = removePersistentPassword()
            } else {
                defaults.set(true, forKey: autoSaveKey)
            }
        }
    }

    var username: String {
        get { defaults.string(forKey: usernameKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: usernameKey) }
    }

    var password: String {
        get {
            if let cached = sessionPassword { return cached }
            guard autoSave else {
                defaults.removeObject(forKey: passwordKey)
                return ""
            }
            if let legacy = defaults.string(forKey: passwordKey), !legacy.isEmpty {
                sessionPassword = legacy
                if writeVerified(legacy) {
                    defaults.removeObject(forKey: passwordKey)
                } else {
                    credentialWarning = "旧密码尚未成功迁移到钥匙串，原配置已保留，请解锁钥匙串后重试。"
                }
                return legacy
            }
            do {
                let stored = try credentialStore.read()
                sessionPassword = stored
                credentialWarning = nil
                return stored ?? ""
            } catch {
                credentialWarning = "无法读取已保存的密码，请解锁钥匙串或重新输入。"
                return ""
            }
        }
        set {
            if autoSave {
                let previous = password
                sessionPassword = previous
                guard writeVerified(newValue) else { return }
                defaults.removeObject(forKey: passwordKey)
            } else {
                _ = removePersistentPassword()
            }
            sessionPassword = newValue
        }
    }

    var checkInterval: Int {
        get {
            let value = defaults.integer(forKey: checkIntervalKey)
            return value > 0 ? max(30, min(300, value)) : 30
        }
        set { defaults.set(max(30, min(300, newValue)), forKey: checkIntervalKey) }
    }

    var autoLogin: Bool {
        get {
            defaults.object(forKey: autoLoginKey) == nil ? true : defaults.bool(forKey: autoLoginKey)
        }
        set { defaults.set(newValue, forKey: autoLoginKey) }
    }

    @discardableResult
    func save(username: String, password: String, autoSave: Bool,
              checkInterval: Int = 30, autoLogin: Bool = true) -> Bool {
        if autoSave {
            let previous = self.password
            sessionPassword = previous
            guard writeVerified(password) else { return false }
            defaults.removeObject(forKey: passwordKey)
        }

        self.username = username
        defaults.set(autoSave, forKey: autoSaveKey)
        self.checkInterval = checkInterval
        self.autoLogin = autoLogin
        hasConfigured = true
        sessionPassword = password
        if !autoSave && !removePersistentPassword() { return false }
        credentialWarning = nil
        Logger.info("配置已保存 account=\(Logger.maskUsername(self.username)) remember_password=\(autoSave)")
        return true
    }

    private func writeVerified(_ value: String) -> Bool {
        var previous: String?
        var attemptedWrite = false
        do {
            previous = try credentialStore.read()
            attemptedWrite = true
            try credentialStore.write(value)
            guard try credentialStore.read() == value else {
                throw PasswordStoreError.verificationFailed
            }
            credentialWarning = nil
            return true
        } catch {
            if attemptedWrite {
                do {
                    if let previous { try credentialStore.write(previous) }
                    else { try credentialStore.delete() }
                } catch {
                    credentialWarning = "钥匙串写入和恢复失败，配置未提交，请解锁钥匙串后重试。"
                    return false
                }
            }
            credentialWarning = "密码未能安全保存，配置未提交。请解锁钥匙串，或取消“记住密码”后重试。"
            return false
        }
    }

    private func removePersistentPassword() -> Bool {
        defaults.removeObject(forKey: passwordKey)
        do {
            try credentialStore.delete()
            credentialWarning = nil
            return true
        } catch {
            credentialWarning = "已停止读取已保存密码，但钥匙串条目未能删除，请解锁钥匙串后重试。"
            return false
        }
    }

    @discardableResult
    func clear() -> Bool {
        sessionPassword = ""
        for key in [usernameKey, passwordKey, autoSaveKey, hasConfiguredKey, checkIntervalKey, autoLoginKey] {
            defaults.removeObject(forKey: key)
        }
        return removePersistentPassword()
    }
}
