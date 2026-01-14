#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 窗口基类
// ============================================================================

#include <Windows.h>
#include <string>
#include <map>
#include "../utils/Logger.h"

namespace haut {

class BaseWindow {
public:
    BaseWindow() = default;
    virtual ~BaseWindow() {
        if (m_hwnd) {
            DestroyWindow(m_hwnd);
            m_hwnd = nullptr;
        }
    }

    // 禁止拷贝
    BaseWindow(const BaseWindow&) = delete;
    BaseWindow& operator=(const BaseWindow&) = delete;

    // 创建窗口
    bool create(const std::wstring& title, int width, int height,
        DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        DWORD exStyle = 0) {

        // 注册窗口类（如果尚未注册）
        if (!registerWindowClass()) {
            return false;
        }

        // 计算居中位置
        int screenWidth = GetSystemMetrics(SM_CXSCREEN);
        int screenHeight = GetSystemMetrics(SM_CYSCREEN);
        int x = (screenWidth - width) / 2;
        int y = (screenHeight - height) / 2;

        // 调整窗口大小（包含边框和标题栏）
        RECT rect = { 0, 0, width, height };
        AdjustWindowRectEx(&rect, style, FALSE, exStyle);
        int adjustedWidth = rect.right - rect.left;
        int adjustedHeight = rect.bottom - rect.top;

        // 创建窗口
        m_hwnd = CreateWindowExW(
            exStyle,
            getClassName(),
            title.c_str(),
            style,
            x, y,
            adjustedWidth, adjustedHeight,
            nullptr,
            nullptr,
            GetModuleHandle(nullptr),
            this
        );

        if (!m_hwnd) {
            Logger::error(L"创建窗口失败: " + Logger::getLastErrorString());
            return false;
        }

        return true;
    }

    // 显示窗口
    void show() {
        if (m_hwnd) {
            ShowWindow(m_hwnd, SW_SHOW);
            UpdateWindow(m_hwnd);
            SetForegroundWindow(m_hwnd);
        }
    }

    // 隐藏窗口
    void hide() {
        if (m_hwnd) {
            ShowWindow(m_hwnd, SW_HIDE);
        }
    }

    // 关闭窗口
    void close() {
        if (m_hwnd) {
            DestroyWindow(m_hwnd);
            m_hwnd = nullptr;
        }
    }

    // 是否可见
    bool isVisible() const {
        return m_hwnd && IsWindowVisible(m_hwnd);
    }

    // 获取窗口句柄
    HWND handle() const { return m_hwnd; }

protected:
    HWND m_hwnd = nullptr;
    HFONT m_defaultFont = nullptr;

    // 子类需要实现的窗口类名
    virtual const wchar_t* getClassName() const = 0;

    // 子类需要实现的消息处理
    virtual LRESULT handleMessage(UINT msg, WPARAM wParam, LPARAM lParam) {
        switch (msg) {
        case WM_CREATE:
            onCreate();
            return 0;

        case WM_DESTROY:
            onDestroy();
            return 0;

        case WM_COMMAND:
            onCommand(LOWORD(wParam), HIWORD(wParam), (HWND)lParam);
            return 0;

        case WM_CLOSE:
            hide();  // 默认隐藏而非销毁
            return 0;

        default:
            return DefWindowProcW(m_hwnd, msg, wParam, lParam);
        }
    }

    // 窗口创建时调用
    virtual void onCreate() {
        // 创建默认字体
        m_defaultFont = CreateFontW(
            -14,                    // 高度
            0,                      // 宽度
            0,                      // 倾斜角度
            0,                      // 基线倾斜
            FW_NORMAL,              // 字重
            FALSE,                  // 斜体
            FALSE,                  // 下划线
            FALSE,                  // 删除线
            DEFAULT_CHARSET,        // 字符集
            OUT_DEFAULT_PRECIS,     // 输出精度
            CLIP_DEFAULT_PRECIS,    // 裁剪精度
            CLEARTYPE_QUALITY,      // 质量
            DEFAULT_PITCH | FF_DONTCARE,
            L"Microsoft YaHei UI"   // 字体名称
        );
    }

    // 窗口销毁时调用
    virtual void onDestroy() {
        if (m_defaultFont) {
            DeleteObject(m_defaultFont);
            m_defaultFont = nullptr;
        }
    }

    // 命令处理
    virtual void onCommand(WORD id, WORD code, HWND hwndCtrl) {
        // 子类实现
    }

    // 创建标签
    HWND createLabel(const std::wstring& text, int x, int y, int width, int height,
        DWORD style = WS_CHILD | WS_VISIBLE | SS_LEFT) {
        HWND hwnd = CreateWindowExW(
            0, L"STATIC", text.c_str(),
            style,
            x, y, width, height,
            m_hwnd, nullptr,
            GetModuleHandle(nullptr), nullptr
        );
        if (hwnd && m_defaultFont) {
            SendMessage(hwnd, WM_SETFONT, (WPARAM)m_defaultFont, TRUE);
        }
        return hwnd;
    }

    // 创建编辑框
    HWND createEdit(int x, int y, int width, int height, DWORD id,
        DWORD style = WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL) {
        HWND hwnd = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT", L"",
            style,
            x, y, width, height,
            m_hwnd, (HMENU)(UINT_PTR)id,
            GetModuleHandle(nullptr), nullptr
        );
        if (hwnd && m_defaultFont) {
            SendMessage(hwnd, WM_SETFONT, (WPARAM)m_defaultFont, TRUE);
        }
        return hwnd;
    }

    // 创建密码框
    HWND createPasswordEdit(int x, int y, int width, int height, DWORD id) {
        return createEdit(x, y, width, height, id,
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_PASSWORD);
    }

    // 创建按钮
    HWND createButton(const std::wstring& text, int x, int y, int width, int height, DWORD id,
        DWORD style = WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON) {
        HWND hwnd = CreateWindowExW(
            0, L"BUTTON", text.c_str(),
            style,
            x, y, width, height,
            m_hwnd, (HMENU)(UINT_PTR)id,
            GetModuleHandle(nullptr), nullptr
        );
        if (hwnd && m_defaultFont) {
            SendMessage(hwnd, WM_SETFONT, (WPARAM)m_defaultFont, TRUE);
        }
        return hwnd;
    }

    // 创建复选框
    HWND createCheckBox(const std::wstring& text, int x, int y, int width, int height, DWORD id) {
        return createButton(text, x, y, width, height, id,
            WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX);
    }

    // 创建分组框
    HWND createGroupBox(const std::wstring& text, int x, int y, int width, int height) {
        HWND hwnd = CreateWindowExW(
            0, L"BUTTON", text.c_str(),
            WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
            x, y, width, height,
            m_hwnd, nullptr,
            GetModuleHandle(nullptr), nullptr
        );
        if (hwnd && m_defaultFont) {
            SendMessage(hwnd, WM_SETFONT, (WPARAM)m_defaultFont, TRUE);
        }
        return hwnd;
    }

    // 创建进度条
    HWND createProgressBar(int x, int y, int width, int height) {
        return CreateWindowExW(
            0, PROGRESS_CLASSW, L"",
            WS_CHILD | WS_VISIBLE | PBS_SMOOTH,
            x, y, width, height,
            m_hwnd, nullptr,
            GetModuleHandle(nullptr), nullptr
        );
    }

    // 获取编辑框文本
    std::wstring getEditText(HWND hwndEdit) const {
        int length = GetWindowTextLengthW(hwndEdit);
        if (length == 0) return L"";

        std::wstring text(length + 1, L'\0');
        GetWindowTextW(hwndEdit, &text[0], length + 1);
        text.resize(length);
        return text;
    }

    // 设置编辑框文本
    void setEditText(HWND hwndEdit, const std::wstring& text) {
        SetWindowTextW(hwndEdit, text.c_str());
    }

    // 获取复选框状态
    bool isChecked(HWND hwndCheck) const {
        return SendMessage(hwndCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
    }

    // 设置复选框状态
    void setChecked(HWND hwndCheck, bool checked) {
        SendMessage(hwndCheck, BM_SETCHECK, checked ? BST_CHECKED : BST_UNCHECKED, 0);
    }

private:
    // 静态窗口映射
    static std::map<HWND, BaseWindow*>& getWindowMap() {
        static std::map<HWND, BaseWindow*> map;
        return map;
    }

    // 注册窗口类
    bool registerWindowClass() {
        WNDCLASSEXW wc = { 0 };
        wc.cbSize = sizeof(WNDCLASSEXW);

        // 检查是否已注册
        if (GetClassInfoExW(GetModuleHandle(nullptr), getClassName(), &wc)) {
            return true;
        }

        wc.style = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc = BaseWindow::WndProc;
        wc.cbClsExtra = 0;
        wc.cbWndExtra = 0;
        wc.hInstance = GetModuleHandle(nullptr);
        wc.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
        wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        wc.lpszMenuName = nullptr;
        wc.lpszClassName = getClassName();
        wc.hIconSm = LoadIcon(nullptr, IDI_APPLICATION);

        return RegisterClassExW(&wc) != 0;
    }

    // 静态窗口过程
    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
        BaseWindow* pThis = nullptr;

        if (msg == WM_NCCREATE) {
            CREATESTRUCT* pCreate = (CREATESTRUCT*)lParam;
            pThis = (BaseWindow*)pCreate->lpCreateParams;
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)pThis);
            pThis->m_hwnd = hwnd;
            getWindowMap()[hwnd] = pThis;
        } else {
            pThis = (BaseWindow*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
        }

        if (pThis) {
            return pThis->handleMessage(msg, wParam, lParam);
        }

        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
};

} // namespace haut
