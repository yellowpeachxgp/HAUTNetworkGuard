#include "trayicon.h"
#include <QApplication>
#include <QColor>
#include <QIcon>
#include <QPainter>
#include <QPixmap>
#include <QStyle>

TrayIcon::TrayIcon(QObject *parent, bool notificationsEnabled)
    : QObject(parent), m_notificationsEnabled(notificationsEnabled) {
  m_trayIcon = new QSystemTrayIcon(this);

  createMenu();
  updateIcon(false);
  updateActionStates();

  connect(m_trayIcon, &QSystemTrayIcon::activated, this,
          &TrayIcon::onTrayActivated);
}

TrayIcon::~TrayIcon() {
  m_trayIcon->setContextMenu(nullptr);
  delete m_menu;
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
  m_online = online;
  updateIcon(online);
  updateActionStates();
  m_trayIcon->setToolTip(online ? "HAUT Network Guard - 在线"
                                : "HAUT Network Guard - 离线");
}

void TrayIcon::setBusy(bool busy) {
  m_busy = busy;
  updateActionStates();
}

void TrayIcon::setManualOfflineHold(bool hold) {
  m_manualOfflineHold = hold;
  m_loginAction->setText(hold ? "立即登录（解除暂停）" : "立即登录");
  updateActionStates();
}

void TrayIcon::showMessage(const QString &title, const QString &message,
                           QSystemTrayIcon::MessageIcon icon) {
  if (m_notificationsEnabled) m_trayIcon->showMessage(title, message, icon, 3000);
}

void TrayIcon::updateIcon(bool online) {
  QIcon baseIcon = QApplication::windowIcon();
  if (baseIcon.isNull()) {
    baseIcon = QApplication::style()->standardIcon(QStyle::SP_ComputerIcon);
  }

  QPixmap pixmap = baseIcon.pixmap(32, 32);
  if (pixmap.isNull()) {
    m_trayIcon->setIcon(baseIcon);
    return;
  }

  QPainter painter(&pixmap);
  painter.setRenderHint(QPainter::Antialiasing, true);
  painter.setPen(Qt::white);
  painter.setBrush(online ? QColor("#4CAF50") : QColor("#f44336"));
  painter.drawEllipse(QRect(20, 20, 10, 10));
  painter.end();

  m_trayIcon->setIcon(QIcon(pixmap));
}

void TrayIcon::updateActionStates() {
  if (m_loginAction) {
    m_loginAction->setEnabled((!m_online || m_manualOfflineHold) && !m_busy);
  }
  if (m_logoutAction) {
    m_logoutAction->setEnabled(m_online && !m_busy);
  }
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
