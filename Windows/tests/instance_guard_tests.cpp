#include "../src/instance_guard.h"
#include <QCoreApplication>
#include <QDebug>
#include <stdexcept>

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  try {
    InstanceGuard first;
    if (!first.acquire()) throw std::runtime_error("首个实例无法取得锁");
    InstanceGuard second;
    if (second.acquire(50)) throw std::runtime_error("第二个实例错误取得锁");
  }
  catch (const std::exception &error) {
    qCritical().noquote() << "单实例锁测试失败：" << error.what();
    return 1;
  }
  qInfo().noquote() << "Windows 单实例锁测试通过";
  return 0;
}
