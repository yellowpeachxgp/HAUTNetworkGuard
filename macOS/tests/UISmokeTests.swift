import Cocoa
import Darwin

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    Darwin.exit(EXIT_FAILURE)
}

private func pumpRunLoop(until condition: @escaping () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return condition()
}

@main
struct UISmokeTests {
    static func main() {
        Logger.isEnabled = false
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.accessory)
        guard DirectHTTPClient.preferredInterfaceName(from: [
            (name: "en1", type: .wifi),
            (name: "en0", type: .wiredEthernet)
        ]) == "en0" else { fail("有线接口应优先于 Wi-Fi") }
        guard DirectHTTPClient.preferredInterfaceName(from: [
            (name: "en1", type: .wifi)
        ]) == "en1" else { fail("没有有线接口时应回退到 Wi-Fi") }
        guard DirectHTTPClient.preferredInterfaceName(from: [
            (name: "utun0", type: .other)
        ]) == "utun0" else { fail("没有有线或 Wi-Fi 时应使用首个可用接口") }
        guard DirectHTTPClient.preferredInterfaceName(from: []) == nil else {
            fail("没有可用接口时应返回 nil")
        }
        guard !SingleInstanceGuard.anotherInstanceExists(testMode: true) else {
            fail("UI smoke 测试模式不应触发生产实例检查")
        }
        let lockPath = NSTemporaryDirectory() + "haut-instance-test-" + UUID().uuidString
        guard let firstLock = SingleInstanceGuard.tryAcquireLock(at: lockPath) else {
            fail("测试实例锁无法取得")
        }
        guard SingleInstanceGuard.tryAcquireLock(at: lockPath) == nil else {
            Darwin.close(firstLock)
            fail("第二个实例错误取得文件锁")
        }
        Darwin.close(firstLock)
        runControllerSessionTests()

        let controller = StatusBarController()
        var outcome: (Bool, String)?

        controller.runUISmokeTest { success, message in
            outcome = (success, message)
        }

        let finished = pumpRunLoop(until: { outcome != nil }, timeout: 10.0)
        guard finished, let outcome else {
            fail("UI smoke test 超时，未收到完成回调")
        }

        if !outcome.0 {
            fail(outcome.1)
        }

        let trackedTitles: Set<String> = ["账号设置", "关于", "检查更新"]
        let noVisibleTrackedWindows = pumpRunLoop(
            until: {
                NSApp.windows.allSatisfy { window in
                    !window.isVisible || !trackedTitles.contains(window.title)
                }
            },
            timeout: 2.0
        )
        guard noVisibleTrackedWindows else {
            let visibleWindows = NSApp.windows
                .filter { $0.isVisible && trackedTitles.contains($0.title) }
                .map { $0.title.isEmpty ? "<untitled>" : $0.title }
                .joined(separator: ", ")
            fputs("Visible windows: \(visibleWindows)\n", stderr)
            fail("UI smoke test 结束后仍有窗口未关闭")
        }

        guard NSApp.activationPolicy() == .accessory else {
            fail("UI smoke test 结束后激活策略未恢复到 accessory")
        }

        print("macOS UI smoke tests passed: \(outcome.1)")
    }
}
