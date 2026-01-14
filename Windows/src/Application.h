#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 应用主类
// ============================================================================

#include <Windows.h>
#include <memory>
#include "TrayIcon.h"
#include "../core/SrunAPI.h"
#include "../core/NetworkStatus.h"
#include "../config/AppConfig.h"
#include "../resource/resource.h"
#include "../utils/Logger.h"
#include "../utils/StringUtils.h"

// 前向声明
namespace haut {
    class SettingsWindow;
    class AboutWindow;
    class UpdateWindow;
    class DashboardWindow;
    class UpdateChecker;
}

namespace haut {

class Application {
public:
    // 单例模式
    static Application& instance() {
        static Application instance;
        return instance;
    }

    // 初始化
    bool initialize(HINSTANCE hInstance) {
        m_hInstance = hInstance;

        Logger::log(L"===========================================");
        Logger::logf(L"  %s v%s 启动", APP_NAME, APP_VERSION);
        Logger::log(L"===========================================");

        // 创建消息窗口
        if (!createMessageWindow()) {
            Logger::error(L"创建消息窗口失败");
            return false;
        }

        // 创建托盘图标
        m_trayIcon = std::make_unique<TrayIcon>(m_hwndMain, WM_TRAYICON);
        if (!m_trayIcon->create()) {
            Logger::error(L"创建托盘图标失败");
            return false;
        }

        // 设置托盘菜单回调
        m_trayIcon->setMenuCallback([this](UINT cmd) {
            handleMenuCommand(cmd);
        });

        // 初始化API
        m_api = std::make_unique<SrunAPI>();

        // 检查是否首次运行
        if (!AppConfig::instance().hasConfigured()) {
            Logger::log(L"首次运行，显示设置窗口");
            showSettings();
        } else {
            // 启动状态监控
            startStatusMonitor();
        }

        Logger::log(L"应用初始化完成");
        return true;
    }

    // 运行消息循环
    int run() {
        MSG msg;
        while (GetMessage(&msg, nullptr, 0, 0)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        return static_cast<int>(msg.wParam);
    }

    // 退出
    void quit() {
        Logger::log(L"应用退出");
        PostQuitMessage(0);
    }

    // 获取实例句柄
    HINSTANCE instanceHandle() const { return m_hInstance; }

    // 获取主窗口句柄
    HWND mainWindow() const { return m_hwndMain; }

    // 网络操作
    void checkStatus();
    void performLogin();
    void performLogout();

    // 显示窗口
    void showSettings();
    void showAbout();
    void showDashboard();
    void showUpdateWindow(const ReleaseInfo& info);

    // 获取当前状态
    const NetworkStatus& currentStatus() const { return m_currentStatus; }

    // 状态更新通知
    void onStatusUpdated(const NetworkStatus& status);
    void onLoginResult(const LoginResponse& result);
    void onLogoutResult(const LoginResponse& result);

private:
    Application() = default;
    ~Application() = default;
    Application(const Application&) = delete;
    Application& operator=(const Application&) = delete;

    HINSTANCE m_hInstance = nullptr;
    HWND m_hwndMain = nullptr;

    std::unique_ptr<TrayIcon> m_trayIcon;
    std::unique_ptr<SrunAPI> m_api;
    std::unique_ptr<SettingsWindow> m_settingsWindow;
    std::unique_ptr<AboutWindow> m_aboutWindow;
    std::unique_ptr<DashboardWindow> m_dashboardWindow;
    std::unique_ptr<UpdateWindow> m_updateWindow;

    NetworkStatus m_currentStatus;
    bool m_wasOnline = false;

    // 创建消息窗口
    bool createMessageWindow() {
        // 注册窗口类
        WNDCLASSEXW wc = { 0 };
        wc.cbSize = sizeof(WNDCLASSEXW);
        wc.lpfnWndProc = Application::WndProc;
        wc.hInstance = m_hInstance;
        wc.lpszClassName = L"HAUTNetworkGuard_MainWindow";

        if (!RegisterClassExW(&wc)) {
            return false;
        }

        // 创建隐藏的消息窗口
        m_hwndMain = CreateWindowExW(
            0,
            L"HAUTNetworkGuard_MainWindow",
            APP_NAME,
            0,
            0, 0, 0, 0,
            HWND_MESSAGE,
            nullptr,
            m_hInstance,
            nullptr
        );

        return m_hwndMain != nullptr;
    }

    // 启动状态监控
    void startStatusMonitor() {
        // 立即检测一次
        checkStatus();

        // 设置定时器
        SetTimer(m_hwndMain, TIMER_STATUS_CHECK, STATUS_CHECK_INTERVAL, nullptr);
        Logger::log(L"状态监控已启动 (间隔: 3秒)");
    }

    // 停止状态监控
    void stopStatusMonitor() {
        KillTimer(m_hwndMain, TIMER_STATUS_CHECK);
        Logger::log(L"状态监控已停止");
    }

    // 处理托盘消息
    void handleTrayMessage(LPARAM lParam) {
        switch (LOWORD(lParam)) {
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
            m_trayIcon->showContextMenu();
            break;

        case WM_LBUTTONDBLCLK:
            showDashboard();
            break;
        }
    }

    // 处理菜单命令
    void handleMenuCommand(UINT id) {
        switch (id) {
        case ID_MENU_LOGIN:
            performLogin();
            break;

        case ID_MENU_LOGOUT:
            performLogout();
            break;

        case ID_MENU_CHECK_NOW:
            Logger::log(L"手动检测");
            checkStatus();
            break;

        case ID_MENU_DASHBOARD:
            showDashboard();
            break;

        case ID_MENU_SETTINGS:
            showSettings();
            break;

        case ID_MENU_ABOUT:
            showAbout();
            break;

        case ID_MENU_CHECK_UPDATE:
            Logger::log(L"手动检查更新");
            checkForUpdate(true);
            break;

        case ID_MENU_QUIT:
            quit();
            break;
        }
    }

    // 处理状态更新
    void handleStatusUpdate(const NetworkStatus& status) {
        bool wasOnline = m_currentStatus.isOnline();
        m_currentStatus = status;

        // 更新托盘图标
        switch (status.state) {
        case NetworkState::Online:
            m_trayIcon->setState(TrayIconState::Online);
            break;
        case NetworkState::Offline:
            m_trayIcon->setState(TrayIconState::Offline);
            break;
        default:
            m_trayIcon->setState(TrayIconState::Checking);
            break;
        }

        // 更新托盘菜单
        m_trayIcon->updateMenuStatus(status);

        // 离线时自动重连
        if (!status.isOnline() && status.state != NetworkState::Checking) {
            if (wasOnline) {
                Logger::log(L"检测到掉线，尝试自动重连...");
                m_trayIcon->showBalloon(L"网络已断开", L"正在尝试自动重连...", NIIF_WARNING);
            } else {
                Logger::log(L"仍处于离线状态，继续尝试登录...");
            }
            performLogin();
        }
    }

    // 处理登录结果
    void handleLoginResult(const LoginResponse& result) {
        switch (result.result) {
        case LoginResultType::Success:
            m_trayIcon->showBalloon(L"登录成功", L"已连接校园网", NIIF_INFO);
            break;
        case LoginResultType::AlreadyOnline:
            // 已经在线，不显示通知
            break;
        case LoginResultType::Failed:
            m_trayIcon->showBalloon(L"登录失败", result.message, NIIF_ERROR);
            break;
        }
        checkStatus();
    }

    // 处理注销结果
    void handleLogoutResult(const LoginResponse& result) {
        if (result.result == LoginResultType::Success) {
            m_trayIcon->showBalloon(L"注销成功", L"已断开校园网", NIIF_INFO);
        } else {
            m_trayIcon->showBalloon(L"注销失败", result.message, NIIF_ERROR);
        }
        checkStatus();
    }

    // 检查更新
    void checkForUpdate(bool force = false);

    // 静态窗口过程
    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
        auto& app = Application::instance();

        switch (msg) {
        case WM_TRAYICON:
            app.handleTrayMessage(lParam);
            return 0;

        case WM_TIMER:
            if (wParam == TIMER_STATUS_CHECK) {
                app.checkStatus();
            } else if (wParam == TIMER_UPDATE_CHECK) {
                app.checkForUpdate(false);
            }
            return 0;

        case WM_UPDATE_STATUS:
            // 从工作线程发来的状态更新
            if (lParam) {
                NetworkStatus* pStatus = reinterpret_cast<NetworkStatus*>(lParam);
                app.handleStatusUpdate(*pStatus);
                delete pStatus;
            }
            return 0;

        case WM_LOGIN_RESULT:
            if (lParam) {
                LoginResponse* pResult = reinterpret_cast<LoginResponse*>(lParam);
                app.handleLoginResult(*pResult);
                delete pResult;
            }
            return 0;

        case WM_LOGOUT_RESULT:
            if (lParam) {
                LoginResponse* pResult = reinterpret_cast<LoginResponse*>(lParam);
                app.handleLogoutResult(*pResult);
                delete pResult;
            }
            return 0;

        case WM_DESTROY:
            app.quit();
            return 0;

        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        }
    }
};

} // namespace haut
