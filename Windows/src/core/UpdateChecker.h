#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 更新检测器
// ============================================================================

#include <Windows.h>
#include <string>
#include <functional>
#include <thread>
#include <ctime>
#include "NetworkStatus.h"
#include "../utils/HttpClient.h"
#include "../utils/StringUtils.h"
#include "../utils/Logger.h"
#include "../config/AppConfig.h"
#include "../resource/resource.h"

namespace haut {

using UpdateCallback = std::function<void(const ReleaseInfo&)>;

class UpdateChecker {
public:
    // 单例模式
    static UpdateChecker& instance() {
        static UpdateChecker instance;
        return instance;
    }

    // 检查更新（异步）
    void checkForUpdate(bool force, UpdateCallback callback) {
        // 检查是否需要检查更新
        if (!force) {
            ULONGLONG lastCheck = AppConfig::instance().lastUpdateCheck();
            ULONGLONG now = GetTickCount64();

            // 如果距离上次检查不足24小时，跳过
            if (lastCheck > 0 && (now - lastCheck) < UPDATE_CHECK_INTERVAL) {
                Logger::log(L"距离上次检查更新不足24小时，跳过");
                return;
            }
        }

        std::thread([this, force, callback]() {
            ReleaseInfo info = checkForUpdateSync();

            if (info.isValid()) {
                // 检查是否跳过此版本
                std::wstring skipped = AppConfig::instance().skippedVersion();
                if (!force && info.version == skipped) {
                    Logger::log(L"版本 " + info.version + L" 已被跳过");
                    return;
                }

                // 检查是否为新版本
                if (isNewerVersion(info.version, APP_VERSION)) {
                    Logger::log(L"发现新版本: " + info.version);
                    if (callback) {
                        callback(info);
                    }
                } else {
                    Logger::log(L"当前已是最新版本");
                }
            }

            // 更新检查时间
            AppConfig::instance().setLastUpdateCheck(GetTickCount64());

        }).detach();
    }

    // 跳过版本
    void skipVersion(const std::wstring& version) {
        AppConfig::instance().setSkippedVersion(version);
        Logger::log(L"已跳过版本: " + version);
    }

private:
    UpdateChecker() = default;
    ~UpdateChecker() = default;
    UpdateChecker(const UpdateChecker&) = delete;
    UpdateChecker& operator=(const UpdateChecker&) = delete;

    HttpClient m_httpClient;

    // 同步检查更新
    ReleaseInfo checkForUpdateSync() {
        ReleaseInfo info;

        Logger::log(L"正在检查更新...");
        HttpResponse response = m_httpClient.get(GITHUB_API_URL);

        if (!response.success) {
            Logger::error(L"检查更新失败: " + response.errorMessage);
            return info;
        }

        // 解析JSON响应
        info = parseReleaseJson(response.body);
        return info;
    }

    // 简单的JSON解析（不使用第三方库）
    ReleaseInfo parseReleaseJson(const std::string& json) {
        ReleaseInfo info;

        // 提取 tag_name (版本号)
        info.version = extractJsonString(json, "tag_name");
        // 去除 "v" 前缀
        if (!info.version.empty() && info.version[0] == L'v') {
            info.version = info.version.substr(1);
        }

        // 提取 body (更新说明)
        info.releaseNotes = extractJsonString(json, "body");

        // 提取 html_url (发布页面)
        info.htmlUrl = extractJsonString(json, "html_url");

        // 提取 published_at (发布时间)
        info.publishedAt = extractJsonString(json, "published_at");

        // 尝试从 assets 中提取下载链接
        size_t assetsStart = json.find("\"assets\"");
        if (assetsStart != std::string::npos) {
            size_t assetsEnd = json.find(']', assetsStart);
            if (assetsEnd != std::string::npos) {
                std::string assets = json.substr(assetsStart, assetsEnd - assetsStart);

                // 查找 .exe 或 .zip 下载链接
                std::wstring downloadUrl = extractJsonString(assets, "browser_download_url");
                if (!downloadUrl.empty()) {
                    info.downloadUrl = downloadUrl;
                }
            }
        }

        return info;
    }

    // 从JSON中提取字符串值
    std::wstring extractJsonString(const std::string& json, const std::string& key) {
        std::string searchKey = "\"" + key + "\"";
        size_t keyPos = json.find(searchKey);
        if (keyPos == std::string::npos) return L"";

        size_t colonPos = json.find(':', keyPos + searchKey.length());
        if (colonPos == std::string::npos) return L"";

        // 跳过空白
        size_t valueStart = colonPos + 1;
        while (valueStart < json.length() && (json[valueStart] == ' ' || json[valueStart] == '\t')) {
            valueStart++;
        }

        if (valueStart >= json.length() || json[valueStart] != '"') return L"";

        valueStart++; // 跳过开始的引号

        // 查找结束引号（处理转义）
        std::string value;
        bool escaped = false;
        for (size_t i = valueStart; i < json.length(); i++) {
            char c = json[i];
            if (escaped) {
                switch (c) {
                case 'n': value += '\n'; break;
                case 'r': value += '\r'; break;
                case 't': value += '\t'; break;
                case '"': value += '"'; break;
                case '\\': value += '\\'; break;
                default: value += c; break;
                }
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                break;
            } else {
                value += c;
            }
        }

        return StringUtils::utf8ToWide(value);
    }

    // 版本比较
    bool isNewerVersion(const std::wstring& newVersion, const std::wstring& currentVersion) {
        auto parseVersion = [](const std::wstring& ver) -> std::vector<int> {
            std::vector<int> parts;
            std::wstring num;
            for (wchar_t c : ver) {
                if (c >= L'0' && c <= L'9') {
                    num += c;
                } else if (!num.empty()) {
                    parts.push_back(std::stoi(num));
                    num.clear();
                }
            }
            if (!num.empty()) {
                parts.push_back(std::stoi(num));
            }
            return parts;
        };

        auto newParts = parseVersion(newVersion);
        auto curParts = parseVersion(currentVersion);

        // 补齐长度
        while (newParts.size() < curParts.size()) newParts.push_back(0);
        while (curParts.size() < newParts.size()) curParts.push_back(0);

        // 逐位比较
        for (size_t i = 0; i < newParts.size(); i++) {
            if (newParts[i] > curParts[i]) return true;
            if (newParts[i] < curParts[i]) return false;
        }

        return false;
    }
};

} // namespace haut
