#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QCheckBox>
#include <QCloseEvent>
#include <QLabel>
#include <QElapsedTimer>
#include <QLineEdit>
#include <QMainWindow>
#include <QPushButton>
#include <QSpinBox>
#include <QTimer>
#include <functional>

#include "api.h"
#include "config.h"
#include "session_policy.h"
#include "trayicon.h"

class QNetworkInformation;

class MainWindow : public QMainWindow {
  Q_OBJECT

public:
  explicit MainWindow(QWidget *parent = nullptr);
  // 注入存储、网络和时钟；隔离测试关闭后台任务与桌面通知。
  MainWindow(Config &config, Api *api, std::function<double()> now,
             bool backgroundTasks, QWidget *parent = nullptr);
  QString diagnosticText() const;
  ~MainWindow();

protected:
  void closeEvent(QCloseEvent *event) override;

private slots:
  void onLoginClicked();
  void onLogoutClicked();
  void onSaveClicked();
  void onCopyDiagnosticsClicked();

  void onLoginSuccess(quint64 token, const QString &message);
  void onLoginFailed(quint64 token, const QString &error);
  void onLogoutSuccess(quint64 token, const QString &resultClass);
  void onLogoutFailed(quint64 token, const QString &error);
  void onStatusChecked(quint64 token, bool online, const QString &resultClass,
                       const QString &ip, qint64 bytesUsed,
                       qint64 secondsOnline);

  void checkNetworkStatus();
  void onNetworkEnvironmentChanged();
  void onNetworkChangeDebounced();
  void showWindow();
  void exitApplication();

private:
  void applyWindowStyle();
  void setupUi();
  void loadSettings();
  bool saveSettings();
  bool syncCredentialsToConfig();
  void triggerAutoLoginIfPossible(const QString &reason);
  void refreshActionState();
  void setStatusDetail(const QString &message, bool warning = false);
  void updateLastCheckLabel(const QString &prefix = "最近检测");
  void updateOptionHint();
  void updateStatusDisplay(bool online, const QString &ip = "",
                           qint64 bytes = 0, qint64 seconds = 0);
  void setupNetworkMonitor();
  void flushPendingNetworkCheck();
  QString formatBytes(qint64 bytes);
  QString formatTime(qint64 seconds);
  QString automaticRetryHint() const;

  // UI 组件
  QWidget *m_centralWidget;
  QLabel *m_statusLabel;
  QLabel *m_statusDetailLabel;
  QLabel *m_ipLabel;
  QLabel *m_usageLabel;
  QLabel *m_timeLabel;
  QLabel *m_lastCheckLabel;
  QLineEdit *m_usernameEdit;
  QLineEdit *m_passwordEdit;
  QCheckBox *m_autoSaveCheck;
  QCheckBox *m_autoLaunchCheck;
  QCheckBox *m_autoLoginCheck;
  QLabel *m_optionHintLabel;
  QSpinBox *m_intervalSpinBox;
  QPushButton *m_loginBtn;
  QPushButton *m_logoutBtn;
  QPushButton *m_saveBtn;

  // 功能组件
  Api *m_api = nullptr;
  TrayIcon *m_trayIcon = nullptr;
  QTimer *m_statusTimer = nullptr;
  QTimer *m_networkChangeTimer = nullptr;
  QNetworkInformation *m_networkInformation = nullptr;
  Config &m_config;
  std::function<double()> m_now;
  bool m_backgroundTasks;
  bool m_externalApi = false;
  bool m_networkRecheckPending = false;

  bool m_isOnline = false;
  bool m_isManualLogin = false;
  SessionPolicy m_session;
  QElapsedTimer m_clock;
  double monotonicNow() const { return m_now ? m_now() : m_clock.elapsed() / 1000.0; }
};

#endif // MAINWINDOW_H
