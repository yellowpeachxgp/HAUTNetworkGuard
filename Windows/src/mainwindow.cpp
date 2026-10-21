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
#include <QGuiApplication>
#include <QNetworkInformation>
#include <QScreen>
#include <QScrollArea>
#include <QScrollBar>
#include <QSizePolicy>
#include <QVBoxLayout>
#include <QtGlobal>

namespace {
constexpr int kNetworkChangeDebounceMs = 500;
}

MainWindow::MainWindow(QWidget *parent)
    : MainWindow(Config::instance(), nullptr, {}, true, false, parent) {}

MainWindow::MainWindow(bool deferUi, QWidget *parent)
    : MainWindow(Config::instance(), nullptr, {}, true, deferUi, parent) {}

MainWindow::MainWindow(Config &config, Api *api, std::function<double()> now,
                       bool backgroundTasks, bool deferUi, QWidget *parent)
    : QMainWindow(parent), m_config(config), m_now(std::move(now)),
      m_backgroundTasks(backgroundTasks), m_externalApi(api != nullptr),
      m_deferUi(deferUi) {
  m_clock.start();
  setWindowTitle(QStringLiteral("HAUT Network Guard v" HAUT_VERSION_STRING));
  // 宽度先按设计值固定；构建 UI 后会按内容最小宽度和屏幕宽度再校准。
  setFixedWidth(460);
  Logger::debug("MainWindow 初始化开始");

  // 先建立托盘：开机自启时用户应尽快看到菜单栏/托盘图标，
  // 不等待完整窗口、样式表或网络后端初始化。
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
  Logger::info(QString("系统托盘已初始化 (available=%1, ui_ready=%2)")
                   .arg(m_trayIcon->isAvailable() ? "true" : "false")
                   .arg(m_uiReady ? "true" : "false"));

  // 初始化 API
  m_api = api ? api : new Api(this);
  connect(m_api, &Api::loginSuccess, this, &MainWindow::onLoginSuccess);
  connect(m_api, &Api::loginFailed, this, &MainWindow::onLoginFailed);
  connect(m_api, &Api::logoutSuccess, this, &MainWindow::onLogoutSuccess);
  connect(m_api, &Api::logoutFailed, this, &MainWindow::onLogoutFailed);
  connect(m_api, &Api::statusChecked, this, &MainWindow::onStatusChecked);

  // 状态检测定时器 (使用配置的间隔)
  m_statusTimer = new QTimer(this);
  connect(m_statusTimer, &QTimer::timeout, this,
          &MainWindow::checkNetworkStatus);
  int interval = m_config.checkInterval() * 1000;
  m_statusTimer->setInterval(interval);
  if (m_backgroundTasks) m_statusTimer->start();
  Logger::info(QString("网络状态定时器已启动: %1 ms").arg(interval));

  if (!m_deferUi) ensureUiBuilt();

  // Windows 网络信息后端会初始化 COM/Network List Manager，登录初期可能阻塞；
  // 正常启动也延后到事件循环，先让窗口/托盘可见。
  if (m_backgroundTasks && !m_externalApi) {
    QTimer::singleShot(1500, this, &MainWindow::setupNetworkMonitor);
  } else {
    setupNetworkMonitor();
  }

  // 启动时检测状态。后台启动更早触发，尽快完成首次登录。
  if (m_backgroundTasks) {
    QTimer::singleShot(m_deferUi ? 100 : 1000, this,
                       &MainWindow::checkNetworkStatus);
  }

  // 自动登录只由明确离线的状态响应触发。
  Logger::info(QString("MainWindow 初始化完成: %1ms").arg(m_clock.elapsed()));
}

MainWindow::~MainWindow() {}

void MainWindow::setupNetworkMonitor() {
  m_networkChangeTimer = new QTimer(this);
  m_networkChangeTimer->setObjectName(QStringLiteral("networkChangeDebounceTimer"));
  m_networkChangeTimer->setSingleShot(true);
  m_networkChangeTimer->setInterval(kNetworkChangeDebounceMs);
  connect(m_networkChangeTimer, &QTimer::timeout, this,
          &MainWindow::onNetworkChangeDebounced);

  // 测试构造关闭后台任务或注入 Api，避免加载系统网络后端或访问任何真实网络。
  if (!m_backgroundTasks || m_externalApi) return;

#if defined(Q_OS_WIN) && QT_VERSION >= QT_VERSION_CHECK(6, 3, 0)
  const bool loaded = QNetworkInformation::loadDefaultBackend();
  m_networkInformation = QNetworkInformation::instance();
  if (!m_networkInformation) {
    Logger::debug(QString("网络环境监视器不可用 (backend_loaded=%1)")
                      .arg(loaded ? "true" : "false"));
    return;
  }

  connect(m_networkInformation, &QNetworkInformation::reachabilityChanged,
          this, [this](QNetworkInformation::Reachability) {
            onNetworkEnvironmentChanged();
          });
  connect(m_networkInformation, &QNetworkInformation::transportMediumChanged,
          this, [this](QNetworkInformation::TransportMedium) {
            onNetworkEnvironmentChanged();
          });
  Logger::debug(QString("网络环境监视器已启用 (backend=%1, loaded=%2)")
                    .arg(m_networkInformation->backendName())
                    .arg(loaded ? "true" : "false"));
#else
  Logger::debug("当前平台或 Qt 版本不提供 Windows 网络环境变化通知，继续使用周期检测");
#endif
}

void MainWindow::applyWindowStyle() {
  setStyleSheet(R"(
    QMainWindow {
      background-color: #f3f6fb;
    }
    QScrollArea#contentScrollArea, QWidget#centralContent {
      background: transparent;
      border: none;
    }
    QScrollBar:vertical {
      background: transparent;
      width: 10px;
      margin: 4px 2px;
    }
    QScrollBar::handle:vertical {
      background: #cbd5e1;
      border-radius: 4px;
      min-height: 32px;
    }
    QScrollBar::handle:vertical:hover {
      background: #94a3b8;
    }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical,
    QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {
      background: transparent;
      height: 0;
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
  // 内容放在滚动区域中：字体行高较大或屏幕较矮时仍能完整阅读，
  // 不会因为窗口高度受限而把 QLabel 压扁。
  QScrollArea *scrollArea = new QScrollArea(this);
  scrollArea->setObjectName("contentScrollArea");
  scrollArea->setWidgetResizable(true);
  scrollArea->setFrameShape(QFrame::NoFrame);
  // 极端字体/缩放比例下允许横向滚动，绝不能把控件压到互相重叠。
  scrollArea->setHorizontalScrollBarPolicy(Qt::ScrollBarAsNeeded);
  scrollArea->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
  m_centralWidget = new QWidget();
  m_centralWidget->setObjectName("centralContent");
  m_centralWidget->setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Minimum);
  scrollArea->setWidget(m_centralWidget);
  setCentralWidget(scrollArea);

  QVBoxLayout *mainLayout = new QVBoxLayout(m_centralWidget);
  mainLayout->setSpacing(14);
  mainLayout->setContentsMargins(18, 18, 18, 18);
  // 让内容控件的最小尺寸等于布局最小尺寸，QScrollArea 会据此滚动而不是压缩。
  mainLayout->setSizeConstraint(QLayout::SetMinimumSize);

  // 顶部概览
  QFrame *heroCard = new QFrame();
  heroCard->setObjectName("heroCard");
  QVBoxLayout *heroLayout = new QVBoxLayout(heroCard);
  heroLayout->setContentsMargins(18, 16, 18, 16);
  heroLayout->setSpacing(6);
  heroLayout->setSizeConstraint(QLayout::SetMinimumSize);

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
  statusLayout->setSizeConstraint(QLayout::SetMinimumSize);

  m_statusLabel = new QLabel("检测中");
  m_statusLabel->setObjectName("statusValue");
  m_statusLabel->setAccessibleName("网络状态");
  m_statusLabel->setAlignment(Qt::AlignCenter);
  m_statusLabel->setStyleSheet(
      "font-size: 22px; font-weight: 700; color: #2563eb;");
  statusLayout->addWidget(m_statusLabel);

  m_statusDetailLabel = new QLabel("正在初始化网络状态检测...");
  m_statusDetailLabel->setObjectName("supportingText");
  m_statusDetailLabel->setAccessibleName("网络状态详情");
  m_statusDetailLabel->setAlignment(Qt::AlignCenter);
  m_statusDetailLabel->setWordWrap(true);
  m_statusDetailLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
  statusLayout->addWidget(m_statusDetailLabel);

  QFormLayout *infoLayout = new QFormLayout();
  infoLayout->setHorizontalSpacing(20);
  infoLayout->setVerticalSpacing(10);
  infoLayout->setRowWrapPolicy(QFormLayout::DontWrapRows);
  infoLayout->setFieldGrowthPolicy(QFormLayout::AllNonFixedFieldsGrow);
  m_ipLabel = new QLabel("-");
  m_usageLabel = new QLabel("-");
  m_timeLabel = new QLabel("-");
  m_ipLabel->setObjectName("metricValue");
  m_usageLabel->setObjectName("metricValue");
  m_timeLabel->setObjectName("metricValue");
  m_ipLabel->setAccessibleName("IP 地址");
  m_usageLabel->setAccessibleName("已用流量");
  m_timeLabel->setAccessibleName("在线时长");
  m_ipLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
  m_usageLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
  m_timeLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
  infoLayout->addRow("IP 地址:", m_ipLabel);
  infoLayout->addRow("已用流量:", m_usageLabel);
  infoLayout->addRow("在线时长:", m_timeLabel);
  statusLayout->addLayout(infoLayout);

  m_lastCheckLabel = new QLabel("最近检测：尚未开始");
  m_lastCheckLabel->setObjectName("supportingText");
  m_lastCheckLabel->setAccessibleName("最近检测时间");
  statusLayout->addWidget(m_lastCheckLabel);

  mainLayout->addWidget(statusGroup);

  // 账号区域
  QGroupBox *accountGroup = new QGroupBox("账号设置");
  QFormLayout *accountLayout = new QFormLayout(accountGroup);
  accountLayout->setHorizontalSpacing(18);
  accountLayout->setVerticalSpacing(10);
  accountLayout->setRowWrapPolicy(QFormLayout::DontWrapRows);
  accountLayout->setFieldGrowthPolicy(QFormLayout::AllNonFixedFieldsGrow);
  accountLayout->setSizeConstraint(QLayout::SetMinimumSize);

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
  QLabel *footerLabel = new QLabel(
      QString("YellowPeach | v%1 | QQ群: 789860526 | 关闭窗口后仍会驻留系统托盘")
          .arg(QStringLiteral(HAUT_VERSION_STRING)));
  footerLabel->setAlignment(Qt::AlignCenter);
  footerLabel->setObjectName("supportingText");
  footerLabel->setWordWrap(true);
  mainLayout->addWidget(footerLabel);
}

void MainWindow::ensureUiBuilt() {
  if (m_uiReady) return;

  QElapsedTimer uiClock;
  uiClock.start();
  setupUi();
  applyWindowStyle();
  m_uiReady = true;
  loadSettings();
  applyCachedUiState();
  refitWindowSize();
  m_windowFitDone = true;
  Logger::info(QString("主窗口 UI 构建完成: %1ms").arg(uiClock.elapsed()));
}

void MainWindow::applyCachedUiState() {
  if (!m_uiReady) return;
  setStatusBadge(m_cachedStatusText, m_cachedStatusColor);
  setStatusDetail(m_cachedDetail, m_cachedDetailWarning);
  m_ipLabel->setText(m_cachedIp);
  m_usageLabel->setText(m_cachedUsage);
  m_timeLabel->setText(m_cachedTime);
  m_lastCheckLabel->setText(m_cachedLastCheckText);
  refreshActionState();
}

void MainWindow::refitWindowSize() {
  if (!m_uiReady || !m_centralWidget) return;
  m_centralWidget->ensurePolished();

  QScreen *targetScreen = screen();
  const QRect available =
      targetScreen ? targetScreen->availableGeometry() : QRect(0, 0, 1280, 900);
  const int maxWindowWidth = qMax(460, available.width() - 40);
  const int maxWindowHeight = qMax(560, available.height() - 60);

  const int designWidth = 460;
  m_centralWidget->setMinimumWidth(0);
  m_centralWidget->resize(designWidth, qMax(640, m_centralWidget->height()));
  if (QLayout *layout = m_centralWidget->layout()) layout->activate();

  auto refreshLabelMinimums = [&](int fallbackWidth) {
    // 每个 QLabel 至少保留一行文字的高度；自动换行的标签按当前宽度计算
    // 实际需要的高度。这样即使系统字体行高更大，布局也不会把文字压扁。
    const QList<QLabel *> labels = findChildren<QLabel *>();
    for (QLabel *label : labels) {
      if (!label || label->text().isEmpty()) continue;
      label->ensurePolished();
      int minimum = qMax(label->fontMetrics().height(), label->sizeHint().height());
      if (label->wordWrap()) {
        int availableWidth = label->width();
        if (availableWidth <= 0) availableWidth = fallbackWidth;
        const int wrappedHeight = label->heightForWidth(availableWidth);
        if (wrappedHeight > 0) minimum = qMax(minimum, wrappedHeight);
      }
      label->setMinimumHeight(minimum);
      label->setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Minimum);
    }
  };
  refreshLabelMinimums(qMax(240, designWidth - 80));

  if (QLayout *layout = m_centralWidget->layout()) {
    layout->activate();
    const int minimumContentWidth = layout->minimumSize().width();
    const int targetWidth = qBound(460, minimumContentWidth + 2, maxWindowWidth);
    setFixedWidth(targetWidth);

    // 滚动区域内部画布不得小于布局最小宽度；窗口放不下时横向滚动。
    m_centralWidget->setMinimumWidth(minimumContentWidth);
    m_centralWidget->resize(qMax(minimumContentWidth, targetWidth),
                            qMax(640, m_centralWidget->height()));
    layout->activate();
    refreshLabelMinimums(qMax(240, targetWidth - 80));

    int contentHeight =
        qMax(layout->minimumSize().height(), layout->sizeHint().height());
    const int wrappedHeight = m_centralWidget->heightForWidth(
        qMax(minimumContentWidth, targetWidth));
    if (wrappedHeight > 0) contentHeight = qMax(contentHeight, wrappedHeight);
    contentHeight = qMax(contentHeight, 640);
    // 明确设置内容最小高度，保证窗口变小时出现滚动条而不是压缩/重叠控件。
    m_centralWidget->setMinimumHeight(contentHeight);

    if (!m_windowFitDone) {
      const int targetHeight = qBound(560, contentHeight, maxWindowHeight);
      resize(targetWidth, targetHeight);
    } else {
      // 用户可能调整过窗口；后续只保证最小高度，溢出交给滚动区域。
      setMinimumHeight(qMin(560, maxWindowHeight));
    }
  }
}

void MainWindow::scheduleRefit() {
  if (!m_uiReady || m_refitPending) return;
  m_refitPending = true;
  QTimer::singleShot(0, this, [this] {
    m_refitPending = false;
    refitWindowSize();
  });
}

void MainWindow::showEvent(QShowEvent *event) {
  QMainWindow::showEvent(event);
  ensureUiBuilt();
  // 首次显示后按真实屏幕/字体再校准一次尺寸；后续文本变化只更新最小尺寸，
  // 避免状态刷新导致窗口来回跳动。
  m_windowFitDone = false;
  refitWindowSize();
  m_windowFitDone = true;
}

void MainWindow::changeEvent(QEvent *event) {
  QMainWindow::changeEvent(event);
  if (event->type() == QEvent::FontChange ||
      event->type() == QEvent::StyleChange) {
    scheduleRefit();
  }
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
  if (m_session.isBusy()) {
    Logger::debug("忽略手动登录：已有操作进行中");
    return;
  }

  // 托盘菜单或开机自启阶段可能尚未构建窗口；需要时按需构建，
  // 保证用户从托盘登录时仍有完整输入界面。
  ensureUiBuilt();
  if (!m_uiReady) {
    Logger::warn("主窗口不可用，忽略手动登录");
    return;
  }

  QString username = m_usernameEdit->text().trimmed();
  QString password = m_passwordEdit->text();

  if (username.isEmpty() || password.isEmpty()) {
    if (m_backgroundTasks) QMessageBox::warning(this, "提示", "请输入学号和密码");
    return;
  }

  // 同步凭据到 Config，确保自动重连可用
  if (!syncCredentialsToConfig()) return;

  const auto token = m_session.beginLogin(true, m_config.autoLogin(),
      true, monotonicNow(), m_config.checkInterval());
  if (!token) return;
  m_isManualLogin = true;
  setStatusDetail("正在提交登录请求，请稍候...");
  refreshActionState();

  Logger::info(QString("手动登录触发: %1")
                   .arg(Logger::maskUsername(username)));
  m_api->login(*token, username, password);
}

void MainWindow::onLogoutClicked() {
  const auto token = m_session.beginLogout();
  if (!token) return;
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
  // 首次完成配置后立即确认网络状态，避免学生还要额外点击一次登录。
  if (m_backgroundTasks) {
    QTimer::singleShot(0, this, &MainWindow::checkNetworkStatus);
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
  const QString retry = automaticRetryHint();
  setStatusDetail(QString("登录失败：%1%2").arg(error, retry.isEmpty() ? "" : "；" + retry), true);
  refreshActionState();

  Logger::warn(QString("登录失败: %1").arg(error));
  m_trayIcon->showMessage("登录失败", error, QSystemTrayIcon::Warning);
  // 只有手动登录失败才弹模态对话框，自动登录失败仅显示托盘通知
  if (wasManual && m_backgroundTasks) {
    QMessageBox::warning(this, "登录失败", error);
  }
  flushPendingNetworkCheck();
}

void MainWindow::triggerAutoLoginIfPossible(const QString &reason) {
  QString username = m_config.username();
  QString password = m_config.password();
  const auto token = m_session.beginLogin(false, m_config.autoLogin(),
      !username.isEmpty() && !password.isEmpty(), monotonicNow(),
      m_config.checkInterval());
  if (!token) return;
  m_isManualLogin = false;
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
  flushPendingNetworkCheck();
}

void MainWindow::onLogoutFailed(quint64 token, const QString &error) {
  if (!m_session.completeLogout(token, false)) return;
  setStatusDetail(QString("注销失败：%1；自动重连已暂停，可再次注销。").arg(error), true);
  refreshActionState();

  if (m_backgroundTasks) QMessageBox::warning(this, "注销失败", error);
  flushPendingNetworkCheck();
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
    setStatusBadge("状态异常", "#ff9800");
    setStatusDetail("网络状态接口返回异常，已保留上一次在线判断以避免误触发自动重连。",
                    true);
    if (!wasOnline) clearMetrics();
    Logger::warn(QString("状态检测异常，保持当前在线状态不变: class=%1")
                     .arg(resultClass));
    flushPendingNetworkCheck();
    return;
  }

  m_isOnline = online;
  updateStatusDisplay(online, ip, bytesUsed, secondsOnline);

  refreshActionState();

  if (!online) {
    triggerAutoLoginIfPossible(wasOnline ? "掉线重连" : "离线重试");
  }
  flushPendingNetworkCheck();
}

void MainWindow::refreshActionState() {
  const bool busy = m_session.isBusy();
  if (m_uiReady) {
    m_loginBtn->setEnabled(!busy && (!m_isOnline || m_session.manualOfflineHold()));
    m_logoutBtn->setEnabled(!busy && m_isOnline);
    m_saveBtn->setEnabled(!busy);
    if (busy) {
      const auto operation = m_session.operation();
      m_loginBtn->setText(operation == SessionPolicy::Operation::Login
                              ? QStringLiteral("登录中...")
                              : QStringLiteral("登录"));
      m_logoutBtn->setText(operation == SessionPolicy::Operation::Logout
                               ? QStringLiteral("注销中...")
                               : QStringLiteral("注销"));
    } else {
      m_loginBtn->setText(QStringLiteral("登录"));
      m_logoutBtn->setText(QStringLiteral("注销"));
    }
  }

  if (m_trayIcon) {
    m_trayIcon->setBusy(busy);
    m_trayIcon->setOnlineStatus(m_isOnline);
    m_trayIcon->setManualOfflineHold(m_session.manualOfflineHold());
  }
}

void MainWindow::setStatusDetail(const QString &message, bool warning) {
  m_cachedDetail = message;
  m_cachedDetailWarning = warning;
  if (!m_uiReady || !m_statusDetailLabel) return;

  m_statusDetailLabel->setText(message);
  m_statusDetailLabel->setStyleSheet(
      QString("font-size: 12px; color: %1;")
          .arg(warning ? "#a56a00" : "#60758f"));
  scheduleRefit();
}

void MainWindow::setStatusBadge(const QString &text, const QString &color) {
  m_cachedStatusText = text;
  m_cachedStatusColor = color;
  if (!m_uiReady || !m_statusLabel) return;

  m_statusLabel->setText(text);
  m_statusLabel->setStyleSheet(
      QString("font-size: 22px; font-weight: 700; color: %1;").arg(color));
}

void MainWindow::clearMetrics() {
  m_cachedIp = "-";
  m_cachedUsage = "-";
  m_cachedTime = "-";
  if (!m_uiReady) return;
  m_ipLabel->setText(m_cachedIp);
  m_usageLabel->setText(m_cachedUsage);
  m_timeLabel->setText(m_cachedTime);
}

void MainWindow::updateLastCheckLabel(const QString &prefix) {
  const QString time = QDateTime::currentDateTime().toString("HH:mm:ss");
  m_cachedLastCheckText = QString("%1：%2").arg(prefix, time);
  if (!m_uiReady || !m_lastCheckLabel) return;

  m_lastCheckLabel->setText(m_cachedLastCheckText);
  scheduleRefit();
}

void MainWindow::updateOptionHint() {
  if (!m_uiReady || !m_optionHintLabel) return;

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
  scheduleRefit();
}

void MainWindow::updateStatusDisplay(bool online, const QString &ip,
                                     qint64 bytes, qint64 seconds) {
  if (online) {
    setStatusBadge("在线", "#4caf50");
    m_cachedIp = ip.isEmpty() ? "-" : ip;
    m_cachedUsage = formatBytes(bytes);
    m_cachedTime = formatTime(seconds);
    if (m_uiReady) {
      m_ipLabel->setText(m_cachedIp);
      m_usageLabel->setText(m_cachedUsage);
      m_timeLabel->setText(m_cachedTime);
    }
    setStatusDetail(ip.isEmpty()
                        ? "网络连接正常，程序会持续监测在线状态。"
                        : QString("网络连接正常，当前 IP 为 %1。").arg(ip));
    if (m_session.manualOfflineHold()) {
      setStatusDetail("当前检测为在线，自动重连仍暂停；可再次注销，或点击登录解除暂停。");
    }
  } else {
    setStatusBadge("离线", "#f44336");
    clearMetrics();

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
  return QString("HAUT Network Guard v" HAUT_VERSION_STRING
                 "\n状态: %1\n%2\n自动登录: %3\n自动重试: %4")
      .arg(m_cachedStatusText, m_cachedLastCheckText,
           m_config.autoLogin() ? "开启" : "关闭", retry);
}

void MainWindow::onNetworkEnvironmentChanged() {
  if (!m_networkChangeTimer) return;

  // 单次定时器重启会把连续的网卡/可达性通知合并为一次检测。
  m_networkRecheckPending = true;
  m_networkChangeTimer->start();
  Logger::debug("收到网络环境变化通知，等待去抖后重新检测");
}

void MainWindow::onNetworkChangeDebounced() {
  if (!m_networkRecheckPending) return;
  // 网络事件在认证/注销期间不能丢失，完成回调再补一次；普通周期检测仍按原规则忽略。
  if (m_session.isBusy()) return;
  checkNetworkStatus();
}

void MainWindow::flushPendingNetworkCheck() {
  if (!m_networkRecheckPending || m_session.isBusy()) return;
  // 仍在去抖窗口内时，让定时器继续合并后续通知。
  if (m_networkChangeTimer && m_networkChangeTimer->isActive()) return;
  checkNetworkStatus();
}

void MainWindow::checkNetworkStatus() {
  const auto token = m_session.beginStatus();
  if (!token) return;
  if (m_networkChangeTimer) m_networkChangeTimer->stop();
  m_networkRecheckPending = false;
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

bool MainWindow::isTrayAvailable() const {
  return m_trayIcon && m_trayIcon->isAvailable();
}

void MainWindow::closeEvent(QCloseEvent *event) {
  // 托盘不可用时隐藏窗口会让应用无法再被找回；此时允许关闭并退出。
  if (m_backgroundTasks && !isTrayAvailable()) {
    Logger::warn("系统托盘不可用，关闭窗口将退出应用");
    event->accept();
    QApplication::quit();
    return;
  }
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
