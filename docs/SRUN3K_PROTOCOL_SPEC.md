# SRUN3K Protocol Spec

日期: 2026-04-11

## 1. 固定端点

- 状态检查:
  - `http://172.16.154.130/cgi-bin/rad_user_info`
- 登录/注销:
  - `http://172.16.154.130:69/cgi-bin/srun_portal`

## 2. 登录参数

固定字段:

- `action=login`
- `ac_id=1`
- `drop=0`
- `pop=1`
- `type=10`
- `n=117`
- `mbytes=0`
- `minutes=0`
- `mac=02:00:00:00:00:00`

## 3. 用户名加密

规则:

- 每个字符 ASCII `+4`
- 前缀固定为 `{SRUN3}\r\n`

示例:

- 输入: `231040600203`
- 输出: `{SRUN3}\r\n675484:44647`

## 4. 密码加密

规则:

- 密钥固定: `1234567890`
- 使用反向密钥索引:
  - `key[len - 1 - (i % len)]`
- `XOR` 后拆分为:
  - 低 4 位 `+ 0x36`
  - 高 4 位 `+ 0x63`
- 偶数索引:
  - `low + high`
- 奇数索引:
  - `high + low`

示例:

- `password123` -> `6gh>Agg:7gh@<gh=9cc99c`
- `abc123` -> `7hhAAhc<:cc<`
- `Z9` -> `@ic6`

## 5. 状态响应

支持两种格式:

### JSONP

格式:

```text
jQuery_<timestamp>({...})
```

优先读取字段:

- `user_name`
- `online_ip`
- `sum_bytes`
- `sum_seconds`
- `error`

`sum_bytes` 与 `sum_seconds` 兼容 JSON number 与 quoted numeric string 两种返回形态。三端只保留有限、非负、整数且不超过 `9007199254740991` 的值；无法转换、带小数、负数或超出安全范围的数值按 `0` 处理，但不影响已包含有效账号或 IP 的在线判断。quoted numeric 只接受十进制整数。

### CSV

格式:

```text
username,seconds,ip,bytes,...
```


CSV 的 `seconds` 和 `bytes` 只接受非负十进制整数；小数、负数、超出安全范围或其他脏字段会使整行标记为 `unparsed`。

## 6. 登录响应分类

- 包含 `login_ok`:
  - `success`
- 包含 `already_online`:
  - `already_online`
- 包含 `logout_ok`:
  - `logout_ok`
- 包含 `not_online`:
  - `not_online`
- 包含任意 `E####`:
  - `error_E####`（错误码必须为恰好四位数字；其他位数归为 `unknown`）
- 空响应:
  - `empty`
- 其他:
  - `unknown`

UI 应把协议分类转换为学生可理解的提示；例如 `error_E2531` 显示“学号或密码错误，请检查后重试”，不要直接把网关原始响应当作弹窗内容。原始响应只允许进入经过脱敏和长度限制的调试日志。

## 7. OpenWrt UCI 清洗规则

配置读取后统一执行:

- 去除 UTF-8 BOM
- 去除 `\r`
- 去除控制字符
- 去除首尾空白
- 去除首尾成对引号

## 8. 共享回归向量

共享回归向量位于:

- `tests/fixtures/protocol_vectors.json`
- `tests/test_openwrt_modules.lua`
- `tests/test_protocol_contract.py`
- `Windows/tests/windows_smoke_tests.cpp`
- `macOS/tests/SmokeTests.swift`
