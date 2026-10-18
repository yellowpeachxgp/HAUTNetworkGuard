#!/usr/bin/lua
-- 验证共享配置模块：文件解析、UCI 优先级、注释/引号/CRLF/BOM 边界。

package.path = "OpenWrt/files/usr/lib/haut-network-guard/?.lua;" .. package.path

local config = require("config")

local function check(condition, message)
    assert(condition, message)
end

local function write_temp(content)
    local path = os.tmpname()
    local file = assert(io.open(path, "wb"))
    file:write(content)
    file:close()
    return path
end

-- 文件后端：BOM、CRLF、注释、引号、行内注释、重复键、非法行。
local path = write_temp(
    "\239\187\191# comment\r\n" ..
    "; another comment\r\n" ..
    "username=first\r\n" ..
    "username = \"  student  \"\r\n" ..
    "password='p#ss;word'\r\n" ..
    "interval=30 # seconds\r\n" ..
    "log_level=debug\r\n" ..
    "gateway_host=10.20.30.40\r\n" ..
    "gateway_port=8080\r\n" ..
    "ac_id=\r\n" ..
    "malformed line without equals\r\n" ..
    "bad-key=value\r\n" ..
    "enabled=0\r\n")

config.FILE_PATH = path
config.detect_uci = function() return false end

local values = assert(config.read_file(path), "文件后端应能读取配置")
check(values.username == "  student  ", "引号内的空格必须保留")
check(values.password == "p#ss;word", "引号内的 # 和 ; 必须保留")
check(values.interval == "30", "未加引号的行内注释应被去除")
check(values.log_level == "debug", "普通值解析失败")
check(values.gateway_host == "10.20.30.40", "网关字段解析失败")
check(values.ac_id == "", "空值应保留为空串")
check(values["bad-key"] == nil, "非法键名必须忽略")
check(config.get("username") == "  student  ", "重复键应以后出现的值为准")
check(config.get("password") == "p#ss;word", "密码读取失败")
check(config.get("interval") == "30", "间隔读取失败")
check(config.get("missing") == "", "缺失字段应返回空串")
check(config.backend_name() == "通用 Linux/systemd", "文件后端名称不正确")
check(config.platform_name() == "Linux", "文件后端平台名称不正确")
check(config.using_uci() == false, "文件后端不应报告 UCI")

-- 引号不配对时按普通值处理，不能吞掉密码内容。
local unpaired = write_temp("password=\"unterminated\n")
config.FILE_PATH = unpaired
check(config.get("password") == "\"unterminated", "不配对引号应按普通值保留")
os.remove(unpaired)

-- 文件不存在时返回空串。
config.FILE_PATH = path .. ".missing"
check(config.get("username") == "", "缺失配置文件应返回空串")

-- UCI 后端：优先 UCI，空值回退文件。
config.FILE_PATH = path
config.detect_uci = function() return true end
local original_popen = io.popen
io.popen = function(command)
    check(command:find("^uci %-q get haut%-network%-guard%.main%."), "UCI 命令格式不正确")
    local field = command:match("%.main%.([%w_]+)")
    local value = ({ username = "uci-user\n", password = "", log_level = "warn" })[field] or ""
    return { read = function() return value end, close = function() end }
end
check(config.get("username") == "uci-user\n", "UCI 值应优先")
check(config.get("password") == "p#ss;word", "UCI 空值应回退文件")
check(config.get("log_level") == "warn", "UCI 日志级别读取失败")
check(config.backend_name() == "OpenWrt/procd", "UCI 后端名称不正确")
check(config.platform_name() == "OpenWrt", "UCI 后端平台名称不正确")
io.popen = original_popen

-- parse_line 的独立边界。
local key, value = config.parse_line("  interval = 45 ; 注释")
check(key == "interval" and value == "45", "行内分号注释解析失败")
key, value = config.parse_line("password=\"a b\"")
check(key == "password" and value == "a b", "双引号空格解析失败")
key, value = config.parse_line("# full line")
check(key == nil, "整行注释不应产生字段")

-- 对抗性输入：随机字节行不得让解析器抛错或返回非字符串值。
math.randomseed(20261019)
for _ = 1, 1000 do
    local length = math.random(0, 80)
    local bytes = {}
    for index = 1, length do bytes[index] = string.char(math.random(0, 255)) end
    local line = table.concat(bytes)
    local key, value = config.parse_line(line)
    if key ~= nil then
        check(type(key) == "string", "随机输入返回了非字符串键")
        check(type(value) == "string", "随机输入返回了非字符串值")
    end
end

-- 超长值不得截断或崩溃。
local long_key, long_value = config.parse_line("username=" .. string.rep("a", 200000))
check(long_key == "username" and #long_value == 200000, "超长配置值解析失败")

os.remove(path)
print("OpenWrt 配置模块测试通过：" .. _VERSION)
