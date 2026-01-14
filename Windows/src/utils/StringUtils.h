#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 字符串工具类
// ============================================================================

#include <Windows.h>
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <cstdint>

namespace haut {

class StringUtils {
public:
    // UTF-8 转 宽字符
    static std::wstring utf8ToWide(const std::string& str) {
        if (str.empty()) return L"";

        int size = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
        if (size <= 0) return L"";

        std::wstring result(size - 1, L'\0');
        MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, &result[0], size);
        return result;
    }

    // 宽字符 转 UTF-8
    static std::string wideToUtf8(const std::wstring& str) {
        if (str.empty()) return "";

        int size = WideCharToMultiByte(CP_UTF8, 0, str.c_str(), -1, nullptr, 0, nullptr, nullptr);
        if (size <= 0) return "";

        std::string result(size - 1, '\0');
        WideCharToMultiByte(CP_UTF8, 0, str.c_str(), -1, &result[0], size, nullptr, nullptr);
        return result;
    }

    // ANSI 转 宽字符
    static std::wstring ansiToWide(const std::string& str) {
        if (str.empty()) return L"";

        int size = MultiByteToWideChar(CP_ACP, 0, str.c_str(), -1, nullptr, 0);
        if (size <= 0) return L"";

        std::wstring result(size - 1, L'\0');
        MultiByteToWideChar(CP_ACP, 0, str.c_str(), -1, &result[0], size);
        return result;
    }

    // 宽字符 转 ANSI
    static std::string wideToAnsi(const std::wstring& str) {
        if (str.empty()) return "";

        int size = WideCharToMultiByte(CP_ACP, 0, str.c_str(), -1, nullptr, 0, nullptr, nullptr);
        if (size <= 0) return "";

        std::string result(size - 1, '\0');
        WideCharToMultiByte(CP_ACP, 0, str.c_str(), -1, &result[0], size, nullptr, nullptr);
        return result;
    }

    // 字符串分割
    static std::vector<std::string> split(const std::string& str, char delimiter) {
        std::vector<std::string> result;
        std::stringstream ss(str);
        std::string item;
        while (std::getline(ss, item, delimiter)) {
            result.push_back(item);
        }
        return result;
    }

    static std::vector<std::wstring> split(const std::wstring& str, wchar_t delimiter) {
        std::vector<std::wstring> result;
        std::wstringstream ss(str);
        std::wstring item;
        while (std::getline(ss, item, delimiter)) {
            result.push_back(item);
        }
        return result;
    }

    // 去除首尾空白
    static std::string trim(const std::string& str) {
        size_t start = str.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) return "";
        size_t end = str.find_last_not_of(" \t\r\n");
        return str.substr(start, end - start + 1);
    }

    static std::wstring trim(const std::wstring& str) {
        size_t start = str.find_first_not_of(L" \t\r\n");
        if (start == std::wstring::npos) return L"";
        size_t end = str.find_last_not_of(L" \t\r\n");
        return str.substr(start, end - start + 1);
    }

    // 字节格式化 (如 2.45 GB)
    static std::wstring formatBytes(int64_t bytes) {
        const wchar_t* units[] = { L"B", L"KB", L"MB", L"GB", L"TB" };
        int unitIndex = 0;
        double size = static_cast<double>(bytes);

        while (size >= 1024.0 && unitIndex < 4) {
            size /= 1024.0;
            unitIndex++;
        }

        wchar_t buffer[64];
        if (unitIndex == 0) {
            swprintf_s(buffer, L"%.0f %s", size, units[unitIndex]);
        } else {
            swprintf_s(buffer, L"%.2f %s", size, units[unitIndex]);
        }
        return buffer;
    }

    // 时长格式化 (如 3小时25分18秒)
    static std::wstring formatDuration(int64_t seconds) {
        int64_t hours = seconds / 3600;
        int64_t minutes = (seconds % 3600) / 60;
        int64_t secs = seconds % 60;

        wchar_t buffer[64];
        if (hours > 0) {
            swprintf_s(buffer, L"%lld小时%lld分%lld秒", hours, minutes, secs);
        } else if (minutes > 0) {
            swprintf_s(buffer, L"%lld分%lld秒", minutes, secs);
        } else {
            swprintf_s(buffer, L"%lld秒", secs);
        }
        return buffer;
    }

    // 获取当前时间字符串
    static std::wstring getCurrentTimeString() {
        SYSTEMTIME st;
        GetLocalTime(&st);

        wchar_t buffer[64];
        swprintf_s(buffer, L"%04d-%02d-%02d %02d:%02d:%02d",
            st.wYear, st.wMonth, st.wDay,
            st.wHour, st.wMinute, st.wSecond);
        return buffer;
    }

    // 字符串替换
    static std::string replace(const std::string& str, const std::string& from, const std::string& to) {
        std::string result = str;
        size_t pos = 0;
        while ((pos = result.find(from, pos)) != std::string::npos) {
            result.replace(pos, from.length(), to);
            pos += to.length();
        }
        return result;
    }

    static std::wstring replace(const std::wstring& str, const std::wstring& from, const std::wstring& to) {
        std::wstring result = str;
        size_t pos = 0;
        while ((pos = result.find(from, pos)) != std::wstring::npos) {
            result.replace(pos, from.length(), to);
            pos += to.length();
        }
        return result;
    }
};

} // namespace haut
