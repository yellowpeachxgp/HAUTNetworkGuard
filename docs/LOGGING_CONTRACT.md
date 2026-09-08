# Logging Contract

适用范围:

- `Windows/`
- `macOS/`
- `OpenWrt/`

## 1. 目标

三端日志需要满足同一套排障契约:

- 能追踪单次请求
- 能判断请求所处阶段
- 能看到耗时和响应分类
- 不泄漏原始账号或密码
- 凭据存储实现和迁移失败不得把密码或完整编码内容写入日志
- 响应正文及 curl 错误正文统一输出 `<redacted>` 和字节数摘要；分类、HTTP 状态和耗时单独记录。JSON、CSV、表单、HTML 和无法解析的正文均遵循该规则，不把未知字段原样放入日志。

## 2. 核心字段

请求相关日志至少包含以下字段:

- `request id`
- `action`
  - `login`
  - `logout`
  - `status`
- `phase`
  - `request`
  - `encode`
  - `response`
  - `stderr`
  - `error`
- `class`
  - 例如 `success` / `already_online` / `error_E2531` / `offline` / `online_jsonp` / `online_csv` / `network_error`
- `elapsed_ms`

账号相关字段:

- `account`
  - 仅允许输出掩码后的账号
- `user_len`
- `pass_len`

## 3. 脱敏规则

### 用户名

- 长度 `<= 4`: 全部替换为 `*`
- 长度 `> 4`: 保留前 `2` 位与后 `2` 位，中间替换为 `*`

示例:

- `231040600203` -> `23********03`
- `test01` -> `te**01`
- `9999` -> `****`

### 密码

- 不记录原文
- 不记录可逆编码后的完整内容
- 可记录:
  - `pass_len`
  - 编码后长度

## 4. 推荐日志格式

示例:

```text
[req:login-1] action=login phase=request account=23********03 user_len=12 pass_len=10
[req:login-1] action=login phase=response class=success elapsed_ms=143
[req:status-8] action=status phase=response class=online_jsonp elapsed_ms=41
[req:status-9] action=status phase=error class=network_error elapsed_ms=5001 msg=timeout
```

## 5. 响应分类建议

登录:

- `success`
- `already_online`
- `error_E####`（错误码必须为恰好四位数字）
- `empty`
- `unknown`
- `network_error`

注销:

- `logout_ok`
- `not_online`
- `error_E####`
- `unknown`
- `network_error`

状态检查:

- `online_jsonp`
- `online_json`
- `online_csv`
- `offline`
- `unparsed`
- `network_error`
