#include "config.h"
#include "logger.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMap>
#include <QProcess>
#include <QTextStream>
#include <cstring>
#include <utility>

#ifdef Q_OS_WIN
#include <windows.h>
#include <wincrypt.h>
#endif

Config &Config::instance() {
  static Config instance;
  return instance;
}

Config::Config()
    : m_ownedSettings(std::make_unique<QSettings>("HAUTNetworkGuard", "HAUTNetworkGuard")),
      m_settings(*m_ownedSettings), m_startupIntegration(true) {
  load();
}

Config::Config(QSettings &settings, PasswordCodec codec)
    : m_settings(settings), m_codec(std::move(codec)) { load(); }

Config::Snapshot Config::snapshot() const {
  return {m_username, m_password, m_autoSave, m_autoLaunch, m_hasConfigured,
          m_autoLogin, m_credentialReadFailed, m_checkInterval};
}

void Config::restore(const Snapshot &saved) {
  m_username = saved.username;
  m_password = saved.password;
  m_autoSave = saved.autoSave;
  m_autoLaunch = saved.autoLaunch;
  m_hasConfigured = saved.hasConfigured;
  m_autoLogin = saved.autoLogin;
  m_credentialReadFailed = saved.credentialReadFailed;
  m_checkInterval = saved.checkInterval;
}

bool Config::failSave(const QString &message) {
  restore(m_lastSaved);
  m_lastError = message;
  Logger::error(message);
  return false;
}

void Config::load() {
  QSettings &settings = m_settings;

  m_username = settings.value("username", "").toString();
  m_autoSave = settings.value("auto_save", false).toBool();
  const QString persistedPassword = settings.value("password", "").toString();
  m_password = m_autoSave ? decodePassword(persistedPassword) : QString();
  m_credentialReadFailed = m_autoSave && !persistedPassword.isEmpty() && m_password.isEmpty();
  m_lastError = m_credentialReadFailed
      ? "无法读取已保存的密码，请重新输入，或关闭记住密码。" : QString();
  if (!m_autoSave && !persistedPassword.isEmpty()) {
    settings.remove("password");
    settings.sync();
    Logger::warn("检测到未启用记住密码但仍存在持久化密码，已清理");
  }
  m_autoLaunch = settings.value("auto_launch", false).toBool();
  m_hasConfigured = settings.value("has_configured", false).toBool();
  m_checkInterval = settings.value("check_interval", 30).toInt();
  m_autoLogin = settings.value("auto_login", true).toBool();

  m_checkInterval = qBound(30, m_checkInterval, 300);

  Logger::info(QString("配置已加载 (用户: %1, 间隔: %2s, 自动保存: %3, 自动登录: %4, "
                       "开机自启: %5)")
                   .arg(Logger::maskUsername(m_username))
                   .arg(m_checkInterval)
                   .arg(Logger::boolText(m_autoSave))
                   .arg(Logger::boolText(m_autoLogin))
                   .arg(Logger::boolText(m_autoLaunch)));

  // 开机自启修复涉及注册表/计划任务/磁盘操作，不能在启动路径同步执行；
  // 由主程序在事件循环启动后调用 repairAutoLaunchIfNeeded()。
  m_lastSaved = snapshot();
}

void Config::repairAutoLaunchIfNeeded() {
  if (!m_autoLaunch || !m_startupIntegration) return;
  verifyAndRepairAutoLaunch();
}

bool Config::save() {
  m_lastError.clear();
  if (m_autoSave && m_password.isEmpty() && m_credentialReadFailed) {
    return failSave("旧密码无法解密，原配置已保留。请重新输入密码，或关闭记住密码。");
  }
  const QString encoded = m_autoSave && !m_password.isEmpty() ? encodePassword(m_password) : QString();
  if (m_autoSave && !m_password.isEmpty() &&
      (encoded.isEmpty() || decodePassword(encoded) != m_password)) {
    return failSave("密码保护失败，原配置已保留，请重试。");
  }

  // 每次写入使用新实例，故障修复后不会继承 QSettings 的旧错误状态。
  std::unique_ptr<QSettings> writer;
  if (m_settings.organizationName().isEmpty()) {
    writer = std::make_unique<QSettings>(m_settings.fileName(), m_settings.format());
  } else {
    writer = std::make_unique<QSettings>(m_settings.format(), m_settings.scope(),
        m_settings.organizationName(), m_settings.applicationName());
  }
  QSettings &settings = *writer;
  settings.sync();
  if (settings.status() != QSettings::NoError || !settings.isWritable()) {
    return failSave("配置存储不可写，原配置已保留，请检查磁盘空间和文件权限后重试。");
  }
  const QStringList keys = {"username", "password", "auto_save", "auto_launch",
                            "has_configured", "check_interval", "auto_login"};
  QMap<QString, QVariant> previous;
  for (const auto &key : keys) {
    if (settings.contains(key)) previous.insert(key, settings.value(key));
  }

  settings.setValue("username", m_username);
  settings.setValue("password", encoded);
  settings.setValue("auto_save", m_autoSave);
  settings.setValue("auto_launch", m_autoLaunch);
  settings.setValue("has_configured", m_hasConfigured);
  settings.setValue("check_interval", m_checkInterval);
  settings.setValue("auto_login", m_autoLogin);

  settings.sync();
  if (settings.status() != QSettings::NoError || settings.value("password").toString() != encoded) {
    // 恢复本次涉及的键；异常期间可能仍不可写，不能报告保存成功。
    for (const auto &key : keys) {
      if (previous.contains(key)) settings.setValue(key, previous.value(key));
      else settings.remove(key);
    }
    settings.sync();
    return failSave("写入设置失败，已恢复会话设置并尝试保留原配置。请检查磁盘后重试。");
  }
  const bool autoLaunchChanged = m_autoLaunch != m_lastSaved.autoLaunch;
  m_credentialReadFailed = false;
  m_lastSaved = snapshot();
  if (m_startupIntegration && autoLaunchChanged) updateAutoLaunch(m_autoLaunch);

  Logger::info(QString("配置已保存 (用户: %1, 自动保存: %2, 自动登录: %3, "
                       "开机自启: %4, 间隔: %5s)")
                   .arg(Logger::maskUsername(m_username))
                   .arg(Logger::boolText(m_autoSave))
                   .arg(Logger::boolText(m_autoLogin))
                   .arg(Logger::boolText(m_autoLaunch))
                   .arg(m_checkInterval));
  return true;
}

QString Config::encodePassword(const QString &password) {
  if (m_codec.encode) return m_codec.encode(password);
#ifdef Q_OS_WIN
  QByteArray inputData = password.toUtf8();
  DATA_BLOB input{static_cast<DWORD>(inputData.size()),
                  reinterpret_cast<BYTE *>(inputData.data())};
  DATA_BLOB output{};
  if (CryptProtectData(&input, L"HAUTNetworkGuard password", nullptr,
                       nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    QByteArray protectedData(reinterpret_cast<const char *>(output.pbData),
                             static_cast<int>(output.cbData));
    LocalFree(output.pbData);
    return QStringLiteral("DPAPI:") +
           QString::fromLatin1(protectedData.toBase64());
  }
  Logger::error("Windows DPAPI 加密失败，密码不会持久化");
  return "";
#endif

  // 非 Windows 构建保留旧格式，Windows 仅在 decodePassword 中读取旧配置并迁移。
#ifndef Q_OS_WIN
  QByteArray data = password.toUtf8();
  const char key[] = "HAUTGuard2024";
  int keyLen = strlen(key);

  for (int i = 0; i < data.size(); ++i) {
    data[i] = data[i] ^ key[i % keyLen];
  }

  return QString::fromLatin1(data.toBase64());
#else
  return "";
#endif
}

QString Config::decodePassword(const QString &encoded) {
  if (m_codec.decode) return m_codec.decode(encoded);
  if (encoded.isEmpty())
    return "";

#ifdef Q_OS_WIN
  if (encoded.startsWith(QStringLiteral("DPAPI:"))) {
    QByteArray protectedData = QByteArray::fromBase64(
        encoded.mid(QStringLiteral("DPAPI:").size()).toLatin1());
    DATA_BLOB input{static_cast<DWORD>(protectedData.size()),
                    reinterpret_cast<BYTE *>(protectedData.data())};
    DATA_BLOB output{};
    if (CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                           CRYPTPROTECT_UI_FORBIDDEN, &output)) {
      QByteArray plain(reinterpret_cast<const char *>(output.pbData),
                       static_cast<int>(output.cbData));
      LocalFree(output.pbData);
      return QString::fromUtf8(plain);
    }
    Logger::warn("Windows DPAPI 解密失败");
    return "";
  }
#endif

  // 读取旧版本的 XOR 混淆配置，下一次保存时会迁移到 DPAPI。
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
  Logger::info(QString("开机自启动设置变更: %1")
                   .arg(Logger::boolText(m_autoLaunch)));
  // 系统自启动变更在配置保存成功后执行，避免保存失败仍修改系统设置。
}

QString Config::autoLaunchCommand() const {
  const QString appPath =
      QDir::toNativeSeparators(QCoreApplication::applicationFilePath());
  return QString("\"%1\" --startup").arg(appPath);
}

QString Config::startupScriptPath() const {
  const QString appData = qEnvironmentVariable("APPDATA");
  if (appData.isEmpty()) {
    return QString();
  }
  return QDir::toNativeSeparators(
      appData + "\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\"
                 "HAUTNetworkGuard-Startup.vbs");
}

QString Config::scheduledTaskName() { return QStringLiteral("HAUTNetworkGuard"); }

QStringList Config::scheduledTaskCreateArgs(const QString &command) {
  // 登录时触发（/SC ONLOGON）比注册表 Run 更早，且可在网络就绪前启动。
  // 固定最高权限会在部分策略下触发 UAC，因此保持普通用户权限。
  return {QStringLiteral("/Create"),
          QStringLiteral("/TN"), scheduledTaskName(),
          QStringLiteral("/TR"), command,
          QStringLiteral("/SC"), QStringLiteral("ONLOGON"),
          QStringLiteral("/RL"), QStringLiteral("LIMITED"),
          QStringLiteral("/F")};
}

QStringList Config::scheduledTaskQueryArgs() {
  return {QStringLiteral("/Query"), QStringLiteral("/TN"), scheduledTaskName()};
}

QStringList Config::scheduledTaskDeleteArgs() {
  return {QStringLiteral("/Delete"), QStringLiteral("/TN"), scheduledTaskName(),
          QStringLiteral("/F")};
}

bool Config::runScheduledTask(const QStringList &args, int *exitCode,
                              QString *output) const {
  if (m_autoLaunchRunner) {
    return m_autoLaunchRunner(args, exitCode, output);
  }
#ifdef Q_OS_WIN
  QProcess process;
  process.setProgram(QStringLiteral("schtasks.exe"));
  process.setArguments(args);
  process.setProcessChannelMode(QProcess::MergedChannels);
  // 避免从 GUI 进程调用 schtasks 时闪出控制台窗口。
  process.setCreateProcessArgumentsModifier(
      [](QProcess::CreateProcessArguments *arguments) {
        arguments->flags |= CREATE_NO_WINDOW;
      });
  process.start();
  if (!process.waitForStarted(5000)) {
    if (exitCode) *exitCode = -1;
    if (output) *output = process.errorString();
    return false;
  }
  if (!process.waitForFinished(8000)) {
    process.kill();
    process.waitForFinished(1000);
    if (exitCode) *exitCode = -2;
    if (output) *output = QStringLiteral("schtasks timeout");
    return false;
  }
  const QString text = QString::fromLocal8Bit(process.readAll());
  if (exitCode) *exitCode = process.exitCode();
  if (output) *output = text;
  return process.exitStatus() == QProcess::NormalExit;
#else
  Q_UNUSED(args);
  if (exitCode) *exitCode = -3;
  if (output) *output = QStringLiteral("unsupported platform");
  return false;
#endif
}

bool Config::scheduledTaskExists() const {
  int exitCode = -1;
  QString output;
  const bool started =
      runScheduledTask(scheduledTaskQueryArgs(), &exitCode, &output);
  if (!started) return false;
  // schtasks 在任务不存在时也返回 0，但从输出中能看出“找不到”。
  if (output.contains("ERROR: The system cannot find", Qt::CaseInsensitive) ||
      output.contains("错误: 系统找不到", Qt::CaseInsensitive) ||
      output.contains("cannot find the file", Qt::CaseInsensitive)) {
    return false;
  }
  return exitCode == 0;
}

bool Config::createScheduledTask(const QString &command) {
  int exitCode = -1;
  QString output;
  const bool started =
      runScheduledTask(scheduledTaskCreateArgs(command), &exitCode, &output);
  if (started && exitCode == 0 && scheduledTaskExists()) {
    Logger::info("开机自启主链路已写入计划任务（登录触发）");
    return true;
  }
  Logger::warn(QString("计划任务自启不可用 (started=%1, exit=%2)")
                   .arg(Logger::boolText(started))
                   .arg(exitCode));
  return false;
}

bool Config::deleteScheduledTask() {
  int exitCode = -1;
  QString output;
  runScheduledTask(scheduledTaskDeleteArgs(), &exitCode, &output);
  const bool removed = !scheduledTaskExists();
  Logger::info(QString("计划任务自启清理: removed=%1, exit=%2")
                   .arg(Logger::boolText(removed))
                   .arg(exitCode));
  return removed;
}

void Config::updateAutoLaunch(bool enable) {
  const QString command = autoLaunchCommand();
  Logger::debug(QString("更新开机自启配置: enable=%1, command=%2")
                    .arg(Logger::boolText(enable))
                    .arg(command));
  if (!enable) {
    deleteScheduledTask();
    updateAutoLaunchRegistry(false, command);
    updateAutoLaunchStartupScript(false, command);
    return;
  }

  // 主链路：计划任务 ONLOGON，登录后立即启动，早于资源管理器加载 Startup 目录。
  if (createScheduledTask(command)) {
    updateAutoLaunchRegistry(false, command);
    updateAutoLaunchStartupScript(false, command);
    return;
  }

  Logger::warn("计划任务自启写入未生效，回退注册表 Run");
  updateAutoLaunchRegistry(true, command);
  if (isRegistryCommandExpected(command)) {
    Logger::info("开机自启回退链路已更新为注册表 Run，清理 Startup 脚本兜底");
    updateAutoLaunchStartupScript(false, command);
    return;
  }

  Logger::warn("注册表自启写入未生效，启用 Startup 脚本兜底");
  updateAutoLaunchStartupScript(true, command);
}

void Config::updateAutoLaunchRegistry(bool enable, const QString &command) {
#ifdef Q_OS_WIN
  QSettings bootSettings(
      "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      QSettings::NativeFormat);

  if (enable) {
    bootSettings.setValue("HAUTNetworkGuard", command);
    bootSettings.sync();
    QString stored;
    const bool ok = isRegistryCommandExpected(command, &stored);
    Logger::info(QString("开机自启注册表已写入 (回读: %1)")
                     .arg(ok ? "ok" : "mismatch"));
    if (!ok) {
      Logger::warn(
          QString("开机自启注册表回读不一致: expected=%1, actual=%2")
              .arg(command, stored));
    }
  } else {
    bootSettings.remove("HAUTNetworkGuard");
    bootSettings.sync();
    Logger::info("开机自启注册表项已删除");
  }
#endif
}

void Config::updateAutoLaunchStartupScript(bool enable, const QString &command) {
#ifdef Q_OS_WIN
  const QString scriptPath = startupScriptPath();
  if (scriptPath.isEmpty()) {
    Logger::warn("无法定位 Startup 目录，跳过启动脚本兜底");
    return;
  }

  QFileInfo scriptInfo(scriptPath);
  QDir dir = scriptInfo.dir();
  if (!dir.exists() && !dir.mkpath(".")) {
    Logger::warn(QString("创建 Startup 目录失败: %1").arg(dir.absolutePath()));
    return;
  }

  if (enable) {
    QFile scriptFile(scriptPath);
    if (!scriptFile.open(QIODevice::WriteOnly | QIODevice::Text |
                         QIODevice::Truncate)) {
      Logger::warn(QString("写入 Startup 脚本失败: %1")
                       .arg(scriptFile.errorString()));
      return;
    }

    QString escaped = command;
    escaped.replace("\"", "\"\"");

    QTextStream out(&scriptFile);
    out << "Set WshShell = CreateObject(\"WScript.Shell\")\r\n";
    out << "WshShell.Run \"" << escaped << "\", 0, False\r\n";
    scriptFile.close();
    Logger::info(QString("Startup 目录兜底脚本已写入: %1")
                     .arg(scriptPath));
    if (!isStartupScriptExpected(command)) {
      Logger::warn("Startup 兜底脚本写入后校验失败");
    }
  } else if (QFile::exists(scriptPath)) {
    if (QFile::remove(scriptPath)) {
      Logger::info(QString("Startup 目录兜底脚本已删除: %1").arg(scriptPath));
    } else {
      Logger::warn(QString("删除 Startup 脚本失败: %1").arg(scriptPath));
    }
  }
#endif
}

bool Config::isRegistryCommandExpected(const QString &command,
                                       QString *storedValue) const {
#ifdef Q_OS_WIN
  QSettings bootSettings(
      "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      QSettings::NativeFormat);
  const QString stored = bootSettings.value("HAUTNetworkGuard").toString();
  if (storedValue) {
    *storedValue = stored;
  }
  return stored.trimmed() == command.trimmed();
#else
  Q_UNUSED(command);
  Q_UNUSED(storedValue);
  return false;
#endif
}

bool Config::isStartupScriptExpected(const QString &command,
                                     QString *scriptPathOut) const {
  const QString path = startupScriptPath();
  if (scriptPathOut) {
    *scriptPathOut = path;
  }
  if (path.isEmpty() || !QFile::exists(path)) {
    return false;
  }

  QFile file(path);
  if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return false;
  }
  const QString content = QString::fromUtf8(file.readAll());
  QString escaped = command;
  escaped.replace("\"", "\"\"");
  return content.contains(escaped, Qt::CaseInsensitive);
}

void Config::verifyAndRepairAutoLaunch() {
  const QString command = autoLaunchCommand();
  QString storedRegistryValue;
  QString scriptPath;

  const bool taskOk = scheduledTaskExists();
  const bool registryOk =
      isRegistryCommandExpected(command, &storedRegistryValue);
  const bool startupOk = isStartupScriptExpected(command, &scriptPath);

  Logger::debug(
      QString("开机自启一致性检查: task=%1, registry=%2, startup=%3")
          .arg(Logger::boolText(taskOk))
          .arg(Logger::boolText(registryOk))
          .arg(Logger::boolText(startupOk)));

  if (taskOk) {
    // 计划任务是最早的启动链路；保留它并清理旧的重复入口。
    if (registryOk) updateAutoLaunchRegistry(false, command);
    if (startupOk) updateAutoLaunchStartupScript(false, command);
    return;
  }

  // 旧版本只写注册表或 Startup；这里迁移到计划任务，让后续开机更早启动。
  Logger::info(QString("开机自启链路迁移: registry=%1, startup=%2 -> 计划任务")
                   .arg(Logger::boolText(registryOk))
                   .arg(Logger::boolText(startupOk)));
  updateAutoLaunch(true);
}
