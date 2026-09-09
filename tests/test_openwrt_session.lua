#!/usr/bin/lua

package.path = "OpenWrt/files/usr/lib/haut-network-guard/?.lua;" .. package.path
local session = require("session")
local checks = 0
local function expect(condition, message)
    assert(condition, message)
    checks = checks + 1
end

local state = session.new(30)
expect(state.phase == "unknown" and not state:can_auto_login(0, true, true), "启动未确认离线时不得登录")
state:observe("error")
expect(not state:can_auto_login(0, true, true) and state.phase == "error", "异常状态不得触发登录")
state:observe("offline")
expect(state:can_auto_login(0, true, true), "明确离线应允许首次自动登录")
expect(state:begin_login(0), "首次自动登录应开始")
expect(not state:begin_login(1), "登录进行中不得重复开始")
expect(state:finish_login(false, 10), "登录失败应结束请求")
expect(state.phase == "error" and state.failures == 1 and state:remaining(10) == 60,
    "首次失败应等待基础冷却")
state:observe("offline")
expect(not state:can_auto_login(69, true, true), "基础冷却结束前不得重试")
expect(state:can_auto_login(70, true, true), "基础冷却结束后允许重试")
expect(state:begin_login(70) and state:finish_login(false, 71), "第二次失败回放应成功")
expect(state.failures == 2 and state:remaining(71) == 120, "第二次失败应使用两倍退避")
state:observe("offline")
expect(state:can_auto_login(191, true, true), "两倍退避结束后允许重试")
expect(state:begin_login(191) and state:finish_login(true, 192), "登录成功回放应成功")
expect(state.phase == "unknown" and state.failures == 0 and state:remaining(192) == 60,
    "成功后应等待状态接口确认并保留基础保护间隔")
state:observe("online")
expect(state.phase == "online" and state:remaining(1000) == 0, "在线确认应清除冷却")

local long_interval = session.new(600)
long_interval:observe("offline")
expect(long_interval:begin_login(0) and long_interval:finish_login(false, 1), "长间隔登录回放应成功")
expect(long_interval:remaining(1) == 600, "检测间隔超过五分钟时不得缩短退避")
long_interval:observe("offline")
expect(not long_interval:can_auto_login(600, true, true), "长间隔边界前不得重试")
expect(long_interval:can_auto_login(601, true, true), "长间隔结束后允许重试")

print("OpenWrt 会话策略测试通过：" .. _VERSION .. "，" .. checks .. " 个断言")
