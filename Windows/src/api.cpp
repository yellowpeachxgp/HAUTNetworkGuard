#include "api.h"
#include "encryption.h"
#include "logger.h"
#include "protocol_utils.h"
#include <QDateTime>
#include <QNetworkReply>
#include <QUrl>
#include <QUrlQuery>
#include <QVariant>

const QString Api::STATUS_URL = "http://172.16.154.130/cgi-bin/rad_user_info";
const QString Api::LOGIN_URL = "http://172.16.154.130:69/cgi-bin/srun_portal";

Api::Api(QObject *parent)
    : QObject(parent), m_networkManager(new QNetworkAccessManager(this)) {}

Api::~Api() {}

QString Api::percentEncode(const QString &value) {
  QByteArray utf8 = value.toUtf8();
  QString result;
  for (int i = 0; i < utf8.size(); ++i) {
    unsigned char c = static_cast<unsigned char>(utf8[i]);
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' ||
        c == '~') {
      result.append(QChar(c));
    } else {
      result.append(QString("%%1").arg(c, 2, 16, QChar('0')).toUpper());
    }
  }
  return result;
}

quint64 Api::trackReply(QNetworkReply *reply, const QString &action) {
  if (!reply)
    return 0;
  const quint64 requestId = ++m_nextRequestId;
  m_requestIds.insert(reply, requestId);
  m_requestStartMs.insert(reply, QDateTime::currentMSecsSinceEpoch());
  m_requestActions.insert(reply, action);
  return requestId;
}

void Api::finishTrackedReply(QNetworkReply *reply, quint64 *requestId,
                             QString *action, qint64 *elapsedMs) {
  quint64 id = 0;
  QString act = "unknown";
  qint64 elapsed = -1;

  if (reply) {
    id = m_requestIds.take(reply);
    act = m_requestActions.take(reply);
    const qint64 startedAt = m_requestStartMs.take(reply);
    if (startedAt > 0) {
      elapsed = QDateTime::currentMSecsSinceEpoch() - startedAt;
    }
  }

  if (requestId)
    *requestId = id;
  if (action)
    *action = act;
  if (elapsedMs)
    *elapsedMs = elapsed;
}

void Api::login(quint64 token, const QString &username, const QString &password) {
  if (m_authRequestInFlight) {
    Logger::debug("跳过登录：上一个认证请求尚未完成");
    return;
  }
  m_authRequestInFlight = true;
  QString encUsername = Encryption::encryptUsername(username);
  QString encPassword = Encryption::encryptPassword(password);

  // 手动拼接 POST body，使用自定义 percentEncode 确保特殊字符被正确编码
  QString body = "action=login"
                 "&username=" +
                 percentEncode(encUsername) + "&password=" +
                 percentEncode(encPassword) + "&ac_id=1"
                                              "&drop=0"
                                              "&pop=1"
                                              "&type=10"
                                              "&n=117"
                                              "&mbytes=0"
                                              "&minutes=0"
                                              "&mac=02%3A00%3A00%3A00%3A00%3A00";

  QUrl loginUrl(LOGIN_URL);
  QNetworkRequest request(loginUrl);
  request.setHeader(QNetworkRequest::ContentTypeHeader,
                    "application/x-www-form-urlencoded");
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    QStringLiteral("HAUTNetworkGuard/" HAUT_VERSION_STRING " Qt"));
  request.setTransferTimeout(10000);

  QNetworkReply *reply = m_networkManager->post(request, body.toUtf8());
  const quint64 requestId = trackReply(reply, "login");
  reply->setProperty("sessionToken", QVariant::fromValue(token));
  Logger::info(QString("[req:%1] action=login phase=request account=%2 "
                       "user_len=%3 pass_len=%4 enc_user_len=%5 enc_pass_len=%6")
                   .arg(requestId)
                   .arg(Logger::maskUsername(username))
                   .arg(username.length())
                   .arg(password.length())
                   .arg(encUsername.length())
                   .arg(encPassword.length()));
  connect(reply, &QNetworkReply::finished, this, &Api::onLoginReplyFinished);
}

void Api::logout(quint64 token) {
  if (m_authRequestInFlight) {
    Logger::debug("跳过注销：上一个认证请求尚未完成");
    return;
  }
  m_authRequestInFlight = true;
  QString body = "action=logout";

  QUrl logoutUrl(LOGIN_URL);
  QNetworkRequest request(logoutUrl);
  request.setHeader(QNetworkRequest::ContentTypeHeader,
                    "application/x-www-form-urlencoded");
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    QStringLiteral("HAUTNetworkGuard/" HAUT_VERSION_STRING " Qt"));
  request.setTransferTimeout(10000);

  QNetworkReply *reply = m_networkManager->post(request, body.toUtf8());
  const quint64 requestId = trackReply(reply, "logout");
  reply->setProperty("sessionToken", QVariant::fromValue(token));
  Logger::info(
      QString("[req:%1] action=logout phase=request").arg(requestId));
  connect(reply, &QNetworkReply::finished, this, &Api::onLogoutReplyFinished);
}

void Api::checkStatus(quint64 token) {
  if (m_statusCheckInFlight) {
    Logger::debug("跳过状态检测：上一个状态请求尚未完成");
    return;
  }

  // 使用 JSONP callback 格式获取 JSON 响应 (与 OpenWrt 一致)
  qint64 timestamp = QDateTime::currentMSecsSinceEpoch();
  QString callback = QString("jQuery_%1").arg(timestamp);

  QUrl url(STATUS_URL);
  QUrlQuery query;
  query.addQueryItem("callback", callback);
  query.addQueryItem("_", QString::number(timestamp));
  url.setQuery(query);

  QNetworkRequest request(url);
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    QStringLiteral("HAUTNetworkGuard/" HAUT_VERSION_STRING " Qt"));
  request.setTransferTimeout(5000);

  QNetworkReply *reply = m_networkManager->get(request);
  m_statusCheckInFlight = true;
  const quint64 requestId = trackReply(reply, "status");
  reply->setProperty("sessionToken", QVariant::fromValue(token));
  Logger::debug(QString("[req:%1] action=status phase=request url=%2")
                    .arg(requestId)
                    .arg(url.toString()));
  connect(reply, &QNetworkReply::finished, this, &Api::onStatusReplyFinished);
}

void Api::onLoginReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  quint64 requestId = 0;
  QString action;
  qint64 elapsedMs = -1;
  finishTrackedReply(reply, &requestId, &action, &elapsedMs);
  m_authRequestInFlight = false;
  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    Logger::error(QString("[req:%1] action=%2 phase=error class=network_error "
                          "elapsed_ms=%3 msg=%4")
                      .arg(requestId)
                      .arg(action)
                      .arg(elapsedMs)
                      .arg(reply->errorString()));
    emit loginFailed(reply->property("sessionToken").toULongLong(), QString("网络错误: %1").arg(reply->errorString()));
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());
  const QString classification = ProtocolUtils::classifyLoginResponse(response);
  Logger::info(QString("[req:%1] action=%2 phase=response class=%3 "
                       "elapsed_ms=%4")
                   .arg(requestId)
                   .arg(action)
                   .arg(classification)
                   .arg(elapsedMs));
  Logger::debug(QString("[req:%1] 登录响应预览: %2")
                    .arg(requestId)
                    .arg(ProtocolUtils::responsePreview(response)));

  // 检查登录结果 (与 Rust 版本一致)
  if (classification == "success" || classification == "already_online") {
    emit loginSuccess(reply->property("sessionToken").toULongLong(), classification == "already_online" ? "已在线" : "登录成功");
  } else {
    QString error = ProtocolUtils::userFacingLoginMessage(classification);
    emit loginFailed(reply->property("sessionToken").toULongLong(), error);
  }
}

void Api::onLogoutReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  quint64 requestId = 0;
  QString action;
  qint64 elapsedMs = -1;
  finishTrackedReply(reply, &requestId, &action, &elapsedMs);
  m_authRequestInFlight = false;
  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    Logger::error(QString("[req:%1] action=%2 phase=error class=network_error "
                          "elapsed_ms=%3 msg=%4")
                      .arg(requestId)
                      .arg(action)
                      .arg(elapsedMs)
                      .arg(reply->errorString()));
    emit logoutFailed(reply->property("sessionToken").toULongLong(), QString("网络错误: %1").arg(reply->errorString()));
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());
  const QString classification = ProtocolUtils::classifyLoginResponse(response);
  Logger::info(QString("[req:%1] action=%2 phase=response class=%3 "
                       "elapsed_ms=%4")
                   .arg(requestId)
                   .arg(action)
                   .arg(classification)
                   .arg(elapsedMs));
  Logger::debug(QString("[req:%1] 注销响应预览: %2")
                    .arg(requestId)
                    .arg(ProtocolUtils::responsePreview(response)));

  if (classification == "logout_ok" || classification == "not_online") {
    emit logoutSuccess(reply->property("sessionToken").toULongLong(), classification);
  } else {
    emit logoutFailed(reply->property("sessionToken").toULongLong(), "注销失败");
  }
}

void Api::onStatusReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  quint64 requestId = 0;
  QString action;
  qint64 elapsedMs = -1;
  finishTrackedReply(reply, &requestId, &action, &elapsedMs);
  m_statusCheckInFlight = false;
  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    Logger::warn(QString("[req:%1] action=%2 phase=error class=network_error "
                         "elapsed_ms=%3 msg=%4")
                     .arg(requestId)
                     .arg(action)
                     .arg(elapsedMs)
                     .arg(reply->errorString()));
    emit statusChecked(reply->property("sessionToken").toULongLong(), false, "network_error", "", 0, 0);
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());
  Logger::debug(QString("[req:%1] 状态响应长度: %2 bytes, 耗时: %3 ms, 预览: %4")
                    .arg(requestId)
                    .arg(response.toUtf8().size())
                    .arg(elapsedMs)
                    .arg(ProtocolUtils::responsePreview(response)));

  const StatusParseResult parsed = ProtocolUtils::parseStatusResponse(response);
  if (parsed.online) {
    Logger::debug(QString("[req:%1] %2 状态解析成功: user=%3 ip=%4 bytes=%5 "
                          "seconds=%6")
                      .arg(requestId)
                      .arg(parsed.format)
                      .arg(Logger::maskUsername(parsed.username))
                      .arg(parsed.ip)
                      .arg(parsed.bytes)
                      .arg(parsed.seconds));
    Logger::info(QString("[req:%1] action=%2 phase=response class=online_%3 "
                         "elapsed_ms=%4")
                     .arg(requestId)
                     .arg(action)
                     .arg(parsed.format)
                     .arg(elapsedMs));
    emit statusChecked(reply->property("sessionToken").toULongLong(), true, QString("online_%1").arg(parsed.format),
                       parsed.ip, parsed.bytes, parsed.seconds);
    return;
  }

  if (parsed.format == "offline") {
    Logger::debug(QString("[req:%1] action=%2 phase=response class=offline "
                          "elapsed_ms=%3")
                      .arg(requestId)
                      .arg(action)
                      .arg(elapsedMs));
    emit statusChecked(reply->property("sessionToken").toULongLong(), false, "offline", "", 0, 0);
    return;
  }

  Logger::warn(QString("[req:%1] action=%2 phase=response class=%3 "
                       "elapsed_ms=%4")
                   .arg(requestId)
                   .arg(action)
                   .arg(parsed.format)
                   .arg(elapsedMs));
  emit statusChecked(reply->property("sessionToken").toULongLong(), false, parsed.format, "", 0, 0);
}
