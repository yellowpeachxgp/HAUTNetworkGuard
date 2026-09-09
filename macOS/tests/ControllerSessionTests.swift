import Cocoa

private final class SessionTestPasswordStore: PasswordStore {
    func read() throws -> String? { nil }
    func write(_ value: String) throws { fatalError("控制器测试不得持久化密码") }
    func delete() throws {}
}

private final class ReplaySrunService: SrunService {
    var statusReplies: [(NetworkStatus) -> Void] = []
    var loginReplies: [(LoginResult) -> Void] = []
    var logoutReplies: [(LoginResult) -> Void] = []
    private var networkChangeHandler: (() -> Void)?
    func checkStatus(completion: @escaping (NetworkStatus) -> Void) { statusReplies.append(completion) }
    func login(completion: @escaping (LoginResult) -> Void) { loginReplies.append(completion) }
    func logout(completion: @escaping (LoginResult) -> Void) { logoutReplies.append(completion) }
    func setNetworkChangeHandler(_ handler: (() -> Void)?) { networkChangeHandler = handler }
    func emitNetworkChange() { networkChangeHandler?() }
}

/// 执行正式菜单栏控制器；仅替换 I/O 与时钟，不连接校园网、不调用正式凭据域。
func runControllerSessionTests() {
    precondition(AppRuntime.isUISmokeTest, "必须使用隔离的 UI 测试模式")
    let namespace = "cn.ehaut.networkguard.tests.session." + UUID().uuidString
    let defaults = UserDefaults(suiteName: namespace)!
    defer { defaults.removePersistentDomain(forName: namespace) }
    let config = AppConfig(defaults: defaults, credentialStore: SessionTestPasswordStore())
    precondition(config.save(username: "test-student", password: "test-only", autoSave: false))
    let service = ReplaySrunService()
    let workspaceCenter = NotificationCenter()
    var clock: TimeInterval = 0
    let controller = StatusBarController(
        api: service,
        config: config,
        now: { clock },
        workspaceNotificationCenter: workspaceCenter,
        networkRecoveryEnabled: true,
        networkEventDebounceInterval: 0
    )
    var checked = 0

    func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checked += 1
    }
    func settle(_ extraWait: TimeInterval = 0) {
        var drained = false
        DispatchQueue.main.async { drained = true }
        let deadline = Date().addingTimeInterval(1)
        while !drained && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        precondition(drained, "主线程回调未完成")
        if extraWait > 0 {
            let waitUntil = Date().addingTimeInterval(extraWait)
            while Date() < waitUntil {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
            }
        }
    }
    func status(_ result: NetworkStatus) {
        let previous = service.statusReplies.count
        controller.checkStatus(reason: "session_test")
        expect(service.statusReplies.count == previous + 1, "空闲时应接受状态检测")
        service.statusReplies.last!(result)
        settle()
    }
    let online = NetworkStatus.online(username: "test-student", ip: "10.0.0.1", usedBytes: 0, usedSeconds: 0)
    let diagnostics = controller.diagnosticText()
    precondition(diagnostics.contains(AppConfig.version) &&
                 !diagnostics.contains("test-student") && !diagnostics.contains("test-only"),
                 "诊断信息不得包含账号或密码")

    expect(service.statusReplies.isEmpty && service.loginReplies.isEmpty, "测试初始化不得启动真实后台任务")
    controller.checkStatus(reason: "startup")
    controller.checkStatus(reason: "duplicate")
    controller.loginAction()
    controller.logoutAction()
    expect(service.statusReplies.count == 1, "状态请求必须串行")
    expect(service.loginReplies.isEmpty && service.logoutReplies.isEmpty, "检测未完成前不能认证")
    service.statusReplies[0](.error("模拟超时"))
    settle()
    expect(service.loginReplies.isEmpty, "状态异常不能触发自动登录")

    status(.offline)
    expect(service.loginReplies.count == 1, "明确离线应自动登录一次")
    controller.checkStatus(reason: "during_login")
    controller.loginAction()
    controller.logoutAction()
    expect(service.statusReplies.count == 2 && service.loginReplies.count == 1 && service.logoutReplies.isEmpty,
           "登录中必须拦截检测、重复登录和注销")
    clock = 10
    service.loginReplies[0](.failed("模拟密码错误"))
    settle()
    let retryDiagnostics = controller.diagnosticText()
    expect(retryDiagnostics.contains("自动重试约") && !retryDiagnostics.contains("Int(ceil"),
           "自动重试提示必须显示实际剩余秒数")
    clock = 11
    controller.loginAction()
    expect(service.loginReplies.count == 2, "用户纠正凭据后可手动重试")
    clock = 12
    service.loginReplies[1](.failed("模拟密码错误"))
    settle()
    expect(service.statusReplies.count == 3, "手动失败后应检查实际状态")
    service.statusReplies[2](.offline)
    settle()
    expect(service.loginReplies.count == 2, "手动失败后的离线结果不得立即再次登录")
    clock = 131
    status(.offline)
    expect(service.loginReplies.count == 2, "第二次失败后必须等待完整退避")
    clock = 132
    status(.offline)
    expect(service.loginReplies.count == 3, "冷却结束后可重试")
    clock = 133
    service.loginReplies[2](.success)
    settle()
    expect(service.statusReplies.count == 6, "登录成功后必须重新确认状态")
    service.statusReplies[5](online)
    settle()

    controller.logoutAction()
    expect(service.logoutReplies.count == 1, "在线时可注销")
    service.statusReplies[5](online)
    settle()
    controller.checkStatus(reason: "during_logout")
    expect(service.statusReplies.count == 6, "迟到的状态回调不得释放注销忙碌状态")
    service.logoutReplies[0](.alreadyOnline)
    settle()
    expect(service.statusReplies.count == 7, "注销返回当前未在线后应确认状态")
    service.statusReplies[6](.offline)
    settle()
    clock = 10000
    status(online)
    status(.offline)
    expect(service.loginReplies.count == 3, "注销后在线与离线变化都不能撤销暂停")

    controller.loginAction()
    expect(service.loginReplies.count == 4, "手动登录可恢复自动重连")
    service.loginReplies[2](.success)
    settle()
    expect(service.statusReplies.count == 9, "过期的登录回调不能启动额外检测")
    controller.logoutAction()
    expect(service.logoutReplies.count == 1, "过期回调不能释放当前登录忙碌状态")
    service.loginReplies[3](.success)
    settle()
    service.statusReplies.last!(online)
    settle()
    status(.offline)
    expect(service.loginReplies.count == 5, "显式恢复并确认在线后，断线可以重新自动登录")
    service.loginReplies[4](.failed("模拟结束"))
    settle()

    // 网络路径事件应去抖为一次检测；事件撞上请求时要在请求完成后补发一次。
    let beforeDebouncedRecovery = service.statusReplies.count
    service.emitNetworkChange()
    service.emitNetworkChange()
    service.emitNetworkChange()
    settle(0.05)
    expect(service.statusReplies.count == beforeDebouncedRecovery + 1,
           "连续网络路径事件应去抖为一次状态检测")
    service.statusReplies.last!(.error("模拟网络变化"))
    settle()

    let beforeWakeRecovery = service.statusReplies.count
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    settle(0.05)
    expect(service.statusReplies.count == beforeWakeRecovery + 1,
           "连续唤醒事件应去抖为一次状态检测")
    service.statusReplies.last!(.error("模拟唤醒"))
    settle()

    let beforeBusyRecovery = service.statusReplies.count
    controller.checkStatus(reason: "recovery_busy_seed")
    expect(service.statusReplies.count == beforeBusyRecovery + 1,
           "恢复检测串行测试应先占用一个状态请求")
    service.emitNetworkChange()
    settle(0.05)
    expect(service.statusReplies.count == beforeBusyRecovery + 1,
           "网络事件撞上状态请求时不得并发发起请求")
    service.statusReplies.last!(.error("模拟忙碌期间网络变化"))
    settle()
    expect(service.statusReplies.count == beforeBusyRecovery + 2,
           "忙碌期间网络事件应在当前请求完成后补发检测")
    service.statusReplies.last!(.error("模拟补发检测"))
    settle()

    print("macOS 正式控制器会话回放通过：\(checked) 个断言")
}
