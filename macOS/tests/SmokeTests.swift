import Foundation

private var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("失败：\(message)\n", stderr)
        failures += 1
    }
}

@main
struct SmokeTests {
    static func main() {
        Logger.isEnabled = false
        let namespace = "cn.ehaut.networkguard.tests.logic." + UUID().uuidString
        let defaults = UserDefaults(suiteName: namespace)!
        let config = AppConfig(defaults: defaults, credentialStore: FaultPasswordStore())
        defer { defaults.removePersistentDomain(forName: namespace) }
        expect(SrunEncryption.encryptUsername("231040600203") == "{SRUN3}\r\n675484:44647", "用户名加密向量不匹配")
        expect(SrunEncryption.encryptPassword("password123") == "6gh>Agg:7gh@<gh=9cc99c", "密码加密向量不匹配")
        let okHTTP = Data("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nnot_online".utf8)
        expect(DirectHTTPClient.responseStatusCode(from: okHTTP) == 200,
               "HTTP 200 状态行应能被识别")
        let failedHTTP = Data("HTTP/1.1 503 Service Unavailable\r\n\r\nnot_online".utf8)
        expect(DirectHTTPClient.responseStatusCode(from: failedHTTP) == 503,
               "HTTP 503 状态行应能被识别")
        expect(DirectHTTPClient.responseStatusCode(from: Data("not_online".utf8)) == nil,
               "缺少 HTTP 状态行的响应应被拒绝")

        let login = SrunProtocol.classifyLoginResponse("login_error#E2531:User not found")
        expect(login.category == "error_E2531", "登录响应分类不匹配")
        expect(
            SrunProtocol.userFacingLoginMessage(login) == "学号或密码错误，请检查后重试。",
            "常见登录错误应转换为学生可理解的提示"
        )
        expect(
            SrunProtocol.userFacingNetworkError("The request timed out") ==
                "连接校园网网关超时，请确认已连接 Wi-Fi 或有线网络后重试。",
            "网络超时应转换为学生可理解的提示"
        )
        expect(
            SrunProtocol.userFacingNetworkError("Network is unreachable") ==
                "无法连接校园网网关，请检查网络连接后重试。",
            "网关不可达应转换为学生可理解的提示"
        )
        expect(
            SrunProtocol.userFacingNetworkError("unknown transport failure") ==
                "网络请求失败，请检查网络连接后重试。",
            "未知网络错误应使用通用提示"
        )
        expect(SrunProtocol.classifyLoginResponse("login_error#E25:short-code").category == "unknown",
               "短错误码不应被分类为标准错误")
        expect(SrunProtocol.classifyLoginResponse("login_error#E12345:long-code").category == "unknown",
               "超长错误码不应被分类为标准错误")
        expect(SrunProtocol.classifyLoginResponse("login_ok already_online").category == "success",
               "多个登录标记同时出现时应遵循 success 优先级")

        let parsed = SrunProtocol.parseStatusResponse(
            "jQuery_1712630100000({\"error\":\"ok\",\"user_name\":\"231040600203\",\"online_ip\":\"10.10.0.8\",\"sum_bytes\":12345678,\"sum_seconds\":321})",
            callback: "jQuery_1712630100000"
        )
        expect(parsed.online, "JSONP 状态解析应判定为在线")
        expect(parsed.format == "jsonp", "JSONP 状态解析格式不匹配")
        expect(parsed.ip == "10.10.0.8", "JSONP 状态解析 IP 不匹配")
        expect(parsed.usedBytes == 12345678, "JSONP 状态解析流量不匹配")
        expect(parsed.usedSeconds == 321, "JSONP 状态解析时长不匹配")

        let parsedStringNumbers = SrunProtocol.parseStatusResponse(
            "jQuery_1712630100001({\"error\":\"ok\",\"user_name\":\"231040600203\",\"online_ip\":\"10.10.0.8\",\"sum_bytes\":\"12345678\",\"sum_seconds\":\"321\"})",
            callback: "jQuery_1712630100001"
        )
        expect(parsedStringNumbers.online, "字符串数字 JSONP 状态解析应判定为在线")
        expect(parsedStringNumbers.usedBytes == 12345678, "字符串数字 JSONP 状态解析流量不匹配")
        expect(parsedStringNumbers.usedSeconds == 321, "字符串数字 JSONP 状态解析时长不匹配")

        let parsedInvalidNumber = SrunProtocol.parseStatusResponse(
            "jQuery_1712630100002({\"error\":\"ok\",\"user_name\":\"231040600203\",\"online_ip\":\"10.10.0.8\",\"sum_bytes\":\"invalid\",\"sum_seconds\":\"321\"})",
            callback: "jQuery_1712630100002"
        )
        expect(parsedInvalidNumber.online, "异常数字 JSONP 状态解析应保留在线状态")
        expect(parsedInvalidNumber.usedBytes == 0, "异常数字 JSONP 流量应回退为 0")
        expect(parsedInvalidNumber.usedSeconds == 321, "部分异常数字 JSONP 时长不匹配")
        let overflow = SrunProtocol.parseStatusResponse(
            #"{"user_name":"test-student","sum_bytes":1e100,"sum_seconds":-1e100}"#
        )
        expect(overflow.online && overflow.usedBytes == 0 && overflow.usedSeconds == 0,
               "超出 Int64 范围的数值应回退为零，不能导致应用崩溃")
        let fractional = SrunProtocol.parseStatusResponse(
            #"{"user_name":"test-student","sum_bytes":1.5,"sum_seconds":"321.5"}"#
        )
        expect(fractional.online && fractional.usedBytes == 0 && fractional.usedSeconds == 0,
               "JSON 小数指标应在各端安全回退为零")
        let malformedJSON = SrunProtocol.parseStatusResponse(
            #"jQuery_1712630100004({"error":"ok","user_name":"231040600203","online_ip":"10.10.0.8","sum_bytes":01,"sum_seconds":321})"#
        )
        expect(!malformedJSON.online && malformedJSON.format == "unparsed",
               "非法 JSON 数字语法应统一判为异常")
        let invalidJSONIP = SrunProtocol.parseStatusResponse(
            #"{"error":"ok","user_name":"","online_ip":"not-an-ip","sum_bytes":0,"sum_seconds":0}"#
        )
        expect(!invalidJSONIP.online && invalidJSONIP.format == "unparsed",
               "非法 JSON IP 应统一判为异常")
        let nullIdentity = SrunProtocol.parseStatusResponse(
            #"{"error":"ok","user_name":null,"online_ip":null,"sum_bytes":null,"sum_seconds":null}"#
        )
        expect(!nullIdentity.online && nullIdentity.format == "unparsed",
               "空身份 JSON 应统一判为异常")
        let emptyStatus = SrunProtocol.parseStatusResponse("  \n\t")
        expect(!emptyStatus.online && emptyStatus.format == "unparsed",
               "空状态响应不得误判离线")
        let integerBoundary = SrunProtocol.parseStatusResponse(
            #"{"user_name":"test-student","sum_bytes":9007199254740991,"sum_seconds":"9007199254740992"}"#
        )
        expect(integerBoundary.usedBytes == 9007199254740991 && integerBoundary.usedSeconds == 0,
               "跨语言安全范围上界应保留，超范围数字字符串应回退")
        expect(
            !SrunProtocol.preview("{\"user_name\":\"231040600203\"}").contains("231040600203"),
            "状态响应预览不得记录完整账号"
        )
        let privacyResponses = [
            "231040600203,321,10.10.0.8,12345678",
            #"{"user_name":"231040600203","password":"test-private","escaped":"x\"test-private"}"#,
            "username=%7BSRUN3%7Dencoded-private&password=test-private",
            "<html>231040600203 test-private encoded-private</html>",
            "未知结果：231040600203 test-private"
        ]
        for response in privacyResponses {
            let summary = SrunProtocol.preview(response)
            expect(!summary.contains("231040600203") && !summary.contains("test-private") &&
                   !summary.contains("encoded-private"), "任意格式响应不得泄漏账号或凭据")
            expect(summary.contains("<redacted>") && summary.contains("bytes"), "日志应保留脱敏标记和长度诊断")
        }
        expect(SrunProtocol.preview("test-private", limit: 0).isEmpty, "零长度预览不能输出正文")

        config.clear()
        config.save(
            username: " 231040600203 \n",
            password: "password123",
            autoSave: false,
            checkInterval: 45,
            autoLogin: true
        )
        expect(config.username == "231040600203", "用户名保存时应自动清洗空白")
        expect(defaults.string(forKey: "haut_password") == nil, "未勾选记住密码时不应持久化密码")

        config.password = "session-only"
        expect(config.password == "session-only", "会话密码应可读回")
        expect(defaults.string(forKey: "haut_password") == nil, "会话密码不应落盘")

        config.save(
            username: "231040600203",
            password: "keychain-password",
            autoSave: true,
            checkInterval: 45,
            autoLogin: true
        )
        expect(config.password == "keychain-password", "记住密码后应可读回")
        expect(defaults.string(forKey: "haut_password") == nil, "记住密码不应写入 UserDefaults")

        let unparsed = SrunProtocol.parseStatusResponse("unexpected body")
        expect(!unparsed.online, "无法解析的状态响应不应判定为在线")
        expect(unparsed.format == "unparsed", "无法解析的状态响应应标记为 unparsed")

        let invalidCsv = SrunProtocol.parseStatusResponse("oops,NaN,not-an-ip,garbage")
        expect(!invalidCsv.online, "异常 CSV 响应不应判定为在线")
        expect(invalidCsv.format == "unparsed", "异常 CSV 响应应标记为 unparsed")

        config.clear()
        runCredentialFailureTests()
        runNativeKeychainTests()
        if failures != 0 {
            fputs("macOS 测试失败，共 \(failures) 项。\n", stderr)
            exit(1)
        }
        print("macOS 协议、隔离配置、凭据故障注入及原生 Keychain 测试通过")
    }
}
