// ============================================================================
// HAUT Network Guard - Windows
// 可视化面板窗口实现
// ============================================================================

#include "DashboardWindow.h"
#include "../Application.h"

namespace haut {

void DashboardWindow::onCommand(WORD id, WORD code, HWND hwndCtrl) {
    auto& app = Application::instance();

    switch (id) {
    case 4001: // 刷新状态
        Logger::log(L"面板: 刷新状态");
        app.checkStatus();
        break;

    case 4002: // 立即登录
        Logger::log(L"面板: 立即登录");
        app.performLogin();
        break;

    case 4003: // 注销登录
        Logger::log(L"面板: 注销登录");
        app.performLogout();
        break;

    case 4004: // 账号设置
        Logger::log(L"面板: 打开设置");
        app.showSettings();
        break;
    }
}

} // namespace haut
