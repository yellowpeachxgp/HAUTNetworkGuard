#ifndef LOGGER_H
#define LOGGER_H

#include <QFile>
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
  ~Logger();
  void write(Level level, const QString &msg);
  bool ensureOpen();
  void rotateIfNeeded();

  QMutex m_mutex;
  Level m_minLevel = DEBUG;
  bool m_enabled = true;
  // 日志文件保持打开，避免每条日志都做路径解析、目录创建和开关文件；
  // 这在 Windows + 杀毒软件环境下会明显拖慢启动和检测循环。
  QFile m_file;
  qint64 m_writtenBytes = 0;
  QString m_path;
  static const qint64 MAX_LOG_SIZE = 1024 * 1024; // 1MB
};

#endif // LOGGER_H
