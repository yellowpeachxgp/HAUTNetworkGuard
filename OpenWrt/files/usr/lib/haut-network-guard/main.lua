#!/usr/bin/lua
-- HAUT Network Guard - OpenWrt 版本
-- 主程序入口

local VERSION = "1.3.18"

package.path = package.path .. ";/usr/lib/haut-network-guard/?.lua"

local api = require("api")
local log = require("log")
local protocol = require("protocol")

local function read_uci_value(key)
    local handle = io.popen("uci -q get " .. key .. " 2>/dev/null")
    if not handle then
        return ""
    end
    local value = handle:read("*a") or ""
    handle:close()
    return value
end

-- 读取 UCI 配置
local function read_config()
    local config = {
        username = "",
        password = "",
        enabled = true,
        interval = 30,
        log_level = "info"
    }
    local diagnostics = {}

    config.username, diagnostics.username =
        protocol.sanitize_uci_value(read_uci_value("haut-network-guard.main.username"))
    config.password, diagnostics.password =
        protocol.sanitize_uci_value(read_uci_value("haut-network-guard.main.password"))
    config.log_level, diagnostics.log_level =
        protocol.sanitize_uci_value(read_uci_value("haut-network-guard.main.log_level"))

    local enabled_value, enabled_diag =
        protocol.sanitize_uci_value(read_uci_value("haut-network-guard.main.enabled"))
    diagnostics.enabled = enabled_diag
    if enabled_value ~= "" then
        local normalized = enabled_value:lower()
        config.enabled = not (normalized == "0" or normalized == "false" or normalized == "off")
    end

    local interval_value, interval_diag =
        protocol.sanitize_uci_value(read_uci_value("haut-network-guard.main.interval"))
    diagnostics.interval = interval_diag
    if interval_value ~= "" then
        config.interval = tonumber(interval_value) or 30
    end

    -- 限制检测间隔，避免请求过于频繁导致风控
    if config.interval < 30 then
        config.interval = 30
    elseif config.interval > 300 then
        config.interval = 300
    end

    return config, diagnostics
end

local function has_suspicious_changes(diag)
    return protocol.has_suspicious_changes(diag)
end

local function config_signature(config)
    return table.concat({
        config.enabled and "1" or "0",
        config.username,
        config.password,
        tostring(config.interval),
        tostring(config.log_level)
    }, "|")
end

local function config_summary(config)
    return string.format(
        "enabled=%s user=%s user_len=%d pass_len=%d interval=%d log_level=%s",
        tostring(config.enabled),
        log.mask_username(config.username),
        #config.username,
        #config.password,
        tonumber(config.interval) or -1,
        tostring(config.log_level)
    )
end

local function log_diagnostics(diagnostics)
    if has_suspicious_changes(diagnostics.username) then
        log.warn(string.format(
            "用户名已清洗: raw_len=%d clean_len=%d trim=%s cr=%s ctrl=%s unquote=%s",
            diagnostics.username.raw_len,
            diagnostics.username.clean_len,
            tostring(diagnostics.username.trimmed),
            tostring(diagnostics.username.had_cr),
            tostring(diagnostics.username.had_control),
            tostring(diagnostics.username.unquoted)
        ))
    end
    if has_suspicious_changes(diagnostics.password) then
        log.warn(string.format(
            "密码已清洗: raw_len=%d clean_len=%d trim=%s cr=%s ctrl=%s unquote=%s",
            diagnostics.password.raw_len,
            diagnostics.password.clean_len,
            tostring(diagnostics.password.trimmed),
            tostring(diagnostics.password.had_cr),
            tostring(diagnostics.password.had_control),
            tostring(diagnostics.password.unquoted)
        ))
    end
end

-- 格式化流量
local function format_bytes(bytes)
    if bytes < 1024 then
        return string.format("%.0f B", bytes)
    elseif bytes < 1048576 then
        return string.format("%.2f KB", bytes / 1024)
    elseif bytes < 1073741824 then
        return string.format("%.2f MB", bytes / 1048576)
    else
        return string.format("%.2f GB", bytes / 1073741824)
    end
end

-- 格式化时间
local function format_time(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%.0f小时%.0f分%.0f秒", hours, mins, secs)
    elseif mins > 0 then
        return string.format("%.0f分%.0f秒", mins, secs)
    else
        return string.format("%.0f秒", secs)
    end
end

-- 主循环
local function main()
    log.info("HAUT Network Guard v" .. VERSION .. " 启动")
    log.info("运行模式: OpenWrt/procd 自动登录守护进程")

    local last_signature = nil
    local previous_online = nil
    local consecutive_failures = 0
    local last_login_error = ""
    local last_status_issue = ""

    while true do
        log.refresh_level()

        local config, diagnostics = read_config()
        local signature = config_signature(config)
        local sleep_seconds = config.interval

        if signature ~= last_signature then
            log.info("配置更新: " .. config_summary(config))
            log_diagnostics(diagnostics)
            last_signature = signature
        end

        if not config.enabled then
            log.warn("服务已禁用，等待下一轮检测")
        elseif config.username == "" or config.password == "" then
            log.error("未配置用户名或密码，等待下一轮检测")
        else
            local user_info, status_class = api.get_user_info("monitor_loop")

            if user_info then
                if previous_online ~= true then
                    log.info("状态迁移: offline -> online")
                end
                previous_online = true
                consecutive_failures = 0
                last_login_error = ""
                last_status_issue = ""
                log.info(string.format(
                    "在线 - user=%s, IP=%s, 流量=%s, 时长=%s",
                    log.mask_username(user_info.username),
                    user_info.ip,
                    format_bytes(user_info.bytes),
                    format_time(user_info.seconds)
                ))
            elseif status_class == "offline" then
                if previous_online ~= false then
                    log.warn("状态迁移: online -> offline")
                end
                previous_online = false
                last_status_issue = ""
                log.warn("离线，触发自动登录")

                local success, msg, category = api.login(
                    config.username,
                    config.password,
                    { source = "auto_loop" }
                )

                if success then
                    consecutive_failures = 0
                    last_login_error = ""
                    log.info("登录成功: " .. tostring(msg))
                else
                    consecutive_failures = consecutive_failures + 1
                    local sanitized_msg = log.preview(msg or "登录失败", 180)
                    if sanitized_msg == last_login_error then
                        log.warn(string.format(
                            "登录连续失败(%d次), 分类=%s, msg=%s",
                            consecutive_failures, tostring(category or "unknown"), sanitized_msg
                        ))
                    else
                        log.error(string.format(
                            "登录失败, 分类=%s, msg=%s",
                            tostring(category or "unknown"), sanitized_msg
                        ))
                    end
                    last_login_error = sanitized_msg

                    if consecutive_failures > 1 then
                        local backoff = math.min(60, (consecutive_failures - 1) * 5)
                        sleep_seconds = sleep_seconds + backoff
                        log.warn(string.format(
                            "应用失败退避: +%ds (连续失败=%d)",
                            backoff, consecutive_failures
                        ))
                    end
                end
            else
                local issue = tostring(status_class or "unknown")
                if issue ~= last_status_issue then
                    log.warn(string.format(
                        "状态检测异常，跳过自动登录: class=%s",
                        issue
                    ))
                    last_status_issue = issue
                else
                    log.debug("状态检测异常持续存在，继续等待下一轮检测")
                end
            end
        end

        log.debug("下次检测等待: " .. tostring(sleep_seconds) .. "秒")
        os.execute("sleep " .. tostring(sleep_seconds))
    end
end

main()
