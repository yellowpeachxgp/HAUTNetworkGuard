#include "config.h"
#include "logger.h"
#include "mainwindow.h"
#include "instance_guard.h"
#include <QApplication>
#include <QCoreApplication>
#include <QDir>
#include <QStringList>
#include <QStyle>

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);

  // 设置应用程序信息
  app.setApplicationName("HAUTNetworkGuard");
  app.setApplicationVersion(QStringLiteral(HAUT_VERSION_STRING));
  app.setOrganizationName("YellowPeach");
  // 使用系统默认图标
  app.setWindowIcon(app.style()->standardIcon(QStyle::SP_ComputerIcon));

  // 设置关闭最后窗口时不退出应用（托盘常驻）
  app.setQuitOnLastWindowClosed(false);

  InstanceGuard instanceGuard;
  if (!instanceGuard.acquire()) {
    qWarning("检测到 HAUTNetworkGuard 已在运行，当前启动请求退出");
    return 0;
  }

  // 加载配置
  Config::instance();

  // 带 --startup 参数时静默启动到托盘（开机自启场景）。
  // 首次启动尚未配置账号时必须显示窗口，避免开机自启后学生找不到配置入口。
  const QStringList args = app.arguments();
  const bool startupRequested = args.contains("--startup", Qt::CaseInsensitive);
  const bool hasConfigured = Config::instance().hasConfigured();
  const bool startInBackground = startupRequested && hasConfigured;
  if (startupRequested && !hasConfigured) {
    Logger::info("检测到 --startup 但尚未完成首次配置，显示配置窗口");
  }
  Logger::info(QString("应用启动 (版本: %1, 路径: %2, 参数: %3, 启动模式: %4)")
                   .arg(QCoreApplication::applicationVersion())
                   .arg(QDir::toNativeSeparators(
                       QCoreApplication::applicationFilePath()))
                   .arg(args.join(" "))
                   .arg(startInBackground ? "background" : "normal"));

  // 创建主窗口
  MainWindow mainWindow;
  if (!startInBackground) {
    Logger::debug("主窗口前台显示");
    mainWindow.show();
  } else {
    Logger::info("检测到 --startup，主窗口保持隐藏，仅托盘常驻");
  }

  return app.exec();
}
