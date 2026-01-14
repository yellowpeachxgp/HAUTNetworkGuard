#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 配置管理 (Windows注册表)
// ============================================================================

#include <Windows.h>
#include <string>
#include "../resource/resource.h"
#include "../utils/StringUtils.h"
#include "../utils/Logger.h"

namespace haut {

class AppConfig {
public:
    // 单例模式
    static AppConfig& instance() {
        static AppConfig instance;
        return instance;
    }

    // 是否已配置
    bool hasConfigured() const {
        return readBool(REG_VALUE_CONFIGURED, false);
    }

    void setConfigured(bool value) {
        writeBool(REG_VALUE_CONFIGURED, value);
    }

    // 是否自动保存
    bool autoSave() const {
        return readBool(REG_VALUE_AUTOSAVE, false);
    }

    void setAutoSave(bool value) {
        writeBool(REG_VALUE_AUTOSAVE, value);
    }

    // 用户名
    std::wstring username() const {
        return readString(REG_VALUE_USERNAME, L"");
    }

    void setUsername(const std::wstring& value) {
        writeString(REG_VALUE_USERNAME, value);
    }

    // 密码（简单混淆存储，非安全加密）
    std::wstring password() const {
        std::wstring encoded = readString(REG_VALUE_PASSWORD, L"");
        return decodePassword(encoded);
    }

    void setPassword(const std::wstring& value) {
        std::wstring encoded = encodePassword(value);
        writeString(REG_VALUE_PASSWORD, encoded);
    }

    // 跳过的版本
    std::wstring skippedVersion() const {
        return readString(REG_VALUE_SKIPPED_VER, L"");
    }

    void setSkippedVersion(const std::wstring& value) {
        writeString(REG_VALUE_SKIPPED_VER, value);
    }

    // 上次更新检查时间
    ULONGLONG lastUpdateCheck() const {
        return readDword(REG_VALUE_LAST_CHECK, 0);
    }

    void setLastUpdateCheck(ULONGLONG value) {
        writeDword(REG_VALUE_LAST_CHECK, static_cast<DWORD>(value));
    }

    // 保存配置
    void save(const std::wstring& username, const std::wstring& password, bool autoSave) {
        setUsername(username);
        setPassword(password);
        setAutoSave(autoSave);
        setConfigured(true);
        Logger::log(L"配置已保存");
    }

    // 清除配置
    void clear() {
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, REG_KEY_PATH, 0, KEY_ALL_ACCESS, &hKey) == ERROR_SUCCESS) {
            RegDeleteValueW(hKey, REG_VALUE_USERNAME);
            RegDeleteValueW(hKey, REG_VALUE_PASSWORD);
            RegDeleteValueW(hKey, REG_VALUE_AUTOSAVE);
            RegDeleteValueW(hKey, REG_VALUE_CONFIGURED);
            RegDeleteValueW(hKey, REG_VALUE_SKIPPED_VER);
            RegDeleteValueW(hKey, REG_VALUE_LAST_CHECK);
            RegCloseKey(hKey);
        }
        Logger::log(L"配置已清除");
    }

private:
    AppConfig() = default;
    ~AppConfig() = default;
    AppConfig(const AppConfig&) = delete;
    AppConfig& operator=(const AppConfig&) = delete;

    // 读取字符串
    std::wstring readString(const wchar_t* name, const std::wstring& defaultValue) const {
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, REG_KEY_PATH, 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
            return defaultValue;
        }

        wchar_t buffer[512];
        DWORD bufferSize = sizeof(buffer);
        DWORD type = REG_SZ;

        LONG result = RegQueryValueExW(hKey, name, nullptr, &type, (LPBYTE)buffer, &bufferSize);
        RegCloseKey(hKey);

        if (result == ERROR_SUCCESS && type == REG_SZ) {
            return buffer;
        }
        return defaultValue;
    }

    // 写入字符串
    void writeString(const wchar_t* name, const std::wstring& value) const {
        HKEY hKey;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, REG_KEY_PATH, 0, nullptr,
            REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) != ERROR_SUCCESS) {
            return;
        }

        RegSetValueExW(hKey, name, 0, REG_SZ,
            (const BYTE*)value.c_str(),
            static_cast<DWORD>((value.length() + 1) * sizeof(wchar_t)));
        RegCloseKey(hKey);
    }

    // 读取布尔值
    bool readBool(const wchar_t* name, bool defaultValue) const {
        return readDword(name, defaultValue ? 1 : 0) != 0;
    }

    // 写入布尔值
    void writeBool(const wchar_t* name, bool value) const {
        writeDword(name, value ? 1 : 0);
    }

    // 读取DWORD
    DWORD readDword(const wchar_t* name, DWORD defaultValue) const {
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, REG_KEY_PATH, 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
            return defaultValue;
        }

        DWORD value = 0;
        DWORD size = sizeof(value);
        DWORD type = REG_DWORD;

        LONG result = RegQueryValueExW(hKey, name, nullptr, &type, (LPBYTE)&value, &size);
        RegCloseKey(hKey);

        if (result == ERROR_SUCCESS && type == REG_DWORD) {
            return value;
        }
        return defaultValue;
    }

    // 写入DWORD
    void writeDword(const wchar_t* name, DWORD value) const {
        HKEY hKey;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, REG_KEY_PATH, 0, nullptr,
            REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) != ERROR_SUCCESS) {
            return;
        }

        RegSetValueExW(hKey, name, 0, REG_DWORD, (const BYTE*)&value, sizeof(value));
        RegCloseKey(hKey);
    }

    // 简单密码混淆（非安全加密，仅防止明文显示）
    std::wstring encodePassword(const std::wstring& password) const {
        std::wstring encoded;
        for (wchar_t c : password) {
            encoded += static_cast<wchar_t>(c ^ 0x5A);
        }
        return encoded;
    }

    std::wstring decodePassword(const std::wstring& encoded) const {
        std::wstring decoded;
        for (wchar_t c : encoded) {
            decoded += static_cast<wchar_t>(c ^ 0x5A);
        }
        return decoded;
    }
};

} // namespace haut
