import Foundation

struct SrunParsedStatus {
    let online: Bool
    let format: String
    let username: String
    let ip: String
    let usedBytes: Int64
    let usedSeconds: Int64
}

struct SrunLoginClassification {
    let category: String
    let message: String
    let errorCode: String?
}

enum SrunProtocol {
    static func userFacingLoginMessage(_ classification: SrunLoginClassification) -> String {
        switch classification.category {
        case "error_E2531":
            return "学号或密码错误，请检查后重试。"
        case "empty":
            return "校园网网关返回空响应，请检查网络后重试。"
        case "unknown":
            return "校园网网关返回了无法识别的结果，请稍后重试。"
        case "success":
            return "登录成功"
        case "already_online":
            return "已经在线"
        case "logout_ok":
            return "注销成功"
        case "not_online":
            return "当前未在线"
        default:
            if let errorCode = classification.errorCode {
                return "登录失败（错误码 \(errorCode)），请稍后重试。"
            }
            return "登录失败，请稍后重试。"
        }
    }

    static func preview(_ value: String, limit: Int = 160) -> String {
        // 网关可能在任意字段或异常正文中回显凭据，只输出长度摘要。
        let summary = "<redacted> (\(value.utf8.count) bytes)"
        return String(summary.prefix(max(0, limit)))
    }

    static func extractErrorCode(_ response: String) -> String? {
        guard let range = response.range(of: "E\\d+", options: .regularExpression) else {
            return nil
        }
        return String(response[range])
    }

    static func classifyLoginResponse(_ response: String) -> SrunLoginClassification {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("login_ok") {
            return SrunLoginClassification(category: "success", message: "登录成功", errorCode: nil)
        }
        if trimmed.contains("already_online") {
            return SrunLoginClassification(category: "already_online", message: "已在线", errorCode: nil)
        }
        if trimmed.contains("logout_ok") {
            return SrunLoginClassification(category: "logout_ok", message: "注销成功", errorCode: nil)
        }
        if trimmed.contains("not_online") {
            return SrunLoginClassification(category: "not_online", message: "当前不在线", errorCode: nil)
        }
        if let errorCode = extractErrorCode(trimmed) {
            return SrunLoginClassification(
                category: "error_\(errorCode)",
                message: trimmed.isEmpty ? "登录失败 (\(errorCode))" : trimmed,
                errorCode: errorCode
            )
        }
        if trimmed.isEmpty {
            return SrunLoginClassification(category: "empty", message: "空响应", errorCode: nil)
        }
        return SrunLoginClassification(category: "unknown", message: trimmed, errorCode: nil)
    }

    static func parseStatusResponse(_ response: String, callback: String? = nil) -> SrunParsedStatus {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("not_online") {
            return SrunParsedStatus(online: false, format: "offline", username: "", ip: "", usedBytes: 0, usedSeconds: 0)
        }

        let jsonString: String
        let format: String
        if let extracted = extractJSONFromJSONP(trimmed, callback: callback) {
            jsonString = extracted
            format = "jsonp"
        } else {
            jsonString = trimmed
            format = "json"
        }

        if let jsonData = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let error = json["error"] as? String,
               error.contains("not_online") {
                return SrunParsedStatus(online: false, format: "offline", username: "", ip: "", usedBytes: 0, usedSeconds: 0)
            }

            let username = json["user_name"] as? String ?? ""
            let ip = json["online_ip"] as? String ?? ""
            let usedBytes = parseNumber(json["sum_bytes"])
            let usedSeconds = parseNumber(json["sum_seconds"])
            if !username.isEmpty || !ip.isEmpty {
                return SrunParsedStatus(
                    online: true,
                    format: format,
                    username: username,
                    ip: ip,
                    usedBytes: usedBytes,
                    usedSeconds: usedSeconds
                )
            }
        }

        let parts = trimmed.components(separatedBy: ",")
        if parts.count >= 4,
           !parts[0].isEmpty,
           let usedSeconds = Int64(parts[1]),
           isValidIPv4(parts[2]),
           let usedBytes = Int64(parts[3]) {
            return SrunParsedStatus(
                online: true,
                format: "csv",
                username: parts[0],
                ip: parts[2],
                usedBytes: usedBytes,
                usedSeconds: usedSeconds
            )
        }

        return SrunParsedStatus(online: false, format: "unparsed", username: "", ip: "", usedBytes: 0, usedSeconds: 0)
    }

    private static func extractJSONFromJSONP(_ response: String, callback: String?) -> String? {
        let pattern = "jQuery_\\d+\\((.+)\\)$"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
           let range = Range(match.range(at: 1), in: response) {
            return String(response[range])
        }

        if let callback {
            let prefix = "\(callback)("
            if response.hasPrefix(prefix) && response.hasSuffix(")") {
                let start = response.index(response.startIndex, offsetBy: prefix.count)
                let end = response.index(before: response.endIndex)
                return String(response[start..<end])
            }
        }

        return nil
    }

    private static func parseNumber(_ value: Any?) -> Int64 {
        if let intValue = value as? Int64 {
            return intValue
        }
        if let intValue = value as? Int {
            return Int64(intValue)
        }
        if let doubleValue = value as? Double {
            return Int64(doubleValue)
        }
        if let stringValue = value as? String {
            return Int64(stringValue) ?? 0
        }
        return 0
    }

    private static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let octet = Int(part), octet >= 0, octet <= 255 else {
                return false
            }
            return true
        }
    }
}
