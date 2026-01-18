#ifndef TRAYICON_H
#define TRAYICON_H

#include <QAction>
#include <QMenu>
#include <QObject>
#include <QSystemTrayIcon>

class TrayIcon : public QObject {
  Q_OBJECT

public:
  explicit TrayIcon(QObject *parent = nullptr);

  void show();
  void hide();

  void setOnlineStatus(bool online);
  void
  showMessage(const QString &title, const QString &message,
              QSystemTrayIcon::MessageIcon icon = QSystemTrayIcon::Information);

signals:
  void showWindowRequested();
  void exitRequested();
  void loginRequested();
  void logoutRequested();

private slots:
  void onTrayActivated(QSystemTrayIcon::ActivationReason reason);

private:
  void createMenu();
  void updateIcon(bool online);

  QSystemTrayIcon *m_trayIcon;
  QMenu *m_menu;
  QAction *m_showAction;
  QAction *m_loginAction;
  QAction *m_logoutAction;
  QAction *m_exitAction;
};

#endif // TRAYICON_H
