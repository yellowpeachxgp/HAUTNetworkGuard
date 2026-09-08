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

local MAX_SAFE_COUNTER = 9007199254740991

local function parse_counter(value, quoted)
    if value == nil then return 0 end
    if quoted then
        local text = tostring(value)
        if not text:match("^[0-9]+$") then return 0 end
        local number = tonumber(text)
        return number and number <= MAX_SAFE_COUNTER and number or 0
    end
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number < 0 or number > MAX_SAFE_COUNTER
        or math.floor(number) ~= number then
        return 0
    end
    return number
end

local function utf8_character(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    if code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000),
            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000),
        0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

-- 小型严格 JSON 解码器：OpenWrt 只依赖 Lua 和 curl，不强制额外 JSON 包。
local function decode_json(text)
    local length = #text
    local function spaces(position)
        while position <= length and text:sub(position, position):match("%s") do
            position = position + 1
        end
        return position
    end

    local parse_value
    local function parse_string(position)
        if text:sub(position, position) ~= '"' then return nil end
        position = position + 1
        local result = {}
        while position <= length do
            local character = text:sub(position, position)
            if character == '"' then
                return table.concat(result), position + 1
            end
            if character == "\\" then
                local escape = text:sub(position + 1, position + 1)
                local replacements = { ['"'] = '"', ["\\"] = "\\", ['/'] = '/',
                    ["b"] = "\b", ["f"] = "\f", ["n"] = "\n", ["r"] = "\r", ["t"] = "\t" }
                if replacements[escape] then
                    result[#result + 1] = replacements[escape]
                    position = position + 2
                elseif escape == "u" then
                    local hex = text:sub(position + 2, position + 5)
                    if not hex:match("^[0-9a-fA-F]+$") or #hex ~= 4 then return nil end
                    local code = tonumber(hex, 16)
                    if code >= 0xD800 and code <= 0xDFFF then code = 0xFFFD end
                    result[#result + 1] = utf8_character(code)
                    position = position + 6
                else
                    return nil
                end
            else
                if string.byte(character) < 0x20 then return nil end
                result[#result + 1] = character
                position = position + 1
            end
        end
        return nil
    end

    local function parse_number(position)
        local begin = position
        if text:sub(position, position) == "-" then position = position + 1 end
        local first = text:sub(position, position)
        if first == "0" then
            position = position + 1
            if text:sub(position, position):match("%d") then return nil end
        elseif first:match("[1-9]") then
            repeat position = position + 1 until not text:sub(position, position):match("%d")
        else
            return nil
        end
        if text:sub(position, position) == "." then
            position = position + 1
            if not text:sub(position, position):match("%d") then return nil end
            repeat position = position + 1 until not text:sub(position, position):match("%d")
        end
        local exponent = text:sub(position, position)
        if exponent == "e" or exponent == "E" then
            position = position + 1
            local sign = text:sub(position, position)
            if sign == "+" or sign == "-" then position = position + 1 end
            if not text:sub(position, position):match("%d") then return nil end
            repeat position = position + 1 until not text:sub(position, position):match("%d")
        end
        local token = text:sub(begin, position - 1)
        return tonumber(token), position
    end

    parse_value = function(position)
        position = spaces(position)
        local character = text:sub(position, position)
        if character == '"' then return parse_string(position) end
        if character == "{" then
            local object = {}
            position = spaces(position + 1)
            if text:sub(position, position) == "}" then return object, position + 1 end
            while position <= length do
                local key, next_position = parse_string(position)
                if key == nil then return nil end
                position = spaces(next_position)
                if text:sub(position, position) ~= ":" then return nil end
                local value, after_value = parse_value(position + 1)
                if after_value == nil then return nil end
                object[key] = value
                position = spaces(after_value)
                local delimiter = text:sub(position, position)
                if delimiter == "}" then return object, position + 1 end
                if delimiter ~= "," then return nil end
                position = spaces(position + 1)
            end
            return nil
        end
        if character == "[" then
            local array = {}
            position = spaces(position + 1)
            if text:sub(position, position) == "]" then return array, position + 1 end
            while position <= length do
                local value, after_value = parse_value(position)
                if after_value == nil then return nil end
                array[#array + 1] = value
                position = spaces(after_value)
                local delimiter = text:sub(position, position)
                if delimiter == "]" then return array, position + 1 end
                if delimiter ~= "," then return nil end
                position = spaces(position + 1)
            end
            return nil
        end
        if text:sub(position, position + 3) == "true" then return true, position + 4 end
        if text:sub(position, position + 4) == "false" then return false, position + 5 end
        if text:sub(position, position + 3) == "null" then return nil, position + 4 end
        return parse_number(position)
    end

    local value, position = parse_value(1)
    if position == nil or spaces(position) <= length then return nil end
    return value
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

    local error_code = body:match("E(%d%d%d%d)%D") or body:match("E(%d%d%d%d)$")
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
    if body == "not_online" then
        return nil, "offline"
    end
    if body == "" then
        return nil, "unparsed"
    end

    local json_body = body:match("^jQuery_%d+%((.+)%)$")
    local format = "json"
    if json_body then
        format = "jsonp"
    else
        json_body = body
    end

    local decoded = decode_json(json_body)
    if type(decoded) == "table" then
        local error_value = decoded.error
        if type(error_value) == "string" and error_value:find("not_online", 1, true) then
            return nil, "offline"
        end
        local username = type(decoded.user_name) == "string" and decoded.user_name or ""
        local user_ip = type(decoded.online_ip) == "string" and decoded.online_ip or ""
        local sum_bytes = parse_counter(decoded.sum_bytes, type(decoded.sum_bytes) == "string")
        local sum_seconds = parse_counter(decoded.sum_seconds, type(decoded.sum_seconds) == "string")
        if username ~= "" or is_valid_ipv4(user_ip) then
            return { username = username, ip = user_ip, bytes = sum_bytes, seconds = sum_seconds }, format
        end
    end

    local csv_username, csv_seconds, csv_ip, csv_bytes =
        body:match("^([^,]+),([^,]+),([^,]+),([^,]+)")
    if csv_username and csv_ip and csv_seconds:match("^[0-9]+$")
        and csv_bytes:match("^[0-9]+$")
        and parse_counter(csv_seconds, true) == tonumber(csv_seconds)
        and parse_counter(csv_bytes, true) == tonumber(csv_bytes)
        and csv_username ~= "" and is_valid_ipv4(csv_ip) then
        return { username = csv_username, ip = csv_ip,
            bytes = parse_counter(csv_bytes, true), seconds = parse_counter(csv_seconds, true) }, "csv"
    end

    return nil, "unparsed"
end

return protocol
