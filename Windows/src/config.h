#ifndef CONFIG_H
#define CONFIG_H

#include <QSettings>
#include <QString>
#include <memory>
#include <functional>

struct PasswordCodec {
  std::function<QString(const QString &)> encode;
  std::function<QString(const QString &)> decode;
};

class Config {
public:
  static Config &instance();
  // 注入独立存储；此构造方式始终关闭系统自启动集成。
  explicit Config(QSettings &settings, PasswordCodec codec = {});
  ~Config() = default;

  // 加载/保存配置
  void load();
  bool save();
  QString lastError() const { return m_lastError; }

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
    m_checkInterval = qBound(30, seconds, 300);
  }

  // 自动登录
  bool autoLogin() const { return m_autoLogin; }
  void setAutoLogin(bool autoLogin) { m_autoLogin = autoLogin; }

private:
  Config();
  struct Snapshot {
    QString username, password;
    bool autoSave, autoLaunch, hasConfigured, autoLogin, credentialReadFailed;
    int checkInterval;
  };
  Snapshot snapshot() const;
  void restore(const Snapshot &saved);
  bool failSave(const QString &message);

  // Windows 使用 DPAPI；解码同时兼容旧版格式。
  QString encodePassword(const QString &password);
  QString decodePassword(const QString &encoded);

  // 设置开机自启动
  void updateAutoLaunch(bool enable);
  void updateAutoLaunchRegistry(bool enable, const QString &command);
  void updateAutoLaunchStartupScript(bool enable, const QString &command);
  void verifyAndRepairAutoLaunch();
  bool isRegistryCommandExpected(const QString &command,
                                 QString *storedValue = nullptr) const;
  bool isStartupScriptExpected(const QString &command,
                               QString *scriptPath = nullptr) const;
  QString autoLaunchCommand() const;
  QString startupScriptPath() const;

  QString m_username;
  std::unique_ptr<QSettings> m_ownedSettings;
  QSettings &m_settings;
  bool m_startupIntegration = false;
  PasswordCodec m_codec;
  QString m_lastError;
  bool m_credentialReadFailed = false;
  Snapshot m_lastSaved{};
  QString m_password;
  bool m_autoSave = false;
  bool m_autoLaunch = false;
  bool m_hasConfigured = false;
  int m_checkInterval = 30; // 默认 30 秒，最小 30 秒避免请求过于频繁
  bool m_autoLogin = true;  // 默认开启自动登录
};

#endif // CONFIG_H
