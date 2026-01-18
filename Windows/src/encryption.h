#ifndef ENCRYPTION_H
#define ENCRYPTION_H

#include <QByteArray>
#include <QString>

class Encryption {
public:
  // SRUN3K 用户名加密: 每个字符 ASCII + 4，添加前缀
  static QString encryptUsername(const QString &username);

  // SRUN3K 密码加密: XOR + 位分割
  static QString encryptPassword(const QString &password);

  // MD5 哈希
  static QString md5Hash(const QString &input);
  static QString md5Hash(const QByteArray &input);

private:
  static const QString PASSWORD_KEY;
};

#endif // ENCRYPTION_H
