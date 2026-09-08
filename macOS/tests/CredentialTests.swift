import Foundation

final class FaultPasswordStore: PasswordStore {
    var value: String?
    var failRead = false
    var failWrite = false
    var failDelete = false
    var dropNextWrite = false
    var readCount = 0

    func read() throws -> String? {
        readCount += 1
        if failRead { throw PasswordStoreError.operationFailed(-1) }
        return value
    }

    func write(_ value: String) throws {
        if failWrite { throw PasswordStoreError.operationFailed(-2) }
        if dropNextWrite { dropNextWrite = false; return }
        self.value = value
    }

    func delete() throws {
        if failDelete { throw PasswordStoreError.operationFailed(-3) }
        value = nil
    }
}

func runCredentialFailureTests() {
    let namespace = "cn.ehaut.networkguard.tests.failure." + UUID().uuidString
    let defaults = UserDefaults(suiteName: namespace)!
    defer { defaults.removePersistentDomain(forName: namespace) }
    let store = FaultPasswordStore()
    let config = AppConfig(defaults: defaults, credentialStore: store)

    store.value = "stale-value"
    defaults.set("legacy-stale", forKey: "haut_password")
    expect(config.password.isEmpty, "未勾选记住密码时不得读取旧持久化凭据")
    expect(store.readCount == 0, "未勾选记住密码时不得访问钥匙串")
    expect(defaults.string(forKey: "haut_password") == nil, "应清理未授权保留的旧明文")

    defaults.set(true, forKey: "haut_auto_save")
    defaults.set("legacy-password", forKey: "haut_password")
    store.value = nil
    store.failWrite = true
    let migrating = AppConfig(defaults: defaults, credentialStore: store)
    expect(migrating.password == "legacy-password", "迁移失败后本次会话仍应有可用密码")
    expect(migrating.password == "legacy-password", "重复读取不应因迁移失败而丢失密码")
    expect(defaults.string(forKey: "haut_password") == "legacy-password", "迁移失败不得删除唯一恢复来源")
    expect(migrating.credentialWarning != nil, "迁移失败应报告而不能假成功")
    store.failWrite = false
    let retryMigration = AppConfig(defaults: defaults, credentialStore: store)
    expect(retryMigration.password == "legacy-password", "后续启动应能重试迁移")
    expect(store.value == "legacy-password", "迁移必须写入存储后端")
    expect(defaults.string(forKey: "haut_password") == nil, "回读成功后才删除旧明文")

    expect(config.save(username: "old-user", password: "old-password", autoSave: true), "准备原配置失败")
    store.failWrite = true
    expect(!config.save(username: "new-user", password: "new-password", autoSave: true), "写入失败必须返回失败")
    expect(config.username == "old-user", "写入失败不得提交新账号")
    expect(config.password == "old-password", "写入失败不得形成新账号与旧密码混用")
    expect(store.value == "old-password", "写入失败应保留旧持久化密码")
    expect(config.credentialWarning != nil, "设置窗口必须能取得失败说明")

    store.failWrite = false
    store.dropNextWrite = true
    expect(!config.save(username: "new-user", password: "new-password", autoSave: true), "写入声称成功但回读不一致也必须失败")
    expect(store.value == "old-password", "回读校验失败应恢复旧密码")
    expect(config.username == "old-user", "回读校验失败不得提交新账号")

    store.failDelete = true
    expect(!config.save(username: "session-user", password: "session-password", autoSave: false), "删除失败必须对用户可见")
    expect(!config.autoSave, "删除失败也必须停止使用持久化密码")
    expect(config.password == "session-password", "本次会话应使用明确输入的新密码")
    let optedOut = AppConfig(defaults: defaults, credentialStore: store)
    let before = store.readCount
    expect(optedOut.password.isEmpty && store.readCount == before, "重启后不得重新加载删除失败的旧条目")
    store.failDelete = false
    expect(config.clear(), "恢复访问后应可清除凭据")
    expect(store.value == nil && config.password.isEmpty, "清除应同时清空会话与后端")

    defaults.set(true, forKey: "haut_auto_save")
    store.value = "unlock-password"
    store.failRead = true
    let locked = AppConfig(defaults: defaults, credentialStore: store)
    expect(locked.password.isEmpty && locked.credentialWarning != nil, "读取失败应报告状态")
    store.failRead = false
    expect(locked.password == "unlock-password", "解锁后应重试读取，不能永久缓存空密码")
}

func runNativeKeychainTests() {
    // 名称随机且带 tests 前缀；不查询、修改或删除正式应用的服务名。
    let namespace = "cn.ehaut.networkguard.tests.native." + UUID().uuidString
    let defaults = UserDefaults(suiteName: namespace)!
    let store = KeychainPasswordStore(service: namespace)
    defer {
        do { try store.delete() }
        catch { expect(false, "测试钥匙串清理失败") }
        defaults.removePersistentDomain(forName: namespace)
    }
    do {
        let config = AppConfig(defaults: defaults, credentialStore: store)
        expect(config.save(username: "native-user", password: "native-password", autoSave: true), "原生钥匙串保存失败")
        let persisted = try store.read()
        expect(persisted == "native-password", "必须直接验证钥匙串值，不能只验证会话缓存")
        let cold = AppConfig(defaults: defaults, credentialStore: store)
        expect(cold.password == "native-password", "新配置实例应从钥匙串恢复密码")
        expect(defaults.string(forKey: "haut_password") == nil, "新保存不得产生明文 UserDefaults")
        cold.autoSave = false
        let deleted = try store.read()
        expect(deleted == nil, "取消记住密码应实际删除钥匙串条目")
        expect(cold.password == "native-password", "取消持久化应保留当前会话")
        let restart = AppConfig(defaults: defaults, credentialStore: store)
        expect(restart.password.isEmpty, "取消记住密码后重启应没有密码")

        defaults.set(true, forKey: "haut_auto_save")
        defaults.set("native-legacy", forKey: "haut_password")
        let migrating = AppConfig(defaults: defaults, credentialStore: store)
        expect(migrating.password == "native-legacy", "原生旧配置迁移失败")
        let migrated = try store.read()
        expect(migrated == "native-legacy", "迁移结果必须存在于真实钥匙串")
        expect(defaults.string(forKey: "haut_password") == nil, "迁移回读成功后应清理旧值")
        expect(migrating.clear(), "原生清理失败")
        let cleared = try store.read()
        expect(cleared == nil, "清除配置后不应残留测试条目")
    } catch {
        expect(false, "原生钥匙串测试发生存储错误：\(error)")
    }
}
