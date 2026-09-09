import Foundation
import CFNetwork

/// 版本更新信息
struct ReleaseInfo {
    let version: String
    let htmlURL: String
    let downloadURL: String?
    let releaseNotes: String
}

/// 更新检测结果
enum UpdateCheckResult {
    case hasUpdate(ReleaseInfo)
    case noUpdate(ReleaseInfo)  // 包含当前最新版本信息
    case error(String)
}

/// 更新检测器
class UpdateChecker {
    static let shared = UpdateChecker()

    // GitHub Release API
    private let releaseAPIURL = "https://api.github.com/repos/yellowpeachxgp/HAUTNetworkGuard/releases/latest"

    // 检测间隔：1天 (秒)
    private let checkInterval: TimeInterval = 86400

    // UserDefaults 键
    private let lastCheckKey = "haut_last_update_check"
    private let skippedVersionKey = "haut_skipped_version"

    private static let defaultRequestTimeout: TimeInterval = 10
    private static let defaultResourceTimeout: TimeInterval = 15
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval
    private let directSession: URLSession
    private let systemSession: URLSession
    private let transportQueue = DispatchQueue(label: "cn.ehaut.networkguard.update.transport", qos: .utility)
    private var checkTimer: Timer?
    private var isChecking = false

    static func isValidReleaseTag(_ tag: String) -> Bool {
        tag.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    }

    static func isTrustedReleaseURL(_ value: String, tag: String, assetName: String? = nil) -> Bool {
        guard isValidReleaseTag(tag), let url = URL(string: value), url.scheme == "https",
              url.host == "github.com", url.path.hasPrefix("/yellowpeachxgp/HAUTNetworkGuard/") else { return false }
        if let assetName {
            return url.path == "/yellowpeachxgp/HAUTNetworkGuard/releases/download/\(tag)/\(assetName)"
        }
        return url.path == "/yellowpeachxgp/HAUTNetworkGuard/releases/tag/\(tag)"
    }

    // 后台自动检测回调（只在有更新时触发）
    var onUpdateAvailable: ((ReleaseInfo) -> Void)?

    // 手动检测完成回调（无论是否有更新都触发）
    var onCheckComplete: ((UpdateCheckResult) -> Void)?

    private init() {
        self.requestTimeout = UpdateChecker.defaultRequestTimeout
        self.resourceTimeout = UpdateChecker.defaultResourceTimeout
        self.directSession = UpdateChecker.makeSession(
            useSystemProxy: false,
            requestTimeout: UpdateChecker.defaultRequestTimeout,
            resourceTimeout: UpdateChecker.defaultResourceTimeout
        )
        self.systemSession = UpdateChecker.makeSession(
            useSystemProxy: true,
            requestTimeout: UpdateChecker.defaultRequestTimeout,
            resourceTimeout: UpdateChecker.defaultResourceTimeout
        )
    }

    private enum TransportMode: String {
        case directSession = "urlsession_direct_no_proxy"
        case curlHTTP1 = "curl_http1_no_proxy"
        case systemSession = "urlsession_system_proxy"
    }

    private enum UpdateNetworkError: Error, LocalizedError {
        case invalidHTTPStatus(Int)
        case missingResponseData
        case invalidReleasePayload
        case curlUnavailable(String)
        case curlFailure(Int32, String)

        var errorDescription: String? {
            switch self {
            case .invalidHTTPStatus(let statusCode):
                if statusCode == 403 {
                    return "GitHub API 请求被拒绝，可能触发了频率限制"
                }
                return "GitHub API 返回异常状态码: \(statusCode)"
            case .missingResponseData:
                return "服务器无响应"
            case .invalidReleasePayload:
                return "版本信息或下载地址不可信，已停止更新。"
            case .curlUnavailable(let message):
                return "无法执行更新回退链路: \(message)"
            case .curlFailure(_, let message):
                return message
            }
        }
    }

    private static func makeSession(
        useSystemProxy: Bool,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        if #available(macOS 10.13, *) {
            config.waitsForConnectivity = false
        }
        if !useSystemProxy {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: false,
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false,
                kCFNetworkProxiesProxyAutoConfigEnable as String: false,
                kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false
            ]
        }
        return URLSession(configuration: config)
    }

    /// 启动定期检测
    func startPeriodicCheck() {
        checkTimer?.invalidate()

        // 立即检测一次（如果距离上次检测超过1天）
        if shouldCheckNow() {
            checkForUpdate(isManual: false)
        }

        // 设置定时器，每小时检查一次是否需要检测更新
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            if self?.shouldCheckNow() == true {
                self?.checkForUpdate(isManual: false)
            }
        }
    }

    /// 停止定期检测
    func stopPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// 判断是否需要立即检测
    private func shouldCheckNow() -> Bool {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        return (now - lastCheck) >= checkInterval
    }

    /// 检测更新
    /// - Parameters:
    ///   - isManual: 是否为手动检测（手动检测会触发 onCheckComplete 回调）
    ///   - force: 是否强制检测（忽略跳过的版本）
    func checkForUpdate(isManual: Bool = true, force: Bool = false) {
        if isChecking {
            Logger.info("已有更新检测进行中，跳过重复请求")
            return
        }

        guard let url = URL(string: releaseAPIURL) else {
            if isManual {
                DispatchQueue.main.async {
                    self.onCheckComplete?(.error("无效的 API 地址"))
                }
            }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("HAUTNetworkGuard/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")

        isChecking = true
        let requestID = Logger.makeRequestID(prefix: "update")
        let startedAt = CFAbsoluteTimeGetCurrent()

        Logger.info("[\(requestID)] action=update phase=request manual=\(isManual) force=\(force) url=\(releaseAPIURL)")
        Logger.debug("[\(requestID)] action=update phase=proxy_snapshot value=\(proxySnapshot())")

        fetchReleasePayload(request: request, requestID: requestID) { [weak self] result in
            guard let self = self else { return }
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            defer { self.isChecking = false }

            switch result {
            case .success(let data):
                Logger.info("[\(requestID)] action=update phase=response elapsed_ms=\(durationMs) bytes=\(data.count)")
                self.parseReleaseResponse(data, requestID: requestID, isManual: isManual, force: force)
            case .failure(let error):
                let message = self.userFriendlyMessage(for: error)
                Logger.warn("[\(requestID)] action=update phase=error elapsed_ms=\(durationMs) msg=\(message) detail=\(self.describeError(error))")
                if isManual {
                    DispatchQueue.main.async {
                        self.onCheckComplete?(.error(message))
                    }
                }
            }
        }
    }

    /// 解析 Release 响应
    private func parseReleaseResponse(_ data: Data, requestID: String, isManual: Bool, force: Bool) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                Logger.warn("[\(requestID)] action=update phase=parse_error class=invalid_release_payload")
                if isManual {
                    DispatchQueue.main.async {
                        self.onCheckComplete?(.error("解析版本信息失败"))
                    }
                }
                return
            }

            guard Self.isValidReleaseTag(tagName),
                  let htmlURL = json["html_url"] as? String,
                  Self.isTrustedReleaseURL(htmlURL, tag: tagName) else {
                throw UpdateNetworkError.invalidReleasePayload
            }
            // 提取版本号 (去掉 v 前缀)
            let latestVersion = String(tagName.dropFirst())

            Logger.info("[\(requestID)] action=update phase=compare current=\(AppConfig.version) latest=\(latestVersion)")

            // 获取下载链接
            var downloadURL: String? = nil
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name == "HAUTNetworkGuard.dmg",
                       let url = asset["browser_download_url"] as? String,
                       Self.isTrustedReleaseURL(url, tag: tagName, assetName: name) {
                        downloadURL = url
                        break
                    }
                }
            }

            let releaseInfo = ReleaseInfo(
                version: latestVersion,
                htmlURL: htmlURL,
                downloadURL: downloadURL,
                releaseNotes: json["body"] as? String ?? "暂无更新说明"
            )

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

            // 比较版本号
            let hasUpdate = isNewerVersion(latestVersion, than: AppConfig.version)

            if hasUpdate {
                // 检查是否跳过了此版本
                let skippedVersion = UserDefaults.standard.string(forKey: skippedVersionKey)
                if !force && !isManual && skippedVersion == latestVersion {
                    Logger.info("[\(requestID)] action=update phase=skip_skipped_version version=\(latestVersion)")
                    return
                }

                Logger.info("[\(requestID)] action=update phase=has_update version=\(latestVersion)")

                DispatchQueue.main.async {
                    if !isManual {
                        self.onUpdateAvailable?(releaseInfo)
                    } else {
                        self.onCheckComplete?(.hasUpdate(releaseInfo))
                    }
                }
            } else {
                Logger.info("[\(requestID)] action=update phase=no_update")
                if isManual {
                    DispatchQueue.main.async {
                        self.onCheckComplete?(.noUpdate(releaseInfo))
                    }
                }
            }
        } catch {
            Logger.warn("[\(requestID)] action=update phase=parse_error class=json_decode_failure detail=\(describeError(error))")
            if isManual {
                DispatchQueue.main.async {
                    self.onCheckComplete?(.error("解析数据失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 比较版本号
    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(newParts.count, currentParts.count)

        for i in 0..<maxCount {
            let newPart = i < newParts.count ? newParts[i] : 0
            let currentPart = i < currentParts.count ? currentParts[i] : 0

            if newPart > currentPart {
                return true
            } else if newPart < currentPart {
                return false
            }
        }

        return false
    }

    /// 跳过此版本
    func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: skippedVersionKey)
        Logger.info("已跳过版本: \(version)")
    }

    /// 清除跳过的版本
    func clearSkippedVersion() {
        UserDefaults.standard.removeObject(forKey: skippedVersionKey)
        Logger.info("已清除跳过的版本记录")
    }

    private func fetchReleasePayload(
        request: URLRequest,
        requestID: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        performCurlRequest(request: request, requestID: requestID) { [weak self] curlResult in
            guard let self = self else { return }

            switch curlResult {
            case .success(let data):
                completion(.success(data))
            case .failure(let curlError):
                let fallbackSession = self.hasConfiguredSystemProxy() ? self.systemSession : self.directSession
                let fallbackTransport: TransportMode = self.hasConfiguredSystemProxy() ? .systemSession : .directSession

                self.performURLSessionRequest(
                    session: fallbackSession,
                    transport: fallbackTransport,
                    request: request,
                    requestID: requestID
                ) { sessionResult in
                    switch sessionResult {
                    case .success(let data):
                        completion(.success(data))
                    case .failure(let sessionError):
                        Logger.error("[\(requestID)] action=update phase=fallback_result curl=\(self.describeError(curlError)) session=\(self.describeError(sessionError))")
                        completion(.failure(sessionError))
                    }
                }
            }
        }
    }

    private func performURLSessionRequest(
        session: URLSession,
        transport: TransportMode,
        request: URLRequest,
        requestID: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        Logger.info("[\(requestID)] action=update phase=transport_start mode=\(transport.rawValue)")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                Logger.warn("[\(requestID)] action=update phase=transport_error mode=\(transport.rawValue) detail=\(self.describeError(error))")
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let error = UpdateNetworkError.invalidHTTPStatus(httpResponse.statusCode)
                Logger.warn("[\(requestID)] action=update phase=transport_error mode=\(transport.rawValue) detail=\(self.describeError(error))")
                completion(.failure(error))
                return
            }

            guard let data = data else {
                let error = UpdateNetworkError.missingResponseData
                Logger.warn("[\(requestID)] action=update phase=transport_error mode=\(transport.rawValue) detail=\(self.describeError(error))")
                completion(.failure(error))
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            Logger.info("[\(requestID)] action=update phase=transport_ok mode=\(transport.rawValue) status=\(statusCode) bytes=\(data.count)")
            completion(.success(data))
        }

        task.resume()
    }

    private func performCurlRequest(
        request: URLRequest,
        requestID: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let url = request.url?.absoluteString else {
            completion(.failure(UpdateNetworkError.curlUnavailable("更新地址为空")))
            return
        }

        transportQueue.async { [weak self] in
            guard let self = self else { return }
            Logger.info("[\(requestID)] action=update phase=transport_start mode=\(TransportMode.curlHTTP1.rawValue)")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

            var arguments = [
                "--silent",
                "--show-error",
                "--location",
                "--fail",
                "--http1.1",
                "--noproxy", "*",
                "--connect-timeout", String(Int(self.requestTimeout)),
                "--max-time", String(Int(self.resourceTimeout))
            ]

            if let method = request.httpMethod, method.uppercased() != "GET" {
                arguments.append(contentsOf: ["--request", method.uppercased()])
            }

            let headers = request.allHTTPHeaderFields ?? [:]
            for header in headers.keys.sorted() {
                if let value = headers[header] {
                    arguments.append(contentsOf: ["--header", "\(header): \(value)"])
                }
            }

            arguments.append(url)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    Logger.info("[\(requestID)] action=update phase=transport_ok mode=\(TransportMode.curlHTTP1.rawValue) status=0 bytes=\(outputData.count)")
                    completion(.success(outputData))
                    return
                }

                let message = stderr.isEmpty
                    ? "curl 回退链路失败，退出码 \(process.terminationStatus)"
                    : "curl 回退链路失败: \(stderr)"
                let error = UpdateNetworkError.curlFailure(process.terminationStatus, message)
                Logger.warn("[\(requestID)] action=update phase=transport_error mode=\(TransportMode.curlHTTP1.rawValue) detail=\(self.describeError(error))")
                completion(.failure(error))
            } catch {
                let fallbackError = UpdateNetworkError.curlUnavailable(error.localizedDescription)
                Logger.warn("[\(requestID)] action=update phase=transport_error mode=\(TransportMode.curlHTTP1.rawValue) detail=\(self.describeError(fallbackError))")
                completion(.failure(fallbackError))
            }
        }
    }

    private func userFriendlyMessage(for error: Error) -> String {
        if let updateError = error as? UpdateNetworkError {
            switch updateError {
            case .curlFailure(_, let detail):
                let lowercased = detail.lowercased()
                if lowercased.contains("ssl") || lowercased.contains("tls") {
                    return "TLS错误导致安全连接失败。"
                }
                if lowercased.contains("timed out") || lowercased.contains("timeout") {
                    return "请求超时。"
                }
                return updateError.localizedDescription
            default:
                return updateError.localizedDescription
            }
        }

        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "请求超时。"
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return "TLS错误导致安全连接失败。"
        case NSURLErrorNotConnectedToInternet:
            return "当前网络不可用。"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "无法连接到 GitHub 更新服务器。"
        default:
            if nsError.domain == NSURLErrorDomain {
                return nsError.localizedDescription
            }
            return error.localizedDescription
        }
    }

    private func describeError(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "type=\(String(describing: type(of: error)))",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "desc=\(error.localizedDescription)"
        ]

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)#\(underlying.code):\(underlying.localizedDescription)")
        }
        if let failingURL = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            parts.append("url=\(failingURL)")
        }

        return parts.joined(separator: " ")
    }

    private func proxySnapshot() -> String {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return "unavailable"
        }

        var parts: [String] = []

        if isProxyEnabled(settings[kCFNetworkProxiesProxyAutoConfigEnable as String]),
           let pacURL = settings[kCFNetworkProxiesProxyAutoConfigURLString as String] as? String,
           !pacURL.isEmpty {
            parts.append("pac=\(pacURL)")
        }
        if isProxyEnabled(settings[kCFNetworkProxiesHTTPEnable as String]) {
            let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String ?? "unknown"
            let port = settings[kCFNetworkProxiesHTTPPort as String] ?? "?"
            parts.append("http=\(host):\(port)")
        }
        if isProxyEnabled(settings[kCFNetworkProxiesHTTPSEnable as String]) {
            let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String ?? "unknown"
            let port = settings[kCFNetworkProxiesHTTPSPort as String] ?? "?"
            parts.append("https=\(host):\(port)")
        }
        if isProxyEnabled(settings[kCFNetworkProxiesSOCKSEnable as String]) {
            let host = settings[kCFNetworkProxiesSOCKSProxy as String] as? String ?? "unknown"
            let port = settings[kCFNetworkProxiesSOCKSPort as String] ?? "?"
            parts.append("socks=\(host):\(port)")
        }

        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }

    private func hasConfiguredSystemProxy() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return false
        }

        return isProxyEnabled(settings[kCFNetworkProxiesProxyAutoConfigEnable as String])
            || isProxyEnabled(settings[kCFNetworkProxiesHTTPEnable as String])
            || isProxyEnabled(settings[kCFNetworkProxiesHTTPSEnable as String])
            || isProxyEnabled(settings[kCFNetworkProxiesSOCKSEnable as String])
    }

    private func isProxyEnabled(_ value: Any?) -> Bool {
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        return false
    }
}
