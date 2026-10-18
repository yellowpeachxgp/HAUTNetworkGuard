import AppKit
import Darwin

/// 用户临时目录上的原子实例锁；UI smoke 使用独立测试模式，不参与生产实例判断。
enum SingleInstanceGuard {
    static let bundleIdentifier = "cn.ehaut.networkguard"
    private static var lockDescriptor: Int32 = -1

    static func tryAcquireLock(at path: String) -> Int32? {
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            return nil
        }
        return descriptor
    }

    static func anotherInstanceExists(testMode: Bool = AppRuntime.isUISmokeTest) -> Bool {
        guard !testMode else { return false }
        if lockDescriptor >= 0 { return false }
        let lockPath = NSTemporaryDirectory() + bundleIdentifier + ".lock"
        guard let descriptor = tryAcquireLock(at: lockPath) else { return true }
        lockDescriptor = descriptor
        return false
    }
}
