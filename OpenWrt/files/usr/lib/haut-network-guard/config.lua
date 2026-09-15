#!/usr/bin/lua
-- HAUT Network Guard - 配置读取模块
--
-- 统一封装配置读取，支持两种后端：
--   1) OpenWrt UCI（系统存在 uci 命令时优先使用，保持 OpenWrt 行为不变）
--   2) 纯文本配置文件（通用 Linux / Debian / Ubuntu 回退方案）
--
-- 字段与 UCI 配置一一对应：enabled / username / password / interval / log_level

local config = {}

config.UCI_NAMESPACE = "haut-network-guard.main"
config.FILE_PATH = "/etc/haut-network-guard.conf"

local uci_available = nil

-- 探测 uci 命令是否可用（结果缓存，避免重复 fork）
local function detect_uci()
    if uci_available == nil then
        local handle = io.popen("command -v uci >/dev/null 2>&1 && echo 1")
        if handle then
            local out = (handle:read("*a") or ""):gsub("[%s\r\n]+", "")
            handle:close()
            uci_available = (out == "1")
        else
            uci_available = false
        end
    end
    return uci_available
end

local function read_from_uci(key)
    local handle = io.popen("uci -q get " .. key .. " 2>/dev/null")
    if not handle then
        return nil
    end
    local value = handle:read("*a") or ""
    handle:close()
    if value == "" then
        return nil
    end
    return value
end

local function read_from_file(field)
    local file = io.open(config.FILE_PATH, "r")
    if not file then
        return nil
    end
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key == field then
            file:close()
            return value or ""
        end
    end
    file:close()
    return nil
end

-- 读取单个配置项，返回字符串（不存在时返回空串）
function config.get(field)
    if detect_uci() then
        local value = read_from_uci(config.UCI_NAMESPACE .. "." .. field)
        if value ~= nil then
            return value
        end
    end
    local value = read_from_file(field)
    if value ~= nil then
        return value
    end
    return ""
end

-- 当前部署后端描述，用于日志展示
function config.backend_name()
    return detect_uci() and "OpenWrt/procd" or "通用 Linux/systemd"
end

-- 是否正在使用 UCI 后端
function config.using_uci()
    return detect_uci()
end

return config
