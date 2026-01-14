// ============================================================================
// HAUT Network Guard - Windows
// 应用入口
// ============================================================================

#include <Windows.h>
#include <commctrl.h>
#include "Application.h"

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "advapi32.lib")

// 启用视觉样式
#pragma comment(linker, "\"/manifestdependency:type='win32' \
    name='Microsoft.Windows.Common-Controls' version='6.0.0.0' \
    processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

int WINAPI wWinMain(
    _In_ HINSTANCE hInstance,
    _In_opt_ HINSTANCE hPrevInstance,
    _In_ LPWSTR lpCmdLine,
    _In_ int nShowCmd
) {
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);
    UNREFERENCED_PARAMETER(nShowCmd);

    // 防止多实例运行
    HANDLE hMutex = CreateMutexW(NULL, TRUE, L"HAUTNetworkGuard_SingleInstance_Mutex");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        MessageBoxW(NULL, L"HAUT Network Guard 已在运行中！\n\n请检查系统托盘区域。",
            L"提示", MB_ICONINFORMATION | MB_OK);
        if (hMutex) {
            CloseHandle(hMutex);
        }
        return 0;
    }

    // 初始化 COM
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(hr)) {
        MessageBoxW(NULL, L"COM 初始化失败", L"错误", MB_ICONERROR);
        ReleaseMutex(hMutex);
        CloseHandle(hMutex);
        return 1;
    }

    // 初始化通用控件
    INITCOMMONCONTROLSEX icc = { 0 };
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_STANDARD_CLASSES | ICC_PROGRESS_CLASS | ICC_WIN95_CLASSES;
    InitCommonControlsEx(&icc);

    // 初始化应用
    auto& app = haut::Application::instance();
    if (!app.initialize(hInstance)) {
        MessageBoxW(NULL, L"应用初始化失败", L"错误", MB_ICONERROR);
        CoUninitialize();
        ReleaseMutex(hMutex);
        CloseHandle(hMutex);
        return 1;
    }

    // 运行消息循环
    int result = app.run();

    // 清理
    CoUninitialize();
    ReleaseMutex(hMutex);
    CloseHandle(hMutex);

    return result;
}
