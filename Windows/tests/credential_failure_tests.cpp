#include "../src/config.h"
#include "../src/logger.h"
#include <QCoreApplication>
#include <QDataStream>
#include <QDebug>
#include <QFile>
#include <QTemporaryDir>
#include <stdexcept>

namespace {
bool rejectWrites = false;
bool readSettings(QIODevice &device, QSettings::SettingsMap &map) {
  if (device.atEnd()) return true;
  QDataStream stream(&device);
  stream >> map;
  return stream.status() == QDataStream::Ok;
}
bool writeSettings(QIODevice &device, const QSettings::SettingsMap &map) {
  if (rejectWrites) return false;
  QDataStream stream(&device);
  stream << map;
  return stream.status() == QDataStream::Ok;
}
QByteArray diskBytes(const QString &path) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly)) throw std::runtime_error("无法回读测试配置");
  return file.readAll();
}
}

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  Logger::setEnabled(false);
  int checked = 0;
  auto expect = [&](bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
    ++checked;
  };
  try {
    QTemporaryDir directory;
    expect(directory.isValid(), "无法创建临时配置目录");
    const auto format = QSettings::registerFormat("haut-test", readSettings, writeSettings);
    expect(format != QSettings::InvalidFormat, "无法注册存储故障测试后端");
    QSettings settings(directory.filePath("settings.haut-test"), format);
    bool failEncoding = false, mismatch = false;
    PasswordCodec codec{
        [&](const QString &plain) { return failEncoding ? QString() : "test:" + plain; },
        [&](const QString &encoded) {
          if (mismatch) return QString("mismatch");
          return encoded.startsWith("test:") ? encoded.mid(5) : QString();
        }};
    Config config(settings, codec);
    config.setUsername("original-student");
    config.setPassword("original-password");
    config.setAutoSave(true);
    config.setAutoLaunch(true);
    config.setCheckInterval(45);
    expect(config.save(), "初始配置应保存成功");
    const auto original = diskBytes(settings.fileName());

    failEncoding = true;
    config.setUsername("pending-student");
    config.setPassword("pending-password");
    config.setAutoLaunch(false);
    config.setCheckInterval(120);
    expect(!config.save(), "编码失败必须向调用方报告失败");
    expect(!config.lastError().isEmpty(), "编码失败应有可理解的错误");
    expect(config.username() == "original-student" && config.password() == "original-password" &&
           config.autoLaunch() && config.checkInterval() == 45, "编码失败必须还原运行配置");
    expect(diskBytes(settings.fileName()) == original, "编码失败不能改写旧文件");

    failEncoding = false;
    mismatch = true;
    config.setPassword("pending-password");
    expect(!config.save(), "编码后解码不符不能提交");
    expect(diskBytes(settings.fileName()) == original, "解码不符不能改写旧文件");
    mismatch = false;
    config.setPassword("updated-password");
    expect(config.save(), "保护后端恢复后同一实例应可重试");
    const auto beforeDiskFailure = diskBytes(settings.fileName());
    rejectWrites = true;
    config.setPassword("write-rejected");
    config.setUsername("write-rejected-student");
    expect(!config.save(), "真实 QSettings 写入失败必须报告失败");
    expect(config.password() == "updated-password" && config.username() == "original-student",
           "写入失败后必须还原运行凭据");
    expect(diskBytes(settings.fileName()) == beforeDiskFailure, "写入被拒绝后磁盘必须保留原文件");
    rejectWrites = false;
    config.setPassword("recovered-password");
    expect(config.save(), "存储恢复后同一实例必须能够保存");
    {
      QSettings reread(settings.fileName(), format);
      Config coldStart(reread, codec);
      expect(coldStart.password() == "recovered-password", "重新构造配置应读回修复后的密码");
    }

    settings.setValue("password", "unreadable");
    settings.sync();
    const auto unreadable = diskBytes(settings.fileName());
    Config failedRead(settings, codec);
    expect(failedRead.password().isEmpty() && !failedRead.lastError().isEmpty(), "读取失败应提示重新输入");
    expect(!failedRead.save(), "不能用读取失败得到的空密码覆盖旧凭据");
    expect(diskBytes(settings.fileName()) == unreadable, "读取失败必须保留旧凭据供后续恢复");
    failedRead.setAutoSave(false);
    expect(failedRead.save(), "用户明确关闭记住密码时允许清除不可读凭据");
    expect(settings.value("password").toString().isEmpty(), "清除后不应留下不可读密码");
  } catch (const std::exception &error) {
    qCritical().noquote() << "凭据故障回放失败：" << error.what();
    return 1;
  }
  qInfo().noquote() << "Qt 凭据故障回放通过：" << checked << "个断言";
}
