#include "api.h"
#include "encryption.h"
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>

const QString Api::BASE_URL = "http://172.20.255.2";
const QString Api::AC_ID = "1";

Api::Api(QObject *parent) : QObject(parent) {
  m_networkManager = new QNetworkAccessManager(this);
}

void Api::login(const QString &username, const QString &password) {
  QString url = buildLoginUrl(username, password);

  QNetworkRequest request(url);
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.0 Qt");

  QNetworkReply *reply = m_networkManager->get(request);
  connect(reply, &QNetworkReply::finished, this, &Api::onLoginReplyFinished);
}

void Api::logout() {
  QString url = buildLogoutUrl();

  QNetworkRequest request(url);
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.0 Qt");

  QNetworkReply *reply = m_networkManager->get(request);
  connect(reply, &QNetworkReply::finished, this, &Api::onLogoutReplyFinished);
}

void Api::checkStatus() {
  QString url = buildStatusUrl();

  QNetworkRequest request(url);
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.0 Qt");
  request.setTransferTimeout(5000); // 5 秒超时

  QNetworkReply *reply = m_networkManager->get(request);
  connect(reply, &QNetworkReply::finished, this, &Api::onStatusReplyFinished);
}

QString Api::buildLoginUrl(const QString &username, const QString &password) {
  // SRUN3K 登录 URL
  QString encUsername = Encryption::encryptUsername(username);
  QString encPassword = Encryption::encryptPassword(password);

  qint64 timestamp = QDateTime::currentMSecsSinceEpoch();
  QString callback = QString("jQuery_%1").arg(timestamp);

  QUrl url(BASE_URL + "/cgi-bin/srun_portal");
  QUrlQuery query;
  query.addQueryItem("callback", callback);
  query.addQueryItem("action", "login");
  query.addQueryItem("username", encUsername);
  query.addQueryItem("password", encPassword);
  query.addQueryItem("ac_id", AC_ID);
  query.addQueryItem("type", "2");
  query.addQueryItem("n", "117");
  query.addQueryItem("_", QString::number(timestamp));

  url.setQuery(query);
  return url.toString();
}

QString Api::buildLogoutUrl() {
  qint64 timestamp = QDateTime::currentMSecsSinceEpoch();
  QString callback = QString("jQuery_%1").arg(timestamp);

  QUrl url(BASE_URL + "/cgi-bin/srun_portal");
  QUrlQuery query;
  query.addQueryItem("callback", callback);
  query.addQueryItem("action", "logout");
  query.addQueryItem("ac_id", AC_ID);
  query.addQueryItem("_", QString::number(timestamp));

  url.setQuery(query);
  return url.toString();
}

QString Api::buildStatusUrl() {
  qint64 timestamp = QDateTime::currentMSecsSinceEpoch();
  QString callback = QString("jQuery_%1").arg(timestamp);

  QUrl url(BASE_URL + "/cgi-bin/rad_user_info");
  QUrlQuery query;
  query.addQueryItem("callback", callback);
  query.addQueryItem("_", QString::number(timestamp));

  url.setQuery(query);
  return url.toString();
}

void Api::onLoginReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    emit loginFailed(reply->errorString());
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());

  // 解析 JSONP 响应
  QRegularExpression re("\"result\":\"(\\d+)\"");
  QRegularExpressionMatch match = re.match(response);

  if (match.hasMatch() && match.captured(1) == "1") {
    emit loginSuccess("登录成功");
  } else {
    // 提取错误信息
    QRegularExpression errRe("\"error\":\"([^\"]+)\"");
    QRegularExpressionMatch errMatch = errRe.match(response);
    QString error = errMatch.hasMatch() ? errMatch.captured(1) : "登录失败";
    emit loginFailed(error);
  }
}

void Api::onLogoutReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    emit logoutFailed(reply->errorString());
    return;
  }

  emit logoutSuccess();
}

void Api::onStatusReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    emit statusChecked(false, "", 0, 0);
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());

  // 如果响应为空或包含 "not_online"，则离线
  if (response.isEmpty() || response.contains("not_online")) {
    emit statusChecked(false, "", 0, 0);
    return;
  }

  // 解析在线信息
  QRegularExpression ipRe("\"online_ip\":\"([^\"]+)\"");
  QRegularExpression bytesRe("\"sum_bytes\":(\\d+)");
  QRegularExpression secondsRe("\"sum_seconds\":(\\d+)");

  QRegularExpressionMatch ipMatch = ipRe.match(response);
  QRegularExpressionMatch bytesMatch = bytesRe.match(response);
  QRegularExpressionMatch secondsMatch = secondsRe.match(response);

  QString ip = ipMatch.hasMatch() ? ipMatch.captured(1) : "";
  qint64 bytes =
      bytesMatch.hasMatch() ? bytesMatch.captured(1).toLongLong() : 0;
  qint64 seconds =
      secondsMatch.hasMatch() ? secondsMatch.captured(1).toLongLong() : 0;

  emit statusChecked(true, ip, bytes, seconds);
}
