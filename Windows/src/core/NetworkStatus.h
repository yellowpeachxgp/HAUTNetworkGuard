#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 网络状态数据结构
// ============================================================================

#include <string>
#include <cstdint>

namespace haut {

// 网络状态枚举
enum class NetworkState {
    Online,     // 在线
    Offline,    // 离线
    Checking,   // 检测中
    Error       // 错误
};

// 网络状态详情
struct NetworkStatus {
    NetworkState state = NetworkState::Checking;
    std::wstring username;          // 用户名
    std::wstring ipAddress;         // IP地址
    int64_t usedBytes = 0;          // 已用流量（字节）
    int64_t onlineSeconds = 0;      // 在线时长（秒）
    std::wstring errorMessage;      // 错误信息

    // 是否在线
    bool isOnline() const {
        return state == NetworkState::Online;
    }

    // 获取状态文本
    std::wstring getStateText() const {
        switch (state) {
        case NetworkState::Online:
            return L"已连接";
        case NetworkState::Offline:
            return L"未连接";
        case NetworkState::Checking:
            return L"检测中...";
        case NetworkState::Error:
            return L"错误: " + errorMessage;
        default:
            return L"未知";
        }
    }
};

// 登录结果枚举
enum class LoginResultType {
    Success,        // 成功
    AlreadyOnline,  // 已经在线
    Failed          // 失败
};

// 登录响应
struct LoginResponse {
    LoginResultType result = LoginResultType::Failed;
    std::wstring message;

    bool isSuccess() const {
        return result == LoginResultType::Success || result == LoginResultType::AlreadyOnline;
    }
};

// 版本发布信息
struct ReleaseInfo {
    std::wstring version;           // 版本号
    std::wstring releaseNotes;      // 更新说明
    std::wstring downloadUrl;       // 下载链接 (DMG/EXE)
    std::wstring htmlUrl;           // 发布页面链接
    std::wstring publishedAt;       // 发布时间

    bool isValid() const {
        return !version.empty();
    }
};

} // namespace haut
