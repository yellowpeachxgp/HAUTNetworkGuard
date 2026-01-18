#include "config.h"
#include "mainwindow.h"
#include <QApplication>
#include <QIcon>

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);

  // 设置应用程序信息
  app.setApplicationName("HAUTNetworkGuard");
  app.setApplicationVersion("1.3.0");
  app.setOrganizationName("YellowPeach");
  app.setWindowIcon(QIcon(":/icons/app.ico"));

  // 设置关闭最后窗口时不退出应用（托盘常驻）
  app.setQuitOnLastWindowClosed(false);

  // 加载配置
  Config::instance();

  // 创建主窗口
  MainWindow mainWindow;
  mainWindow.show();

  return app.exec();
}
