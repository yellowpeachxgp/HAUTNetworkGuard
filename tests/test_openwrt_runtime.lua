-- 执行真实 api/main 模块，替换边界 I/O；不访问校园网、UCI 或系统服务。
package.path = "OpenWrt/files/usr/lib/haut-network-guard/?.lua;" .. package.path

local messages, files = {}, {}
local response_body = ""
local curl_exit = 0
local http_status = "200"
local interval = "30"
local last_post_body = ""
local function record(value) messages[#messages + 1] = tostring(value) end
package.loaded.log = {
    info = record, warn = record, error = record, debug = record,
    refresh_level = function() end,
    mask_username = function() return "st***er" end,
    preview = tostring,
    bytes_summary = function(value) return tostring(#value) .. " bytes" end
}

io.open = function(path, mode)
    if mode == "w" or mode == "wb" then
        files[path] = ""
        return {
            write = function(_, value) files[path] = value; last_post_body = value; return true end,
            close = function() return true end
        }
    end
    if files[path] then
        return { read = function() return files[path] end, close = function() end }
    end
    return nil
end
os.remove = function(path) files[path] = nil; return true end
local stop = {}
os.execute = function(command)
    if command:find("^chmod 600 ") then return true end
    assert(command:find("^sleep "), "不得执行系统命令")
    error(stop)
end
io.popen = function(command)
    local output
    if command:find("^curl ") then
        output = response_body .. "\n__HAUT_CURL_META__:" .. http_status .. ":0.0125\n__HAUT_CURL_EXIT__:" .. curl_exit .. "\n"
    elseif command:find("^uci ") then
        local key = command:match("haut%-network%-guard%.main%.(%w+)")
        output = ({ username = "student-user", password = "test-only", interval = interval,
                    enabled = "1", log_level = "info" })[key] or ""
    else
        error("未预期的外部命令")
    end
    return { read = function() return output end, close = function() return true end }
end

local api = require("api")
local function check(condition, message)
    assert(condition, message)
end

response_body = "student-user,321,10.10.0.8,512,0,0"
local parsed, class = api.get_user_info("regression")
check(parsed and class == "online_csv", "整数状态字段应正常解析")
check(parsed.bytes == 512 and parsed.seconds == 321, "整数状态字段结果不匹配")
response_body = "student-user,321.5,10.10.0.8,512.5,0,0"
local fractional, fractional_class = api.get_user_info("regression")
check(fractional == nil and fractional_class == "unparsed", "CSV 小数指标应在三端统一判为异常")

response_body = "login_ok"
local success = api.login("student-user", "test-only")
check(success, "登录成功链路失败")
check(last_post_body:find("username=%%7BSRUN3%%7D%%0D%%0A"), "SRUN3K 前缀和换行必须 URL 编码")
check(not last_post_body:find("{MD5}", 1, true), "不能重新引入旧协议字段")
response_body = "logout_ok"
check(api.logout(), "注销成功链路失败")
response_body = 'jQuery_123({"error" : "ok", "user_name" : "student-user", "online_ip" : "10.10.0.8", "sum_bytes" : "512", "sum_seconds" : "321"})'
local spaced = api.get_user_info("regression")
check(spaced and spaced.bytes == 512 and spaced.seconds == 321, "JSON 空格和字符串数值兼容性回归")
response_body = "not_online"
local offline, offline_class = api.get_user_info("regression")
check(offline == nil and offline_class == "offline", "离线分类回归")
response_body = "   "
local empty, empty_class = api.get_user_info("regression")
check(empty == nil and empty_class == "unparsed", "空状态响应不得误判离线")
response_body = "invalid body"
local invalid, invalid_class = api.get_user_info("regression")
check(invalid == nil and invalid_class == "unparsed", "异常响应分类回归")
curl_exit = 7
local unavailable, unavailable_class = api.get_user_info("regression")
check(unavailable == nil and unavailable_class == "curl_exit_7", "连接失败不得误判离线，并应保留 curl 错误")
curl_exit = 0

-- 错误状态码正文伪装为成功或离线时，不得继续驱动认证状态机。
for _, code in ipairs({"000", "302", "403", "503"}) do
    http_status = code
    response_body = "not_online"
    local value, category = api.get_user_info("regression")
    check(value == nil and category == "http_status_" .. code,
          "HTTP 异常不能被解析为离线：" .. code)
    response_body = "login_ok"
    local ok, message, category = api.login("student-user", "test-only")
    check(not ok and category == "network_error" and
          message == "校园网网关返回异常，请稍后重试。",
          "HTTP 异常不能被解析为登录成功：" .. code)
    response_body = "logout_ok"
    check(not api.logout(), "HTTP 异常不能被解析为注销成功：" .. code)
end
http_status = "200"
curl_exit = 28
local timed_out, timeout_message = api.login("student-user", "test-only")
check(not timed_out and timeout_message ==
      "连接校园网网关超时，请确认已连接 Wi-Fi 或有线网络后重试。", "超时应给出处理建议")
curl_exit = 7
local connected, connect_message = api.logout()
check(not connected and connect_message == "无法连接校园网网关，请检查网络连接后重试。",
      "连接失败应给出与桌面端一致的处理建议")
curl_exit = 0

-- PR #3 的浮点格式修复仍需防御 API 之外的异常调用，直接回放 main 的格式化边界。
api.get_user_info = function()
    return { username = "student-user", ip = "10.10.0.8", bytes = 512.5, seconds = 59.8 }, "online_csv"
end
for _, seconds in ipairs({0.5, 59.8, 61.5, 3601.5}) do
    response_body = "student-user," .. seconds .. ",10.10.0.8,512.5,0,0"
    local ok, result = pcall(dofile, "OpenWrt/files/usr/lib/haut-network-guard/main.lua")
    check(not ok and result == stop, "守护循环格式化小数流量/时长时崩溃：" .. tostring(result))
end
interval = "30.5"
response_body = "student-user,59.8,10.10.0.8,512.5,0,0"
local ok, result = pcall(dofile, "OpenWrt/files/usr/lib/haut-network-guard/main.lua")
check(not ok and result == stop, "小数 UCI 检测间隔不得使日志格式化崩溃")
local all_messages = table.concat(messages, "\n")
check(all_messages:find("时长=59秒", 1, true), "时长应先截断再分解，不能显示 60 秒余数")
check(all_messages:find("interval=30 ", 1, true), "UCI 检测间隔应统一为整数秒")

check(next(files) == nil, "认证临时文件必须清理")
print("OpenWrt 请求与守护循环行为测试通过：" .. _VERSION)
