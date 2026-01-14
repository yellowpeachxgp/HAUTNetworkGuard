#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 设置窗口
// ============================================================================

#include "BaseWindow.h"
#include "../config/AppConfig.h"
#include "../resource/resource.h"
#include <functional>

namespace haut {

class SettingsWindow : public BaseWindow {
public:
    using SaveCallback = std::function<void()>;

    SettingsWindow() {
        create(L"账号设置", SETTINGS_WINDOW_WIDTH, SETTINGS_WINDOW_HEIGHT);
    }

    void setOnSaveCallback(SaveCallback callback) {
        m_saveCallback = callback;
    }

    void show() {
        // 加载现有配置
        loadConfig();
        BaseWindow::show();
    }

protected:
    const wchar_t* getClassName() const override {
        return L"HAUTNetworkGuard_SettingsWindow";
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

        int y = 220;
        int labelWidth = 60;
        int editWidth = 300;
        int margin = 20;

        // 标题
        HWND hwndTitle = createLabel(APP_NAME, margin, y, 200, 24);
        SendMessage(hwndTitle, WM_SETFONT, (WPARAM)m_titleFont, TRUE);
        y -= 25;

        // 副标题
        HWND hwndSubtitle = createLabel(L"河南工业大学校园网自动登录工具", margin, y, 300, 20);
        SendMessage(hwndSubtitle, WM_SETFONT, (WPARAM)m_smallFont, TRUE);
        SetWindowLongW(hwndSubtitle, GWL_STYLE, GetWindowLong(hwndSubtitle, GWL_STYLE) | SS_CENTERIMAGE);
        y -= 50;

        // 学号
        createLabel(L"学号:", margin, y + 3, labelWidth, 20);
        m_hwndUsername = createEdit(margin + labelWidth, y, editWidth, 26, 1001);
        y -= 40;

        // 密码
        createLabel(L"密码:", margin, y + 3, labelWidth, 20);
        m_hwndPassword = createPasswordEdit(margin + labelWidth, y, editWidth, 26, 1002);
        y -= 35;

        // 记住密码
        m_hwndAutoSave = createCheckBox(L"记住密码", margin + labelWidth, y, 100, 20, 1003);
        y -= 50;

        // 版本信息
        std::wstring versionText = L"v";
        versionText += APP_VERSION;
        versionText += L" by ";
        versionText += APP_AUTHOR;
        HWND hwndVersion = createLabel(versionText, margin, 20, 150, 20);
        SendMessage(hwndVersion, WM_SETFONT, (WPARAM)m_smallFont, TRUE);

        // 保存按钮
        m_hwndSaveBtn = createButton(L"保存并启动", 280, 18, 100, 32, 1010,
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
        BaseWindow::onDestroy();
    }

    void onCommand(WORD id, WORD code, HWND hwndCtrl) override {
        if (id == 1010 && code == BN_CLICKED) {
            saveConfig();
        }
    }

    LRESULT handleMessage(UINT msg, WPARAM wParam, LPARAM lParam) override {
        switch (msg) {
        case WM_CLOSE:
            // 如果尚未配置，关闭则退出应用
            if (!AppConfig::instance().hasConfigured()) {
                PostQuitMessage(0);
                return 0;
            }
            break;
        }
        return BaseWindow::handleMessage(msg, wParam, lParam);
    }

private:
    HWND m_hwndUsername = nullptr;
    HWND m_hwndPassword = nullptr;
    HWND m_hwndAutoSave = nullptr;
    HWND m_hwndSaveBtn = nullptr;
    HFONT m_titleFont = nullptr;
    HFONT m_smallFont = nullptr;
    SaveCallback m_saveCallback;

    void loadConfig() {
        auto& config = AppConfig::instance();
        setEditText(m_hwndUsername, config.username());
        setEditText(m_hwndPassword, config.password());
        setChecked(m_hwndAutoSave, config.autoSave());
    }

    void saveConfig() {
        std::wstring username = getEditText(m_hwndUsername);
        std::wstring password = getEditText(m_hwndPassword);
        bool autoSave = isChecked(m_hwndAutoSave);

        if (username.empty()) {
            MessageBoxW(m_hwnd, L"请输入学号", L"提示", MB_ICONWARNING);
            SetFocus(m_hwndUsername);
            return;
        }

        if (password.empty()) {
            MessageBoxW(m_hwnd, L"请输入密码", L"提示", MB_ICONWARNING);
            SetFocus(m_hwndPassword);
            return;
        }

        // 保存配置
        AppConfig::instance().save(username, password, autoSave);

        // 隐藏窗口
        hide();

        // 回调通知
        if (m_saveCallback) {
            m_saveCallback();
        }
    }
};

} // namespace haut
