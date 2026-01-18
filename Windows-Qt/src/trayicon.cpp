#include "trayicon.h"
#include <QApplication>
#include <QIcon>

TrayIcon::TrayIcon(QObject *parent) : QObject(parent) {
  m_trayIcon = new QSystemTrayIcon(this);

  createMenu();
  updateIcon(false);

  connect(m_trayIcon, &QSystemTrayIcon::activated, this,
          &TrayIcon::onTrayActivated);
}

void TrayIcon::createMenu() {
  m_menu = new QMenu();

  m_showAction = m_menu->addAction("显示窗口");
  connect(m_showAction, &QAction::triggered, this,
          &TrayIcon::showWindowRequested);

  m_menu->addSeparator();

  m_loginAction = m_menu->addAction("立即登录");
  connect(m_loginAction, &QAction::triggered, this, &TrayIcon::loginRequested);

  m_logoutAction = m_menu->addAction("注销登录");
  connect(m_logoutAction, &QAction::triggered, this,
          &TrayIcon::logoutRequested);

  m_menu->addSeparator();

  m_exitAction = m_menu->addAction("退出程序");
  connect(m_exitAction, &QAction::triggered, this, &TrayIcon::exitRequested);

  m_trayIcon->setContextMenu(m_menu);
}

void TrayIcon::show() { m_trayIcon->show(); }

void TrayIcon::hide() { m_trayIcon->hide(); }

void TrayIcon::setOnlineStatus(bool online) {
  updateIcon(online);
  m_trayIcon->setToolTip(online ? "HAUT Network Guard - 在线"
                                : "HAUT Network Guard - 离线");
}

void TrayIcon::showMessage(const QString &title, const QString &message,
                           QSystemTrayIcon::MessageIcon icon) {
  m_trayIcon->showMessage(title, message, icon, 3000);
}

void TrayIcon::updateIcon(bool online) {
  // 使用应用程序图标
  QIcon icon = QApplication::windowIcon();
  if (icon.isNull()) {
    icon = QIcon(":/icons/app.ico");
  }
  m_trayIcon->setIcon(icon);
}

void TrayIcon::onTrayActivated(QSystemTrayIcon::ActivationReason reason) {
  switch (reason) {
  case QSystemTrayIcon::Trigger:
  case QSystemTrayIcon::DoubleClick:
    emit showWindowRequested();
    break;
  default:
    break;
  }
}
