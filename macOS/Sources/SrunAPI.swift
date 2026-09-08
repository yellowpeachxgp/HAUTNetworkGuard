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

    var kindLabel: String {
        switch self {
        case .online:
            return "online"
        case .offline:
            return "offline"
        case .checking:
            return "checking"
        case .error:
            return "error"
        }
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
        }
        return String(format: "%.2f MB", mb)
    }

    private func formatDuration(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d小时%d分%d秒", hours, minutes, secs)
        }
        if minutes > 0 {
            return String(format: "%d分%d秒", minutes, secs)
        }
        return String(format: "%d秒", secs)
    }
}

/// 登录结果枚举
enum LoginResult {
    case success
    case alreadyOnline
    case failed(String)
}

/// 请求边界可替换，以便在不连接校园网的情况下回放控制器行为。
protocol SrunService {
    func checkStatus(completion: @escaping (NetworkStatus) -> Void)
    func login(completion: @escaping (LoginResult) -> Void)
    func logout(completion: @escaping (LoginResult) -> Void)
}

/// SRUN3K API 封装
class SrunAPI: SrunService {
    static let serverIP = "172.16.154.130"
    static let loginPort = 69
    static let statusURL = "http://\(serverIP)/cgi-bin/rad_user_info"
    static let loginURL = "http://\(serverIP):\(loginPort)/cgi-bin/srun_portal"
    static let acId = "1"

    private var username: String { AppConfig.shared.username }
    private var password: String { AppConfig.shared.password }
    private let httpClient = DirectHTTPClient(timeout: 10)

    func checkStatus(completion: @escaping (NetworkStatus) -> Void) {
        let requestID = Logger.makeRequestID(prefix: "status")
        let startedAt = CFAbsoluteTimeGetCurrent()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let callback = "jQuery_\(timestamp)"

        var urlComponents = URLComponents(string: SrunAPI.statusURL)
        urlComponents?.queryItems = [
            URLQueryItem(name: "callback", value: callback),
            URLQueryItem(name: "_", value: String(timestamp))
        ]

        guard let url = urlComponents?.url?.absoluteString else {
            Logger.warn("[\(requestID)] action=status phase=error class=invalid_url")
            completion(.error("无效的URL"))
            return
        }

        Logger.debug("[\(requestID)] action=status phase=request url=\(url)")
        httpClient.get(url: url) { result in
            switch result {
            case .success(let responseString):
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                let parsed = SrunProtocol.parseStatusResponse(responseString, callback: callback)
                let status: NetworkStatus
                if parsed.online {
                    status = .online(
                        username: parsed.username,
                        ip: parsed.ip,
                        usedBytes: parsed.usedBytes,
                        usedSeconds: parsed.usedSeconds
                    )
                } else if parsed.format == "offline" {
                    status = .offline
                } else {
                    status = .error("状态解析失败(\(parsed.format))")
                }
                let classification = parsed.online ? "online_\(parsed.format)" : parsed.format
                Logger.info("[\(requestID)] action=status phase=response class=\(classification) elapsed_ms=\(durationMs)")
                Logger.debug("[\(requestID)] action=status phase=response bytes=\(responseString.utf8.count) preview=\(SrunProtocol.preview(responseString))")
                completion(status)
            case .failure(let error):
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                Logger.warn("[\(requestID)] action=status phase=error class=network_error elapsed_ms=\(durationMs) msg=\(error.localizedDescription)")
                completion(.error(error.localizedDescription))
            }
        }
    }

    func login(completion: @escaping (LoginResult) -> Void) {
        guard !username.isEmpty, !password.isEmpty else {
            Logger.warn("登录已取消：凭据为空")
            completion(.failed("未配置学号或密码"))
            return
        }

        let requestID = Logger.makeRequestID(prefix: "login")
        let encryptedUsername = SrunEncryption.encryptUsername(username)
        let encryptedPassword = SrunEncryption.encryptPassword(password)

        Logger.info(
            "[\(requestID)] action=login phase=request account=\(Logger.maskUsername(username)) user_len=\(username.count) pass_len=\(password.count) remember_password=\(AppConfig.shared.autoSave)"
        )
        Logger.debug(
            "[\(requestID)] action=login phase=encode enc_user_len=\(encryptedUsername.count) enc_pass_len=\(encryptedPassword.count)"
        )

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

        sendRequest(params: params, requestID: requestID, completion: completion)
    }

    func logout(completion: @escaping (LoginResult) -> Void) {
        let requestID = Logger.makeRequestID(prefix: "logout")
        sendRequest(params: ["action": "logout"], requestID: requestID, completion: completion)
    }

    private func sendRequest(params: [String: String],
                             requestID: String,
                             completion: @escaping (LoginResult) -> Void) {
        let action = params["action"] ?? "unknown"
        let startedAt = CFAbsoluteTimeGetCurrent()
        let bodyString = params.map { "\($0.key)=\($0.value.urlEncoded)" }
            .joined(separator: "&")

        Logger.info("[\(requestID)] action=\(action) phase=request url=\(SrunAPI.loginURL) field_count=\(params.count) body_len=\(bodyString.utf8.count)")

        httpClient.post(url: SrunAPI.loginURL, body: bodyString) { result in
            switch result {
            case .success(let responseString):
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                let classified = SrunProtocol.classifyLoginResponse(responseString)
                Logger.info("[\(requestID)] action=\(action) phase=response class=\(classified.category) elapsed_ms=\(durationMs)")
                Logger.debug("[\(requestID)] action=\(action) phase=response preview=\(SrunProtocol.preview(responseString))")
                completion(self.mapLoginResult(action: action, classified: classified))
            case .failure(let error):
                let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                Logger.error("[\(requestID)] action=\(action) phase=error class=network_error elapsed_ms=\(durationMs) msg=\(error.localizedDescription)")
                completion(.failed(error.localizedDescription))
            }
        }
    }

    private func mapLoginResult(action: String, classified: SrunLoginClassification) -> LoginResult {
        if action == "logout" {
            if classified.category == "logout_ok" {
                return .success
            }
            if classified.category == "not_online" {
                return .alreadyOnline
            }
            return .failed(SrunProtocol.userFacingLoginMessage(classified))
        }

        switch classified.category {
        case "success":
            return .success
        case "already_online":
            return .alreadyOnline
        default:
            return .failed(SrunProtocol.userFacingLoginMessage(classified))
        }
    }
}

extension String {
    var urlEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
