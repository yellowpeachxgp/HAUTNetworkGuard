#include "mainwindow.h"
#include "config.h"
#include "logger.h"
#include <QApplication>
#include <QClipboard>
#include <QDateTime>
#include <QFrame>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QMessageBox>
#include <QtGlobal>
#include <QVBoxLayout>

MainWindow::MainWindow(QWidget *parent)
    : MainWindow(Config::instance(), nullptr, {}, true, parent) {}

MainWindow::MainWindow(Config &config, Api *api, std::function<double()> now,
                       bool backgroundTasks, QWidget *parent)
    : QMainWindow(parent), m_config(config), m_now(std::move(now)),
      m_backgroundTasks(backgroundTasks) {
  m_clock.start();
  setWindowTitle(QStringLiteral("HAUT Network Guard v" HAUT_VERSION_STRING));
  setFixedSize(460, 640);
  Logger::debug("MainWindow 初始化开始");

  setupUi();
  applyWindowStyle();
  loadSettings();

  // 初始化 API
  m_api = api ? api : new Api(this);
  connect(m_api, &Api::loginSuccess, this, &MainWindow::onLoginSuccess);
  connect(m_api, &Api::loginFailed, this, &MainWindow::onLoginFailed);
  connect(m_api, &Api::logoutSuccess, this, &MainWindow::onLogoutSuccess);
  connect(m_api, &Api::logoutFailed, this, &MainWindow::onLogoutFailed);
  connect(m_api, &Api::statusChecked, this, &MainWindow::onStatusChecked);

  // 初始化托盘图标
  m_trayIcon = new TrayIcon(this, m_backgroundTasks);
  connect(m_trayIcon, &TrayIcon::showWindowRequested, this,
          &MainWindow::showWindow);
  connect(m_trayIcon, &TrayIcon::exitRequested, this,
          &MainWindow::exitApplication);
  connect(m_trayIcon, &TrayIcon::loginRequested, this,
          &MainWindow::onLoginClicked);
  connect(m_trayIcon, &TrayIcon::logoutRequested, this,
          &MainWindow::onLogoutClicked);
  if (m_backgroundTasks) m_trayIcon->show();
  refreshActionState();
  Logger::info("系统托盘已初始化");

  // 状态检测定时器 (使用配置的间隔)
  m_statusTimer = new QTimer(this);
  connect(m_statusTimer, &QTimer::timeout, this,
          &MainWindow::checkNetworkStatus);
  int interval = m_config.checkInterval() * 1000;
  m_statusTimer->setInterval(interval);
  if (m_backgroundTasks) m_statusTimer->start();
  Logger::info(QString("网络状态定时器已启动: %1 ms").arg(interval));

  // 启动时检测状态
  if (m_backgroundTasks) QTimer::singleShot(1000, this, &MainWindow::checkNetworkStatus);

  // 自动登录只由明确离线的状态响应触发。
  Logger::debug("MainWindow 初始化完成");
}

MainWindow::~MainWindow() {}

void MainWindow::applyWindowStyle() {
  setStyleSheet(R"(
    QMainWindow {
      background-color: #f3f6fb;
    }
    QFrame#heroCard, QGroupBox {
      background: #ffffff;
      border: 1px solid #d7e1ee;
      border-radius: 14px;
    }
    QGroupBox {
      margin-top: 18px;
      padding-top: 10px;
      font-size: 14px;
      font-weight: 600;
      color: #1f3656;
    }
    QGroupBox::title {
      subcontrol-origin: margin;
      left: 14px;
      padding: 0 6px;
    }
    QLabel#heroTitle {
      font-size: 26px;
      font-weight: 700;
      color: #16365c;
    }
    QLabel#heroSubtitle {
      font-size: 12px;
      color: #60758f;
    }
    QLabel#metricValue {
      font-size: 13px;
      font-weight: 600;
      color: #173a63;
    }
    QLabel#supportingText {
      font-size: 12px;
      color: #60758f;
    }
    QLineEdit, QSpinBox {
      min-height: 38px;
      padding: 0 10px;
      border-radius: 10px;
      border: 1px solid #cbd5e1;
      background: #fbfdff;
      selection-background-color: #2563eb;
    }
    QLineEdit:focus, QSpinBox:focus {
      border: 1px solid #2563eb;
      background: #ffffff;
    }
    QCheckBox {
      color: #243b53;
      spacing: 8px;
    }
    QPushButton {
      min-height: 40px;
      padding: 0 14px;
      border-radius: 10px;
      border: none;
      font-weight: 600;
    }
    QPushButton#secondaryButton {
      background: #e7eef8;
      color: #173a63;
    }
    QPushButton#secondaryButton:disabled {
      background: #eef3fa;
      color: #93a4ba;
    }
    QPushButton#primaryButton {
      background: #2563eb;
      color: #ffffff;
    }
    QPushButton#primaryButton:disabled {
      background: #b7c8f0;
      color: #f6f9ff;
    }
    QPushButton#dangerButton {
      background: #e85d5d;
      color: #ffffff;
    }
    QPushButton#dangerButton:disabled {
      background: #f0b5b5;
      color: #fff7f7;
    }
  )");
}

void MainWindow::setupUi() {
  m_centralWidget = new QWidget(this);
  setCentralWidget(m_centralWidget);

  QVBoxLayout *mainLayout = new QVBoxLayout(m_centralWidget);
  mainLayout->setSpacing(14);
  mainLayout->setContentsMargins(18, 18, 18, 18);

  // 顶部概览
  QFrame *heroCard = new QFrame();
  heroCard->setObjectName("heroCard");
  QVBoxLayout *heroLayout = new QVBoxLayout(heroCard);
  heroLayout->setContentsMargins(18, 16, 18, 16);
  heroLayout->setSpacing(6);

  QLabel *titleLabel = new QLabel("HAUT Network Guard");
  titleLabel->setObjectName("heroTitle");
  heroLayout->addWidget(titleLabel);

  QLabel *subtitleLabel = new QLabel("河南工业大学校园网自动登录工具");
  subtitleLabel->setObjectName("heroSubtitle");
  heroLayout->addWidget(subtitleLabel);

  QLabel *summaryLabel =
      new QLabel("集中管理登录、掉线重连、自启动和状态检测，减少重复操作。");
  summaryLabel->setObjectName("heroSubtitle");
  summaryLabel->setWordWrap(true);
  heroLayout->addWidget(summaryLabel);

  mainLayout->addWidget(heroCard);

  // 状态区域
  QGroupBox *statusGroup = new QGroupBox("网络状态");
  QVBoxLayout *statusLayout = new QVBoxLayout(statusGroup);
  statusLayout->setContentsMargins(16, 22, 16, 16);
  statusLayout->setSpacing(10);

  m_statusLabel = new QLabel("检测中");
  m_statusLabel->setAlignment(Qt::AlignCenter);
  m_statusLabel->setStyleSheet(
      "font-size: 22px; font-weight: 700; color: #2563eb;");
  statusLayout->addWidget(m_statusLabel);

  m_statusDetailLabel = new QLabel("正在初始化网络状态检测...");
  m_statusDetailLabel->setObjectName("supportingText");
  m_statusDetailLabel->setAlignment(Qt::AlignCenter);
  m_statusDetailLabel->setWordWrap(true);
  statusLayout->addWidget(m_statusDetailLabel);

  QFormLayout *infoLayout = new QFormLayout();
  infoLayout->setHorizontalSpacing(20);
  infoLayout->setVerticalSpacing(10);
  m_ipLabel = new QLabel("-");
  m_usageLabel = new QLabel("-");
  m_timeLabel = new QLabel("-");
  m_ipLabel->setObjectName("metricValue");
  m_usageLabel->setObjectName("metricValue");
  m_timeLabel->setObjectName("metricValue");
  infoLayout->addRow("IP 地址:", m_ipLabel);
  infoLayout->addRow("已用流量:", m_usageLabel);
  infoLayout->addRow("在线时长:", m_timeLabel);
  statusLayout->addLayout(infoLayout);

  m_lastCheckLabel = new QLabel("最近检测：尚未开始");
  m_lastCheckLabel->setObjectName("supportingText");
  statusLayout->addWidget(m_lastCheckLabel);

  mainLayout->addWidget(statusGroup);

  // 账号区域
  QGroupBox *accountGroup = new QGroupBox("账号设置");
  QFormLayout *accountLayout = new QFormLayout(accountGroup);
  accountLayout->setHorizontalSpacing(18);
  accountLayout->setVerticalSpacing(10);

  QLabel *accountHintLabel =
      new QLabel("建议将“记住密码”和“自动登录”配合使用，这样重启后也能自动恢复连接。");
  accountHintLabel->setObjectName("supportingText");
  accountHintLabel->setWordWrap(true);
  accountLayout->addRow(accountHintLabel);

  m_usernameEdit = new QLineEdit();
  m_usernameEdit->setObjectName("usernameInput");
  m_usernameEdit->setAccessibleName("学号输入框");
  m_usernameEdit->setPlaceholderText("请输入学号");
  m_usernameEdit->setClearButtonEnabled(true);
  m_usernameEdit->setToolTip("校园网登录学号");
  accountLayout->addRow("学号:", m_usernameEdit);

  m_passwordEdit = new QLineEdit();
  m_passwordEdit->setObjectName("passwordInput");
  m_passwordEdit->setAccessibleName("密码输入框");
  m_passwordEdit->setEchoMode(QLineEdit::Password);
  m_passwordEdit->setPlaceholderText("请输入密码");
  m_passwordEdit->setClearButtonEnabled(true);
  m_passwordEdit->setToolTip("不会在界面明文显示");
  accountLayout->addRow("密码:", m_passwordEdit);

  m_autoSaveCheck = new QCheckBox("记住密码");
  m_autoSaveCheck->setAccessibleName("记住密码");
  m_autoSaveCheck->setToolTip("勾选后会持久化保存密码，方便重启后自动恢复连接");
  m_autoLaunchCheck = new QCheckBox("开机自启动");
  m_autoLaunchCheck->setAccessibleName("开机自启动");
  m_autoLaunchCheck->setToolTip("随系统启动并在托盘中保持运行");
  m_autoLoginCheck = new QCheckBox("自动登录 (断线重连)");
  m_autoLoginCheck->setAccessibleName("自动登录和断线重连");
  m_autoLoginCheck->setToolTip("离线时自动尝试重连，避免频繁手动登录");
  accountLayout->addRow(m_autoSaveCheck);
  accountLayout->addRow(m_autoLaunchCheck);
  accountLayout->addRow(m_autoLoginCheck);

  m_optionHintLabel = new QLabel();
  m_optionHintLabel->setWordWrap(true);
  accountLayout->addRow(m_optionHintLabel);

  // 检测间隔设置
  QHBoxLayout *intervalLayout = new QHBoxLayout();
  m_intervalSpinBox = new QSpinBox();
  m_intervalSpinBox->setAccessibleName("检测间隔（秒）");
  m_intervalSpinBox->setRange(30, 300);
  m_intervalSpinBox->setSingleStep(15);
  m_intervalSpinBox->setSuffix(" 秒");
  m_intervalSpinBox->setToolTip("网络状态检测间隔 (30-300 秒)");
  intervalLayout->addWidget(m_intervalSpinBox);
  intervalLayout->addStretch();
  accountLayout->addRow("检测间隔:", intervalLayout);

  mainLayout->addWidget(accountGroup);

  // 按钮区域
  QHBoxLayout *buttonLayout = new QHBoxLayout();
  buttonLayout->setSpacing(10);

  m_saveBtn = new QPushButton("保存设置");
  m_saveBtn->setObjectName("secondaryButton");
  m_saveBtn->setAccessibleName("保存设置");
  connect(m_saveBtn, &QPushButton::clicked, this, &MainWindow::onSaveClicked);
  buttonLayout->addWidget(m_saveBtn);

  m_loginBtn = new QPushButton("登录");
  m_loginBtn->setObjectName("primaryButton");
  m_loginBtn->setAccessibleName("登录");
  m_loginBtn->setDefault(true);
  connect(m_loginBtn, &QPushButton::clicked, this, &MainWindow::onLoginClicked);
  buttonLayout->addWidget(m_loginBtn);

  m_logoutBtn = new QPushButton("注销");
  m_logoutBtn->setObjectName("dangerButton");
  m_logoutBtn->setAccessibleName("注销");
  connect(m_logoutBtn, &QPushButton::clicked, this,
          &MainWindow::onLogoutClicked);
  buttonLayout->addWidget(m_logoutBtn);

  QPushButton *diagnosticsBtn = new QPushButton("复制诊断");
  diagnosticsBtn->setObjectName("diagnosticsButton");
  diagnosticsBtn->setAccessibleName("复制脱敏诊断信息");
  connect(diagnosticsBtn, &QPushButton::clicked, this,
          &MainWindow::onCopyDiagnosticsClicked);
  buttonLayout->addWidget(diagnosticsBtn);

  mainLayout->addLayout(buttonLayout);

  connect(m_usernameEdit, &QLineEdit::returnPressed, this,
          &MainWindow::onLoginClicked);
  connect(m_passwordEdit, &QLineEdit::returnPressed, this,
          &MainWindow::onLoginClicked);
  connect(m_autoSaveCheck, &QCheckBox::toggled, this,
          &MainWindow::updateOptionHint);
  connect(m_autoLaunchCheck, &QCheckBox::toggled, this,
          &MainWindow::updateOptionHint);
  connect(m_autoLoginCheck, &QCheckBox::toggled, this,
          &MainWindow::updateOptionHint);

  // 明确键盘焦点顺序，确保只用键盘也能完成首次配置和登录。
  QWidget::setTabOrder(m_usernameEdit, m_passwordEdit);
  QWidget::setTabOrder(m_passwordEdit, m_autoSaveCheck);
  QWidget::setTabOrder(m_autoSaveCheck, m_autoLaunchCheck);
  QWidget::setTabOrder(m_autoLaunchCheck, m_autoLoginCheck);
  QWidget::setTabOrder(m_autoLoginCheck, m_intervalSpinBox);
  QWidget::setTabOrder(m_intervalSpinBox, m_saveBtn);
  QWidget::setTabOrder(m_saveBtn, m_loginBtn);
  QWidget::setTabOrder(m_loginBtn, m_logoutBtn);
  QWidget::setTabOrder(m_logoutBtn, diagnosticsBtn);

  // 底部信息
  QLabel *footerLabel =
      new QLabel("YellowPeach | QQ群: 789860526 | 关闭窗口后仍会驻留系统托盘");
  footerLabel->setAlignment(Qt::AlignCenter);
  footerLabel->setObjectName("supportingText");
  mainLayout->addWidget(footerLabel);
}

void MainWindow::loadSettings() {
  Config &config = m_config;

  m_usernameEdit->setText(config.username());
  m_passwordEdit->setText(config.password());
  m_autoSaveCheck->setChecked(config.autoSave());
  m_autoLaunchCheck->setChecked(config.autoLaunch());
  m_autoLoginCheck->setChecked(config.autoLogin());
  m_intervalSpinBox->setValue(config.checkInterval());
  updateOptionHint();

  Logger::debug(QString("设置已加载到 UI (用户: %1, 记住密码: %2, 开机自启: %3, "
                        "自动登录: %4, 间隔: %5, 自动重试冷却: %6ms)")
                    .arg(Logger::maskUsername(config.username()))
                    .arg(config.autoSave() ? "on" : "off")
                    .arg(config.autoLaunch() ? "on" : "off")
                    .arg(config.autoLogin() ? "on" : "off")
                    .arg(config.checkInterval())
                    .arg(qMax(60000, config.checkInterval() * 1000)));
}

bool MainWindow::saveSettings() {
  Config &config = m_config;

  const QString trimmedUsername = m_usernameEdit->text().trimmed();
  if (trimmedUsername.isEmpty() || m_passwordEdit->text().isEmpty()) {
    Logger::warn("设置保存已拒绝：学号或密码为空");
    return false;
  }
  m_usernameEdit->setText(trimmedUsername);
  config.setUsername(trimmedUsername);
  config.setPassword(m_passwordEdit->text());
  config.setAutoSave(m_autoSaveCheck->isChecked());
  config.setAutoLaunch(m_autoLaunchCheck->isChecked());
  config.setAutoLogin(m_autoLoginCheck->isChecked());
  config.setCheckInterval(m_intervalSpinBox->value());
  config.setHasConfigured(true);
  if (!config.save()) {
    updateOptionHint();
    return false;
  }

  // 更新定时器间隔
  m_statusTimer->setInterval(config.checkInterval() * 1000);
  updateOptionHint();
  Logger::info(QString("设置已应用 (用户: %1, 开机自启: %2, 自动登录: %3, "
                       "间隔: %4s, 自动重试冷却: %5ms)")
                   .arg(Logger::maskUsername(config.username()))
                   .arg(config.autoLaunch() ? "on" : "off")
                   .arg(config.autoLogin() ? "on" : "off")
                   .arg(config.checkInterval())
                   .arg(qMax(60000, config.checkInterval() * 1000)));
  return true;
}

bool MainWindow::syncCredentialsToConfig() {
  Config &config = m_config;
  const QString trimmedUsername = m_usernameEdit->text().trimmed();
  m_usernameEdit->setText(trimmedUsername);
  config.setUsername(trimmedUsername);
  config.setPassword(m_passwordEdit->text());
  config.setAutoSave(m_autoSaveCheck->isChecked());
  if (!config.save()) {
    updateOptionHint();
    setStatusDetail(config.lastError(), true);
    if (m_backgroundTasks) QMessageBox::warning(this, "保存失败", config.lastError());
    return false;
  }
  Logger::debug(QString("凭据已同步到配置 (用户: %1, 密码长度: %2)")
                    .arg(Logger::maskUsername(config.username()))
                    .arg(m_passwordEdit->text().length()));
  updateOptionHint();
  return true;
}

void MainWindow::onLoginClicked() {
  QString username = m_usernameEdit->text().trimmed();
  QString password = m_passwordEdit->text();

  if (username.isEmpty() || password.isEmpty()) {
    if (m_backgroundTasks) QMessageBox::warning(this, "提示", "请输入学号和密码");
    return;
  }

  if (m_session.isBusy()) {
    Logger::debug("忽略手动登录：已有操作进行中");
    return;
  }

  // 同步凭据到 Config，确保自动重连可用
  if (!syncCredentialsToConfig()) return;

  const auto token = m_session.beginLogin(true, m_config.autoLogin(),
      true, monotonicNow(), m_config.checkInterval());
  if (!token) return;
  m_isManualLogin = true;
  m_loginBtn->setText("登录中...");
  setStatusDetail("正在提交登录请求，请稍候...");
  refreshActionState();

  Logger::info(QString("手动登录触发: %1")
                   .arg(Logger::maskUsername(username)));
  m_api->login(*token, username, password);
}

void MainWindow::onLogoutClicked() {
  const auto token = m_session.beginLogout();
  if (!token) return;
  m_logoutBtn->setText("注销中...");
  setStatusDetail("正在执行注销请求...");
  refreshActionState();
  Logger::info(QString("手动注销触发 (online=%1)")
                   .arg(m_isOnline ? "true" : "false"));

  m_api->logout(*token);
}

void MainWindow::onSaveClicked() {
  if (!saveSettings()) {
    const QString error = m_config.lastError().isEmpty()
                              ? "请输入学号和密码。"
                              : m_config.lastError();
    setStatusDetail(error, true);
    if (m_backgroundTasks) QMessageBox::warning(this, "保存失败", error);
    return;
  }
  setStatusDetail("设置已保存，新的检测间隔和运行策略已立即生效。");
  if (m_trayIcon) {
    m_trayIcon->showMessage("设置已保存", "新的配置已应用");
  }
}

void MainWindow::onCopyDiagnosticsClicked() {
  if (m_session.isBusy()) return;
  QApplication::clipboard()->setText(diagnosticText());
  setStatusDetail("诊断信息已复制；内容不含账号、密码或网关正文。");
  Logger::info("已复制脱敏诊断信息");
}

void MainWindow::onLoginSuccess(quint64 token, const QString &message) {
  if (!m_session.completeLogin(token, true, monotonicNow())) return;
  m_loginBtn->setText("登录");
  setStatusDetail("登录请求成功，正在确认校园网连接状态。");
  refreshActionState();

  Logger::info(QString("登录成功: %1").arg(message));
  m_trayIcon->showMessage("登录请求成功", "正在确认校园网连接状态");
  m_isManualLogin = false;
  checkNetworkStatus();
}

void MainWindow::onLoginFailed(quint64 token, const QString &error) {
  if (!m_session.completeLogin(token, false, monotonicNow())) return;
  const bool wasManual = m_isManualLogin;
  m_isManualLogin = false;
  m_loginBtn->setText("登录");
  const QString retry = automaticRetryHint();
  setStatusDetail(QString("登录失败：%1%2").arg(error, retry.isEmpty() ? "" : "；" + retry), true);
  refreshActionState();

  Logger::warn(QString("登录失败: %1").arg(error));
  m_trayIcon->showMessage("登录失败", error, QSystemTrayIcon::Warning);
  // 只有手动登录失败才弹模态对话框，自动登录失败仅显示托盘通知
  if (wasManual && m_backgroundTasks) {
    QMessageBox::warning(this, "登录失败", error);
  }
}

void MainWindow::triggerAutoLoginIfPossible(const QString &reason) {
  QString username = m_config.username();
  QString password = m_config.password();
  const auto token = m_session.beginLogin(false, m_config.autoLogin(),
      !username.isEmpty() && !password.isEmpty(), monotonicNow(),
      m_config.checkInterval());
  if (!token) return;
  m_isManualLogin = false;
  m_loginBtn->setText("登录中...");
  setStatusDetail(QString("%1：正在尝试自动恢复连接...").arg(reason));
  Logger::info(QString("%1 自动登录触发 (用户: %2, 密码长度: %3)")
                   .arg(reason)
                   .arg(Logger::maskUsername(username))
                   .arg(password.length()));
  refreshActionState();
  m_api->login(*token, username, password);
}

void MainWindow::onLogoutSuccess(quint64 token, const QString &resultClass) {
  if (!m_session.completeLogout(token, true)) return;
  m_logoutBtn->setText("注销");

  m_isOnline = false;
  updateStatusDisplay(false);
  if (resultClass == "not_online") {
    setStatusDetail("当前未在线；自动重连已暂停，点击登录可解除暂停。");
  } else {
    setStatusDetail("已退出网络连接；自动重连已暂停，点击登录可解除暂停。");
  }
  refreshActionState();
  if (resultClass == "not_online") {
    m_trayIcon->showMessage("提示", "当前未在线");
  } else {
    m_trayIcon->showMessage("注销成功", "已退出网络");
  }
}

void MainWindow::onLogoutFailed(quint64 token, const QString &error) {
  if (!m_session.completeLogout(token, false)) return;
  m_logoutBtn->setText("注销");
  setStatusDetail(QString("注销失败：%1；自动重连已暂停，可再次注销。").arg(error), true);
  refreshActionState();

  if (m_backgroundTasks) QMessageBox::warning(this, "注销失败", error);
}

void MainWindow::onStatusChecked(quint64 token, bool online, const QString &resultClass,
                                 const QString &ip,
                                 qint64 bytesUsed, qint64 secondsOnline) {
  const auto observation = online ? SessionPolicy::Observation::Online :
      (resultClass == "offline" ? SessionPolicy::Observation::Offline : SessionPolicy::Observation::Error);
  if (!m_session.completeStatus(token, observation)) return;
  bool wasOnline = m_isOnline;
  refreshActionState();

  Logger::debug(QString("状态检测完成 (wasOnline=%1, online=%2, class=%3, ip=%4, bytes=%5, "
                        "seconds=%6)")
                    .arg(wasOnline ? "true" : "false")
                    .arg(online ? "true" : "false")
                    .arg(resultClass)
                    .arg(ip)
                    .arg(bytesUsed)
                    .arg(secondsOnline));
  updateLastCheckLabel(resultClass == "offline" || online ? "最近检测" : "最近异常");

  if (!online && resultClass != "offline") {
    m_statusLabel->setText("状态异常");
    m_statusLabel->setStyleSheet(
        "font-size: 22px; font-weight: 700; color: #ff9800;");
    setStatusDetail("网络状态接口返回异常，已保留上一次在线判断以避免误触发自动重连。",
                    true);
    if (!wasOnline) {
      m_ipLabel->setText("-");
      m_usageLabel->setText("-");
      m_timeLabel->setText("-");
    }
    Logger::warn(QString("状态检测异常，保持当前在线状态不变: class=%1")
                     .arg(resultClass));
    return;
  }

  m_isOnline = online;
  updateStatusDisplay(online, ip, bytesUsed, secondsOnline);

  refreshActionState();

  if (!online) {
    triggerAutoLoginIfPossible(wasOnline ? "掉线重连" : "离线重试");
  }
}

void MainWindow::refreshActionState() {
  const bool busy = m_session.isBusy();
  m_loginBtn->setEnabled(!busy && (!m_isOnline || m_session.manualOfflineHold()));
  m_logoutBtn->setEnabled(!busy && m_isOnline);
  m_saveBtn->setEnabled(!busy);

  if (m_trayIcon) {
    m_trayIcon->setBusy(busy);
    m_trayIcon->setOnlineStatus(m_isOnline);
    m_trayIcon->setManualOfflineHold(m_session.manualOfflineHold());
  }
}

void MainWindow::setStatusDetail(const QString &message, bool warning) {
  if (!m_statusDetailLabel)
    return;

  m_statusDetailLabel->setText(message);
  m_statusDetailLabel->setStyleSheet(
      QString("font-size: 12px; color: %1;")
          .arg(warning ? "#a56a00" : "#60758f"));
}

void MainWindow::updateLastCheckLabel(const QString &prefix) {
  if (!m_lastCheckLabel)
    return;

  const QString time = QDateTime::currentDateTime().toString("HH:mm:ss");
  m_lastCheckLabel->setText(QString("%1：%2").arg(prefix, time));
}

void MainWindow::updateOptionHint() {
  if (!m_optionHintLabel)
    return;

  QString message;
  QString color = "#38557a";
  QString background = "#eef5ff";
  QString border = "#d6e7ff";

  if (m_autoLoginCheck->isChecked() && m_autoSaveCheck->isChecked()) {
    message =
        "当前配置适合长期托管：启动后和掉线后都可以自动恢复连接，日常基本无需重复操作。";
  } else if (m_autoLoginCheck->isChecked()) {
    message =
        "已开启自动登录，但未记住密码。当前运行中的会话仍可重连；重启应用或系统后需要重新输入密码。";
    color = "#8a5a00";
    background = "#fff7e8";
    border = "#f7d79b";
  } else {
    message =
        "已关闭自动登录。程序会继续做状态检测，但需要你在离线时手动点击登录。";
  }

  if (m_autoLaunchCheck->isChecked()) {
    message += " 同时已启用开机自启动。";
  } else {
    message += " 当前未启用开机自启动。";
  }
  if (!m_config.lastError().isEmpty()) {
    message = m_config.lastError();
    color = "#8a5a00";
    background = "#fff7e8";
    border = "#f7d79b";
  }

  m_optionHintLabel->setText(message);
  m_optionHintLabel->setStyleSheet(
      QString("QLabel { color: %1; background: %2; border: 1px solid %3; "
              "border-radius: 10px; padding: 10px 12px; }")
          .arg(color, background, border));
}

void MainWindow::updateStatusDisplay(bool online, const QString &ip,
                                     qint64 bytes, qint64 seconds) {
  if (online) {
    m_statusLabel->setText("在线");
    m_statusLabel->setStyleSheet(
        "font-size: 22px; font-weight: 700; color: #4caf50;");
    m_ipLabel->setText(ip.isEmpty() ? "-" : ip);
    m_usageLabel->setText(formatBytes(bytes));
    m_timeLabel->setText(formatTime(seconds));
    setStatusDetail(ip.isEmpty()
                        ? "网络连接正常，程序会持续监测在线状态。"
                        : QString("网络连接正常，当前 IP 为 %1。").arg(ip));
    if (m_session.manualOfflineHold()) {
      setStatusDetail("当前检测为在线，自动重连仍暂停；可再次注销，或点击登录解除暂停。");
    }
  } else {
    m_statusLabel->setText("离线");
    m_statusLabel->setStyleSheet(
        "font-size: 22px; font-weight: 700; color: #f44336;");
    m_ipLabel->setText("-");
    m_usageLabel->setText("-");
    m_timeLabel->setText("-");

    if (m_session.manualOfflineHold()) {
      setStatusDetail("自动重连已暂停；点击登录可解除暂停。", true);
    } else if (m_config.autoLogin()) {
      const QString retry = automaticRetryHint();
      setStatusDetail(retry.isEmpty()
                          ? "当前离线，程序会按照检测节奏自动尝试重连。"
                          : QString("当前离线，%1。自动重连仍在运行。" ).arg(retry));
    } else {
      setStatusDetail("当前离线，自动登录已关闭，请按需手动登录。");
    }
  }
}

QString MainWindow::automaticRetryHint() const {
  if (!m_config.autoLogin() || m_session.manualOfflineHold()) return {};
  const double remaining = m_session.nextAutomaticAttempt() - monotonicNow();
  if (remaining <= 0) return {};
  return QString("自动重试约 %1 秒后").arg(qCeil(remaining));
}

QString MainWindow::diagnosticText() const {
  const QString retry = automaticRetryHint().isEmpty() ? "无" : automaticRetryHint();
  return QString("HAUT Network Guard v" HAUT_VERSION_STRING "\n状态: %1\n%2\n自动登录: %3\n自动重试: %4")
      .arg(m_statusLabel->text(), m_lastCheckLabel->text(),
           m_config.autoLogin() ? "开启" : "关闭", retry);
}

void MainWindow::checkNetworkStatus() {
  const auto token = m_session.beginStatus();
  if (!token) return;
  refreshActionState();
  Logger::debug("触发网络状态检测");
  m_api->checkStatus(*token);
}

void MainWindow::showWindow() {
  Logger::debug("显示主窗口");
  show();
  raise();
  activateWindow();
}

void MainWindow::exitApplication() {
  Logger::info("用户请求退出应用");
  m_trayIcon->hide();
  QApplication::quit();
}

void MainWindow::closeEvent(QCloseEvent *event) {
  // 关闭窗口时最小化到托盘
  event->ignore();
  hide();
  Logger::info("主窗口关闭动作已拦截，应用最小化到托盘");
  m_trayIcon->showMessage("HAUT Network Guard", "程序已最小化到系统托盘");
}

QString MainWindow::formatBytes(qint64 bytes) {
  if (bytes < 1024)
    return QString("%1 B").arg(bytes);
  if (bytes < 1024 * 1024)
    return QString("%1 KB").arg(bytes / 1024.0, 0, 'f', 2);
  if (bytes < 1024 * 1024 * 1024)
    return QString("%1 MB").arg(bytes / (1024.0 * 1024), 0, 'f', 2);
  return QString("%1 GB").arg(bytes / (1024.0 * 1024 * 1024), 0, 'f', 2);
}

QString MainWindow::formatTime(qint64 seconds) {
  qint64 hours = seconds / 3600;
  qint64 minutes = (seconds % 3600) / 60;
  qint64 secs = seconds % 60;
  return QString("%1:%2:%3")
      .arg(hours, 2, 10, QChar('0'))
      .arg(minutes, 2, 10, QChar('0'))
      .arg(secs, 2, 10, QChar('0'));
}
