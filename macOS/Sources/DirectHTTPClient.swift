import Foundation
import Network
import Darwin

/// 绕过系统代理/VPN，通过物理网络接口直连内网网关的 HTTP 客户端
/// 使用 POSIX socket + IP_BOUND_IF 在内核层面绑定物理接口，
/// 彻底绕过 TUN 路由和系统代理设置
class DirectHTTPClient {
    private let queue = DispatchQueue(label: "DirectHTTPClient")
    private let stateQueue = DispatchQueue(label: "DirectHTTPClient.state")
    private let monitorQueue = DispatchQueue(label: "DirectHTTPClient.monitor")
    private var interfaceName: String?
    private var pathSignature: String?
    private var didReceiveInitialMonitorPath = false
    private var networkChangeHandler: (() -> Void)?
    private let monitor: NWPathMonitor
    private let timeout: TimeInterval

    /// 网络路径发生实际变化时回调。回调在 Network 监控队列上执行，调用方应自行切回主线程。
    var onNetworkChange: (() -> Void)? {
        get { stateQueue.sync { networkChangeHandler } }
        set { stateQueue.sync { networkChangeHandler = newValue } }
    }

    init(timeout: TimeInterval = 10) {
        self.timeout = timeout
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            self?.updateInterface(from: path, isMonitorUpdate: true)
        }
        self.monitor.start(queue: monitorQueue)
        updateInterface(from: monitor.currentPath, isMonitorUpdate: false)
    }

    deinit {
        monitor.cancel()
    }

    static func preferredInterfaceName(
        from interfaces: [(name: String, type: NWInterface.InterfaceType)]
    ) -> String? {
        if let wired = interfaces.first(where: { $0.type == .wiredEthernet }) {
            return wired.name
        }
        if let wifi = interfaces.first(where: { $0.type == .wifi }) {
            return wifi.name
        }
        return interfaces.first?.name
    }

    /// 从网络路径中选取物理接口（优先有线，其次 WiFi）
    private func updateInterface(from path: NWPath, isMonitorUpdate: Bool) {
        let interfaces = path.availableInterfaces
        let resolvedName = Self.preferredInterfaceName(
            from: interfaces.map { (name: $0.name, type: $0.type) }
        )
        if let resolvedName {
            if interfaces.first(where: { $0.name == resolvedName })?.type == .wiredEthernet {
                Logger.info("[DirectHTTP] 使用有线接口: \(resolvedName)")
            } else if interfaces.first(where: { $0.name == resolvedName })?.type == .wifi {
                Logger.info("[DirectHTTP] 使用 WiFi 接口: \(resolvedName)")
            } else {
                Logger.info("[DirectHTTP] 使用接口: \(resolvedName)")
            }
        } else {
            Logger.warn("[DirectHTTP] 未找到可用物理接口")
        }

        // 首次回调通常只是 currentPath 的重复快照；后续回调即使仍使用同一 en 接口，
        // 也可能代表用户切换了 Wi-Fi，交给控制器统一去抖，避免漏掉恢复检测。
        let signature = Self.pathSignature(path, resolvedInterface: resolvedName)
        let shouldNotify = stateQueue.sync {
            let signatureChanged = pathSignature != signature
            let isInitialMonitorPath = isMonitorUpdate && !didReceiveInitialMonitorPath
            if isMonitorUpdate {
                didReceiveInitialMonitorPath = true
            }
            pathSignature = signature
            interfaceName = resolvedName
            guard isMonitorUpdate else { return false }
            // 第一次异步快照若与同步 currentPath 不同，仍需通知；之后每个系统路径事件
            // 都交给上层去抖，因为 NWPath 的公开字段不足以区分同一接口下的 Wi-Fi 切换。
            return isInitialMonitorPath ? signatureChanged : true
        }
        if shouldNotify, let handler = onNetworkChange {
            handler()
        }
    }

    private static func pathSignature(_ path: NWPath, resolvedInterface: String?) -> String {
        let interfaces = path.availableInterfaces
            .map { "\($0.name):\($0.type)" }
            .sorted()
            .joined(separator: ",")
        return "status=\(path.status);interface=\(resolvedInterface ?? "");available=\(interfaces);expensive=\(path.isExpensive);constrained=\(path.isConstrained)"
    }

    // MARK: - Public API

    /// 发送 GET 请求
    func get(url: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let parsed = parseURL(url) else {
            completion(.failure(HTTPError.invalidURL("无效的 URL: \(url)")))
            return
        }
        let request = "GET \(parsed.path) HTTP/1.1\r\n" +
                      hostHeader(parsed.host, port: parsed.port) +
                      "Connection: close\r\n\r\n"
        performRequest(host: parsed.host, port: parsed.port, request: request, completion: completion)
    }

    /// 发送 POST 请求（application/x-www-form-urlencoded）
    func post(url: String, body: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let parsed = parseURL(url) else {
            completion(.failure(HTTPError.invalidURL("无效的 URL: \(url)")))
            return
        }
        let bodyBytes = body.data(using: .utf8) ?? Data()
        let request = "POST \(parsed.path) HTTP/1.1\r\n" +
                      hostHeader(parsed.host, port: parsed.port) +
                      "Content-Type: application/x-www-form-urlencoded\r\n" +
                      "Content-Length: \(bodyBytes.count)\r\n" +
                      "Connection: close\r\n\r\n" +
                      body
        performRequest(host: parsed.host, port: parsed.port, request: request, completion: completion)
    }

    // MARK: - Private

    private func hostHeader(_ host: String, port: UInt16) -> String {
        return port == 80 ? "Host: \(host)\r\n" : "Host: \(host):\(port)\r\n"
    }

    /// 使用 POSIX socket 发送 HTTP 请求，通过 IP_BOUND_IF 绑定物理接口
    private func performRequest(host: String, port: UInt16, request: String,
                                completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 解析目标地址
            guard var addr = self.resolveHost(host, port: port) else {
                completion(.failure(HTTPError.invalidURL("无法解析主机 \(host):\(port)")))
                return
            }

            let interfaceForRequest = self.waitForInterfaceName(timeout: 1.0)
            Logger.debug(
                "[DirectHTTP] 准备发起请求 host=\(host) port=\(port) interface=\(interfaceForRequest ?? "system_default") timeout=\(Int(self.timeout))s"
            )

            // 创建 TCP socket
            let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else {
                completion(.failure(self.socketError(phase: "socket", code: errno)))
                return
            }
            defer { Darwin.close(fd) }

            // 绑定到物理接口（绕过 TUN 路由和代理）
            if let ifName = interfaceForRequest {
                let ifIndex = if_nametoindex(ifName)
                if ifIndex > 0 {
                    var idx = ifIndex
                    let ret = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF,
                                         &idx, socklen_t(MemoryLayout<UInt32>.size))
                    if ret == 0 {
                        Logger.debug("[DirectHTTP] 绑定接口: \(ifName) (index=\(ifIndex))")
                    } else {
                        Logger.warn("[DirectHTTP] 绑定接口失败: \(ifName), errno=\(errno)")
                    }
                }
            } else {
                Logger.warn("[DirectHTTP] 请求开始时仍未解析到物理接口，将使用系统默认路由")
            }

            // 避免在写入已关闭 socket 时触发 SIGPIPE
            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            // 设置超时
            var tv = timeval(tv_sec: Int(self.timeout), tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            // connect 在 macOS 上不会遵守 SO_SNDTIMEO，需要显式做非阻塞超时控制
            let originalFlags = fcntl(fd, F_GETFL, 0)
            if originalFlags >= 0 {
                _ = fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK)
            }

            let connectResult = self.connectWithTimeout(fd: fd, address: &addr)
            if originalFlags >= 0 {
                _ = fcntl(fd, F_SETFL, originalFlags)
            }

            if let connectError = connectResult {
                completion(.failure(connectError))
                return
            }

            // 发送请求
            guard let requestData = request.data(using: .utf8) else {
                completion(.failure(HTTPError.invalidURL("请求编码失败")))
                return
            }
            let sent = self.sendAll(fd: fd, data: requestData)
            if let sentError = sent {
                completion(.failure(sentError))
                return
            }

            // 接收响应（Connection: close，读到 EOF）
            var responseData = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = recv(fd, &buffer, buffer.count, 0)
                if n == 0 { break }
                if n < 0 {
                    let err = errno
                    if self.isTimeoutErrno(err) {
                        completion(.failure(HTTPError.timeout(phase: "recv")))
                    } else {
                        completion(.failure(self.socketError(phase: "recv", code: err)))
                    }
                    return
                }
                responseData.append(buffer, count: n)
            }

            guard let statusCode = Self.responseStatusCode(from: responseData) else {
                completion(.failure(HTTPError.invalidResponse("响应缺少有效 HTTP 状态行")))
                return
            }
            guard (200..<300).contains(statusCode) else {
                completion(.failure(HTTPError.httpStatus(statusCode)))
                return
            }

            // 解析 HTTP body
            if let body = self.extractHTTPBody(from: responseData) {
                Logger.debug("[DirectHTTP] 收到响应 host=\(host) port=\(port) bytes=\(responseData.count) body_chars=\(body.count)")
                completion(.success(body))
            } else if let str = String(data: responseData, encoding: .utf8) {
                Logger.debug("[DirectHTTP] 收到原始响应 host=\(host) port=\(port) bytes=\(responseData.count) body_chars=\(str.count)")
                completion(.success(str))
            } else {
                completion(.failure(HTTPError.invalidResponse("响应不是有效 UTF-8，bytes=\(responseData.count)")))
            }
        }
    }

    /// 解析主机名为 IPv4 地址
    private func resolveHost(_ host: String, port: UInt16) -> sockaddr_in? {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        // 先尝试直接解析 IP
        if inet_pton(AF_INET, host, &addr.sin_addr) == 1 {
            Logger.debug("[DirectHTTP] 主机直连解析成功 host=\(host)")
            return addr
        }

        // DNS 解析
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let ai = result else {
            return nil
        }
        defer { freeaddrinfo(result) }

        if ai.pointee.ai_family == AF_INET {
            let sin = ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            addr.sin_addr = sin.sin_addr
            Logger.debug("[DirectHTTP] DNS 解析成功 host=\(host)")
            return addr
        }
        return nil
    }

    /// 从原始 HTTP 响应中提取 body
    private func extractHTTPBody(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        if let range = raw.range(of: "\r\n\r\n") {
            return String(raw[range.upperBound...])
        }
        return raw
    }

    /// 读取原始 HTTP 响应状态码；非 2xx 由传输层视为失败，不能交给协议层误判。
    static func responseStatusCode(from data: Data) -> Int? {
        guard let headerEnd = data.range(of: Data("\r\n".utf8)) else { return nil }
        guard let statusLine = String(data: data[..<headerEnd.lowerBound], encoding: .ascii) else {
            return nil
        }
        let parts = statusLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"),
              let code = Int(parts[1]), (100...599).contains(code) else {
            return nil
        }
        return code
    }

    // MARK: - URL 解析

    private struct ParsedURL {
        let host: String
        let port: UInt16
        let path: String
    }

    private func parseURL(_ url: String) -> ParsedURL? {
        guard let comps = URLComponents(string: url),
              let host = comps.host else {
            return nil
        }
        let port = UInt16(comps.port ?? 80)
        var path = comps.path.isEmpty ? "/" : comps.path
        if let query = comps.query {
            path += "?\(query)"
        }
        return ParsedURL(host: host, port: port, path: path)
    }

    private func currentInterfaceName() -> String? {
        stateQueue.sync { interfaceName }
    }

    private func waitForInterfaceName(timeout: TimeInterval) -> String? {
        if let name = currentInterfaceName() {
            return name
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            if let name = currentInterfaceName() {
                return name
            }
        }
        return currentInterfaceName()
    }

    private func sendAll(fd: Int32, data: Data) -> HTTPError? {
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return HTTPError.invalidURL("请求数据为空")
            }

            let basePointer = baseAddress.assumingMemoryBound(to: UInt8.self)
            var offset = 0
            while offset < data.count {
                let sent = Darwin.send(fd, basePointer.advanced(by: offset), data.count - offset, 0)
                if sent <= 0 {
                    let err = errno
                    if isTimeoutErrno(err) {
                        return HTTPError.timeout(phase: "send")
                    }
                    return socketError(phase: "send", code: err)
                }
                offset += sent
            }

            return nil
        }
    }

    private func connectWithTimeout(fd: Int32, address: inout sockaddr_in) -> HTTPError? {
        let connectResult = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return nil
        }

        let err = errno
        guard err == EINPROGRESS else {
            if isTimeoutErrno(err) {
                return HTTPError.timeout(phase: "connect")
            }
            return socketError(phase: "connect", code: err)
        }

        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let selected = poll(&descriptor, 1, Int32(timeout * 1000))
        if selected == 0 {
            return HTTPError.timeout(phase: "connect")
        }
        if selected < 0 {
            return socketError(phase: "poll(connect)", code: errno)
        }

        var socketErrorCode: Int32 = 0
        var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
        if getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketErrorCode, &socketErrorLength) < 0 {
            return socketError(phase: "getsockopt(connect)", code: errno)
        }
        if socketErrorCode != 0 {
            if isTimeoutErrno(socketErrorCode) {
                return HTTPError.timeout(phase: "connect")
            }
            return socketError(phase: "connect", code: socketErrorCode)
        }

        return nil
    }

    private func isTimeoutErrno(_ code: Int32) -> Bool {
        code == ETIMEDOUT || code == EAGAIN || code == EWOULDBLOCK
    }

    private func socketError(phase: String, code: Int32) -> HTTPError {
        let message = String(cString: strerror(code))
        return .socketError("\(phase) 失败, errno=\(code) (\(message))")
    }

    enum HTTPError: Error, LocalizedError, CustomStringConvertible {
        case invalidURL(String)
        case timeout(phase: String)
        case invalidResponse(String)
        case httpStatus(Int)
        case socketError(String)

        var description: String {
            switch self {
            case .invalidURL(let message):
                return message
            case .timeout(let phase):
                return "请求超时 (\(phase))"
            case .invalidResponse(let message):
                return message
            case .httpStatus(let code): return "网关 HTTP 状态异常 (\(code))"
            case .socketError(let msg): return "Socket 错误: \(msg)"
            }
        }

        var errorDescription: String? { description }
    }
}
