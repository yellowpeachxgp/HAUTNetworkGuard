#!/usr/bin/lua

package.path = "OpenWrt/files/usr/lib/haut-network-guard/?.lua;" .. package.path

local crypto = require("crypto")
local protocol = require("protocol")

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s failed: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
    end
end

local username_cases = {
    { input = "231040600203", expected = "{SRUN3}\r\n675484:44647" },
    { input = "test01", expected = "{SRUN3}\r\nxiwx45" },
    { input = "9", expected = "{SRUN3}\r\n=" }
}

for _, case in ipairs(username_cases) do
    assert_equal(crypto.encrypt_username(case.input), case.expected, "encrypt_username")
end

local password_cases = {
    { input = "password123", expected = "6gh>Agg:7gh@<gh=9cc99c" },
    { input = "abc123", expected = "7hhAAhc<:cc<" },
    { input = "Z9", expected = "@ic6" }
}

for _, case in ipairs(password_cases) do
    assert_equal(crypto.encrypt_password(case.input), case.expected, "encrypt_password")
end

local value, diag = protocol.sanitize_uci_value("\239\187\191  '231040600203' \r\n")
assert_equal(value, "231040600203", "sanitize_uci_value.value")
assert_equal(diag.had_cr, true, "sanitize_uci_value.had_cr")
assert_equal(diag.trimmed, true, "sanitize_uci_value.trimmed")
assert_equal(diag.unquoted, true, "sanitize_uci_value.unquoted")

local value2, diag2 = protocol.sanitize_uci_value("abc\0\7")
assert_equal(value2, "abc", "sanitize_uci_value.control.value")
assert_equal(diag2.had_control, true, "sanitize_uci_value.control.had_control")

local class1 = protocol.classify_login_response("login_ok")
assert_equal(class1.category, "success", "classify_login_response.success.class")
assert_equal(class1.message, "登录成功", "classify_login_response.success.message")
assert_equal(class1.ok, true, "classify_login_response.success.ok")

local class2 = protocol.classify_login_response("login_error#E2531:User not found")
assert_equal(class2.category, "error_E2531", "classify_login_response.e2531.class")
assert_equal(class2.message, "login_error#E2531:User not found", "classify_login_response.e2531.message")
assert_equal(class2.user_message, "学号或密码错误，请检查后重试。", "classify_login_response.e2531.user_message")
assert_equal(class2.ok, false, "classify_login_response.e2531.ok")

local class3 = protocol.classify_login_response("login_error#E9999:oops")
assert_equal(class3.category, "error_E9999", "classify_login_response.e9999.class")
assert_equal(class3.message, "login_error#E9999:oops", "classify_login_response.e9999.message")

local parsed1, format1 = protocol.parse_status_response(
    "jQuery_1712630100000({\"error\":\"ok\",\"user_name\":\"231040600203\",\"online_ip\":\"10.10.0.8\",\"sum_bytes\":12345678,\"sum_seconds\":321})"
)
assert_equal(format1, "jsonp", "parse_status_response.jsonp.format")
assert_equal(parsed1.username, "231040600203", "parse_status_response.jsonp.username")
assert_equal(parsed1.ip, "10.10.0.8", "parse_status_response.jsonp.ip")
assert_equal(parsed1.bytes, 12345678, "parse_status_response.jsonp.bytes")
assert_equal(parsed1.seconds, 321, "parse_status_response.jsonp.seconds")

local parsed_string_numbers, format_string_numbers = protocol.parse_status_response(
    "jQuery_1712630100001({\"error\":\"ok\",\"user_name\":\"231040600203\",\"online_ip\":\"10.10.0.8\",\"sum_bytes\":\"12345678\",\"sum_seconds\":\"321\"})"
)
assert_equal(format_string_numbers, "jsonp", "parse_status_response.jsonp_string_numbers.format")
assert_equal(parsed_string_numbers.username, "231040600203", "parse_status_response.jsonp_string_numbers.username")
assert_equal(parsed_string_numbers.ip, "10.10.0.8", "parse_status_response.jsonp_string_numbers.ip")
assert_equal(parsed_string_numbers.bytes, 12345678, "parse_status_response.jsonp_string_numbers.bytes")
assert_equal(parsed_string_numbers.seconds, 321, "parse_status_response.jsonp_string_numbers.seconds")

local parsed_invalid_number, format_invalid_number = protocol.parse_status_response(
    "jQuery_1712630100002({\"error\":\"ok\",\"user_name\":\"231040600203\",\"online_ip\":\"10.10.0.8\",\"sum_bytes\":\"invalid\",\"sum_seconds\":\"321\"})"
)
assert_equal(format_invalid_number, "jsonp", "parse_status_response.jsonp_invalid_number.format")
assert_equal(parsed_invalid_number.username, "231040600203", "parse_status_response.jsonp_invalid_number.username")
assert_equal(parsed_invalid_number.bytes, 0, "parse_status_response.jsonp_invalid_number.bytes")
assert_equal(parsed_invalid_number.seconds, 321, "parse_status_response.jsonp_invalid_number.seconds")

local parsed2, format2 = protocol.parse_status_response("231040600203,321,10.10.0.8,12345678,0,0")
assert_equal(format2, "csv", "parse_status_response.csv.format")
assert_equal(parsed2.username, "231040600203", "parse_status_response.csv.username")
assert_equal(parsed2.ip, "10.10.0.8", "parse_status_response.csv.ip")
assert_equal(parsed2.bytes, 12345678, "parse_status_response.csv.bytes")
assert_equal(parsed2.seconds, 321, "parse_status_response.csv.seconds")

local parsed_invalid, format_invalid = protocol.parse_status_response("oops,NaN,not-an-ip,garbage")
assert_equal(parsed_invalid, nil, "parse_status_response.invalid_csv.value")
assert_equal(format_invalid, "unparsed", "parse_status_response.invalid_csv.format")

local parsed3, format3 = protocol.parse_status_response("not_online")
assert_equal(parsed3, nil, "parse_status_response.offline.value")
assert_equal(format3, "offline", "parse_status_response.offline.format")

print("openwrt modules ok")
