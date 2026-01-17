#!/usr/bin/lua
-- HAUT Network Guard - 加密模块
-- XXTEA + HMAC-MD5 + SHA1 + Custom Base64
-- 兼容 Lua 5.1 (OpenWrt)

local crypto = {}

-- 尝试加载 bit 库 (多种方式兼容不同环境)
local bit_loaded, bit = pcall(require, "bit")
if not bit_loaded then
    bit_loaded, bit = pcall(require, "bit32")
end
if not bit_loaded then
    -- 尝试 nixio.bit (OpenWrt 特有)
    local nixio_ok, nixio = pcall(require, "nixio")
    if nixio_ok and nixio.bit then
        bit = nixio.bit
        bit_loaded = true
    end
end

-- 如果没有找到 bit 库，使用纯 Lua 实现
local bxor, band, bor, rshift, lshift

if bit_loaded and bit then
    bxor = bit.bxor or bit.bxor32
    band = bit.band or bit.band32
    bor = bit.bor or bit.bor32
    rshift = bit.rshift or bit.rshift32
    lshift = bit.lshift or bit.lshift32
else
    -- 纯 Lua 实现位运算 (性能较低但兼容性好)
    local function make_bitop(operation)
        return function(a, b)
            local result = 0
            local bitval = 1
            a = a % 0x100000000
            b = b % 0x100000000
            for i = 0, 31 do
                local abit = a % 2
                local bbit = b % 2
                if operation == "xor" then
                    if abit ~= bbit then result = result + bitval end
                elseif operation == "and" then
                    if abit == 1 and bbit == 1 then result = result + bitval end
                elseif operation == "or" then
                    if abit == 1 or bbit == 1 then result = result + bitval end
                end
                a = math.floor(a / 2)
                b = math.floor(b / 2)
                bitval = bitval * 2
            end
            return result
        end
    end
    
    bxor = make_bitop("xor")
    band = make_bitop("and")
    bor = make_bitop("or")
    
    rshift = function(n, bits)
        n = n % 0x100000000
        return math.floor(n / (2 ^ bits))
    end
    
    lshift = function(n, bits)
        n = n % 0x100000000
        return (n * (2 ^ bits)) % 0x100000000
    end
end

-- Custom Base64 编码表
local ALPHABET = "LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA"

-- 字符到索引映射
local char_to_index = {}
for i = 1, 64 do
    char_to_index[ALPHABET:sub(i, i)] = i - 1
end

-- 辅助函数：无符号右移
local function unsigned_right_shift(num, shift)
    if num < 0 then
        num = num + 0x100000000
    end
    return rshift(band(num, 0xFFFFFFFF), shift)
end

-- 辅助函数：字符串转整数数组
local function str_to_int_array(str, include_length)
    local len = #str
    local result = {}
    for i = 1, len, 4 do
        local c1 = str:byte(i) or 0
        local c2 = str:byte(i + 1) or 0
        local c3 = str:byte(i + 2) or 0
        local c4 = str:byte(i + 3) or 0
        local combined = c1 + c2 * 256 + c3 * 65536 + c4 * 16777216
        table.insert(result, combined)
    end
    if include_length then
        table.insert(result, len)
    end
    return result
end

-- 辅助函数：整数数组转字符串
local function int_array_to_str(arr, include_length)
    local d = #arr
    local c = (d - 1) * 4
    if include_length then
        local m = arr[d]
        if m < c - 3 or m > c then
            return nil
        end
        c = m
    end
    local result = {}
    for i = 1, d do
        local num = arr[i]
        table.insert(result, string.char(
            num % 256,
            math.floor(num / 256) % 256,
            math.floor(num / 65536) % 256,
            math.floor(num / 16777216) % 256
        ))
    end
    local str = table.concat(result)
    if include_length then
        return str:sub(1, c)
    end
    return str
end

-- XXTEA 加密
function crypto.xxtea_encode(str, key)
    if not str or str == "" then
        return ""
    end

    local v = str_to_int_array(str, true)
    local k = str_to_int_array(key, false)

    -- 密钥填充到4个元素
    while #k < 4 do
        table.insert(k, 0)
    end

    local n = #v - 1
    if n < 1 then
        return ""
    end

    local z = v[n + 1]
    local y = v[1]
    local delta = 0x9E3779B9
    local q = math.floor(6 + 52 / (n + 1))
    local sum = 0

    while q > 0 do
        sum = (sum + delta) % 0x100000000
        local e = math.floor(sum / 4) % 4

        for p = 0, n - 1 do
            y = v[p + 2]
            local m = bxor(unsigned_right_shift(z, 5), band(y * 4, 0xFFFFFFFF))
            m = m + bxor(bxor(unsigned_right_shift(y, 3), band(z * 16, 0xFFFFFFFF)), bxor(sum, y))
            m = m + bxor(k[bxor(p % 4, e) + 1], z)
            v[p + 1] = (v[p + 1] + m) % 0x100000000
            z = v[p + 1]
        end

        y = v[1]
        local m = bxor(unsigned_right_shift(z, 5), band(y * 4, 0xFFFFFFFF))
        m = m + bxor(bxor(unsigned_right_shift(y, 3), band(z * 16, 0xFFFFFFFF)), bxor(sum, y))
        m = m + bxor(k[bxor(n % 4, e) + 1], z)
        v[n + 1] = (v[n + 1] + m) % 0x100000000
        z = v[n + 1]

        q = q - 1
    end

    return int_array_to_str(v, false)
end

-- Custom Base64 编码
function crypto.base64_encode(data)
    local result = {}
    local padding = 0

    for i = 1, #data, 3 do
        local c1 = data:byte(i) or 0
        local c2 = data:byte(i + 1) or 0
        local c3 = data:byte(i + 2) or 0

        if i + 1 > #data then
            padding = padding + 1
            c2 = 0
        end
        if i + 2 > #data then
            padding = padding + 1
            c3 = 0
        end

        local value = c1 * 65536 + c2 * 256 + c3

        table.insert(result, ALPHABET:sub(math.floor(value / 262144) % 64 + 1, math.floor(value / 262144) % 64 + 1))
        table.insert(result, ALPHABET:sub(math.floor(value / 4096) % 64 + 1, math.floor(value / 4096) % 64 + 1))
        table.insert(result, ALPHABET:sub(math.floor(value / 64) % 64 + 1, math.floor(value / 64) % 64 + 1))
        table.insert(result, ALPHABET:sub(value % 64 + 1, value % 64 + 1))
    end

    -- 添加填充
    for i = 1, padding do
        result[#result - i + 1] = "="
    end

    return table.concat(result)
end

-- HMAC-MD5 (使用 OpenSSL 命令)
function crypto.hmac_md5(key, message)
    local cmd = string.format(
        "echo -n '%s' | openssl dgst -md5 -hmac '%s' | awk '{print $2}'",
        message:gsub("'", "'\\''"),
        key:gsub("'", "'\\''")
    )
    local handle = io.popen(cmd)
    local result = handle:read("*a"):gsub("%s+", "")
    handle:close()
    return result
end

-- SHA1 (使用 OpenSSL 命令)
function crypto.sha1(message)
    local cmd = string.format(
        "echo -n '%s' | openssl dgst -sha1 | awk '{print $2}'",
        message:gsub("'", "'\\''")
    )
    local handle = io.popen(cmd)
    local result = handle:read("*a"):gsub("%s+", "")
    handle:close()
    return result
end

-- 生成加密的用户信息
function crypto.gen_info(token, username, password, ip, ac_id)
    local info = string.format(
        '{"username":"%s","password":"%s","ip":"%s","acid":"%s","enc_ver":"srun_bx1"}',
        username, password, ip, ac_id
    )
    local encoded = crypto.xxtea_encode(info, token)
    return "{SRBX1}" .. crypto.base64_encode(encoded)
end

-- 生成校验和
function crypto.gen_chksum(token, username, hmd5_password, ac_id, ip, n, type_, info)
    local chkstr = token .. username ..
                   token .. hmd5_password ..
                   token .. ac_id ..
                   token .. ip ..
                   token .. n ..
                   token .. type_ ..
                   token .. info
    return crypto.sha1(chkstr)
end

-- 密码加密
function crypto.encrypt_password(password, token)
    return crypto.hmac_md5(token, password)
end

return crypto
