#!/usr/bin/env python3

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_PATH = ROOT / "tests" / "fixtures" / "protocol_vectors.json"


def encrypt_username(username: str) -> str:
    return "{SRUN3}\r\n" + "".join(chr(ord(c) + 4) for c in username)


def encrypt_password(password: str) -> str:
    key = "1234567890"
    result = []
    for i, char in enumerate(password):
        ki = ord(char) ^ ord(key[len(key) - 1 - (i % len(key))])
        low = chr((ki & 0x0F) + 0x36)
        high = chr(((ki >> 4) & 0x0F) + 0x63)
        result.append(low + high if i % 2 == 0 else high + low)
    return "".join(result)


def classify_login_response(response: str):
    if "login_ok" in response:
        return "success", "登录成功"
    if "already_online" in response:
        return "already_online", "已在线"
    if "logout_ok" in response:
        return "logout_ok", "注销成功"
    if "not_online" in response:
        return "not_online", "当前不在线"

    import re

    match = re.search(r"E(\d+)", response)
    if match:
        return f"error_E{match.group(1)}", response or f"登录失败 (E{match.group(1)})"
    if not response:
        return "empty", "空响应"
    return "unknown", response


def parse_status_response(response: str):
    body = response.strip()
    if not body or body == "not_online":
        return {
            "format": "offline",
            "online": False,
            "username": "",
            "ip": "",
            "bytes": 0,
            "seconds": 0,
        }

    import json
    import re

    match = re.match(r"jQuery_\d+\((.+)\)$", body)
    fmt = "json"
    if match:
        body = match.group(1)
        fmt = "jsonp"

    try:
        obj = json.loads(body)
    except json.JSONDecodeError:
        obj = None

    def parse_number(value):
        if isinstance(value, bool):
            return 0
        if isinstance(value, int):
            return value if 0 <= value <= 9_007_199_254_740_991 else 0
        if isinstance(value, float):
            return int(value) if value.is_integer() and value >= 0 and value <= 9_007_199_254_740_991 else 0
        if isinstance(value, str) and re.fullmatch(r"[0-9]+", value):
            parsed = int(value)
            return parsed if parsed <= 9_007_199_254_740_991 else 0
        return 0

    if isinstance(obj, dict):
        error = str(obj.get("error", ""))
        if "not_online" in error:
            return {
                "format": "offline",
                "online": False,
                "username": "",
                "ip": "",
                "bytes": 0,
                "seconds": 0,
            }

        username = str(obj.get("user_name", ""))
        ip = str(obj.get("online_ip", ""))
        bytes_used = parse_number(obj.get("sum_bytes", 0))
        seconds_used = parse_number(obj.get("sum_seconds", 0))
        if username or ip:
            return {
                "format": fmt,
                "online": True,
                "username": username,
                "ip": ip,
                "bytes": bytes_used,
                "seconds": seconds_used,
            }

    parts = body.split(",")
    valid_ip = False
    valid_numbers = False
    seconds = 0
    bytes_used = 0
    if len(parts) >= 4 and parts[0]:
        ip_parts = parts[2].split(".")
        valid_ip = len(ip_parts) == 4 and all(
            part.isdigit() and 0 <= int(part) <= 255 for part in ip_parts
        )
        if not re.fullmatch(r"[0-9]+", parts[1]) or not re.fullmatch(r"[0-9]+", parts[3]):
            pass
        else:
            seconds = int(parts[1])
            bytes_used = int(parts[3])
            valid_numbers = seconds <= 9_007_199_254_740_991 and bytes_used <= 9_007_199_254_740_991

    if len(parts) >= 4 and parts[0] and valid_ip and valid_numbers:
        return {
            "format": "csv",
            "online": True,
            "username": parts[0],
            "ip": parts[2],
            "bytes": bytes_used,
            "seconds": seconds,
        }

    return {
        "format": "unparsed",
        "online": False,
        "username": "",
        "ip": "",
        "bytes": 0,
        "seconds": 0,
    }


def sanitize_uci_value(raw: str):
    original = str(raw or "")
    sanitized = original.lstrip("\ufeff")
    had_cr = "\r" in sanitized
    sanitized = sanitized.replace("\r", "")

    had_control = any(
        ord(ch) == 0
        or 1 <= ord(ch) <= 8
        or ord(ch) in (11, 12)
        or 14 <= ord(ch) <= 31
        or ord(ch) == 127
        for ch in sanitized
    )
    sanitized = "".join(
        ch
        for ch in sanitized
        if not (
            ord(ch) == 0
            or 1 <= ord(ch) <= 8
            or ord(ch) in (11, 12)
            or 14 <= ord(ch) <= 31
            or ord(ch) == 127
        )
    )

    before_trim = sanitized
    sanitized = sanitized.strip()
    trimmed = before_trim != sanitized

    unquoted = False
    if len(sanitized) >= 2 and sanitized[0] == sanitized[-1] and sanitized[0] in ("'", '"'):
        sanitized = sanitized[1:-1].strip()
        unquoted = True

    return sanitized, {
        "had_cr": had_cr,
        "had_control": had_control,
        "trimmed": trimmed,
        "unquoted": unquoted,
    }


def main():
    fixtures = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

    for case in fixtures["username_vectors"]:
        actual = encrypt_username(case["input"])
        assert actual == case["expected"], f"username vector failed: {case}"

    for case in fixtures["password_vectors"]:
        actual = encrypt_password(case["input"])
        assert actual == case["expected"], f"password vector failed: {case}"

    for case in fixtures["login_response_vectors"]:
        actual_class, actual_message = classify_login_response(case["input"])
        assert actual_class == case["class"], f"classification failed: {case}"
        assert actual_message == case["message"], f"classification message failed: {case}"

    for case in fixtures["status_response_vectors"]:
        actual = parse_status_response(case["input"])
        expected = {
            "format": case["format"],
            "online": case["online"],
            "username": case["username"],
            "ip": case["ip"],
            "bytes": case["bytes"],
            "seconds": case["seconds"],
        }
        assert actual == expected, f"status parse failed: {case}"

    for case in fixtures["sanitize_vectors"]:
        actual_value, actual_diag = sanitize_uci_value(case["input"])
        assert actual_value == case["expected"], f"sanitize failed: {case}"
        for key, expected in case["diag"].items():
            assert actual_diag[key] == expected, f"sanitize diag failed for {key}: {case}"

    print("protocol contract ok")


if __name__ == "__main__":
    main()
