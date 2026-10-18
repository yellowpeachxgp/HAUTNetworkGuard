#!/usr/bin/lua

local executed = {}
io.popen = function(command)
    assert(command:find("^uci "), "日志模块不得执行未预期命令")
    return { read = function() return "debug\n" end, close = function() end }
end
os.execute = function(command)
    executed[#executed + 1] = command
    return true
end

package.path = "OpenWrt/files/usr/lib/haut-network-guard/?.lua;" .. package.path
local config = require("config")

-- 先用纯文本配置验证日志级别读取，再用 UCI 后端验证优先级。
local config_path = os.tmpname()
local config_file = assert(io.open(config_path, "wb"))
config_file:write("log_level=debug\n")
config_file:close()
config.FILE_PATH = config_path
config.detect_uci = function() return false end

local log = require("log")

local json_preview = log.preview('{"user_name":"231040600203","online_ip":"10.10.0.8"}')
assert(not json_preview:find("231040600203", 1, true), "JSON 预览不得暴露完整账号")
assert(json_preview:find("<redacted>", 1, true), "JSON 预览应包含脱敏标记")

local csv_preview = log.preview("231040600203,321,10.10.0.8,12345678")
assert(not csv_preview:find("231040600203", 1, true), "CSV 预览不得暴露完整账号")
assert(csv_preview:find("<redacted>", 1, true), "CSV 正文应隐藏")

local responses = {
    '{"user_name":"231040600203","password":"test-private","extra":"encoded-private"}',
    "username=%7BSRUN3%7Dencoded-private&password=test-private",
    "<html>231040600203 test-private encoded-private</html>",
    "未知结果：231040600203 test-private"
}
for _, response in ipairs(responses) do
    local summary = log.preview(response)
    assert(not summary:find("231040600203", 1, true), "不得泄漏完整账号")
    assert(not summary:find("test-private", 1, true), "不得泄漏密码")
    assert(not summary:find("encoded-private", 1, true), "不得泄漏编码字段")
    assert(summary:find("bytes", 1, true), "应保留长度诊断")
    log.info(summary)
end
assert(log.preview("test-private", 0) == "", "零长度预览不能输出正文")
for _, command in ipairs(executed) do
    assert(not command:find("test-private", 1, true), "系统 logger 参数不得泄漏密码")
    assert(not command:find("encoded-private", 1, true), "系统 logger 参数不得泄漏编码字段")
end
log.info("安全日志")
log.info("意外字段 username=231040600203 password=test-private enc_password=encoded-private")
assert(#executed > 0, "日志应调用系统 logger")
local last_command = executed[#executed]
assert(not last_command:find("231040600203", 1, true), "日志出口不得泄漏完整账号")
assert(not last_command:find("test-private", 1, true), "日志出口不得泄漏密码")
assert(not last_command:find("encoded-private", 1, true), "日志出口不得泄漏编码密码")
assert(last_command:find("password=<redacted>", 1, true), "日志出口应保留脱敏字段")

-- 纯文本配置的 debug 级别应生效。
log.debug("file-debug-visible")
assert(table.concat(executed, "\n"):find("file-debug-visible", 1, true),
       "纯文本配置的 debug 日志级别未生效")

-- UCI 后端应优先于文件配置。
config.detect_uci = function() return true end
log.refresh_level()
log.debug("uci-debug-visible")
assert(table.concat(executed, "\n"):find("uci-debug-visible", 1, true),
       "UCI 配置的 debug 日志级别未生效")

-- print 后必须显式刷新 stdout，适配 systemd 块缓冲。
local original_stdout = io.stdout
local flushed = false
io.stdout = { flush = function() flushed = true end }
log.info("flush-check")
io.stdout = original_stdout
assert(flushed, "日志输出后必须刷新 stdout")

os.remove(config_path)
print("OpenWrt 日志脱敏测试通过：" .. _VERSION)
