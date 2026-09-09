#ifndef PROTOCOL_UTILS_H
#define PROTOCOL_UTILS_H

#include <QString>
#include <QtGlobal>

struct StatusParseResult {
  bool online = false;
  QString format = "offline";
  QString username;
  QString ip;
  qint64 bytes = 0;
  qint64 seconds = 0;
};

class ProtocolUtils {
public:
  static QString responsePreview(const QString &response, int maxLen = 160);
  static QString extractErrorCode(const QString &response);
  static QString classifyLoginResponse(const QString &response);
  static QString userFacingLoginMessage(const QString &classification);
  // 将 Qt 网络层错误转换为学生可直接处理的提示，避免把底层英文错误直接展示。
  static QString userFacingNetworkError(const QString &error);
  static StatusParseResult parseStatusResponse(const QString &response);
};

#endif // PROTOCOL_UTILS_H
