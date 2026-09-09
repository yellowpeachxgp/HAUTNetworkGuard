#include "logger.h"
#include <QByteArray>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QStandardPaths>

namespace {

Logger::Level parseLevel(const QByteArray &raw) {
  const QByteArray level = raw.trimmed().toUpper();
  if (level == "ERROR")
    return Logger::ERROR;
  if (level == "WARN" || level == "WARNING")
    return Logger::WARN;
  if (level == "INFO")
    return Logger::INFO;
  return Logger::DEBUG;
}

} // namespace

Logger &Logger::instance() {
  static Logger inst;
  return inst;
}

Logger::Logger() {
  const QByteArray envLevel = qgetenv("HAUT_LOG_LEVEL");
  if (!envLevel.isEmpty()) {
    m_minLevel = parseLevel(envLevel);
  } else {
    m_minLevel = DEBUG;
  }
}

QString Logger::logFilePath() const {
  QString dir =
      QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  QDir().mkpath(dir);
  return dir + "/app.log";
}

void Logger::rotate() {
  QString path = logFilePath();
  QFileInfo fi(path);
  if (fi.exists() && fi.size() > MAX_LOG_SIZE) {
    QString oldPath = path + ".old";
    QFile::remove(oldPath);
    QFile::rename(path, oldPath);
  }
}

void Logger::write(Level level, const QString &msg) {
  QMutexLocker locker(&m_mutex);
  if (!m_enabled || level < m_minLevel)
    return;

  static const char *labels[] = {"DEBUG", "INFO", "WARN", "ERROR"};

  rotate();

  QFile file(logFilePath());
  if (!file.open(QIODevice::Append | QIODevice::Text))
    return;

  QTextStream out(&file);
  QString timestamp =
      QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss");
  out << "[" << timestamp << "] [" << labels[level] << "] " << msg << "\n";
}

void Logger::setMinLevel(Level level) {
  Logger &logger = instance();
  QMutexLocker locker(&logger.m_mutex);
  logger.m_minLevel = level;
}

void Logger::setEnabled(bool enabled) {
  Logger &logger = instance();
  QMutexLocker locker(&logger.m_mutex);
  logger.m_enabled = enabled;
}

Logger::Level Logger::minLevel() {
  Logger &logger = instance();
  QMutexLocker locker(&logger.m_mutex);
  return logger.m_minLevel;
}

QString Logger::levelName(Level level) {
  switch (level) {
  case DEBUG:
    return "DEBUG";
  case INFO:
    return "INFO";
  case WARN:
    return "WARN";
  case ERROR:
    return "ERROR";
  }
  return "UNKNOWN";
}

QString Logger::boolText(bool value) { return value ? "on" : "off"; }

QString Logger::maskUsername(const QString &username) {
  if (username.isEmpty())
    return "<empty>";
  if (username.size() <= 4)
    return QString("*").repeated(username.size());
  return username.left(2) + QString("*").repeated(username.size() - 4) +
         username.right(2);
}

QString Logger::maskSecret(const QString &value, int keepPrefix,
                           int keepSuffix) {
  if (value.isEmpty())
    return "<empty>";
  const int len = value.size();
  if (keepPrefix < 0)
    keepPrefix = 0;
  if (keepSuffix < 0)
    keepSuffix = 0;
  if (keepPrefix + keepSuffix >= len)
    return QString("*").repeated(len);
  return value.left(keepPrefix) + QString("*").repeated(len - keepPrefix - keepSuffix) +
         value.right(keepSuffix);
}

void Logger::debug(const QString &msg) { instance().write(DEBUG, msg); }
void Logger::info(const QString &msg) { instance().write(INFO, msg); }
void Logger::warn(const QString &msg) { instance().write(WARN, msg); }
void Logger::error(const QString &msg) { instance().write(ERROR, msg); }
