#!/usr/bin/lua
-- HAUT Network Guard - 协议与配置辅助模块

local protocol = {}

local function trim_value(value)
    if not value then return "" end
    return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

local function strip_wrapping_quotes(value)
    if #value >= 2 then
        local first = value:sub(1, 1)
        local last = value:sub(-1, -1)
        if (first == "\"" and last == "\"") or (first == "'" and last == "'") then
            return value:sub(2, -2), true
        end
    end
    return value, false
end

local function is_valid_ipv4(value)
    local a, b, c, d = tostring(value or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return false end

    local parts = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
    for _, part in ipairs(parts) do
        if not part or part < 0 or part > 255 then
            return false
        end
    end
    return true
end

local function extract_json_number(body, field)
    local pattern = '"' .. field .. '"%s*:%s*"?(%d+)"?'
    return tonumber(tostring(body or ""):match(pattern)) or 0
end

function protocol.sanitize_uci_value(raw)
    local original = tostring(raw or "")
    local sanitized = original:gsub("^\239\187\191", "")

    local had_cr = sanitized:find("\r", 1, true) ~= nil
    sanitized = sanitized:gsub("\r", "")

    local had_control = sanitized:find("[%z\1-\8\11\12\14-\31\127]") ~= nil
    sanitized = sanitized:gsub("[%z\1-\8\11\12\14-\31\127]", "")

    local before_trim = sanitized
    sanitized = trim_value(sanitized)
    local trimmed = before_trim ~= sanitized

    local unquoted = false
    sanitized, unquoted = strip_wrapping_quotes(sanitized)
    if unquoted then
        sanitized = trim_value(sanitized)
    end

    return sanitized, {
        raw_len = #original,
        clean_len = #sanitized,
        had_cr = had_cr,
        had_control = had_control,
        trimmed = trimmed,
        unquoted = unquoted
    }
end

function protocol.has_suspicious_changes(diag)
    if not diag then return false end
    return diag.had_cr or diag.had_control or diag.trimmed or diag.unquoted
end

local function user_facing_login_message(category, error_code)
    if category == "success" then return "登录成功" end
    if category == "already_online" then return "已经在线" end
    if category == "logout_ok" then return "注销成功" end
    if category == "not_online" then return "当前未在线" end
    if category == "error_E2531" then return "学号或密码错误，请检查后重试。" end
    if category == "empty" then return "校园网网关返回空响应，请检查网络后重试。" end
    if category == "unknown" then return "校园网网关返回了无法识别的结果，请稍后重试。" end
    if error_code then
        return "登录失败（错误码 " .. error_code .. "），请稍后重试。"
    end
    return "登录失败，请稍后重试。"
end

function protocol.classify_login_response(response)
    local body = tostring(response or "")
    if body:find("login_ok", 1, true) then
        return { ok = true, category = "success", message = "登录成功", user_message = "登录成功" }
    end
    if body:find("already_online", 1, true) then
        return { ok = true, category = "already_online", message = "已在线", user_message = "已经在线" }
    end
    if body:find("logout_ok", 1, true) then
        return { ok = true, category = "logout_ok", message = "注销成功", user_message = "注销成功" }
    end
    if body:find("not_online", 1, true) then
        return { ok = true, category = "not_online", message = "当前不在线", user_message = "当前未在线" }
    end

    local error_code = body:match("E(%d+)")
    if error_code then
        return {
            ok = false,
            category = "error_E" .. error_code,
            message = body ~= "" and body or ("登录失败 (E" .. error_code .. ")"),
            error_code = "E" .. error_code,
            user_message = user_facing_login_message("error_E" .. error_code, "E" .. error_code)
        }
    end

    if body == "" then
        return { ok = false, category = "empty", message = "空响应", user_message = "校园网网关返回空响应，请检查网络后重试。" }
    end

    return { ok = false, category = "unknown", message = body, user_message = "校园网网关返回了无法识别的结果，请稍后重试。" }
end

function protocol.parse_status_response(response)
    local body = tostring(response or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if body == "" or body:find("not_online", 1, true) then
        return nil, "offline"
    end

    local json_body = body:match("^jQuery_%d+%((.+)%)$")
    local format = "json"
    if json_body then
        format = "jsonp"
    else
        json_body = body
    end

    local error_value = json_body:match('"error"%s*:%s*"([^"]+)"')
    if error_value and error_value:find("not_online", 1, true) then
        return nil, "offline"
    end

    local username = json_body:match('"user_name"%s*:%s*"([^"]+)"')
    local sum_bytes = extract_json_number(json_body, "sum_bytes")
    local sum_seconds = extract_json_number(json_body, "sum_seconds")
    local user_ip = json_body:match('"online_ip"%s*:%s*"([^"]+)"')

    if username or user_ip then
        return {
            username = username or "",
            ip = user_ip or "",
            bytes = sum_bytes,
            seconds = sum_seconds
        }, format
    end

    local csv_username, csv_seconds, csv_ip, csv_bytes =
        body:match("^([^,]+),([^,]+),([^,]+),([^,]+)")
    if csv_username and csv_ip
        and tonumber(csv_seconds) ~= nil
        and tonumber(csv_bytes) ~= nil
        and csv_username ~= ""
        and is_valid_ipv4(csv_ip) then
        return {
            username = csv_username,
            ip = csv_ip,
            bytes = tonumber(csv_bytes) or 0,
            seconds = tonumber(csv_seconds) or 0
        }, "csv"
    end

    return nil, "unparsed"
end

return protocol
