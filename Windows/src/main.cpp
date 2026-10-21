#include "config.h"
#include "instance_guard.h"
#include "logger.h"
#include "mainwindow.h"
#include <QApplication>
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QIcon>
#include <QStringList>
#include <QStyle>
#include <QTimer>

int main(int argc, char *argv[]) {
  QElapsedTimer startupClock;
  startupClock.start();

  QApplication app(argc, argv);
  const qint64 appReadyMs = startupClock.elapsed();

  // 设置应用程序信息
  app.setApplicationName("HAUTNetworkGuard");
  app.setApplicationVersion(QStringLiteral(HAUT_VERSION_STRING));
  app.setOrganizationName("YellowPeach");
  // 优先使用打包的应用图标，缺失时回退到系统图标。
  const QIcon appIcon(":/app.ico");
  app.setWindowIcon(appIcon.isNull()
                        ? app.style()->standardIcon(QStyle::SP_ComputerIcon)
                        : appIcon);

  // 设置关闭最后窗口时不退出应用（托盘常驻）
  app.setQuitOnLastWindowClosed(false);

  InstanceGuard instanceGuard;
  if (!instanceGuard.acquire()) {
    qWarning("检测到 HAUTNetworkGuard 已在运行，当前启动请求退出");
    return 0;
  }

  // 加载配置
  Config::instance();
  const qint64 configReadyMs = startupClock.elapsed();

  // 带 --startup 参数时静默启动到托盘（开机自启场景）。
  // 首次启动尚未配置账号时必须显示窗口，避免开机自启后学生找不到配置入口。
  const QStringList args = app.arguments();
  const bool startupRequested = args.contains("--startup", Qt::CaseInsensitive);
  const bool hasConfigured = Config::instance().hasConfigured();
  const bool startInBackground = startupRequested && hasConfigured;
  if (startupRequested && !hasConfigured) {
    Logger::info("检测到 --startup 但尚未完成首次配置，显示配置窗口");
  }
  Logger::info(QString("应用启动 (版本: %1, 路径: %2, 参数: %3, 启动模式: %4, "
                       "已耗时: %5ms)")
                   .arg(QCoreApplication::applicationVersion())
                   .arg(QDir::toNativeSeparators(
                       QCoreApplication::applicationFilePath()))
                   .arg(args.join(" "))
                   .arg(startInBackground ? "background" : "normal")
                   .arg(startupClock.elapsed()));

  // 开机自启时先只创建托盘和网络控制器，窗口 UI 等用户真正打开时再构建，
  // 避免字体、样式表和布局初始化占用登录后的黄金启动时间。
  MainWindow mainWindow(startInBackground);
  const qint64 windowReadyMs = startupClock.elapsed();
  Logger::info(QString("启动阶段: qapp=%1ms, config=%2ms, window=%3ms")
                   .arg(appReadyMs)
                   .arg(configReadyMs - appReadyMs)
                   .arg(windowReadyMs - configReadyMs));
  if (startInBackground && !mainWindow.isTrayAvailable()) {
    Logger::warn("系统托盘不可用，--startup 回退为显示主窗口");
    mainWindow.showWindow();
  } else if (!startInBackground) {
    Logger::debug("主窗口前台显示");
    mainWindow.show();
  } else {
    Logger::info("检测到 --startup，主窗口保持隐藏，仅托盘常驻");
  }

  // 自启修复和网络后端初始化都推迟到事件循环，保证托盘先出现。
  QTimer::singleShot(2000, &app, [] {
    Config::instance().repairAutoLaunchIfNeeded();
  });

  QTimer::singleShot(0, &app, [&startupClock, &mainWindow] {
    Logger::info(QString("事件循环已就绪: %1ms, tray_available=%2")
                     .arg(startupClock.elapsed())
                     .arg(mainWindow.isTrayAvailable() ? "true" : "false"));
  });

  return app.exec();
}
