import AppKit

/// bundle 级实例检查；UI smoke 使用独立进程，不参与生产实例判断。
enum SingleInstanceGuard {
    static let bundleIdentifier = "cn.ehaut.networkguard"

    static func anotherInstanceExists(testMode: Bool = AppRuntime.isUISmokeTest) -> Bool {
        guard !testMode else { return false }
        let identifier = Bundle.main.bundleIdentifier ?? bundleIdentifier
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains { $0.processIdentifier != currentPID }
    }
}
