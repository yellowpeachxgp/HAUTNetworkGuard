#include "mainwindow.h"
#include "config.h"
#include <QApplication>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QMessageBox>
#include <QVBoxLayout>

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
  setWindowTitle("HAUT Network Guard v1.3.0");
  setFixedSize(400, 500);

  setupUi();
  loadSettings();

  // 初始化 API
  m_api = new Api(this);
  connect(m_api, &Api::loginSuccess, this, &MainWindow::onLoginSuccess);
  connect(m_api, &Api::loginFailed, this, &MainWindow::onLoginFailed);
  connect(m_api, &Api::logoutSuccess, this, &MainWindow::onLogoutSuccess);
  connect(m_api, &Api::logoutFailed, this, &MainWindow::onLogoutFailed);
  connect(m_api, &Api::statusChecked, this, &MainWindow::onStatusChecked);

  // 初始化托盘图标
  m_trayIcon = new TrayIcon(this);
  connect(m_trayIcon, &TrayIcon::showWindowRequested, this,
          &MainWindow::showWindow);
  connect(m_trayIcon, &TrayIcon::exitRequested, this,
          &MainWindow::exitApplication);
  connect(m_trayIcon, &TrayIcon::loginRequested, this,
          &MainWindow::onLoginClicked);
  connect(m_trayIcon, &TrayIcon::logoutRequested, this,
          &MainWindow::onLogoutClicked);
  m_trayIcon->show();

  // 状态检测定时器
  m_statusTimer = new QTimer(this);
  connect(m_statusTimer, &QTimer::timeout, this,
          &MainWindow::checkNetworkStatus);
  m_statusTimer->start(3000); // 每 3 秒检测一次

  // 启动时检测一次状态
  QTimer::singleShot(1000, this, &MainWindow::checkNetworkStatus);
}

MainWindow::~MainWindow() {}

void MainWindow::setupUi() {
  m_centralWidget = new QWidget(this);
  setCentralWidget(m_centralWidget);

  QVBoxLayout *mainLayout = new QVBoxLayout(m_centralWidget);
  mainLayout->setSpacing(15);
  mainLayout->setContentsMargins(20, 20, 20, 20);

  // 标题
  QLabel *titleLabel = new QLabel("HAUT Network Guard");
  titleLabel->setAlignment(Qt::AlignCenter);
  titleLabel->setStyleSheet(
      "font-size: 24px; font-weight: bold; color: #2196F3;");
  mainLayout->addWidget(titleLabel);

  // 状态区域
  QGroupBox *statusGroup = new QGroupBox("网络状态");
  QVBoxLayout *statusLayout = new QVBoxLayout(statusGroup);

  m_statusLabel = new QLabel("检测中...");
  m_statusLabel->setAlignment(Qt::AlignCenter);
  m_statusLabel->setStyleSheet("font-size: 18px; font-weight: bold;");
  statusLayout->addWidget(m_statusLabel);

  QFormLayout *infoLayout = new QFormLayout();
  m_ipLabel = new QLabel("-");
  m_usageLabel = new QLabel("-");
  m_timeLabel = new QLabel("-");
  infoLayout->addRow("IP 地址:", m_ipLabel);
  infoLayout->addRow("已用流量:", m_usageLabel);
  infoLayout->addRow("在线时长:", m_timeLabel);
  statusLayout->addLayout(infoLayout);

  mainLayout->addWidget(statusGroup);

  // 账号区域
  QGroupBox *accountGroup = new QGroupBox("账号设置");
  QFormLayout *accountLayout = new QFormLayout(accountGroup);

  m_usernameEdit = new QLineEdit();
  m_usernameEdit->setPlaceholderText("请输入学号");
  accountLayout->addRow("学号:", m_usernameEdit);

  m_passwordEdit = new QLineEdit();
  m_passwordEdit->setEchoMode(QLineEdit::Password);
  m_passwordEdit->setPlaceholderText("请输入密码");
  accountLayout->addRow("密码:", m_passwordEdit);

  m_autoSaveCheck = new QCheckBox("记住密码");
  m_autoLaunchCheck = new QCheckBox("开机自启动");
  accountLayout->addRow(m_autoSaveCheck);
  accountLayout->addRow(m_autoLaunchCheck);

  mainLayout->addWidget(accountGroup);

  // 按钮区域
  QHBoxLayout *buttonLayout = new QHBoxLayout();

  m_saveBtn = new QPushButton("保存设置");
  m_saveBtn->setStyleSheet("QPushButton { padding: 10px; }");
  connect(m_saveBtn, &QPushButton::clicked, this, &MainWindow::onSaveClicked);
  buttonLayout->addWidget(m_saveBtn);

  m_loginBtn = new QPushButton("登录");
  m_loginBtn->setStyleSheet("QPushButton { padding: 10px; background-color: "
                            "#4CAF50; color: white; }");
  connect(m_loginBtn, &QPushButton::clicked, this, &MainWindow::onLoginClicked);
  buttonLayout->addWidget(m_loginBtn);

  m_logoutBtn = new QPushButton("注销");
  m_logoutBtn->setStyleSheet("QPushButton { padding: 10px; background-color: "
                             "#f44336; color: white; }");
  connect(m_logoutBtn, &QPushButton::clicked, this,
          &MainWindow::onLogoutClicked);
  buttonLayout->addWidget(m_logoutBtn);

  mainLayout->addLayout(buttonLayout);

  // 底部信息
  QLabel *footerLabel = new QLabel("© 2024-2026 YellowPeach | QQ群: 789860526");
  footerLabel->setAlignment(Qt::AlignCenter);
  footerLabel->setStyleSheet("color: #888;");
  mainLayout->addWidget(footerLabel);
}

void MainWindow::loadSettings() {
  Config &config = Config::instance();

  m_usernameEdit->setText(config.username());
  m_passwordEdit->setText(config.password());
  m_autoSaveCheck->setChecked(config.autoSave());
  m_autoLaunchCheck->setChecked(config.autoLaunch());
}

void MainWindow::saveSettings() {
  Config &config = Config::instance();

  config.setUsername(m_usernameEdit->text());
  config.setPassword(m_autoSaveCheck->isChecked() ? m_passwordEdit->text()
                                                  : "");
  config.setAutoSave(m_autoSaveCheck->isChecked());
  config.setAutoLaunch(m_autoLaunchCheck->isChecked());
  config.setHasConfigured(true);
  config.save();
}

void MainWindow::onLoginClicked() {
  QString username = m_usernameEdit->text().trimmed();
  QString password = m_passwordEdit->text();

  if (username.isEmpty() || password.isEmpty()) {
    QMessageBox::warning(this, "提示", "请输入学号和密码");
    return;
  }

  m_loginBtn->setEnabled(false);
  m_loginBtn->setText("登录中...");

  m_api->login(username, password);
}

void MainWindow::onLogoutClicked() {
  m_logoutBtn->setEnabled(false);
  m_logoutBtn->setText("注销中...");

  m_api->logout();
}

void MainWindow::onSaveClicked() {
  saveSettings();
  QMessageBox::information(this, "提示", "设置已保存");
}

void MainWindow::onLoginSuccess(const QString &message) {
  m_loginBtn->setEnabled(true);
  m_loginBtn->setText("登录");

  m_trayIcon->showMessage("登录成功", message);
  checkNetworkStatus();
}

void MainWindow::onLoginFailed(const QString &error) {
  m_loginBtn->setEnabled(true);
  m_loginBtn->setText("登录");

  m_trayIcon->showMessage("登录失败", error, QSystemTrayIcon::Warning);
  QMessageBox::warning(this, "登录失败", error);
}

void MainWindow::onLogoutSuccess() {
  m_logoutBtn->setEnabled(true);
  m_logoutBtn->setText("注销");

  m_trayIcon->showMessage("注销成功", "已退出网络");
  updateStatusDisplay(false);
}

void MainWindow::onLogoutFailed(const QString &error) {
  m_logoutBtn->setEnabled(true);
  m_logoutBtn->setText("注销");

  QMessageBox::warning(this, "注销失败", error);
}

void MainWindow::onStatusChecked(bool online, const QString &ip,
                                 qint64 bytesUsed, qint64 secondsOnline) {
  bool wasOnline = m_isOnline;
  m_isOnline = online;

  updateStatusDisplay(online, ip, bytesUsed, secondsOnline);
  m_trayIcon->setOnlineStatus(online);

  // 如果从在线变为离线，且配置了自动登录，则自动重连
  if (wasOnline && !online && Config::instance().hasConfigured()) {
    QString username = Config::instance().username();
    QString password = Config::instance().password();

    if (!username.isEmpty() && !password.isEmpty()) {
      m_api->login(username, password);
    }
  }
}

void MainWindow::updateStatusDisplay(bool online, const QString &ip,
                                     qint64 bytes, qint64 seconds) {
  if (online) {
    m_statusLabel->setText("🟢 在线");
    m_statusLabel->setStyleSheet(
        "font-size: 18px; font-weight: bold; color: #4CAF50;");
    m_ipLabel->setText(ip.isEmpty() ? "-" : ip);
    m_usageLabel->setText(formatBytes(bytes));
    m_timeLabel->setText(formatTime(seconds));
  } else {
    m_statusLabel->setText("🔴 离线");
    m_statusLabel->setStyleSheet(
        "font-size: 18px; font-weight: bold; color: #f44336;");
    m_ipLabel->setText("-");
    m_usageLabel->setText("-");
    m_timeLabel->setText("-");
  }
}

void MainWindow::checkNetworkStatus() { m_api->checkStatus(); }

void MainWindow::showWindow() {
  show();
  raise();
  activateWindow();
}

void MainWindow::exitApplication() {
  m_trayIcon->hide();
  QApplication::quit();
}

void MainWindow::closeEvent(QCloseEvent *event) {
  // 关闭窗口时最小化到托盘
  event->ignore();
  hide();
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
