#ifndef API_H
#define API_H

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QObject>
#include <QString>

class Api : public QObject {
  Q_OBJECT

public:
  explicit Api(QObject *parent = nullptr);
  ~Api();

  // 登录
  void login(const QString &username, const QString &password);

  // 注销
  void logout();

  // 检测在线状态
  void checkStatus();

signals:
  void loginSuccess(const QString &message);
  void loginFailed(const QString &error);
  void logoutSuccess();
  void logoutFailed(const QString &error);
  void statusChecked(bool online, const QString &ip, qint64 bytesUsed,
                     qint64 secondsOnline);

private slots:
  void onLoginReplyFinished();
  void onLogoutReplyFinished();
  void onStatusReplyFinished();

private:
  QNetworkAccessManager *m_networkManager;

  static const QString STATUS_URL;
  static const QString LOGIN_URL;
};

#endif // API_H
