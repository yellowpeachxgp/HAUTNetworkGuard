#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 更新提示窗口
// ============================================================================

#include "BaseWindow.h"
#include "../core/NetworkStatus.h"
#include "../resource/resource.h"
#include <shellapi.h>
#include <functional>

namespace haut {

class UpdateWindow : public BaseWindow {
public:
    using SkipCallback = std::function<void()>;

    UpdateWindow() {
        create(L"发现新版本", UPDATE_WINDOW_WIDTH, UPDATE_WINDOW_HEIGHT);
    }

    void setReleaseInfo(const ReleaseInfo& info) {
        m_releaseInfo = info;
        updateUI();
    }

    void setOnSkipCallback(SkipCallback callback) {
        m_skipCallback = callback;
    }

protected:
    const wchar_t* getClassName() const override {
        return L"HAUTNetworkGuard_UpdateWindow";
    }

    void onCreate() override {
        BaseWindow::onCreate();

        // 创建大字体
        m_titleFont = CreateFontW(
            -18, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"
        );

        // 创建小字体
        m_smallFont = CreateFontW(
            -12, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"
        );

        // 创建说明字体
        m_notesFont = CreateFontW(
            -11, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"
        );

        int y = 225;
        int margin = 20;

        // 标题（版本号会在setReleaseInfo中更新）
        m_hwndTitle = createLabel(L"发现新版本", 100, y, 300, 24);
        SendMessage(m_hwndTitle, WM_SETFONT, (WPARAM)m_titleFont, TRUE);
        y -= 25;

        // 当前版本
        std::wstring currentText = L"当前版本: v";
        currentText += APP_VERSION;
        m_hwndCurrent = createLabel(currentText, 100, y, 300, 20);
        SendMessage(m_hwndCurrent, WM_SETFONT, (WPARAM)m_smallFont, TRUE);
        y -= 45;

        // 更新内容标题
        HWND hwndNotesTitle = createLabel(L"更新内容:", margin, y, 380, 20);
        SendMessage(hwndNotesTitle, WM_SETFONT, (WPARAM)m_defaultFont, TRUE);
        y -= 85;

        // 更新内容（使用只读编辑框模拟滚动文本框）
        m_hwndNotes = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL,
            margin, y, 380, 80,
            m_hwnd, nullptr,
            GetModuleHandle(nullptr), nullptr
        );
        SendMessage(m_hwndNotes, WM_SETFONT, (WPARAM)m_notesFont, TRUE);

        // 按钮
        int btnY = 20;
        int btnWidth = 100;
        int btnHeight = 32;

        // 跳过此版本
        m_hwndSkipBtn = createButton(L"跳过此版本", margin, btnY, btnWidth, btnHeight, 3001);

        // 稍后提醒
        m_hwndLaterBtn = createButton(L"稍后提醒", 190, btnY, btnWidth, btnHeight, 3002);

        // 立即更新
        m_hwndUpdateBtn = createButton(L"立即更新", 300, btnY, btnWidth, btnHeight, 3003,
            WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON);
    }

    void onDestroy() override {
        if (m_titleFont) {
            DeleteObject(m_titleFont);
            m_titleFont = nullptr;
        }
        if (m_smallFont) {
            DeleteObject(m_smallFont);
            m_smallFont = nullptr;
        }
        if (m_notesFont) {
            DeleteObject(m_notesFont);
            m_notesFont = nullptr;
        }
        BaseWindow::onDestroy();
    }

    void onCommand(WORD id, WORD code, HWND hwndCtrl) override {
        switch (id) {
        case 3001: // 跳过此版本
            Logger::log(L"用户选择跳过此版本");
            if (m_skipCallback) {
                m_skipCallback();
            }
            hide();
            break;

        case 3002: // 稍后提醒
            Logger::log(L"用户选择稍后提醒");
            hide();
            break;

        case 3003: // 立即更新
            Logger::log(L"用户选择立即更新");
            openDownloadPage();
            hide();
            break;
        }
    }

private:
    ReleaseInfo m_releaseInfo;
    SkipCallback m_skipCallback;

    HWND m_hwndTitle = nullptr;
    HWND m_hwndCurrent = nullptr;
    HWND m_hwndNotes = nullptr;
    HWND m_hwndSkipBtn = nullptr;
    HWND m_hwndLaterBtn = nullptr;
    HWND m_hwndUpdateBtn = nullptr;

    HFONT m_titleFont = nullptr;
    HFONT m_smallFont = nullptr;
    HFONT m_notesFont = nullptr;

    void updateUI() {
        if (!m_hwndTitle) return;

        // 更新标题
        std::wstring titleText = L"发现新版本 v" + m_releaseInfo.version;
        SetWindowTextW(m_hwndTitle, titleText.c_str());

        // 更新说明
        std::wstring notes = simplifyReleaseNotes(m_releaseInfo.releaseNotes);
        SetWindowTextW(m_hwndNotes, notes.c_str());
    }

    // 简化更新说明（移除Markdown标记）
    std::wstring simplifyReleaseNotes(const std::wstring& notes) {
        std::wstring result = notes;
        result = StringUtils::replace(result, L"### ", L"");
        result = StringUtils::replace(result, L"## ", L"");
        result = StringUtils::replace(result, L"# ", L"");
        result = StringUtils::replace(result, L"**", L"");
        result = StringUtils::replace(result, L"\n", L"\r\n");  // Windows换行
        return StringUtils::trim(result);
    }

    void openDownloadPage() {
        std::wstring url;

        // 优先使用下载链接，否则使用发布页面
        if (!m_releaseInfo.downloadUrl.empty()) {
            url = m_releaseInfo.downloadUrl;
        } else if (!m_releaseInfo.htmlUrl.empty()) {
            url = m_releaseInfo.htmlUrl;
        } else {
            url = GITHUB_RELEASE_URL;
        }

        ShellExecuteW(nullptr, L"open", url.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    }
};

} // namespace haut
