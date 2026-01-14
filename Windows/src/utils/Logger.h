#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 日志工具类
// ============================================================================

#include <Windows.h>
#include <string>
#include <cstdio>
#include "StringUtils.h"

namespace haut {

class Logger {
public:
    static bool isEnabled;

    static void log(const std::wstring& message) {
        if (!isEnabled) return;

        SYSTEMTIME st;
        GetLocalTime(&st);

        wchar_t buffer[1024];
        swprintf_s(buffer, L"[%02d:%02d:%02d] %s\n",
            st.wHour, st.wMinute, st.wSecond, message.c_str());

        OutputDebugStringW(buffer);

#ifdef _DEBUG
        wprintf(L"%s", buffer);
#endif
    }

    static void log(const std::string& message) {
        log(StringUtils::utf8ToWide(message));
    }

    static void log(const char* message) {
        log(std::string(message));
    }

    static void log(const wchar_t* message) {
        log(std::wstring(message));
    }

    // 格式化日志
    template<typename... Args>
    static void logf(const wchar_t* format, Args... args) {
        wchar_t buffer[1024];
        swprintf_s(buffer, format, args...);
        log(buffer);
    }

    // 错误日志
    static void error(const std::wstring& message) {
        log(L"[错误] " + message);
    }

    static void error(const std::string& message) {
        error(StringUtils::utf8ToWide(message));
    }

    // 获取Windows错误信息
    static std::wstring getLastErrorString() {
        DWORD errorCode = GetLastError();
        if (errorCode == 0) return L"";

        LPWSTR buffer = nullptr;
        FormatMessageW(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            nullptr,
            errorCode,
            MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
            (LPWSTR)&buffer,
            0,
            nullptr
        );

        std::wstring message;
        if (buffer) {
            message = buffer;
            LocalFree(buffer);
            // 去除换行
            while (!message.empty() && (message.back() == L'\n' || message.back() == L'\r')) {
                message.pop_back();
            }
        }
        return message;
    }
};

// 静态成员初始化
inline bool Logger::isEnabled = true;

} // namespace haut
