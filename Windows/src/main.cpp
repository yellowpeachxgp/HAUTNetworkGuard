#include "config.h"
#include "mainwindow.h"
#include <QApplication>
#include <QStyle>

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);

  // 设置应用程序信息
  app.setApplicationName("HAUTNetworkGuard");
  app.setApplicationVersion("1.3.4");
  app.setOrganizationName("YellowPeach");
  // 使用系统默认图标
  app.setWindowIcon(app.style()->standardIcon(QStyle::SP_ComputerIcon));

  // 设置关闭最后窗口时不退出应用（托盘常驻）
  app.setQuitOnLastWindowClosed(false);

  // 加载配置
  Config::instance();

  // 创建主窗口
  MainWindow mainWindow;
  mainWindow.show();

  return app.exec();
}
