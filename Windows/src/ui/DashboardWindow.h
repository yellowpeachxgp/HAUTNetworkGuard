#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 可视化面板窗口
// ============================================================================

#include "BaseWindow.h"
#include "../core/NetworkStatus.h"
#include "../resource/resource.h"
#include <commctrl.h>

namespace haut {

// 前向声明
class Application;

class DashboardWindow : public BaseWindow {
public:
    DashboardWindow() {
        create(L"HAUT Network Guard - 网络状态", DASHBOARD_WINDOW_WIDTH, DASHBOARD_WINDOW_HEIGHT);
    }

    void updateStatus(const NetworkStatus& status) {
        m_status = status;
        if (m_hwnd && IsWindowVisible(m_hwnd)) {
            updateUI();
        }
    }

    void show() {
        updateUI();
        BaseWindow::show();
    }

protected:
    const wchar_t* getClassName() const override {
        return L"HAUTNetworkGuard_DashboardWindow";
    }

    void onCreate() override {
        BaseWindow::onCreate();

        // 创建各种字体
        m_titleFont = CreateFontW(
            -16, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"
        );

        m_statusFont = CreateFontW(
            -24, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"
        );

        m_smallFont = CreateFontW(
            -11, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"
        );

        int margin = 20;
        int groupWidth = DASHBOARD_WINDOW_WIDTH - margin * 2;
        int y = 340;

        // ============ 连接状态区域 ============
        createGroupBox(L" 连接状态 ", margin, y - 80, groupWidth, 85);
        y -= 25;

        // 状态文本（大字）
        m_hwndStatusText = createLabel(L"检测中...", margin + 80, y, 200, 30);
        SendMessage(m_hwndStatusText, WM_SETFONT, (WPARAM)m_statusFont, TRUE);

        // 状态指示点
        m_hwndStatusDot = createLabel(L"●", margin + 350, y + 5, 30, 24);
        SendMessage(m_hwndStatusDot, WM_SETFONT, (WPARAM)m_statusFont, TRUE);

        // 状态描述
        m_hwndStatusDesc = createLabel(L"", margin + 380, y + 8, 60, 20);
        SendMessage(m_hwndStatusDesc, WM_SETFONT, (WPARAM)m_defaultFont, TRUE);

        y -= 95;

        // ============ 网络信息区域 ============
        createGroupBox(L" 网络信息 ", margin, y - 130, groupWidth, 135);
        y -= 20;

        int labelX = margin + 20;
        int valueX = margin + 100;
        int rowHeight = 25;

        // IP地址
        createLabel(L"IP 地址:", labelX, y, 80, 20);
        m_hwndIP = createLabel(L"-", valueX, y, 200, 20);
        y -= rowHeight;

        // 已用流量
        createLabel(L"已用流量:", labelX, y, 80, 20);
        m_hwndTraffic = createLabel(L"-", valueX, y, 100, 20);

        // 进度条
        m_hwndProgress = createProgressBar(valueX + 110, y + 2, 150, 16);
        SendMessage(m_hwndProgress, PBM_SETRANGE, 0, MAKELPARAM(0, 100));
        SendMessage(m_hwndProgress, PBM_SETPOS, 0, 0);

        m_hwndPercent = createLabel(L"", valueX + 270, y, 50, 20);
        SendMessage(m_hwndPercent, WM_SETFONT, (WPARAM)m_smallFont, TRUE);
        y -= rowHeight;

        // 在线时长
        createLabel(L"在线时长:", labelX, y, 80, 20);
        m_hwndDuration = createLabel(L"-", valueX, y, 200, 20);
        y -= rowHeight;

        // 用户名
        createLabel(L"用户名:", labelX, y, 80, 20);
        m_hwndUsername = createLabel(L"-", valueX, y, 200, 20);
        y -= 45;

        // ============ 操作区域 ============
        createGroupBox(L" 操作 ", margin, y - 55, groupWidth, 60);

        int btnY = y - 35;
        int btnWidth = 90;
        int btnHeight = 30;
        int btnGap = 15;
        int btnStartX = margin + (groupWidth - (btnWidth * 4 + btnGap * 3)) / 2;

        m_hwndRefreshBtn = createButton(L"刷新状态", btnStartX, btnY, btnWidth, btnHeight, 4001);
        m_hwndLoginBtn = createButton(L"立即登录", btnStartX + btnWidth + btnGap, btnY, btnWidth, btnHeight, 4002);
        m_hwndLogoutBtn = createButton(L"注销登录", btnStartX + (btnWidth + btnGap) * 2, btnY, btnWidth, btnHeight, 4003);
        m_hwndSettingsBtn = createButton(L"账号设置", btnStartX + (btnWidth + btnGap) * 3, btnY, btnWidth, btnHeight, 4004);

        // ============ 底部信息 ============
        // 最后更新时间
        m_hwndLastUpdate = createLabel(L"最后更新: -", margin, 15, 250, 20);
        SendMessage(m_hwndLastUpdate, WM_SETFONT, (WPARAM)m_smallFont, TRUE);

        // 版本信息
        std::wstring versionText = L"v";
        versionText += APP_VERSION;
        HWND hwndVersion = createLabel(versionText, DASHBOARD_WINDOW_WIDTH - margin - 60, 15, 60, 20,
            WS_CHILD | WS_VISIBLE | SS_RIGHT);
        SendMessage(hwndVersion, WM_SETFONT, (WPARAM)m_smallFont, TRUE);
    }

    void onDestroy() override {
        if (m_titleFont) {
            DeleteObject(m_titleFont);
            m_titleFont = nullptr;
        }
        if (m_statusFont) {
            DeleteObject(m_statusFont);
            m_statusFont = nullptr;
        }
        if (m_smallFont) {
            DeleteObject(m_smallFont);
            m_smallFont = nullptr;
        }
        BaseWindow::onDestroy();
    }

    void onCommand(WORD id, WORD code, HWND hwndCtrl) override;

private:
    NetworkStatus m_status;

    // 字体
    HFONT m_titleFont = nullptr;
    HFONT m_statusFont = nullptr;
    HFONT m_smallFont = nullptr;

    // 控件
    HWND m_hwndStatusText = nullptr;
    HWND m_hwndStatusDot = nullptr;
    HWND m_hwndStatusDesc = nullptr;
    HWND m_hwndIP = nullptr;
    HWND m_hwndTraffic = nullptr;
    HWND m_hwndProgress = nullptr;
    HWND m_hwndPercent = nullptr;
    HWND m_hwndDuration = nullptr;
    HWND m_hwndUsername = nullptr;
    HWND m_hwndLastUpdate = nullptr;

    // 按钮
    HWND m_hwndRefreshBtn = nullptr;
    HWND m_hwndLoginBtn = nullptr;
    HWND m_hwndLogoutBtn = nullptr;
    HWND m_hwndSettingsBtn = nullptr;

    void updateUI() {
        if (!m_hwndStatusText) return;

        // 状态文本
        std::wstring statusText;
        std::wstring statusDotColor;
        std::wstring statusDesc;

        switch (m_status.state) {
        case NetworkState::Online:
            statusText = L"已连接";
            statusDesc = L"在线";
            break;
        case NetworkState::Offline:
            statusText = L"未连接";
            statusDesc = L"离线";
            break;
        case NetworkState::Checking:
            statusText = L"检测中...";
            statusDesc = L"";
            break;
        case NetworkState::Error:
            statusText = L"错误";
            statusDesc = m_status.errorMessage;
            break;
        }

        SetWindowTextW(m_hwndStatusText, statusText.c_str());
        SetWindowTextW(m_hwndStatusDesc, statusDesc.c_str());

        // 网络信息
        if (m_status.isOnline()) {
            SetWindowTextW(m_hwndIP, m_status.ipAddress.c_str());
            SetWindowTextW(m_hwndTraffic, StringUtils::formatBytes(m_status.usedBytes).c_str());
            SetWindowTextW(m_hwndDuration, StringUtils::formatDuration(m_status.onlineSeconds).c_str());
            SetWindowTextW(m_hwndUsername, m_status.username.c_str());

            // 流量进度条（假设每月限额10GB）
            const int64_t monthlyLimit = 10LL * 1024 * 1024 * 1024;
            int percent = static_cast<int>((m_status.usedBytes * 100) / monthlyLimit);
            if (percent > 100) percent = 100;
            SendMessage(m_hwndProgress, PBM_SETPOS, percent, 0);

            wchar_t percentText[16];
            swprintf_s(percentText, L"%d%%", percent);
            SetWindowTextW(m_hwndPercent, percentText);
        } else {
            SetWindowTextW(m_hwndIP, L"-");
            SetWindowTextW(m_hwndTraffic, L"-");
            SetWindowTextW(m_hwndDuration, L"-");
            SetWindowTextW(m_hwndUsername, L"-");
            SendMessage(m_hwndProgress, PBM_SETPOS, 0, 0);
            SetWindowTextW(m_hwndPercent, L"");
        }

        // 最后更新时间
        std::wstring updateText = L"最后更新: " + StringUtils::getCurrentTimeString();
        SetWindowTextW(m_hwndLastUpdate, updateText.c_str());

        // 刷新窗口
        InvalidateRect(m_hwnd, nullptr, TRUE);
    }
};

} // namespace haut
