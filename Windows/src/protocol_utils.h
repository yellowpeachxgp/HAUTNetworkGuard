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
  static StatusParseResult parseStatusResponse(const QString &response);
};

#endif // PROTOCOL_UTILS_H
