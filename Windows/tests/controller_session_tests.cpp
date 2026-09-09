#include "../src/mainwindow.h"
#include "../src/logger.h"
#include <QApplication>
#include <QDebug>
#include <QEventLoop>
#include <QTemporaryDir>
#include <stdexcept>
#include <vector>

// 仅替换 I/O，仍由正式 MainWindow 接收 Qt 信号并驱动正式会话策略。
class ReplayApi : public Api {
public:
  std::vector<quint64> statusTokens, loginTokens, logoutTokens;
  void checkStatus(quint64 token) override { statusTokens.push_back(token); }
  void login(quint64 token, const QString &, const QString &) override { loginTokens.push_back(token); }
  void logout(quint64 token) override { logoutTokens.push_back(token); }
};

int main(int argc, char **argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QApplication app(argc, argv);
  app.setQuitOnLastWindowClosed(false);
  Logger::setEnabled(false);
  int checked = 0;
  auto expect = [&](bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
    ++checked;
  };
  try {
    QTemporaryDir directory;
    expect(directory.isValid(), "无法创建隔离配置目录");
    QSettings settings(directory.filePath("settings.ini"), QSettings::IniFormat);
    Config config(settings);
    config.setUsername("test-student");
    config.setPassword("test-only");
    config.setAutoSave(true);
    config.setAutoLogin(true);
    config.save();
    ReplayApi api;
    double clock = 0;
    MainWindow window(config, &api, [&] { return clock; }, false);
    auto invoke = [&](const char *action) {
      expect(QMetaObject::invokeMethod(&window, action, Qt::DirectConnection), "无法调用正式操作");
    };
    auto status = [&](bool online, const QString &category) {
      const auto previous = api.statusTokens.size();
      invoke("checkNetworkStatus");
      expect(api.statusTokens.size() == previous + 1, "空闲时应接受状态请求");
      emit api.statusChecked(api.statusTokens.back(), online, category, "", 0, 0);
    };
    auto loginButton = window.findChild<QPushButton *>("primaryButton");
    auto logoutButton = window.findChild<QPushButton *>("dangerButton");
    expect(loginButton && logoutButton, "正式登录和注销按钮必须存在");
    expect(window.findChild<QLineEdit *>("usernameInput")->accessibleName() == "学号输入框" &&
               window.findChild<QLineEdit *>("passwordInput")->accessibleName() == "密码输入框" &&
               loginButton->accessibleName() == "登录" &&
               logoutButton->accessibleName() == "注销",
           "首次配置和登录控件必须提供无障碍名称");
    const QString diagnostics = window.diagnosticText();
    expect(diagnostics.contains(HAUT_VERSION_STRING) && !diagnostics.contains("test-student") &&
           !diagnostics.contains("test-only"), "诊断信息不得包含账号或密码");
    QCheckBox *remember = nullptr;
    for (auto checkbox : window.findChildren<QCheckBox *>()) {
      if (checkbox->text() == "记住密码") remember = checkbox;
    }
    expect(remember != nullptr, "记住密码控件必须存在");
    window.show();
    QApplication::processEvents();
    expect(window.isVisible(), "正式主窗口应能显示");
    QCloseEvent closeEvent;
    QApplication::sendEvent(&window, &closeEvent);
    expect(!closeEvent.isAccepted() && !window.isVisible(),
           "关闭窗口应拦截并隐藏到系统托盘");
    expect(QMetaObject::invokeMethod(&window, "showWindow", Qt::DirectConnection) &&
               window.isVisible(),
           "托盘显示动作应重新显示主窗口");
    remember->setChecked(false);
    expect(api.statusTokens.empty() && api.loginTokens.empty(), "隔离构造不得启动后台请求");
    invoke("checkNetworkStatus");
    invoke("checkNetworkStatus");
    invoke("onLoginClicked");
    invoke("onLogoutClicked");
    expect(api.statusTokens.size() == 1 && api.loginTokens.empty() && api.logoutTokens.empty(),
           "状态未完成前不能重叠请求");
    expect(!loginButton->isEnabled() && !logoutButton->isEnabled(), "检测时按钮必须禁用");
    emit api.statusChecked(api.statusTokens.back(), false, "network_error", "", 0, 0);
    expect(api.loginTokens.empty(), "状态异常不能触发登录");
    expect(loginButton->isEnabled(), "检测错误后必须解除按钮忙碌状态");

    invoke("onLoginClicked");
    expect(api.loginTokens.size() == 1, "用户可主动登录");
    clock = 10;
    emit api.loginFailed(api.loginTokens.back(), "模拟密码错误");
    bool retryHintVisible = false;
    for (auto label : window.findChildren<QLabel *>()) {
      retryHintVisible = retryHintVisible || label->text().contains("自动重试");
    }
    expect(retryHintVisible, "登录失败时应显示下一次自动重试提示");
    status(false, "offline");
    expect(api.loginTokens.size() == 1, "手动失败后不得立即自动重试");
    clock = 69.9;
    status(false, "offline");
    expect(api.loginTokens.size() == 1, "冷却边界前不得登录");
    clock = 70;
    status(false, "offline");
    expect(api.loginTokens.size() == 2, "冷却到期允许自动登录");
    invoke("checkNetworkStatus");
    invoke("onLoginClicked");
    invoke("onLogoutClicked");
    expect(api.statusTokens.size() == 4 && api.loginTokens.size() == 2 && api.logoutTokens.empty(),
           "登录中必须拦截检测和重复认证");
    clock = 71;
    emit api.loginFailed(api.loginTokens.back(), "模拟密码错误");
    clock = 191;
    status(false, "offline");
    expect(api.loginTokens.size() == 3, "连续失败后可在退避结束时重试");
    clock = 192;
    emit api.loginSuccess(api.loginTokens.back(), "模拟成功");
    expect(api.statusTokens.size() == 6, "登录成功必须重新探测");
    emit api.statusChecked(api.statusTokens.back(), true, "online_csv", "", 0, 0);
    expect(logoutButton->isEnabled(), "确认在线后允许注销");

    invoke("onLogoutClicked");
    expect(api.logoutTokens.size() == 1, "正式注销路径应发请求");
    emit api.statusChecked(api.statusTokens.back(), true, "online_csv", "", 0, 0);
    expect(!loginButton->isEnabled() && !logoutButton->isEnabled(), "旧状态回调不能释放注销忙碌状态");
    emit api.logoutSuccess(api.logoutTokens.back(), "not_online");
    clock = 10000;
    status(false, "offline");
    status(true, "online_jsonp");
    expect(loginButton->isEnabled(), "暂停后即使检测在线也须允许显式恢复");
    status(false, "offline");
    expect(api.loginTokens.size() == 3, "注销后网络变化不能撤销暂停");

    invoke("onLoginClicked");
    expect(api.loginTokens.size() == 4, "手动登录可显式恢复");
    emit api.loginSuccess(api.loginTokens[2], "过期成功");
    invoke("onLogoutClicked");
    expect(api.statusTokens.size() == 9 && api.logoutTokens.size() == 1,
           "旧登录回调不能启动检测或释放当前操作");
    emit api.loginSuccess(api.loginTokens.back(), "模拟成功");
    emit api.statusChecked(api.statusTokens.back(), true, "online_jsonp", "", 0, 0);
    status(false, "offline");
    expect(api.loginTokens.size() == 5, "显式恢复并确认在线后掉线可以自动登录");
    emit api.loginFailed(api.loginTokens.back(), "模拟结束");
    expect(settings.value("password").toString().isEmpty(), "控制器测试不得持久化密码");

    // 保存失败必须沿正式按钮路径反馈，不能在失败后提交登录请求。
    QSettings faultSettings(directory.filePath("fault.ini"), QSettings::IniFormat);
    bool failEncoding = false;
    PasswordCodec codec{
        [&](const QString &plain) { return failEncoding ? QString() : "test:" + plain; },
        [](const QString &encoded) { return encoded.startsWith("test:") ? encoded.mid(5) : QString(); }};
    Config faultConfig(faultSettings, codec);
    faultConfig.setUsername("saved-student");
    faultConfig.setPassword("saved-password");
    faultConfig.setAutoSave(true);
    expect(faultConfig.save(), "故障窗口基线配置应保存成功");
    ReplayApi faultApi;
    MainWindow faultWindow(faultConfig, &faultApi, [&] { return clock; }, false);
    auto usernameInput = faultWindow.findChild<QLineEdit *>("usernameInput");
    auto passwordInput = faultWindow.findChild<QLineEdit *>("passwordInput");
    expect(usernameInput && passwordInput, "凭据输入控件必须存在");
    usernameInput->setText("pending-student");
    passwordInput->setText("pending-password");
    failEncoding = true;
    expect(QMetaObject::invokeMethod(&faultWindow, "onLoginClicked", Qt::DirectConnection), "无法调用故障登录操作");
    expect(faultApi.loginTokens.empty(), "保存失败后不得继续提交登录");
    expect(faultConfig.username() == "saved-student", "失败后自动流程必须继续使用原配置");
    expect(usernameInput->text() == "pending-student" && passwordInput->text() == "pending-password",
           "失败后用户输入必须保留供重试");
    bool hasVisibleError = false;
    for (auto label : faultWindow.findChildren<QLabel *>()) {
      if (label->text() == faultConfig.lastError()) hasVisibleError = true;
    }
    expect(!faultConfig.lastError().isEmpty() && hasVisibleError, "保存失败必须在正式界面显示");
    expect(QMetaObject::invokeMethod(&faultWindow, "onSaveClicked", Qt::DirectConnection), "无法调用故障保存操作");
    expect(faultSettings.value("username").toString() == "saved-student", "保存按钮失败不能覆盖旧配置");
    failEncoding = false;
    expect(QMetaObject::invokeMethod(&faultWindow, "onLoginClicked", Qt::DirectConnection), "无法重试登录");
    expect(faultApi.loginTokens.size() == 1 && faultConfig.lastError().isEmpty(), "故障恢复后可重试并清除错误");
    emit faultApi.loginFailed(faultApi.loginTokens.back(), "模拟结束");

    QSettings firstRunSettings(directory.filePath("first-run.ini"), QSettings::IniFormat);
    Config firstRunConfig(firstRunSettings);
    ReplayApi firstRunApi;
    MainWindow firstRunWindow(firstRunConfig, &firstRunApi, [&] { return clock; }, false);
    expect(QMetaObject::invokeMethod(&firstRunWindow, "onSaveClicked", Qt::DirectConnection),
           "无法调用首次配置保存操作");
    expect(!firstRunConfig.hasConfigured() && firstRunConfig.username().isEmpty() &&
               firstRunConfig.password().isEmpty(),
           "空学号或密码不得提交首次配置");
    bool firstRunError = false;
    for (auto label : firstRunWindow.findChildren<QLabel *>()) {
      firstRunError = firstRunError || label->text().contains("请输入学号和密码");
    }
    expect(firstRunError, "空首次配置必须显示可理解的提示");

    QSettings configuredSettings(directory.filePath("configured-run.ini"), QSettings::IniFormat);
    Config configuredConfig(configuredSettings);
    ReplayApi configuredApi;
    MainWindow configuredWindow(configuredConfig, &configuredApi, [&] { return clock; }, true);
    configuredWindow.findChild<QLineEdit *>("usernameInput")->setText("new-student");
    configuredWindow.findChild<QLineEdit *>("passwordInput")->setText("new-password");
    expect(QMetaObject::invokeMethod(&configuredWindow, "onSaveClicked", Qt::DirectConnection),
           "无法调用配置保存操作");
    QApplication::processEvents();
    expect(configuredApi.statusTokens.size() == 1,
           "首次配置保存成功后应立即发起一次状态检测");

    // 网络环境通知使用隔离窗口和模拟 API 回放，不接触真实校园网或生产配置。
    QSettings networkEventSettings(directory.filePath("network-events.ini"),
                                   QSettings::IniFormat);
    Config networkEventConfig(networkEventSettings);
    networkEventConfig.setUsername("event-student");
    networkEventConfig.setPassword("event-password");
    networkEventConfig.setAutoSave(false);
    networkEventConfig.setAutoLogin(true);
    expect(networkEventConfig.save(), "网络事件回放基线配置应保存成功");
    ReplayApi networkEventApi;
    MainWindow networkEventWindow(networkEventConfig, &networkEventApi,
                                  [&] { return clock; }, false);
    auto networkEventTimer =
        networkEventWindow.findChild<QTimer *>("networkChangeDebounceTimer");
    expect(networkEventTimer && networkEventTimer->isSingleShot(),
           "网络环境通知必须使用单次去抖定时器");
    // 缩短测试等待，不改变正式实现的去抖间隔。
    networkEventTimer->setInterval(0);
    auto networkEvent = [&] {
      expect(QMetaObject::invokeMethod(&networkEventWindow,
                                       "onNetworkEnvironmentChanged",
                                       Qt::DirectConnection),
             "无法回放网络环境变化通知");
    };
    auto settleNetworkEvent = [&] {
      QApplication::processEvents(QEventLoop::AllEvents);
      QApplication::processEvents(QEventLoop::AllEvents);
    };

    // 同一去抖窗口内的多个系统通知只能合并为一次状态请求。
    networkEvent();
    networkEvent();
    networkEvent();
    expect(networkEventApi.statusTokens.empty(),
           "去抖窗口结束前不得发起网络状态请求");
    settleNetworkEvent();
    expect(networkEventApi.statusTokens.size() == 1,
           "连续网络环境通知必须合并为一次状态请求");
    emit networkEventApi.statusChecked(networkEventApi.statusTokens.back(), true,
                                       "online_csv", "", 0, 0);

    // 通知在已有检测期间到达时不能丢失，当前检测完成后补发一次且不并发。
    QMetaObject::invokeMethod(&networkEventWindow, "checkNetworkStatus",
                              Qt::DirectConnection);
    const auto busyStatusToken = networkEventApi.statusTokens.back();
    networkEvent();
    settleNetworkEvent();
    expect(networkEventApi.statusTokens.size() == 2,
           "检测忙碌时网络通知不得并发发起请求");
    emit networkEventApi.statusChecked(busyStatusToken, true, "online_csv", "",
                                       0, 0);
    expect(networkEventApi.statusTokens.size() == 3,
           "检测完成后应补发一次待处理网络检测");
    emit networkEventApi.statusChecked(networkEventApi.statusTokens.back(), true,
                                       "online_csv", "", 0, 0);

    // 手动注销建立的暂停意图不能被网络环境通知或离线结果解除。
    QMetaObject::invokeMethod(&networkEventWindow, "onLogoutClicked",
                              Qt::DirectConnection);
    expect(networkEventApi.logoutTokens.size() == 1,
           "网络事件回放应能进入正式注销流程");
    networkEvent();
    settleNetworkEvent();
    expect(networkEventApi.statusTokens.size() == 3,
           "注销请求期间网络通知不得并发检测");
    emit networkEventApi.logoutSuccess(networkEventApi.logoutTokens.back(),
                                        "logout_ok");
    expect(networkEventApi.statusTokens.size() == 4,
           "注销完成后应补发待处理网络检测");
    emit networkEventApi.statusChecked(networkEventApi.statusTokens.back(), true,
                                       "online_csv", "", 0, 0);
    const auto statusBeforeHoldEvent = networkEventApi.statusTokens.size();
    networkEvent();
    settleNetworkEvent();
    expect(networkEventApi.statusTokens.size() == statusBeforeHoldEvent + 1,
           "手动注销暂停期间仍应响应网络环境通知并检测");
    emit networkEventApi.statusChecked(networkEventApi.statusTokens.back(), false,
                                       "offline", "", 0, 0);
    expect(networkEventApi.loginTokens.empty(),
           "网络环境通知不得解除手动注销后的自动重连暂停");

    // 用户显式恢复后，认证中的网络通知同样应在完成后补检。
    QMetaObject::invokeMethod(&networkEventWindow, "onLoginClicked",
                              Qt::DirectConnection);
    expect(networkEventApi.loginTokens.size() == 1,
           "手动登录应显式解除暂停并进入认证流程");
    const auto statusBeforeLoginEvent = networkEventApi.statusTokens.size();
    networkEvent();
    settleNetworkEvent();
    expect(networkEventApi.statusTokens.size() == statusBeforeLoginEvent,
           "认证期间网络通知不得并发检测");
    emit networkEventApi.loginFailed(networkEventApi.loginTokens.back(),
                                     "模拟结束");
    expect(networkEventApi.statusTokens.size() == statusBeforeLoginEvent + 1,
           "认证完成后应补发待处理网络检测");
    emit networkEventApi.statusChecked(networkEventApi.statusTokens.back(), false,
                                       "offline", "", 0, 0);
  } catch (const std::exception &error) {
    qCritical().noquote() << "Qt 控制器回放失败：" << error.what();
    return 1;
  }
  qInfo().noquote() << "Qt 正式控制器会话回放通过：" << checked << "个断言";
  return 0;
}
