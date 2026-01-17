#!/usr/bin/lua
-- HAUT Network Guard - API 模块
-- 处理网络请求和认证

local api = {}
local crypto = require("crypto")

-- 配置
api.BASE_URL = "http://172.16.154.130"
api.AC_ID = "1"

-- URL 编码
local function url_encode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w%-%.%_%~ ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

-- 生成 jQuery 回调名
local function gen_callback()
    local timestamp = os.time() * 1000 + math.random(0, 999)
    return "jQuery112404" .. tostring(timestamp), timestamp
end

-- 解析 JSONP 响应
local function parse_jsonp(response, callback)
    local json_str = response:match(callback .. "%((.+)%)$")
    if json_str then
        -- 简单的 JSON 解析
        return json_str
    end
    return nil
end

-- HTTP GET 请求
local function http_get(url)
    local cmd = string.format("curl -s --connect-timeout 5 '%s'", url)
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- 获取 Challenge (token)
function api.get_challenge(username)
    local callback, timestamp = gen_callback()
    local url = string.format(
        "%s/cgi-bin/get_challenge?callback=%s&username=%s&_=%.0f",
        api.BASE_URL, callback, url_encode(username), math.floor(timestamp)
    )
    local response = http_get(url)
    if not response or response == "" then
        return nil, "网络请求失败"
    end

    -- 解析响应
    local challenge = response:match('"challenge":%s?"([^"]+)"')
    local client_ip = response:match('"client_ip":%s?"([^"]+)"')
    local error_msg = response:match('"error":%s?"([^"]+)"')

    if error_msg and error_msg ~= "ok" then
        return nil, error_msg
    end

    if challenge and client_ip then
        return {
            token = challenge,
            ip = client_ip
        }
    end

    return nil, "解析响应失败"
end

-- 发送登录请求
function api.login(username, password)
    -- 1. 获取 challenge
    local challenge, err = api.get_challenge(username)
    if not challenge then
        return false, err or "获取 token 失败"
    end

    local token = challenge.token
    local ip = challenge.ip

    -- 2. 加密密码
    local hmd5_password = crypto.encrypt_password(password, token)

    -- 3. 生成加密信息
    local info = crypto.gen_info(token, username, password, ip, api.AC_ID)

    -- 4. 生成校验和
    local chksum = crypto.gen_chksum(
        token, username, hmd5_password,
        api.AC_ID, ip, "200", "1", info
    )

    -- 5. 构建请求
    local callback, timestamp = gen_callback()
    local params = {
        "callback=" .. callback,
        "action=login",
        "username=" .. url_encode(username),
        "password=%7BMD5%7D" .. hmd5_password,
        "ac_id=" .. api.AC_ID,
        "ip=" .. url_encode(ip),
        "chksum=" .. chksum,
        "info=" .. url_encode(info),
        "n=200",
        "type=1",
        "os=Linux",
        "name=OpenWrt",
        "double_stack=0",
        "_=" .. timestamp
    }

    local url = api.BASE_URL .. "/cgi-bin/srun_portal?" .. table.concat(params, "&")
    local response = http_get(url)
    for i, v in pairs(params) do
        print(v)
    end
    print(hmd5_password)

    if not response or response == "" then
        
        return false, "登录请求失败"
    end

    -- 解析响应
    local error_code = response:match('"error":"([^"]+)"')
    if error_code == "ok" then
        return true, "登录成功"
    elseif error_code == "ip_already_online_error" then
        return true, "已在线"
    else
        local error_msg = response:match('"error_msg":"([^"]+)"') or error_code
        return false, error_msg or "登录失败"
    end
end

-- 获取用户信息
function api.get_user_info()
    local callback, timestamp = gen_callback()
    local url = string.format(
        "%s/cgi-bin/rad_user_info?callback=%s&_=%.0f",
        api.BASE_URL, callback, math.floor(timestamp)
    )

    local response = http_get(url)
    if not response or response == "" then
        return nil
    end

    if response:find("not_online") then
        return nil
    end

    -- 解析用户信息
    local username = response:match('"user_name":"([^"]+)"')
    local sum_bytes = response:match('"sum_bytes":(%d+)')
    local sum_seconds = response:match('"sum_seconds":(%d+)')
    local user_ip = response:match('"online_ip":"([^"]+)"')

    if username then
        return {
            username = username,
            ip = user_ip or "",
            bytes = tonumber(sum_bytes) or 0,
            seconds = tonumber(sum_seconds) or 0
        }
    end

    return nil
end

-- 测试网络连接
function api.test_connection()
    local cmd = "curl -s --connect-timeout 3 'http://www.apple.com/library/test/success.html'"
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result:find("Success") ~= nil
end

return api
