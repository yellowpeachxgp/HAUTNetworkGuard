#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 关于窗口
// ============================================================================

#include "BaseWindow.h"
#include "../resource/resource.h"
#include <shellapi.h>

namespace haut {

class AboutWindow : public BaseWindow {
public:
    AboutWindow() {
        create(L"关于", ABOUT_WINDOW_WIDTH, ABOUT_WINDOW_HEIGHT);
    }

protected:
    const wchar_t* getClassName() const override {
        return L"HAUTNetworkGuard_AboutWindow";
    }

    void onCreate() override {
        BaseWindow::onCreate();

        // 创建大字体
        m_titleFont = CreateFontW(
            -20, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"
        );

        // 创建小字体
        m_smallFont = CreateFontW(
            -11, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"
        );

        int centerX = ABOUT_WINDOW_WIDTH / 2;
        int y = 160;

        // 应用名称
        HWND hwndTitle = createLabel(APP_NAME, 0, y, ABOUT_WINDOW_WIDTH, 24,
            WS_CHILD | WS_VISIBLE | SS_CENTER);
        SendMessage(hwndTitle, WM_SETFONT, (WPARAM)m_titleFont, TRUE);
        y -= 25;

        // 版本
        std::wstring versionText = L"版本 ";
        versionText += APP_VERSION;
        HWND hwndVersion = createLabel(versionText, 0, y, ABOUT_WINDOW_WIDTH, 20,
            WS_CHILD | WS_VISIBLE | SS_CENTER);
        SendMessage(hwndVersion, WM_SETFONT, (WPARAM)m_smallFont, TRUE);
        y -= 35;

        // 描述
        HWND hwndDesc = createLabel(L"河南工业大学校园网自动登录工具", 0, y, ABOUT_WINDOW_WIDTH, 20,
            WS_CHILD | WS_VISIBLE | SS_CENTER);
        SendMessage(hwndDesc, WM_SETFONT, (WPARAM)m_defaultFont, TRUE);
        y -= 30;

        // 作者
        std::wstring authorText = L"作者: ";
        authorText += APP_AUTHOR;
        HWND hwndAuthor = createLabel(authorText, 0, y, ABOUT_WINDOW_WIDTH, 20,
            WS_CHILD | WS_VISIBLE | SS_CENTER);
        SendMessage(hwndAuthor, WM_SETFONT, (WPARAM)m_smallFont, TRUE);
        y -= 25;

        // QQ群
        std::wstring qqText = L"QQ群: ";
        qqText += APP_QQ_GROUP;
        HWND hwndQQ = createLabel(qqText, 0, y, ABOUT_WINDOW_WIDTH, 20,
            WS_CHILD | WS_VISIBLE | SS_CENTER);
        SendMessage(hwndQQ, WM_SETFONT, (WPARAM)m_smallFont, TRUE);
        y -= 30;

        // 网站链接（作为按钮）
        m_hwndLink = createButton(L"github.com/yellowpeachxgp/HAUTNetworkGuard", 10, y, ABOUT_WINDOW_WIDTH - 20, 20, 2001,
            WS_CHILD | WS_VISIBLE | BS_FLAT);
        SendMessage(m_hwndLink, WM_SETFONT, (WPARAM)m_smallFont, TRUE);
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
        BaseWindow::onDestroy();
    }

    void onCommand(WORD id, WORD code, HWND hwndCtrl) override {
        if (id == 2001 && code == BN_CLICKED) {
            // 打开网站
            ShellExecuteW(nullptr, L"open", APP_WEBSITE, nullptr, nullptr, SW_SHOWNORMAL);
        }
    }

private:
    HFONT m_titleFont = nullptr;
    HFONT m_smallFont = nullptr;
    HWND m_hwndLink = nullptr;
};

} // namespace haut
