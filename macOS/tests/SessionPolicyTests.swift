import Foundation

@main
struct SessionPolicyTests {
    static func main() throws {
        let lines = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).components(separatedBy: .newlines)
        let observations: [String: SessionPolicy.Observation] = [
            "unknown": .unknown, "offline": .offline, "online": .online, "error": .error]
        let operations: [String: SessionPolicy.Operation] = [
            "idle": .idle, "status": .status, "login": .login, "logout": .logout]
        var policy = SessionPolicy()
        var tokens: [String: UInt64] = [:]
        var scenario = ""
        var checked = 0
        var scenarios = 0
        for (lineIndex, line) in lines.enumerated() {
            if line.isEmpty || line.hasPrefix("#") { continue }
            let row = line.split(separator: " ").map(String.init)
            func bit(_ i: Int) -> Bool { row[i] == "1" }
            func number(_ i: Int) -> Double { Double(row[i])! }
            if row[0] == "scenario" {
                scenario = row[1]
                policy = SessionPolicy()
                tokens = [:]
                scenarios += 1
                continue
            }
            let alias = row[1]
            var actual = false
            let expected = row[0] == "expect" ? true : row.last == "1"
            switch row[0] {
            case "expect":
                actual = policy.observation == observations[alias] &&
                    policy.operation == operations[row[2]] &&
                    policy.manualOfflineHold == bit(3) && policy.nextAutomaticAttempt == number(4)
            case "status_start", "logout_start":
                let token = row[0] == "status_start" ? policy.beginStatus() : policy.beginLogout()
                actual = token != nil
                if let token { tokens[alias] = token }
            case "status_end":
                actual = policy.completeStatus(tokens[alias]!, observation: observations[row[2]]!)
            case "login_start":
                let token = policy.beginLogin(manual: bit(2), enabled: bit(3), hasCredentials: bit(4),
                                              now: number(5), interval: number(6))
                actual = token != nil
                if let token { tokens[alias] = token }
            case "login_end":
                actual = policy.completeLogin(tokens[alias]!, succeeded: bit(2), now: number(3))
            case "logout_end":
                actual = policy.completeLogout(tokens[alias]!, succeeded: bit(2))
            default:
                fatalError("未知事件：\(row[0])")
            }
            guard actual == expected else {
                fatalError("失败：\(scenario)，第 \(lineIndex + 1) 行：\(line)")
            }
            checked += 1
        }
        guard checked > 0 else { fatalError("没有执行任何断言") }
        print("Swift 会话策略通过：\(scenarios) 个场景，\(checked) 个事件断言")
    }
}
