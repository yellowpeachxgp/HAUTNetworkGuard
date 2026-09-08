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
        guard !SingleInstanceGuard.anotherInstanceExists(testMode: true) else {
            fail("UI smoke 测试模式不应触发生产实例检查")
        }
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
