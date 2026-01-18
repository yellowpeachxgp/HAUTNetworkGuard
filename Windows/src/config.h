#ifndef CONFIG_H
#define CONFIG_H

#include <QSettings>
#include <QString>

class Config {
public:
  static Config &instance();

  // 加载/保存配置
  void load();
  void save();

  // 配置项
  QString username() const { return m_username; }
  void setUsername(const QString &username) { m_username = username; }

  QString password() const { return m_password; }
  void setPassword(const QString &password) { m_password = password; }

  bool autoSave() const { return m_autoSave; }
  void setAutoSave(bool autoSave) { m_autoSave = autoSave; }

  bool autoLaunch() const { return m_autoLaunch; }
  void setAutoLaunch(bool autoLaunch);

  bool hasConfigured() const { return m_hasConfigured; }
  void setHasConfigured(bool configured) { m_hasConfigured = configured; }

  // 检测间隔 (秒)
  int checkInterval() const { return m_checkInterval; }
  void setCheckInterval(int seconds) {
    m_checkInterval = qBound(5, seconds, 300);
  }

  // 自动登录
  bool autoLogin() const { return m_autoLogin; }
  void setAutoLogin(bool autoLogin) { m_autoLogin = autoLogin; }

private:
  Config();
  ~Config() = default;

  // 简单的密码混淆
  QString encodePassword(const QString &password);
  QString decodePassword(const QString &encoded);

  // 设置开机自启动
  void updateAutoLaunchRegistry(bool enable);

  QString m_username;
  QString m_password;
  bool m_autoSave = false;
  bool m_autoLaunch = false;
  bool m_hasConfigured = false;
  int m_checkInterval = 30; // 默认 30 秒
  bool m_autoLogin = true;  // 默认开启自动登录
};

#endif // CONFIG_H
