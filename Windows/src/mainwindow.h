#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QCheckBox>
#include <QCloseEvent>
#include <QElapsedTimer>
#include <QEvent>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QPushButton>
#include <QShowEvent>
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
  // 开机自启场景可延迟构建完整 UI，先把托盘图标显示出来。
  explicit MainWindow(bool deferUi, QWidget *parent = nullptr);
  // 注入存储、网络和时钟；隔离测试关闭后台任务与桌面通知。
  MainWindow(Config &config, Api *api, std::function<double()> now,
             bool backgroundTasks, bool deferUi = false,
             QWidget *parent = nullptr);
  QString diagnosticText() const;
  bool isTrayAvailable() const;
  ~MainWindow();

public slots:
  void showWindow();

protected:
  void closeEvent(QCloseEvent *event) override;
  void showEvent(QShowEvent *event) override;
  void changeEvent(QEvent *event) override;

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
  void exitApplication();

private:
  void ensureUiBuilt();
  void applyCachedUiState();
  void applyWindowStyle();
  void setupUi();
  void refitWindowSize();
  void scheduleRefit();
  void loadSettings();
  bool saveSettings();
  bool syncCredentialsToConfig();
  void triggerAutoLoginIfPossible(const QString &reason);
  void refreshActionState();
  void setStatusBadge(const QString &text, const QString &color);
  void setStatusDetail(const QString &message, bool warning = false);
  void clearMetrics();
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
  QWidget *m_centralWidget = nullptr;
  QLabel *m_statusLabel = nullptr;
  QLabel *m_statusDetailLabel = nullptr;
  QLabel *m_ipLabel = nullptr;
  QLabel *m_usageLabel = nullptr;
  QLabel *m_timeLabel = nullptr;
  QLabel *m_lastCheckLabel = nullptr;
  QLineEdit *m_usernameEdit = nullptr;
  QLineEdit *m_passwordEdit = nullptr;
  QCheckBox *m_autoSaveCheck = nullptr;
  QCheckBox *m_autoLaunchCheck = nullptr;
  QCheckBox *m_autoLoginCheck = nullptr;
  QLabel *m_optionHintLabel = nullptr;
  QSpinBox *m_intervalSpinBox = nullptr;
  QPushButton *m_loginBtn = nullptr;
  QPushButton *m_logoutBtn = nullptr;
  QPushButton *m_saveBtn = nullptr;

  // 功能组件
  Api *m_api = nullptr;
  TrayIcon *m_trayIcon = nullptr;
  QTimer *m_statusTimer = nullptr;
  QTimer *m_networkChangeTimer = nullptr;
  QNetworkInformation *m_networkInformation = nullptr;
  Config &m_config;
  std::function<double()> m_now;
  bool m_backgroundTasks = false;
  bool m_externalApi = false;
  bool m_networkRecheckPending = false;
  bool m_uiReady = false;
  bool m_deferUi = false;
  bool m_windowFitDone = false;
  bool m_refitPending = false;

  // 未构建 UI 时缓存状态，构建后一次性回填。
  QString m_cachedStatusText = "检测中";
  QString m_cachedStatusColor = "#2563eb";
  QString m_cachedDetail = "正在初始化网络状态检测...";
  bool m_cachedDetailWarning = false;
  QString m_cachedLastCheckText = "最近检测：尚未开始";
  QString m_cachedIp = "-";
  QString m_cachedUsage = "-";
  QString m_cachedTime = "-";

  bool m_isOnline = false;
  bool m_isManualLogin = false;
  SessionPolicy m_session;
  QElapsedTimer m_clock;
  double monotonicNow() const { return m_now ? m_now() : m_clock.elapsed() / 1000.0; }
};

#endif // MAINWINDOW_H
