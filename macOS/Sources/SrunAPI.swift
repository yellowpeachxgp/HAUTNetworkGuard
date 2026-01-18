import Foundation

/// 网络状态枚举
enum NetworkStatus {
    case online(username: String, ip: String, usedBytes: Int64, usedSeconds: Int64)
    case offline
    case checking
    case error(String)

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .online(let username, let ip, let usedBytes, let usedSeconds):
            let dataStr = formatBytes(usedBytes)
            let timeStr = formatDuration(usedSeconds)
            return "在线: \(username)\nIP: \(ip)\n已用流量: \(dataStr)\n在线时长: \(timeStr)"
        case .offline:
            return "未连接"
        case .checking:
            return "检测中..."
        case .error(let msg):
            return "错误: \(msg)"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1073741824.0
        let mb = Double(bytes) / 1048576.0
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else {
            return String(format: "%.2f MB", mb)
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d小时%d分%d秒", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%d分%d秒", minutes, secs)
        } else {
            return String(format: "%d秒", secs)
        }
    }
}

/// 登录结果枚举
enum LoginResult {
    case success
    case alreadyOnline
    case failed(String)
}

/// SRUN3K API 封装
class SrunAPI {
    // 服务器配置
    static let serverIP = "172.16.154.130"
    static let loginPort = 69
    static let statusURL = "http://\(serverIP)/cgi-bin/rad_user_info"
    static let loginURL = "http://\(serverIP):\(loginPort)/cgi-bin/srun_portal"
    static let acId = "1"

    // 从配置读取凭据
    private var username: String { AppConfig.shared.username }
    private var password: String { AppConfig.shared.password }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    /// 检查网络状态 (使用 JSONP 格式，与 OpenWrt 一致)
    func checkStatus(completion: @escaping (NetworkStatus) -> Void) {
        // 生成 JSONP callback 参数
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let callback = "jQuery_\(timestamp)"
        
        var urlComponents = URLComponents(string: SrunAPI.statusURL)
        urlComponents?.queryItems = [
            URLQueryItem(name: "callback", value: callback),
            URLQueryItem(name: "_", value: String(timestamp))
        ]
        
        guard let url = urlComponents?.url else {
            completion(.error("无效的URL"))
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                Logger.log("状态检查失败: \(error.localizedDescription)")
                completion(.offline)
                return
            }

            guard let data = data,
                  let responseStr = String(data: data, encoding: .utf8) else {
                completion(.offline)
                return
            }

            Logger.log("状态响应: \(responseStr)")
            let status = self.parseStatusResponse(responseStr, callback: callback)
            completion(status)
        }
        task.resume()
    }

    /// 解析状态响应 (支持 JSONP 和 CSV 格式)
    private func parseStatusResponse(_ response: String, callback: String) -> NetworkStatus {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果响应为空或包含 "not_online"，则表示离线
        if trimmed.isEmpty || trimmed.contains("not_online") {
            return .offline
        }

        // 尝试解析 JSONP 响应: callback({...})
        if let jsonStr = extractJSONFromJSONP(trimmed, callback: callback) {
            if let jsonData = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                // 检查 error 字段
                if let error = json["error"] as? String,
                   error.contains("not_online") {
                    return .offline
                }
                
                // 解析用户信息 (与 OpenWrt 一致的字段名)
                let ip = json["online_ip"] as? String ?? ""
                let bytes = parseNumber(json["sum_bytes"])
                let seconds = parseNumber(json["sum_seconds"])
                let username = json["user_name"] as? String ?? ""
                
                if !username.isEmpty || !ip.isEmpty {
                    return .online(username: username, ip: ip,
                                  usedBytes: bytes, usedSeconds: seconds)
                }
            }
        }

        // 回退到 CSV 格式: username,time,ip,bytes,...
        let parts = trimmed.components(separatedBy: ",")
        if parts.count >= 4 {
            let username = parts[0]
            let ip = parts[2]
            let usedBytes = Int64(parts[3]) ?? 0
            let usedSeconds = Int64(parts[1]) ?? 0
            return .online(username: username, ip: ip,
                          usedBytes: usedBytes, usedSeconds: usedSeconds)
        }

        return .offline
    }
    
    /// 从 JSONP 响应中提取 JSON 字符串
    private func extractJSONFromJSONP(_ response: String, callback: String) -> String? {
        // 格式: callback({...}) 或 jQuery_xxx({...})
        let pattern = "jQuery_\\d+\\((.+)\\)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
           let range = Range(match.range(at: 1), in: response) {
            return String(response[range])
        }
        
        // 尝试精确匹配 callback
        let prefix = "\(callback)("
        let suffix = ")"
        if response.hasPrefix(prefix) && response.hasSuffix(suffix) {
            let start = response.index(response.startIndex, offsetBy: prefix.count)
            let end = response.index(response.endIndex, offsetBy: -suffix.count)
            return String(response[start..<end])
        }
        
        return nil
    }
    
    /// 解析数字 (支持 Int 和 String)
    private func parseNumber(_ value: Any?) -> Int64 {
        if let intValue = value as? Int64 {
            return intValue
        } else if let intValue = value as? Int {
            return Int64(intValue)
        } else if let doubleValue = value as? Double {
            return Int64(doubleValue)
        } else if let strValue = value as? String {
            return Int64(strValue) ?? 0
        }
        return 0
    }

    /// 执行登录
    func login(completion: @escaping (LoginResult) -> Void) {
        let encryptedUsername = SrunEncryption.encryptUsername(username)
        let encryptedPassword = SrunEncryption.encryptPassword(password)

        Logger.log("原始用户名: \(username)")
        Logger.log("加密用户名: \(encryptedUsername)")
        Logger.log("原始密码: \(password)")
        Logger.log("加密密码: \(encryptedPassword)")

        let params: [String: String] = [
            "action": "login",
            "username": encryptedUsername,
            "password": encryptedPassword,
            "ac_id": SrunAPI.acId,
            "drop": "0",
            "pop": "1",
            "type": "10",
            "n": "117",
            "mbytes": "0",
            "minutes": "0",
            "mac": "02:00:00:00:00:00"
        ]

        sendRequest(params: params) { result in
            completion(result)
        }
    }

    /// 执行注销
    func logout(completion: @escaping (LoginResult) -> Void) {
        let encryptedUsername = SrunEncryption.encryptUsername(username)

        let params: [String: String] = [
            "action": "logout",
            "username": encryptedUsername,
            "ac_id": SrunAPI.acId,
            "mac": "",
            "type": "2"
        ]

        sendRequest(params: params) { result in
            completion(result)
        }
    }

    /// 发送 POST 请求
    private func sendRequest(params: [String: String],
                            completion: @escaping (LoginResult) -> Void) {
        guard let url = URL(string: SrunAPI.loginURL) else {
            completion(.failed("无效的URL"))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                        forHTTPHeaderField: "Content-Type")

        let bodyString = params.map { "\($0.key)=\($0.value.urlEncoded)" }
                               .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        Logger.log("发送请求: \(SrunAPI.loginURL)")
        Logger.log("操作: \(params["action"] ?? "")")
        Logger.log("请求体: \(bodyString)")

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.log("请求失败: \(error.localizedDescription)")
                completion(.failed(error.localizedDescription))
                return
            }

            if let data = data,
               let responseStr = String(data: data, encoding: .utf8) {
                Logger.log("响应: \(responseStr)")
                let result = self.parseLoginResponse(responseStr)
                completion(result)
            } else {
                completion(.failed("无响应数据"))
            }
        }
        task.resume()
    }

    /// 解析登录响应
    private func parseLoginResponse(_ response: String) -> LoginResult {
        if response.contains("login_ok") {
            return .success
        } else if response.contains("already_online") {
            return .alreadyOnline
        } else if response.contains("logout_ok") {
            return .success
        } else {
            return .failed(response)
        }
    }
}

// MARK: - String 扩展
extension String {
    var urlEncoded: String {
        // 使用更严格的字符集，确保特殊字符被正确编码
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

// MARK: - 日志工具
struct Logger {
    static var isEnabled = true

    static func log(_ message: String) {
        guard isEnabled else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
}