#include "encryption.h"
#include <QCryptographicHash>

const QString Encryption::PASSWORD_KEY = "1234567890";

QString Encryption::encryptUsername(const QString &username) {
  // SRUN3K 用户名加密: 每个字符 ASCII + 4
  QString encrypted;
  for (const QChar &c : username) {
    encrypted.append(QChar(c.unicode() + 4));
  }
  // 添加前缀
  return "{SRUN3}\r\n" + encrypted;
}

QString Encryption::encryptPassword(const QString &password) {
  // SRUN3K 密码加密
  // 1. XOR 加密
  // 2. 位分割

  QByteArray xored;
  QByteArray pwdBytes = password.toLatin1();
  QByteArray keyBytes = PASSWORD_KEY.toLatin1();

  // XOR 加密
  for (int i = 0; i < pwdBytes.size(); ++i) {
    unsigned char p = static_cast<unsigned char>(pwdBytes[i]);
    unsigned char k = static_cast<unsigned char>(keyBytes[i % keyBytes.size()]);
    xored.append(static_cast<char>(p ^ k));
  }

  // 位分割: 将每个字节分成高4位和低4位
  QString result;
  for (int i = 0; i < xored.size(); ++i) {
    unsigned char byte = static_cast<unsigned char>(xored[i]);
    unsigned char high = (byte >> 4) & 0x0F;
    unsigned char low = byte & 0x0F;

    // 转换为可打印字符
    result.append(QChar('a' + high));
    result.append(QChar('a' + low));
  }

  return result;
}

QString Encryption::md5Hash(const QString &input) {
  return md5Hash(input.toUtf8());
}

QString Encryption::md5Hash(const QByteArray &input) {
  QByteArray hash = QCryptographicHash::hash(input, QCryptographicHash::Md5);
  return QString::fromLatin1(hash.toHex());
}
