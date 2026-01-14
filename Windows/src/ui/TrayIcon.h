#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 系统托盘图标
// ============================================================================

#include <Windows.h>
#include <shellapi.h>
#include <string>
#include <functional>
#include "../resource/resource.h"
#include "../core/NetworkStatus.h"
#include "../utils/StringUtils.h"
#include "../utils/Logger.h"

namespace haut {

// 托盘图标状态
enum class TrayIconState {
    Online,
    Offline,
    Checking
};

// 菜单命令回调
using MenuCommandCallback = std::function<void(UINT)>;

class TrayIcon {
public:
    TrayIcon(HWND hwndParent, UINT callbackMessage)
        : m_hwndParent(hwndParent)
        , m_callbackMessage(callbackMessage) {
        loadIcons();
        createMenu();
    }

    ~TrayIcon() {
        remove();
        destroyMenu();
        destroyIcons();
    }

    // 创建托盘图标
    bool create() {
        ZeroMemory(&m_nid, sizeof(m_nid));
        m_nid.cbSize = sizeof(NOTIFYICONDATAW);
        m_nid.hWnd = m_hwndParent;
        m_nid.uID = 1;
        m_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
        m_nid.uCallbackMessage = m_callbackMessage;
        m_nid.hIcon = m_iconChecking;
        wcscpy_s(m_nid.szTip, L"HAUT Network Guard - 检测中...");
        m_nid.uVersion = NOTIFYICON_VERSION_4;

        if (!Shell_NotifyIconW(NIM_ADD, &m_nid)) {
            Logger::error(L"创建托盘图标失败");
            return false;
        }

        Shell_NotifyIconW(NIM_SETVERSION, &m_nid);
        Logger::log(L"托盘图标已创建");
        return true;
    }

    // 移除托盘图标
    void remove() {
        if (m_nid.hWnd) {
            Shell_NotifyIconW(NIM_DELETE, &m_nid);
            ZeroMemory(&m_nid, sizeof(m_nid));
            Logger::log(L"托盘图标已移除");
        }
    }

    // 设置状态
    void setState(TrayIconState state) {
        switch (state) {
        case TrayIconState::Online:
            m_nid.hIcon = m_iconOnline;
            wcscpy_s(m_nid.szTip, L"HAUT Network Guard - 已连接");
            break;
        case TrayIconState::Offline:
            m_nid.hIcon = m_iconOffline;
            wcscpy_s(m_nid.szTip, L"HAUT Network Guard - 未连接");
            break;
        case TrayIconState::Checking:
            m_nid.hIcon = m_iconChecking;
            wcscpy_s(m_nid.szTip, L"HAUT Network Guard - 检测中...");
            break;
        }
        Shell_NotifyIconW(NIM_MODIFY, &m_nid);
    }

    // 设置提示文本
    void setTooltip(const std::wstring& tip) {
        wcscpy_s(m_nid.szTip, tip.c_str());
        Shell_NotifyIconW(NIM_MODIFY, &m_nid);
    }

    // 显示气泡通知
    void showBalloon(const std::wstring& title, const std::wstring& message, DWORD icon = NIIF_INFO) {
        m_nid.uFlags |= NIF_INFO;
        wcscpy_s(m_nid.szInfoTitle, title.c_str());
        wcscpy_s(m_nid.szInfo, message.c_str());
        m_nid.dwInfoFlags = icon;
        Shell_NotifyIconW(NIM_MODIFY, &m_nid);
        m_nid.uFlags &= ~NIF_INFO;
    }

    // 显示右键菜单
    void showContextMenu() {
        POINT pt;
        GetCursorPos(&pt);

        SetForegroundWindow(m_hwndParent);
        UINT cmd = TrackPopupMenu(
            m_menu,
            TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
            pt.x, pt.y,
            0,
            m_hwndParent,
            nullptr
        );
        PostMessage(m_hwndParent, WM_NULL, 0, 0);

        if (cmd && m_menuCallback) {
            m_menuCallback(cmd);
        }
    }

    // 更新菜单状态显示
    void updateMenuStatus(const NetworkStatus& status) {
        // 状态文本
        std::wstring statusText = L"状态: " + status.getStateText();
        ModifyMenuW(m_menu, ID_MENU_STATUS, MF_BYCOMMAND | MF_STRING | MF_DISABLED, ID_MENU_STATUS, statusText.c_str());

        // 详细信息
        std::wstring detail1, detail2;
        if (status.isOnline()) {
            detail1 = L"IP: " + status.ipAddress;
            detail2 = L"流量: " + StringUtils::formatBytes(status.usedBytes) +
                L" | 时长: " + StringUtils::formatDuration(status.onlineSeconds);
        }
        ModifyMenuW(m_menu, ID_MENU_DETAIL, MF_BYCOMMAND | MF_STRING | MF_DISABLED, ID_MENU_DETAIL, detail1.c_str());
        ModifyMenuW(m_menu, ID_MENU_DETAIL2, MF_BYCOMMAND | MF_STRING | MF_DISABLED, ID_MENU_DETAIL2, detail2.c_str());
    }

    // 设置菜单命令回调
    void setMenuCallback(MenuCommandCallback callback) {
        m_menuCallback = callback;
    }

private:
    HWND m_hwndParent = nullptr;
    UINT m_callbackMessage = 0;
    NOTIFYICONDATAW m_nid = { 0 };
    HMENU m_menu = nullptr;
    MenuCommandCallback m_menuCallback;

    // 图标
    HICON m_iconOnline = nullptr;
    HICON m_iconOffline = nullptr;
    HICON m_iconChecking = nullptr;

    // 加载图标
    void loadIcons() {
        HINSTANCE hInst = GetModuleHandle(nullptr);

        // 尝试从资源加载
        m_iconOnline = LoadIcon(hInst, MAKEINTRESOURCE(IDI_ONLINE));
        m_iconOffline = LoadIcon(hInst, MAKEINTRESOURCE(IDI_OFFLINE));
        m_iconChecking = LoadIcon(hInst, MAKEINTRESOURCE(IDI_CHECKING));

        // 如果资源加载失败，使用系统图标
        if (!m_iconOnline) {
            m_iconOnline = LoadIcon(nullptr, IDI_APPLICATION);
        }
        if (!m_iconOffline) {
            m_iconOffline = LoadIcon(nullptr, IDI_WARNING);
        }
        if (!m_iconChecking) {
            m_iconChecking = LoadIcon(nullptr, IDI_INFORMATION);
        }
    }

    // 销毁图标
    void destroyIcons() {
        // 系统图标不需要销毁，资源图标会在模块卸载时自动释放
    }

    // 创建菜单
    void createMenu() {
        m_menu = CreatePopupMenu();

        // 状态显示（禁用项）
        AppendMenuW(m_menu, MF_STRING | MF_DISABLED, ID_MENU_STATUS, L"状态: 检测中...");
        AppendMenuW(m_menu, MF_STRING | MF_DISABLED, ID_MENU_DETAIL, L"");
        AppendMenuW(m_menu, MF_STRING | MF_DISABLED, ID_MENU_DETAIL2, L"");
        AppendMenuW(m_menu, MF_SEPARATOR, 0, nullptr);

        // 操作项
        AppendMenuW(m_menu, MF_STRING, ID_MENU_LOGIN, L"立即登录\tL");
        AppendMenuW(m_menu, MF_STRING, ID_MENU_LOGOUT, L"注销登录\tO");
        AppendMenuW(m_menu, MF_SEPARATOR, 0, nullptr);

        AppendMenuW(m_menu, MF_STRING, ID_MENU_CHECK_NOW, L"立即检测\tR");
        AppendMenuW(m_menu, MF_SEPARATOR, 0, nullptr);

        // 功能项
        AppendMenuW(m_menu, MF_STRING, ID_MENU_DASHBOARD, L"打开面板\tD");
        AppendMenuW(m_menu, MF_STRING, ID_MENU_SETTINGS, L"账号设置...\t,");
        AppendMenuW(m_menu, MF_STRING, ID_MENU_ABOUT, L"关于");
        AppendMenuW(m_menu, MF_STRING, ID_MENU_CHECK_UPDATE, L"检查更新...\tU");
        AppendMenuW(m_menu, MF_SEPARATOR, 0, nullptr);

        // 退出
        AppendMenuW(m_menu, MF_STRING, ID_MENU_QUIT, L"退出\tQ");
    }

    // 销毁菜单
    void destroyMenu() {
        if (m_menu) {
            DestroyMenu(m_menu);
            m_menu = nullptr;
        }
    }
};

} // namespace haut
