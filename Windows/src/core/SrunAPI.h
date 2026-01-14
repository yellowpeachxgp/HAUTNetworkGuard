#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// SRUN API 封装
// ============================================================================

#include <Windows.h>
#include <string>
#include <functional>
#include <thread>
#include "NetworkStatus.h"
#include "SrunEncryption.h"
#include "../utils/HttpClient.h"
#include "../utils/StringUtils.h"
#include "../utils/Logger.h"
#include "../resource/resource.h"

namespace haut {

// 状态检测回调
using StatusCallback = std::function<void(const NetworkStatus&)>;
// 登录回调
using LoginCallback = std::function<void(const LoginResponse&)>;

class SrunAPI {
public:
    SrunAPI() = default;
    ~SrunAPI() = default;

    // 检查网络状态（异步）
    void checkStatus(StatusCallback callback) {
        std::thread([this, callback]() {
            NetworkStatus status = checkStatusSync();
            if (callback) {
                callback(status);
            }
        }).detach();
    }

    // 检查网络状态（同步）
    NetworkStatus checkStatusSync() {
        NetworkStatus status;
        status.state = NetworkState::Checking;

        HttpResponse response = m_httpClient.get(STATUS_URL);

        if (!response.success) {
            status.state = NetworkState::Error;
            status.errorMessage = L"网络请求失败";
            Logger::log(L"状态检测失败: " + response.errorMessage);
            return status;
        }

        return parseStatusResponse(response.body);
    }

    // 登录（异步）
    void login(const std::string& username, const std::string& password, LoginCallback callback) {
        std::thread([this, username, password, callback]() {
            LoginResponse response = loginSync(username, password);
            if (callback) {
                callback(response);
            }
        }).detach();
    }

    // 登录（同步）
    LoginResponse loginSync(const std::string& username, const std::string& password) {
        LoginResponse result;

        // 加密用户名和密码
        std::string encryptedUsername = SrunEncryption::encryptUsername(username);
        std::string encryptedPassword = SrunEncryption::encryptPassword(password);

        // URL编码
        std::string encodedUsername = SrunEncryption::urlEncode(encryptedUsername);

        Logger::log(L"开始登录...");
        Logger::log(L"加密用户名: " + StringUtils::utf8ToWide(encodedUsername));

        // 构建请求参数
        std::string body = buildLoginParams(encodedUsername, encryptedPassword);

        // 发送请求
        HttpResponse response = m_httpClient.post(LOGIN_URL, body);

        if (!response.success) {
            result.result = LoginResultType::Failed;
            result.message = L"网络请求失败";
            Logger::log(L"登录请求失败: " + response.errorMessage);
            return result;
        }

        return parseLoginResponse(response.body);
    }

    // 注销（异步）
    void logout(const std::string& username, LoginCallback callback) {
        std::thread([this, username, callback]() {
            LoginResponse response = logoutSync(username);
            if (callback) {
                callback(response);
            }
        }).detach();
    }

    // 注销（同步）
    LoginResponse logoutSync(const std::string& username) {
        LoginResponse result;

        // 加密用户名
        std::string encryptedUsername = SrunEncryption::encryptUsername(username);
        std::string encodedUsername = SrunEncryption::urlEncode(encryptedUsername);

        Logger::log(L"开始注销...");

        // 构建请求参数
        std::string body = buildLogoutParams(encodedUsername);

        // 发送请求
        HttpResponse response = m_httpClient.post(LOGIN_URL, body);

        if (!response.success) {
            result.result = LoginResultType::Failed;
            result.message = L"网络请求失败";
            Logger::log(L"注销请求失败: " + response.errorMessage);
            return result;
        }

        return parseLogoutResponse(response.body);
    }

private:
    HttpClient m_httpClient;

    // 构建登录参数
    std::string buildLoginParams(const std::string& encodedUsername, const std::string& password) {
        std::string params;
        params += "action=login";
        params += "&username=" + encodedUsername;
        params += "&password=" + password;
        params += "&ac_id=" AC_ID;
        params += "&drop=0";
        params += "&pop=1";
        params += "&type=10";
        params += "&n=117";
        params += "&mbytes=0";
        params += "&minutes=0";
        params += "&mac=02:00:00:00:00:00";
        return params;
    }

    // 构建注销参数
    std::string buildLogoutParams(const std::string& encodedUsername) {
        std::string params;
        params += "action=logout";
        params += "&username=" + encodedUsername;
        params += "&ac_id=" AC_ID;
        params += "&type=10";
        return params;
    }

    // 解析状态响应
    // 响应格式: username,time,ip,bytes,...
    NetworkStatus parseStatusResponse(const std::string& response) {
        NetworkStatus status;

        std::string trimmed = StringUtils::trim(response);

        if (trimmed.empty() || trimmed.find("not_online") != std::string::npos) {
            status.state = NetworkState::Offline;
            Logger::log(L"状态: 离线");
            return status;
        }

        auto parts = StringUtils::split(trimmed, ',');

        if (parts.size() >= 4) {
            status.state = NetworkState::Online;
            status.username = StringUtils::utf8ToWide(parts[0]);
            status.onlineSeconds = std::stoll(parts[1]);
            status.ipAddress = StringUtils::utf8ToWide(parts[2]);
            status.usedBytes = std::stoll(parts[3]);

            Logger::logf(L"状态: 在线 | 用户: %s | IP: %s | 流量: %s | 时长: %s",
                status.username.c_str(),
                status.ipAddress.c_str(),
                StringUtils::formatBytes(status.usedBytes).c_str(),
                StringUtils::formatDuration(status.onlineSeconds).c_str());
        } else {
            status.state = NetworkState::Offline;
            Logger::log(L"状态响应解析失败，判定为离线");
        }

        return status;
    }

    // 解析登录响应
    LoginResponse parseLoginResponse(const std::string& response) {
        LoginResponse result;

        Logger::log(L"登录响应: " + StringUtils::utf8ToWide(response));

        if (response.find("login_ok") != std::string::npos) {
            result.result = LoginResultType::Success;
            result.message = L"登录成功";
            Logger::log(L"登录成功");
        } else if (response.find("already_online") != std::string::npos) {
            result.result = LoginResultType::AlreadyOnline;
            result.message = L"已经在线";
            Logger::log(L"已经在线");
        } else {
            result.result = LoginResultType::Failed;
            result.message = StringUtils::utf8ToWide(response);
            Logger::log(L"登录失败: " + result.message);
        }

        return result;
    }

    // 解析注销响应
    LoginResponse parseLogoutResponse(const std::string& response) {
        LoginResponse result;

        Logger::log(L"注销响应: " + StringUtils::utf8ToWide(response));

        if (response.find("logout_ok") != std::string::npos) {
            result.result = LoginResultType::Success;
            result.message = L"注销成功";
            Logger::log(L"注销成功");
        } else {
            result.result = LoginResultType::Failed;
            result.message = StringUtils::utf8ToWide(response);
            Logger::log(L"注销失败: " + result.message);
        }

        return result;
    }
};

} // namespace haut
