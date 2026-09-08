#ifndef API_H
#define API_H

#include <QHash>
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
  virtual void login(quint64 token, const QString &username, const QString &password);

  // 注销
  virtual void logout(quint64 token);

  // 检测在线状态
  virtual void checkStatus(quint64 token);

signals:
  void loginSuccess(quint64 token, const QString &message);
  void loginFailed(quint64 token, const QString &error);
  void logoutSuccess(quint64 token, const QString &resultClass);
  void logoutFailed(quint64 token, const QString &error);
  void statusChecked(quint64 token, bool online, const QString &resultClass,
                     const QString &ip, qint64 bytesUsed,
                     qint64 secondsOnline);

private slots:
  void onLoginReplyFinished();
  void onLogoutReplyFinished();
  void onStatusReplyFinished();

private:
  quint64 trackReply(QNetworkReply *reply, const QString &action);
  void finishTrackedReply(QNetworkReply *reply, quint64 *requestId,
                          QString *action, qint64 *elapsedMs);

  QNetworkAccessManager *m_networkManager;
  QHash<QNetworkReply *, quint64> m_requestIds;
  QHash<QNetworkReply *, qint64> m_requestStartMs;
  QHash<QNetworkReply *, QString> m_requestActions;
  quint64 m_nextRequestId = 0;
  bool m_statusCheckInFlight = false;

  static const QString STATUS_URL;
  static const QString LOGIN_URL;

  static QString percentEncode(const QString &value);
};

#endif // API_H
