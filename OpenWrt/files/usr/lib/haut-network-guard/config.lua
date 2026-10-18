#!/usr/bin/lua
-- HAUT Network Guard - 配置读取模块
--
-- 统一封装配置读取，支持两种后端：
--   1) OpenWrt UCI：存在 /etc/config/haut-network-guard 或 /etc/openwrt_release
--      且系统提供 uci 命令时优先使用，保持 OpenWrt 行为不变。
--   2) 纯文本配置文件：通用 Linux / Debian / Ubuntu 的默认回退方案。
--
-- 纯文本配置格式（每行一个字段，字段名与 UCI 选项一一对应）：
--   enabled=1
--   username=你的学号
--   password=你的密码
--   interval=30
--   log_level=info
--
-- 支持整行注释（# 或 ;）和用单/双引号包裹的值。未加引号的值会去掉
-- 空白后的行内 # / ; 注释；密码里包含 # 或 ; 时请使用引号包裹。

local config = {}

config.UCI_NAMESPACE = "haut-network-guard.main"
config.FILE_PATH = os.getenv("HAUT_CONFIG_FILE") or "/etc/haut-network-guard.conf"
config.UCI_CONFIG_PATH = "/etc/config/haut-network-guard"
config.OPENWRT_RELEASE_PATH = "/etc/openwrt_release"

local uci_available = nil

local function file_exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local function command_available(command)
    local handle = io.popen("command -v " .. command .. " >/dev/null 2>&1 && echo 1")
    if not handle then
        return false
    end
    local output = (handle:read("*a") or ""):gsub("[%s\r\n]+", "")
    handle:close()
    return output == "1"
end

-- 探测是否使用 UCI。结果会缓存，避免每轮配置读取都 fork 子进程。
function config.detect_uci()
    if uci_available == nil then
        -- 只有存在 OpenWrt 配置或发行版标记时才探测 uci，避免通用 Linux
        -- 恰好安装了 uci 工具后误读不存在的 OpenWrt 配置。
        if file_exists(config.UCI_CONFIG_PATH) or file_exists(config.OPENWRT_RELEASE_PATH) then
            uci_available = command_available("uci")
        else
            uci_available = false
        end
    end
    return uci_available
end

function config.reset_cache()
    uci_available = nil
end

local function read_from_uci(field)
    local handle = io.popen(
        "uci -q get " .. config.UCI_NAMESPACE .. "." .. field .. " 2>/dev/null")
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

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function unquote(value)
    if #value >= 2 then
        local first = value:sub(1, 1)
        local last = value:sub(-1)
        if (first == '"' and last == '"') or (first == "'" and last == "'") then
            return value:sub(2, -2), true
        end
    end
    return value, false
end

-- 解析单行配置。返回 nil 表示注释、空行或格式不合法。
function config.parse_line(line)
    line = tostring(line or ""):gsub("\r$", "")
    if line:match("^%s*[#;]") or line:match("^%s*$") then
        return nil
    end
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if not key then
        return nil
    end
    local unquoted, quoted = unquote(value)
    if not quoted then
        -- 未加引号时允许行内注释，例如 interval=30 # 秒。
        unquoted = trim(unquoted:gsub("%s+[#;].*$", ""))
    end
    return key, unquoted
end

-- 读取纯文本配置，返回字段表；文件不存在时返回 nil。
function config.read_file(path)
    path = path or config.FILE_PATH
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local values = {}
    local first_line = true
    for line in file:lines() do
        if first_line then
            line = line:gsub("^\239\187\191", "")
            first_line = false
        end
        local key, value = config.parse_line(line)
        if key then
            values[key] = value
        end
    end
    file:close()
    return values
end

-- 读取单个配置项，返回字符串；不存在时返回空串。
function config.get(field)
    if config.detect_uci() then
        local value = read_from_uci(field)
        if value ~= nil then
            return value
        end
    end
    local values = config.read_file()
    if values and values[field] ~= nil then
        return values[field]
    end
    return ""
end

-- 当前部署后端描述，用于日志展示。
function config.backend_name()
    return config.detect_uci() and "OpenWrt/procd" or "通用 Linux/systemd"
end

-- 平台名称，用于 User-Agent 等展示字段。
function config.platform_name()
    return config.detect_uci() and "OpenWrt" or "Linux"
end

function config.using_uci()
    return config.detect_uci()
end

return config
