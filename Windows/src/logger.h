#ifndef LOGGER_H
#define LOGGER_H

#include <QMutex>
#include <QString>

class Logger {
public:
  enum Level { DEBUG = 0, INFO, WARN, ERROR };

  static Logger &instance();

  static void setMinLevel(Level level);
  static void setEnabled(bool enabled);
  static Level minLevel();

  static void debug(const QString &msg);
  static void info(const QString &msg);
  static void warn(const QString &msg);
  static void error(const QString &msg);

  static QString levelName(Level level);
  static QString boolText(bool value);
  static QString maskUsername(const QString &username);
  static QString maskSecret(const QString &value, int keepPrefix = 1,
                            int keepSuffix = 1);

private:
  Logger();
  void write(Level level, const QString &msg);
  void rotate();
  QString logFilePath() const;

  QMutex m_mutex;
  Level m_minLevel = DEBUG;
  bool m_enabled = true;
  static const qint64 MAX_LOG_SIZE = 1024 * 1024; // 1MB
};

#endif // LOGGER_H
