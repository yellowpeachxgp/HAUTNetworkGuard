#include "api.h"
#include "encryption.h"
#include <QDateTime>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>

// 使用与 Rust 版本相同的 API 地址
const QString Api::STATUS_URL = "http://172.16.154.130/cgi-bin/rad_user_info";
const QString Api::LOGIN_URL = "http://172.16.154.130:69/cgi-bin/srun_portal";

Api::Api(QObject *parent) : QObject(parent) {
  m_networkManager = new QNetworkAccessManager(this);
  // 设置较长的超时时间
  m_networkManager->setTransferTimeout(10000); // 10秒
}

void Api::login(const QString &username, const QString &password) {
  // 加密用户名和密码
  QString encUsername = Encryption::encryptUsername(username);
  QString encPassword = Encryption::encryptPassword(password);

  // 构建 POST 请求体 (与 Rust 版本一致)
  QUrlQuery postData;
  postData.addQueryItem("action", "login");
  postData.addQueryItem("username", encUsername);
  postData.addQueryItem("password", encPassword);
  postData.addQueryItem("ac_id", "1");
  postData.addQueryItem("drop", "0");
  postData.addQueryItem("pop", "1");
  postData.addQueryItem("type", "10");
  postData.addQueryItem("n", "117");
  postData.addQueryItem("mbytes", "0");
  postData.addQueryItem("minutes", "0");
  postData.addQueryItem("mac", "02:00:00:00:00:00");

  QUrl loginUrl(LOGIN_URL);
  QNetworkRequest request(loginUrl);
  request.setHeader(QNetworkRequest::ContentTypeHeader,
                    "application/x-www-form-urlencoded");
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.4 Qt");
  request.setTransferTimeout(10000);

  QNetworkReply *reply = m_networkManager->post(
      request, postData.toString(QUrl::FullyEncoded).toUtf8());
  connect(reply, &QNetworkReply::finished, this, &Api::onLoginReplyFinished);
}

void Api::logout() {
  QUrlQuery postData;
  postData.addQueryItem("action", "logout");

  QUrl logoutUrl(LOGIN_URL);
  QNetworkRequest request(logoutUrl);
  request.setHeader(QNetworkRequest::ContentTypeHeader,
                    "application/x-www-form-urlencoded");
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.4 Qt");
  request.setTransferTimeout(10000);

  QNetworkReply *reply = m_networkManager->post(
      request, postData.toString(QUrl::FullyEncoded).toUtf8());
  connect(reply, &QNetworkReply::finished, this, &Api::onLogoutReplyFinished);
}

void Api::checkStatus() {
  QUrl statusUrl(STATUS_URL);
  QNetworkRequest request(statusUrl);
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    "HAUTNetworkGuard/1.3.4 Qt");
  request.setTransferTimeout(5000); // 5 秒超时

  QNetworkReply *reply = m_networkManager->get(request);
  connect(reply, &QNetworkReply::finished, this, &Api::onStatusReplyFinished);
}

void Api::onLoginReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    emit loginFailed(QString("网络错误: %1").arg(reply->errorString()));
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());

  // 检查登录结果 (与 Rust 版本一致)
  if (response.contains("login_ok") || response.contains("already_online")) {
    emit loginSuccess("登录成功");
  } else {
    // 提取错误信息
    QString error = "登录失败";
    if (response.contains("E")) {
      // 尝试提取错误码
      QRegularExpression errRe("E(\\d+)");
      QRegularExpressionMatch match = errRe.match(response);
      if (match.hasMatch()) {
        error = QString("登录失败 (错误码: E%1)").arg(match.captured(1));
      }
    }
    if (!response.isEmpty() && response.length() < 200) {
      error = response;
    }
    emit loginFailed(error);
  }
}

void Api::onLogoutReplyFinished() {
  QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
  if (!reply)
    return;

  reply->deleteLater();

  if (reply->error() != QNetworkReply::NoError) {
    emit logoutFailed(QString("网络错误: %1").arg(reply->errorString()));
    return;
  }

  QString response = QString::fromUtf8(reply->readAll());

  // 与 Rust 版本一致
  if (response.contains("logout_ok") || response.contains("not_online")) {
    emit logoutSuccess();
  } else {
    emit logoutFailed("注销失败");
  }
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

  // 解析逗号分隔的响应格式: username,seconds,ip,bytes,...
  QStringList parts = response.split(',');
  if (parts.size() >= 4) {
    QString username = parts[0];
    qint64 seconds = parts[1].toLongLong();
    QString ip = parts[2];
    qint64 bytes = parts[3].toLongLong();

    emit statusChecked(true, ip, bytes, seconds);
  } else {
    emit statusChecked(false, "", 0, 0);
  }
}
