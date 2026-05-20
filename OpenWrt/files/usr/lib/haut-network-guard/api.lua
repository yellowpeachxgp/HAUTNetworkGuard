#!/usr/bin/lua
-- HAUT Network Guard - API 模块
-- SRUN3K 协议 (与 macOS/Windows 一致)

local api = {}
local crypto = require("crypto")
local log = require("log")
local protocol = require("protocol")

api.BASE_URL = "http://172.16.154.130"
api.LOGIN_URL = "http://172.16.154.130:69/cgi-bin/srun_portal"
api.USER_AGENT = "HAUTNetworkGuard/1.3.18 OpenWrt"

local request_seq = 0

local function url_encode(str)
    if not str then return "" end
    return string.gsub(str, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function shell_quote(str)
    return "'" .. tostring(str or ""):gsub("'", "'\\''") .. "'"
end

local function next_request_id(prefix)
    request_seq = request_seq + 1
    return string.format("%s-%d-%d", prefix or "req", os.time(), request_seq)
end

local function make_temp_path(prefix)
    prefix = prefix or "haut-network-guard"
    return string.format("/tmp/%s-%d-%d.tmp", prefix, os.time(), math.random(1000, 9999))
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return "" end
    local content = file:read("*a") or ""
    file:close()
    return content
end

local function write_temp_file(path, content)
    local file, err = io.open(path, "wb")
    if not file then
        return nil, err or "open_failed"
    end
    file:write(content or "")
    file:close()
    os.execute("chmod 600 " .. shell_quote(path) .. " >/dev/null 2>&1")
    return true
end

local function gen_callback()
    local timestamp = os.time() * 1000 + math.random(0, 999)
    return "jQuery_" .. tostring(timestamp), timestamp
end

local function parse_curl_output(raw)
    local output = tostring(raw or "")
    local exit_code = tonumber(output:match("\n__HAUT_CURL_EXIT__:(%d+)\n?$")) or 0
    output = output:gsub("\n__HAUT_CURL_EXIT__:%d+\n?$", "")

    local body, http_code, time_total =
        output:match("^(.*)\n__HAUT_CURL_META__:(%d+):([0-9%.]+)\n?$")
    if not body then
        return output, {
            http_code = "000",
            duration_ms = -1,
            exit_code = exit_code
        }
    end

    return body, {
        http_code = http_code,
        duration_ms = math.floor((tonumber(time_total) or 0) * 1000 + 0.5),
        exit_code = exit_code
    }
end

local function http_get(url, req_id, action)
    local err_file = make_temp_path("haut-network-guard-curl-get")
    local cmd = string.format(
        "curl -sS --connect-timeout 5 --max-time 8 -A %s " ..
        "-w '\\n__HAUT_CURL_META__:%%{http_code}:%%{time_total}\\n' %s 2>%s; " ..
        "printf '__HAUT_CURL_EXIT__:%%s\\n' \"$?\"",
        shell_quote(api.USER_AGENT),
        shell_quote(url),
        shell_quote(err_file)
    )

    log.debug(string.format("[%s] action=%s phase=request method=GET url=%s",
        req_id, tostring(action or "get"), url))
    local handle = io.popen(cmd)
    if not handle then
        os.remove(err_file)
        return nil, "popen_failed"
    end

    local raw = handle:read("*a") or ""
    handle:close()

    local body, meta = parse_curl_output(raw)
    local stderr = read_file(err_file)
    os.remove(err_file)
    if stderr ~= "" then
        local stderr_preview = log.preview(stderr)
        if tonumber(meta.exit_code or 0) ~= 0 then
            log.warn(string.format("[%s] action=%s phase=stderr exit=%s preview=%s",
                req_id, tostring(action or "get"), tostring(meta.exit_code), stderr_preview))
        else
            log.debug(string.format("[%s] action=%s phase=stderr preview=%s",
                req_id, tostring(action or "get"), stderr_preview))
        end
    end

    log.debug(string.format("[%s] action=%s phase=response http=%s elapsed_ms=%.0f body=%s",
        req_id, tostring(action or "get"), meta.http_code, meta.duration_ms, log.bytes_summary(body)))
    if tonumber(meta.exit_code or 0) ~= 0 then
        return nil, "curl_exit_" .. tostring(meta.exit_code), meta
    end
    return body, nil, meta
end

local function http_post(url, body, req_id, action)
    local tmp_body = make_temp_path("haut-network-guard-body")
    local err_file = make_temp_path("haut-network-guard-curl-post")
    local ok, err = write_temp_file(tmp_body, body)
    if not ok then
        return nil, "write_temp_failed:" .. tostring(err)
    end

    local cmd = string.format(
        "curl -sS --connect-timeout 5 --max-time 10 -A %s " ..
        "-H 'Content-Type: application/x-www-form-urlencoded' " ..
        "--data-binary @%s -w '\\n__HAUT_CURL_META__:%%{http_code}:%%{time_total}\\n' %s 2>%s; " ..
        "printf '__HAUT_CURL_EXIT__:%%s\\n' \"$?\"",
        shell_quote(api.USER_AGENT),
        shell_quote(tmp_body),
        shell_quote(url),
        shell_quote(err_file)
    )

    log.debug(string.format("[%s] action=%s phase=request method=POST url=%s body=%s",
        req_id, tostring(action or "post"), url, log.bytes_summary(body)))
    local handle = io.popen(cmd)
    if not handle then
        os.remove(tmp_body)
        os.remove(err_file)
        return nil, "popen_failed"
    end

    local raw = handle:read("*a") or ""
    handle:close()

    local body_content, meta = parse_curl_output(raw)
    local stderr = read_file(err_file)
    os.remove(tmp_body)
    os.remove(err_file)
    if stderr ~= "" then
        local stderr_preview = log.preview(stderr)
        if tonumber(meta.exit_code or 0) ~= 0 then
            log.warn(string.format("[%s] action=%s phase=stderr exit=%s preview=%s",
                req_id, tostring(action or "post"), tostring(meta.exit_code), stderr_preview))
        else
            log.debug(string.format("[%s] action=%s phase=stderr preview=%s",
                req_id, tostring(action or "post"), stderr_preview))
        end
    end

    log.debug(string.format("[%s] action=%s phase=response http=%s elapsed_ms=%.0f body=%s",
        req_id, tostring(action or "post"), meta.http_code, meta.duration_ms, log.bytes_summary(body_content)))
    if tonumber(meta.exit_code or 0) ~= 0 then
        return nil, "curl_exit_" .. tostring(meta.exit_code), meta
    end
    return body_content, nil, meta
end

function api.login(username, password, context)
    context = context or {}
    local req_id = next_request_id("login")
    local source = tostring(context.source or "unknown")
    username = tostring(username or "")
    password = tostring(password or "")

    log.info(string.format(
        "[%s] action=login phase=request source=%s user=%s user_len=%d pass_len=%d",
        req_id, source, log.mask_username(username), #username, #password
    ))
    if username:find("[%z\1-\31\127]") then
        log.warn(string.format("[%s] action=login phase=warn class=control_chars_in_username", req_id))
    end

    local enc_username = crypto.encrypt_username(username)
    local enc_password = crypto.encrypt_password(password)
    local body = "action=login"
        .. "&username=" .. url_encode(enc_username)
        .. "&password=" .. url_encode(enc_password)
        .. "&ac_id=1&drop=0&pop=1&type=10&n=117&mbytes=0&minutes=0"
        .. "&mac=02%3A00%3A00%3A00%3A00%3A00"

    log.debug(string.format(
        "[%s] action=login phase=encode user_raw=%d user_enc=%d pass_raw=%d pass_enc=%d",
        req_id, #username, #enc_username, #password, #enc_password
    ))

    local response, post_err, meta = http_post(api.LOGIN_URL, body, req_id, "login")
    if post_err then
        log.error(string.format("[%s] action=login phase=error class=network_error msg=%s",
            req_id, post_err))
        return false, "登录请求失败", "network_error"
    end

    local classified = protocol.classify_login_response(response)
    log.info(string.format(
        "[%s] action=login phase=response class=%s http=%s elapsed_ms=%.0f msg=%s",
        req_id,
        tostring(classified.category),
        tostring(meta and meta.http_code or "000"),
        math.floor(tonumber(meta and meta.duration_ms or -1)),
        log.preview(classified.message, 180)
    ))

    if classified.category == "success" or classified.category == "already_online" then
        return true, classified.message, classified.category
    end
    return false, classified.message, classified.category
end

function api.logout()
    local req_id = next_request_id("logout")
    local body = "action=logout"

    local response, post_err, meta = http_post(api.LOGIN_URL, body, req_id, "logout")
    if post_err then
        log.error(string.format("[%s] action=logout phase=error class=network_error msg=%s",
            req_id, post_err))
        return false, "注销请求失败"
    end

    local classified = protocol.classify_login_response(response)
    log.info(string.format(
        "[%s] action=logout phase=response class=%s http=%s elapsed_ms=%.0f msg=%s",
        req_id,
        tostring(classified.category),
        tostring(meta and meta.http_code or "000"),
        math.floor(tonumber(meta and meta.duration_ms or -1)),
        log.preview(classified.message, 120)
    ))
    if classified.category == "logout_ok" or classified.category == "not_online" then
        return true, classified.message
    end
    return false, classified.message
end

function api.get_user_info(source)
    local req_id = next_request_id("status")
    source = source or "unknown"
    local callback, timestamp = gen_callback()
    local url = string.format(
        "%s/cgi-bin/rad_user_info?callback=%s&_=%.0f",
        api.BASE_URL, callback, math.floor(timestamp)
    )

    local response, get_err, meta = http_get(url, req_id, "status")
    if get_err then
        log.warn(string.format("[%s] action=status phase=error class=network_error source=%s msg=%s",
            req_id, source, tostring(get_err)))
        return nil, tostring(get_err)
    end

    local parsed, format = protocol.parse_status_response(response)
    if parsed then
        log.debug(string.format(
            "[%s] action=status phase=parse class=online_%s user=%s ip=%s bytes=%.0f seconds=%.0f",
            req_id, tostring(format), log.mask_username(parsed.username), tostring(parsed.ip or ""),
            math.floor(tonumber(parsed.bytes or 0)), math.floor(tonumber(parsed.seconds or 0))
        ))
        log.info(string.format("[%s] action=status phase=response class=online_%s source=%s http=%s elapsed_ms=%.0f",
            req_id, tostring(format), source, tostring(meta and meta.http_code or "000"),
            math.floor(tonumber(meta and meta.duration_ms or -1))))
        return parsed, "online_" .. tostring(format)
    end

    if format == "offline" then
        log.debug(string.format("[%s] action=status phase=response class=offline source=%s http=%s elapsed_ms=%.0f",
            req_id, source, tostring(meta and meta.http_code or "000"), math.floor(tonumber(meta and meta.duration_ms or -1))))
        return nil, "offline"
    end

    log.warn(string.format("[%s] action=status phase=response class=%s source=%s http=%s elapsed_ms=%.0f preview=%s",
        req_id, tostring(format), source, tostring(meta and meta.http_code or "000"),
        math.floor(tonumber(meta and meta.duration_ms or -1)), log.preview(response, 180)))
    return nil, tostring(format)
end

function api.test_connection()
    local cmd = "curl -s --connect-timeout 3 'http://www.apple.com/library/test/success.html'"
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result:find("Success") ~= nil
end

return api
