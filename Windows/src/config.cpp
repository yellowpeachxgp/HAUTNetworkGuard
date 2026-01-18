#include "config.h"
#include <QCoreApplication>
#include <QDir>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

Config &Config::instance() {
  static Config instance;
  return instance;
}

Config::Config() { load(); }

void Config::load() {
  QSettings settings("HAUTNetworkGuard", "HAUTNetworkGuard");

  m_username = settings.value("username", "").toString();
  m_password = decodePassword(settings.value("password", "").toString());
  m_autoSave = settings.value("auto_save", false).toBool();
  m_autoLaunch = settings.value("auto_launch", false).toBool();
  m_hasConfigured = settings.value("has_configured", false).toBool();
  m_checkInterval = settings.value("check_interval", 30).toInt();
  m_autoLogin = settings.value("auto_login", true).toBool();

  // 确保间隔在合理范围内
  m_checkInterval = qBound(5, m_checkInterval, 300);
}

void Config::save() {
  QSettings settings("HAUTNetworkGuard", "HAUTNetworkGuard");

  settings.setValue("username", m_username);
  settings.setValue("password", encodePassword(m_password));
  settings.setValue("auto_save", m_autoSave);
  settings.setValue("auto_launch", m_autoLaunch);
  settings.setValue("has_configured", m_hasConfigured);
  settings.setValue("check_interval", m_checkInterval);
  settings.setValue("auto_login", m_autoLogin);

  settings.sync();
}

QString Config::encodePassword(const QString &password) {
  // 简单的 XOR 混淆
  QByteArray data = password.toUtf8();
  const char key[] = "HAUTGuard2024";
  int keyLen = strlen(key);

  for (int i = 0; i < data.size(); ++i) {
    data[i] = data[i] ^ key[i % keyLen];
  }

  return QString::fromLatin1(data.toBase64());
}

QString Config::decodePassword(const QString &encoded) {
  if (encoded.isEmpty())
    return "";

  QByteArray data = QByteArray::fromBase64(encoded.toLatin1());
  const char key[] = "HAUTGuard2024";
  int keyLen = strlen(key);

  for (int i = 0; i < data.size(); ++i) {
    data[i] = data[i] ^ key[i % keyLen];
  }

  return QString::fromUtf8(data);
}

void Config::setAutoLaunch(bool autoLaunch) {
  m_autoLaunch = autoLaunch;
  updateAutoLaunchRegistry(autoLaunch);
}

void Config::updateAutoLaunchRegistry(bool enable) {
#ifdef Q_OS_WIN
  QSettings bootSettings(
      "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      QSettings::NativeFormat);

  if (enable) {
    QString appPath =
        QDir::toNativeSeparators(QCoreApplication::applicationFilePath());
    bootSettings.setValue("HAUTNetworkGuard", QString("\"%1\"").arg(appPath));
  } else {
    bootSettings.remove("HAUTNetworkGuard");
  }
#endif
}
