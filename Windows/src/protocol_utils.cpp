#include "protocol_utils.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>
#include <cmath>

namespace {

bool isValidIpv4(const QString &value) {
  const QStringList octets = value.split('.');
  if (octets.size() != 4) {
    return false;
  }

  for (const QString &octet : octets) {
    bool ok = false;
    const int part = octet.toInt(&ok);
    if (!ok || part < 0 || part > 255) {
      return false;
    }
  }
  return true;
}

constexpr qint64 kMaxSafeCounter = 9007199254740991LL;

qint64 parseCounter(const QJsonValue &value) {
  if (value.isDouble()) {
    const double number = value.toDouble();
    if (std::isfinite(number) && number >= 0 &&
        number <= static_cast<double>(kMaxSafeCounter) &&
        std::floor(number) == number) {
      return static_cast<qint64>(number);
    }
    return 0;
  }
  if (value.isString()) {
    const QString text = value.toString();
    bool ok = false;
    const qint64 number = text.toLongLong(&ok);
    return ok && number >= 0 && number <= kMaxSafeCounter &&
                   QRegularExpression("^[0-9]+$").match(text).hasMatch()
               ? number
               : 0;
  }
  return 0;
}

} // namespace

QString ProtocolUtils::responsePreview(const QString &response, int maxLen) {
  // 网关可能在任意字段或异常正文中回显凭据，只输出长度摘要。
  return QString("<redacted> (%1 bytes)").arg(response.toUtf8().size()).left(qMax(0, maxLen));
}

QString ProtocolUtils::extractErrorCode(const QString &response) {
  QRegularExpression errRe("E([0-9]{4})(?![0-9])");
  QRegularExpressionMatch match = errRe.match(response);
  if (match.hasMatch()) {
    return "E" + match.captured(1);
  }
  return "";
}

QString ProtocolUtils::classifyLoginResponse(const QString &response) {
  const QString body = response.trimmed();
  if (body.contains("login_ok")) {
    return "success";
  }
  if (body.contains("already_online")) {
    return "already_online";
  }
  if (body.contains("logout_ok")) {
    return "logout_ok";
  }
  if (body.contains("not_online")) {
    return "not_online";
  }
  const QString errorCode = extractErrorCode(body);
  if (!errorCode.isEmpty()) {
    return "error_" + errorCode;
  }
  if (body.isEmpty()) {
    return "empty";
  }
  return "unknown";
}

QString ProtocolUtils::userFacingLoginMessage(const QString &classification) {
  if (classification == "success")
    return "登录成功";
  if (classification == "already_online")
    return "已经在线";
  if (classification == "logout_ok")
    return "注销成功";
  if (classification == "not_online")
    return "当前未在线";
  if (classification == "error_E2531")
    return "学号或密码错误，请检查后重试。";
  if (classification == "empty")
    return "校园网网关返回空响应，请检查网络后重试。";
  if (classification.startsWith("error_E"))
    return QString("登录失败（错误码 %1），请稍后重试。")
        .arg(classification.mid(QString("error_").size()));
  if (classification == "unknown")
    return "校园网网关返回了无法识别的结果，请稍后重试。";
  return "登录失败，请稍后重试。";
}

QString ProtocolUtils::userFacingNetworkError(const QString &error, int httpStatus) {
  if (httpStatus > 0 && (httpStatus < 200 || httpStatus >= 300)) {
    return "校园网网关返回异常，请稍后重试。";
  }
  const QString normalized = error.trimmed().toLower();
  if (normalized.contains("timeout") || normalized.contains("timed out") ||
      normalized.contains("超时")) {
    return "连接校园网网关超时，请确认已连接 Wi-Fi 或有线网络后重试。";
  }
  if (normalized.contains("host not found") ||
      normalized.contains("无法解析主机") || normalized.contains("cannot connect") ||
      normalized.contains("network is unreachable") ||
      normalized.contains("connection refused") ||
      normalized.contains("unreachable") || normalized.contains("无法连接")) {
    return "无法连接校园网网关，请检查网络连接后重试。";
  }
  return "网络请求失败，请检查网络连接后重试。";
}

StatusParseResult ProtocolUtils::parseStatusResponse(const QString &response) {
  StatusParseResult result;
  const QString trimmed = response.trimmed();

  if (trimmed == "not_online") {
    result.format = "offline";
    return result;
  }
  if (trimmed.isEmpty()) {
    result.format = "unparsed";
    return result;
  }

  QString jsonStr;
  QRegularExpression jsonpRe("jQuery_\\d+\\((.+)\\)$");
  QRegularExpressionMatch match = jsonpRe.match(trimmed);
  if (match.hasMatch()) {
    jsonStr = match.captured(1);
    result.format = "jsonp";
  } else {
    jsonStr = trimmed;
    result.format = "json";
  }

  QJsonParseError parseError;
  QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8(), &parseError);
  if (doc.isObject()) {
    QJsonObject obj = doc.object();
    const QString error = obj.value("error").toString();
    if (error == "not_online_error" || error.contains("not_online")) {
      result.format = "offline";
      return result;
    }

    result.ip = obj.value("online_ip").toString();
    result.bytes = parseCounter(obj.value("sum_bytes"));
    result.seconds = parseCounter(obj.value("sum_seconds"));
    result.username = obj.value("user_name").toString();
    if (!result.username.isEmpty() || isValidIpv4(result.ip)) {
      result.online = true;
      return result;
    }
  }

  QStringList parts = trimmed.split(',');
  bool secondsOk = false;
  bool bytesOk = false;
  const qint64 seconds = parts.size() >= 2 ? parts[1].toLongLong(&secondsOk)
                                           : 0;
  const qint64 bytes =
      parts.size() >= 4 ? parts[3].toLongLong(&bytesOk) : 0;
  if (parts.size() >= 4 && !parts[0].isEmpty() && secondsOk &&
      bytesOk && seconds >= 0 && bytes >= 0 &&
      seconds <= kMaxSafeCounter && bytes <= kMaxSafeCounter &&
      isValidIpv4(parts[2])) {
    result.format = "csv";
    result.username = parts[0];
    result.seconds = seconds;
    result.ip = parts[2];
    result.bytes = bytes;
    result.online = true;
    return result;
  }

  result.format = "unparsed";
  return result;
}
