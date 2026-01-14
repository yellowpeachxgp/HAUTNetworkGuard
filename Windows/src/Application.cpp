// ============================================================================
// HAUT Network Guard - Windows
// 应用主类实现
// ============================================================================

#include "Application.h"
#include "ui/SettingsWindow.h"
#include "ui/AboutWindow.h"
#include "ui/DashboardWindow.h"
#include "ui/UpdateWindow.h"
#include "core/UpdateChecker.h"

namespace haut {

// 检查网络状态
void Application::checkStatus() {
    if (!m_api) return;

    m_api->checkStatus([this](const NetworkStatus& status) {
        // 在主线程处理状态更新
        NetworkStatus* pStatus = new NetworkStatus(status);
        PostMessage(m_hwndMain, WM_UPDATE_STATUS, 0, reinterpret_cast<LPARAM>(pStatus));
    });
}

// 执行登录
void Application::performLogin() {
    if (!m_api) return;

    auto& config = AppConfig::instance();
    std::string username = StringUtils::wideToUtf8(config.username());
    std::string password = StringUtils::wideToUtf8(config.password());

    if (username.empty() || password.empty()) {
        Logger::log(L"用户名或密码为空，显示设置窗口");
        showSettings();
        return;
    }

    Logger::log(L"执行登录...");
    m_api->login(username, password, [this](const LoginResponse& result) {
        // 在主线程处理登录结果
        LoginResponse* pResult = new LoginResponse(result);
        PostMessage(m_hwndMain, WM_LOGIN_RESULT, 0, reinterpret_cast<LPARAM>(pResult));
    });
}

// 执行注销
void Application::performLogout() {
    if (!m_api) return;

    auto& config = AppConfig::instance();
    std::string username = StringUtils::wideToUtf8(config.username());

    if (username.empty()) {
        Logger::log(L"用户名为空");
        return;
    }

    Logger::log(L"执行注销...");
    m_api->logout(username, [this](const LoginResponse& result) {
        // 在主线程处理注销结果
        LoginResponse* pResult = new LoginResponse(result);
        PostMessage(m_hwndMain, WM_LOGOUT_RESULT, 0, reinterpret_cast<LPARAM>(pResult));
    });
}

// 显示设置窗口
void Application::showSettings() {
    if (!m_settingsWindow) {
        m_settingsWindow = std::make_unique<SettingsWindow>();
    }

    m_settingsWindow->setOnSaveCallback([this]() {
        Logger::log(L"设置已保存，启动状态监控");
        startStatusMonitor();
    });

    m_settingsWindow->show();
}

// 显示关于窗口
void Application::showAbout() {
    if (!m_aboutWindow) {
        m_aboutWindow = std::make_unique<AboutWindow>();
    }
    m_aboutWindow->show();
}

// 显示可视化面板
void Application::showDashboard() {
    if (!m_dashboardWindow) {
        m_dashboardWindow = std::make_unique<DashboardWindow>();
    }
    m_dashboardWindow->updateStatus(m_currentStatus);
    m_dashboardWindow->show();
}

// 显示更新窗口
void Application::showUpdateWindow(const ReleaseInfo& info) {
    if (!m_updateWindow) {
        m_updateWindow = std::make_unique<UpdateWindow>();
    }

    m_updateWindow->setReleaseInfo(info);
    m_updateWindow->setOnSkipCallback([&info]() {
        AppConfig::instance().setSkippedVersion(info.version);
    });

    m_updateWindow->show();
}

// 检查更新
void Application::checkForUpdate(bool force) {
    UpdateChecker::instance().checkForUpdate(force, [this](const ReleaseInfo& info) {
        if (info.isValid()) {
            // 在主线程显示更新窗口
            ReleaseInfo* pInfo = new ReleaseInfo(info);
            PostMessage(m_hwndMain, WM_UPDATE_AVAILABLE, 0, reinterpret_cast<LPARAM>(pInfo));
        }
    });
}

// 状态更新通知
void Application::onStatusUpdated(const NetworkStatus& status) {
    handleStatusUpdate(status);

    // 更新仪表盘（如果打开的话）
    if (m_dashboardWindow && m_dashboardWindow->isVisible()) {
        m_dashboardWindow->updateStatus(status);
    }
}

// 登录结果通知
void Application::onLoginResult(const LoginResponse& result) {
    handleLoginResult(result);
}

// 注销结果通知
void Application::onLogoutResult(const LoginResponse& result) {
    handleLogoutResult(result);
}

} // namespace haut
