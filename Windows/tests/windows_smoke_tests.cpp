#include "../src/config.h"
#include "../src/encryption.h"
#include "../src/logger.h"
#include "../src/protocol_utils.h"
#include <QCoreApplication>
#include <QDebug>
#include <QSettings>
#include <QTemporaryDir>
#include <cstdlib>

namespace {

[[noreturn]] void fail(const QString &message) {
  qCritical().noquote() << message;
  std::exit(1);
}

void expect(bool condition, const QString &message) {
  if (!condition) {
    fail(message);
  }
}

} // namespace

int main(int argc, char *argv[]) {
  QCoreApplication app(argc, argv);
  app.setOrganizationName("YellowPeach");
  app.setApplicationName("HAUTNetworkGuard-SmokeTests");
  Logger::setEnabled(false);
  QTemporaryDir storage;
  expect(storage.isValid(), "无法建立独立测试配置目录");

  expect(Encryption::encryptUsername("231040600203") ==
             "{SRUN3}\r\n675484:44647",
         "用户名加密向量不匹配");
  expect(Encryption::encryptPassword("password123") == "6gh>Agg:7gh@<gh=9cc99c",
         "密码加密向量不匹配");
  expect(Logger::maskUsername("231040600203") != "231040600203",
         "用户名脱敏失败");
  expect(ProtocolUtils::classifyLoginResponse(
             "login_error#E2531:User not found") == "error_E2531",
         "登录响应分类不匹配");
  expect(ProtocolUtils::classifyLoginResponse("login_error#E25:short-code") ==
             "unknown",
         "短错误码不应被分类为标准错误");
  expect(ProtocolUtils::classifyLoginResponse("login_error#E12345:long-code") ==
             "unknown",
         "超长错误码不应被分类为标准错误");
  expect(ProtocolUtils::classifyLoginResponse("login_ok already_online") ==
             "success",
         "多个登录标记同时出现时应遵循 success 优先级");

  const StatusParseResult jsonResult = ProtocolUtils::parseStatusResponse(
      "jQuery_1712630100000({\"error\":\"ok\",\"user_name\":\"231040600203\","
      "\"online_ip\":\"10.10.0.8\",\"sum_bytes\":12345678,"
      "\"sum_seconds\":321})");
  expect(jsonResult.online, "JSONP 状态解析应判定为在线");
  expect(jsonResult.format == "jsonp", "JSONP 状态解析格式不匹配");
  expect(jsonResult.ip == "10.10.0.8", "JSONP 状态解析 IP 不匹配");
  expect(jsonResult.bytes == 12345678, "JSONP 状态解析流量不匹配");
  expect(jsonResult.seconds == 321, "JSONP 状态解析时长不匹配");

  const StatusParseResult stringNumberResult = ProtocolUtils::parseStatusResponse(
      "jQuery_1712630100001({\"error\":\"ok\",\"user_name\":\"231040600203\","
      "\"online_ip\":\"10.10.0.8\",\"sum_bytes\":\"12345678\","
      "\"sum_seconds\":\"321\"})");
  expect(stringNumberResult.online, "字符串数字 JSONP 状态解析应判定为在线");
  expect(stringNumberResult.bytes == 12345678,
         "字符串数字 JSONP 状态解析流量不匹配");
  expect(stringNumberResult.seconds == 321,
         "字符串数字 JSONP 状态解析时长不匹配");

  expect(ProtocolUtils::userFacingLoginMessage("error_E2531") ==
             "学号或密码错误，请检查后重试。",
         "常见登录错误应转换为学生可理解的提示");
  expect(ProtocolUtils::userFacingNetworkError("Connection timed out") ==
             "连接校园网网关超时，请确认已连接 Wi-Fi 或有线网络后重试。",
         "网络超时应转换为学生可理解的提示");
  expect(ProtocolUtils::userFacingNetworkError("Host not found") ==
             "无法连接校园网网关，请检查网络连接后重试。",
         "网关不可达应转换为学生可理解的提示");
  expect(ProtocolUtils::userFacingNetworkError("TLS internal failure") ==
             "网络请求失败，请检查网络连接后重试。",
         "未知网络错误应使用通用提示");
  expect(ProtocolUtils::userFacingNetworkError("Service unavailable", 503) ==
             "校园网网关返回异常，请稍后重试。",
         "HTTP 服务异常不得提示为账号密码错误");
  expect(ProtocolUtils::userFacingNetworkError("cannot connect") ==
             "无法连接校园网网关，请检查网络连接后重试。",
         "三端网关连接失败提示应一致");
  expect(!ProtocolUtils::responsePreview(
                  "{\"user_name\":\"231040600203\"}")
                  .contains("231040600203"),
         "状态响应预览不得记录完整账号");
  const QStringList privacyResponses = {
      "231040600203,321,10.10.0.8,12345678",
      R"({"user_name":"231040600203","password":"test-private","escaped":"x\"test-private"})",
      "username=%7BSRUN3%7Dencoded-private&password=test-private",
      "<html>231040600203 test-private encoded-private</html>",
      "未知结果：231040600203 test-private"};
  for (const auto &response : privacyResponses) {
    const auto summary = ProtocolUtils::responsePreview(response);
    expect(!summary.contains("231040600203") && !summary.contains("test-private") &&
           !summary.contains("encoded-private"), "任意格式响应不得泄漏账号或凭据");
    expect(summary.contains("<redacted>") && summary.contains("bytes"), "日志应保留脱敏标记和长度诊断");
  }
  expect(ProtocolUtils::responsePreview("test-private", 0).isEmpty(), "零长度预览不能输出正文");

  const StatusParseResult invalidNumberResult = ProtocolUtils::parseStatusResponse(
      "jQuery_1712630100002({\"error\":\"ok\",\"user_name\":\"231040600203\","
      "\"online_ip\":\"10.10.0.8\",\"sum_bytes\":\"invalid\","
      "\"sum_seconds\":\"321\"})");
  expect(invalidNumberResult.online, "异常数字 JSONP 状态解析应保留在线状态");
  expect(invalidNumberResult.bytes == 0, "异常数字 JSONP 流量应回退为 0");
  expect(invalidNumberResult.seconds == 321, "部分异常数字 JSONP 时长不匹配");

  const StatusParseResult csvResult = ProtocolUtils::parseStatusResponse(
      "231040600203,321,10.10.0.8,12345678,0,0");
  expect(csvResult.online, "CSV 状态解析应判定为在线");
  expect(csvResult.format == "csv", "CSV 状态解析格式不匹配");

  const StatusParseResult invalidCsvResult =
      ProtocolUtils::parseStatusResponse("oops,NaN,not-an-ip,garbage");
  expect(!invalidCsvResult.online, "异常 CSV 响应不应判定为在线");
  expect(invalidCsvResult.format == "unparsed",
         "异常 CSV 响应应标记为 unparsed");
  const StatusParseResult fractionalResult = ProtocolUtils::parseStatusResponse(
      "jQuery_1712630100003({\"error\":\"ok\",\"user_name\":\"231040600203\","
      "\"online_ip\":\"10.10.0.8\",\"sum_bytes\":1.5,\"sum_seconds\":\"321.5\"})");
  expect(fractionalResult.online && fractionalResult.bytes == 0 && fractionalResult.seconds == 0,
         "JSON 小数指标应安全回退为零");
  const StatusParseResult fractionalCsvResult =
      ProtocolUtils::parseStatusResponse("231040600203,321.5,10.10.0.8,12345678");
  expect(!fractionalCsvResult.online && fractionalCsvResult.format == "unparsed",
         "CSV 小数指标应统一判为异常");
  const StatusParseResult malformedJsonResult = ProtocolUtils::parseStatusResponse(
      "jQuery_1712630100004({\"error\":\"ok\",\"user_name\":\"231040600203\","
      "\"online_ip\":\"10.10.0.8\",\"sum_bytes\":01,\"sum_seconds\":321})");
  expect(!malformedJsonResult.online && malformedJsonResult.format == "unparsed",
         "非法 JSON 数字语法应统一判为异常");
  const StatusParseResult invalidJsonIpResult = ProtocolUtils::parseStatusResponse(
      "{\"error\":\"ok\",\"user_name\":\"\",\"online_ip\":\"not-an-ip\","
      "\"sum_bytes\":0,\"sum_seconds\":0}");
  expect(!invalidJsonIpResult.online && invalidJsonIpResult.format == "unparsed",
         "非法 JSON IP 应统一判为异常");
  const StatusParseResult nullIdentityResult = ProtocolUtils::parseStatusResponse(
      "{\"error\":\"ok\",\"user_name\":null,\"online_ip\":null,"
      "\"sum_bytes\":null,\"sum_seconds\":null}");
  expect(!nullIdentityResult.online && nullIdentityResult.format == "unparsed",
         "空身份 JSON 应统一判为异常");
  const StatusParseResult emptyStatusResult =
      ProtocolUtils::parseStatusResponse("  \n\t");
  expect(!emptyStatusResult.online && emptyStatusResult.format == "unparsed",
         "空状态响应不得误判离线");

  QSettings settings(storage.filePath("settings.ini"), QSettings::IniFormat);

  Config config(settings);
  config.setUsername("231040600203");
  config.setPassword("password123");
  config.setAutoSave(false);
  config.setAutoLaunch(false);
  config.setAutoLogin(true);
  config.setHasConfigured(true);
  config.setCheckInterval(45);
  config.save();

  settings.sync();
  expect(settings.value("password").toString().isEmpty(),
         "未勾选记住密码时不应持久化密码");

  config.setAutoSave(true);
  config.save();
  settings.sync();
  expect(!settings.value("password").toString().isEmpty(),
         "勾选记住密码后应持久化密码");
  const QString savedPassword = settings.value("password").toString();
#ifdef Q_OS_WIN
  expect(settings.value("password").toString().startsWith("DPAPI:"),
         "Windows 持久化密码必须使用 DPAPI 格式");
#endif
  Config coldStart(settings);
  expect(coldStart.password() == "password123", "独立实例应能读取持久化密码");
  config.setAutoSave(false);
  config.save();
  Config forgotten(settings);
  expect(forgotten.password().isEmpty(), "关闭记住密码后冷启动不能读取旧密码");
  settings.setValue("password", savedPassword);
  settings.sync();
  Config residue(settings);
  expect(residue.password().isEmpty(), "未启用记住密码时不得读取残留凭据");
  expect(settings.value("password").toString().isEmpty(), "应清理未启用记住密码时的残留凭据");

  settings.clear();
  settings.sync();
  qInfo().noquote() << "windows smoke tests passed";
  return 0;
}
