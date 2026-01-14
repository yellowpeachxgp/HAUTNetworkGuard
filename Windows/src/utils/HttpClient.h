#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// HTTP客户端 (WinHTTP封装)
// ============================================================================

#include <Windows.h>
#include <winhttp.h>
#include <string>
#include <functional>
#include <memory>

#pragma comment(lib, "winhttp.lib")

namespace haut {

// HTTP响应结构
struct HttpResponse {
    bool success = false;
    int statusCode = 0;
    std::string body;
    std::wstring errorMessage;
};

// HTTP请求回调
using HttpCallback = std::function<void(const HttpResponse&)>;

class HttpClient {
public:
    HttpClient() {
        m_hSession = WinHttpOpen(
            L"HAUTNetworkGuard/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME,
            WINHTTP_NO_PROXY_BYPASS,
            0
        );

        if (m_hSession) {
            // 设置超时
            DWORD timeout = 10000; // 10秒
            WinHttpSetOption(m_hSession, WINHTTP_OPTION_CONNECT_TIMEOUT, &timeout, sizeof(timeout));
            WinHttpSetOption(m_hSession, WINHTTP_OPTION_SEND_TIMEOUT, &timeout, sizeof(timeout));
            WinHttpSetOption(m_hSession, WINHTTP_OPTION_RECEIVE_TIMEOUT, &timeout, sizeof(timeout));
        }
    }

    ~HttpClient() {
        if (m_hSession) {
            WinHttpCloseHandle(m_hSession);
        }
    }

    // 禁止拷贝
    HttpClient(const HttpClient&) = delete;
    HttpClient& operator=(const HttpClient&) = delete;

    // 同步GET请求
    HttpResponse get(const std::string& url) {
        return request(L"GET", url, "");
    }

    // 同步POST请求
    HttpResponse post(const std::string& url, const std::string& body) {
        return request(L"POST", url, body);
    }

    // 异步GET请求
    void getAsync(const std::string& url, HttpCallback callback) {
        std::thread([this, url, callback]() {
            HttpResponse response = get(url);
            if (callback) {
                callback(response);
            }
        }).detach();
    }

    // 异步POST请求
    void postAsync(const std::string& url, const std::string& body, HttpCallback callback) {
        std::thread([this, url, body, callback]() {
            HttpResponse response = post(url, body);
            if (callback) {
                callback(response);
            }
        }).detach();
    }

private:
    HINTERNET m_hSession = nullptr;

    // 解析URL
    struct UrlComponents {
        std::wstring host;
        std::wstring path;
        INTERNET_PORT port = INTERNET_DEFAULT_HTTP_PORT;
        bool isHttps = false;
    };

    UrlComponents parseUrl(const std::string& url) {
        UrlComponents components;

        // 转换为宽字符
        std::wstring wurl(url.begin(), url.end());

        URL_COMPONENTS urlComp = { 0 };
        urlComp.dwStructSize = sizeof(urlComp);

        wchar_t hostBuffer[256] = { 0 };
        wchar_t pathBuffer[1024] = { 0 };

        urlComp.lpszHostName = hostBuffer;
        urlComp.dwHostNameLength = 256;
        urlComp.lpszUrlPath = pathBuffer;
        urlComp.dwUrlPathLength = 1024;

        if (WinHttpCrackUrl(wurl.c_str(), 0, 0, &urlComp)) {
            components.host = hostBuffer;
            components.path = pathBuffer;
            components.port = urlComp.nPort;
            components.isHttps = (urlComp.nScheme == INTERNET_SCHEME_HTTPS);
        }

        if (components.path.empty()) {
            components.path = L"/";
        }

        return components;
    }

    // 发送请求
    HttpResponse request(const wchar_t* method, const std::string& url, const std::string& body) {
        HttpResponse response;

        if (!m_hSession) {
            response.errorMessage = L"HTTP会话未初始化";
            return response;
        }

        auto urlComp = parseUrl(url);
        if (urlComp.host.empty()) {
            response.errorMessage = L"URL解析失败";
            return response;
        }

        // 连接
        HINTERNET hConnect = WinHttpConnect(m_hSession, urlComp.host.c_str(), urlComp.port, 0);
        if (!hConnect) {
            response.errorMessage = L"连接失败";
            return response;
        }

        // 创建请求
        DWORD flags = urlComp.isHttps ? WINHTTP_FLAG_SECURE : 0;
        HINTERNET hRequest = WinHttpOpenRequest(
            hConnect,
            method,
            urlComp.path.c_str(),
            nullptr,
            WINHTTP_NO_REFERER,
            WINHTTP_DEFAULT_ACCEPT_TYPES,
            flags
        );

        if (!hRequest) {
            WinHttpCloseHandle(hConnect);
            response.errorMessage = L"创建请求失败";
            return response;
        }

        // 设置POST请求头
        if (wcscmp(method, L"POST") == 0 && !body.empty()) {
            WinHttpAddRequestHeaders(
                hRequest,
                L"Content-Type: application/x-www-form-urlencoded",
                -1,
                WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE
            );
        }

        // 发送请求
        BOOL result = WinHttpSendRequest(
            hRequest,
            WINHTTP_NO_ADDITIONAL_HEADERS,
            0,
            body.empty() ? WINHTTP_NO_REQUEST_DATA : (LPVOID)body.c_str(),
            body.empty() ? 0 : static_cast<DWORD>(body.length()),
            body.empty() ? 0 : static_cast<DWORD>(body.length()),
            0
        );

        if (!result) {
            WinHttpCloseHandle(hRequest);
            WinHttpCloseHandle(hConnect);
            response.errorMessage = L"发送请求失败";
            return response;
        }

        // 接收响应
        result = WinHttpReceiveResponse(hRequest, nullptr);
        if (!result) {
            WinHttpCloseHandle(hRequest);
            WinHttpCloseHandle(hConnect);
            response.errorMessage = L"接收响应失败";
            return response;
        }

        // 获取状态码
        DWORD statusCode = 0;
        DWORD size = sizeof(statusCode);
        WinHttpQueryHeaders(
            hRequest,
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX,
            &statusCode,
            &size,
            WINHTTP_NO_HEADER_INDEX
        );
        response.statusCode = statusCode;

        // 读取响应体
        std::string responseBody;
        DWORD bytesAvailable = 0;
        DWORD bytesRead = 0;
        char buffer[4096];

        while (WinHttpQueryDataAvailable(hRequest, &bytesAvailable) && bytesAvailable > 0) {
            DWORD toRead = min(bytesAvailable, sizeof(buffer) - 1);
            if (WinHttpReadData(hRequest, buffer, toRead, &bytesRead)) {
                buffer[bytesRead] = '\0';
                responseBody.append(buffer, bytesRead);
            } else {
                break;
            }
        }

        response.body = responseBody;
        response.success = (statusCode >= 200 && statusCode < 300);

        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);

        return response;
    }
};

} // namespace haut
