import Foundation

/// 由主线程驱动；时间使用单调时钟的秒数，不受系统校时影响。
struct SessionPolicy {
    enum Observation { case unknown, offline, online, error }
    enum Operation { case idle, status, login, logout }

    private(set) var observation: Observation = .unknown
    private(set) var operation: Operation = .idle
    private(set) var manualOfflineHold = false
    private(set) var nextAutomaticAttempt: TimeInterval = 0
    private var sequence: UInt64 = 0
    private var failures = 0
    private var attemptInterval: TimeInterval = 60
    var isBusy: Bool { operation != .idle }

    mutating func beginStatus() -> UInt64? { begin(.status) }

    mutating func completeStatus(_ token: UInt64, observation: Observation) -> Bool {
        guard finish(token, .status) else { return false }
        self.observation = observation
        if observation == .online {
            failures = 0
            nextAutomaticAttempt = 0
        }
        // 检测结果不能撤销用户的手动离线意图。
        return true
    }

    mutating func beginLogin(manual: Bool, enabled: Bool, hasCredentials: Bool,
                             now: TimeInterval, interval: TimeInterval) -> UInt64? {
        guard !isBusy, hasCredentials else { return nil }
        if !manual && (!enabled || manualOfflineHold || observation != .offline || now < nextAutomaticAttempt) {
            return nil
        }
        guard let token = begin(.login) else { return nil }
        if manual { manualOfflineHold = false }
        observation = .unknown
        attemptInterval = max(60, interval)
        nextAutomaticAttempt = now + attemptInterval
        return token
    }

    mutating func completeLogin(_ token: UInt64, succeeded: Bool, now: TimeInterval) -> Bool {
        guard finish(token, .login) else { return false }
        // 认证成功仍需状态接口确认在线，不能复用登录前的离线结果。
        observation = succeeded ? .unknown : .error
        failures = succeeded ? 0 : min(failures + 1, 4)
        let multiplier = Double(1 << max(0, failures - 1))
        let delay = min(attemptInterval * multiplier, max(300, attemptInterval))
        nextAutomaticAttempt = now + delay
        return true
    }

    mutating func beginLogout() -> UInt64? {
        guard let token = begin(.logout) else { return nil }
        manualOfflineHold = true
        observation = .unknown
        return token
    }

    mutating func completeLogout(_ token: UInt64, succeeded: Bool) -> Bool {
        guard finish(token, .logout) else { return false }
        observation = succeeded ? .offline : .unknown
        return true
    }

    private mutating func begin(_ operation: Operation) -> UInt64? {
        guard !isBusy else { return nil }
        sequence += 1
        self.operation = operation
        return sequence
    }

    private mutating func finish(_ token: UInt64, _ operation: Operation) -> Bool {
        guard token == sequence, self.operation == operation else { return false }
        self.operation = .idle
        return true
    }
}
