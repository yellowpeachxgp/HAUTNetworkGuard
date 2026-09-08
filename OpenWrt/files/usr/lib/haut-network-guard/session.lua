#!/usr/bin/lua
-- OpenWrt 自动登录会话策略；不依赖系统时间校时，时间由调用方传入。

local session = {}

local function base_interval(value)
    local interval = tonumber(value) or 30
    if interval ~= interval or interval < 60 then return 60 end
    return math.floor(interval)
end

function session.new(interval)
    local state = {
        phase = "unknown",
        failures = 0,
        next_attempt = 0,
        interval = base_interval(interval)
    }

    function state:reset(interval_value)
        self.phase = "unknown"
        self.failures = 0
        self.next_attempt = 0
        self.interval = base_interval(interval_value or self.interval)
    end

    function state:observe(kind)
        if kind == "online" then
            self.phase = "online"
            self.failures = 0
            self.next_attempt = 0
        elseif kind == "offline" then
            self.phase = "offline"
        else
            self.phase = "error"
        end
    end

    function state:can_auto_login(now, enabled, has_credentials)
        return enabled and has_credentials and self.phase == "offline"
            and (tonumber(now) or 0) >= self.next_attempt
    end

    function state:begin_login(now)
        if self.phase ~= "offline" then return false end
        self.phase = "logging_in"
        self.next_attempt = (tonumber(now) or 0) + self.interval
        return true
    end

    function state:finish_login(success, now)
        if self.phase ~= "logging_in" then return false end
        local finished_at = tonumber(now) or 0
        if success then
            -- 登录应答不能代替状态接口确认；等待下一轮检测。
            self.phase = "unknown"
            self.failures = 0
            self.next_attempt = finished_at + self.interval
            return true
        end

        self.failures = math.min(self.failures + 1, 4)
        self.phase = "error"
        local multiplier = 2 ^ (self.failures - 1)
        local delay = math.min(self.interval * multiplier, math.max(300, self.interval))
        self.next_attempt = finished_at + delay
        return true
    end

    function state:remaining(now)
        return math.max(0, self.next_attempt - (tonumber(now) or 0))
    end

    return state
end

return session
