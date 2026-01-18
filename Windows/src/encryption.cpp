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
  // SRUN3K 密码加密 (与 Rust/macOS 版本完全一致)
  // 1. XOR 加密 (密钥反向索引)
  // 2. 位分割 (低4位 + 0x36, 高4位 + 0x63)
  // 3. 奇偶交替组合

  QByteArray keyBytes = PASSWORD_KEY.toLatin1();
  int keyLen = keyBytes.size();
  QByteArray pwdBytes = password.toLatin1();

  QString result;

  for (int i = 0; i < pwdBytes.size(); ++i) {
    unsigned char c = static_cast<unsigned char>(pwdBytes[i]);

    // 密钥索引: 反向 (与 Rust 版本一致)
    int keyIndex = keyLen - 1 - (i % keyLen);
    unsigned char k = static_cast<unsigned char>(keyBytes[keyIndex]);

    // XOR 运算
    unsigned char ki = c ^ k;

    // 位分割: 低4位 + 0x36, 高4位 + 0x63
    unsigned char lowBits = (ki & 0x0F) + 0x36;
    unsigned char highBits = ((ki >> 4) & 0x0F) + 0x63;

    QChar lowChar(lowBits);
    QChar highChar(highBits);

    // 根据索引奇偶交替组合
    if (i % 2 == 0) {
      result.append(lowChar);
      result.append(highChar);
    } else {
      result.append(highChar);
      result.append(lowChar);
    }
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
