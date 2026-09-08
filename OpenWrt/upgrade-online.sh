#!/bin/sh
# HAUT Network Guard - OpenWrt 一键升级脚本
# 用法:
#   最新 main: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/upgrade-online.sh | sh
#   固定版本:   wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.19/OpenWrt/upgrade-online.sh | sh -s -- v1.3.19

set -e

REPO_REF="${1:-main}"
REPO_URL="https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/${REPO_REF}/OpenWrt"
ROOT_PREFIX="${HAUT_ROOT:-}"
case "$ROOT_PREFIX" in ""|/*) ;; *) echo "错误: HAUT_ROOT 必须为绝对路径"; exit 1 ;; esac
INSTALL_DIR="$ROOT_PREFIX/usr/lib/haut-network-guard"
INIT_FILE="$ROOT_PREFIX/etc/init.d/haut-network-guard"
MAIN_LUA="$INSTALL_DIR/main.lua"
TMP_DIR=""
BACKUP_DIR=""
UPGRADE_SUCCESS=0
SWITCH_STARTED=0
WAS_RUNNING=0
CHECKSUM_FILE=""
OLD_SESSION_PRESENT=0
OLD_VERSION_PRESENT=0

version_cmp() {
    awk -v a="$1" -v b="$2" '
        BEGIN {
            na = split(a, aa, ".")
            nb = split(b, bb, ".")
            n = (na > nb) ? na : nb
            for (i = 1; i <= n; i++) {
                x = (aa[i] == "" ? 0 : aa[i]) + 0
                y = (bb[i] == "" ? 0 : bb[i]) + 0
                if (x > y) { print 1; exit }
                if (x < y) { print -1; exit }
            }
            print 0
        }
    '
}

cleanup() {
    status=$?
    trap - EXIT
    set +e
    rollback_failed=0
    if [ "$UPGRADE_SUCCESS" -ne 1 ] && [ "$SWITCH_STARTED" -eq 1 ]; then
        echo ""
        echo "升级失败，正在回滚到原版本..."
        if [ "$WAS_RUNNING" -eq 1 ]; then
            "$INIT_FILE" stop >/dev/null 2>&1
        fi
        for file in version.lua crypto.lua api.lua log.lua protocol.lua main.lua; do
            if [ "$file" = "version.lua" ] && [ "$OLD_VERSION_PRESENT" -eq 0 ]; then
                rm -f "$INSTALL_DIR/$file"
            else
                cp -p "$BACKUP_DIR/$file" "$INSTALL_DIR/$file" || rollback_failed=1
            fi
        done
        if [ "$OLD_SESSION_PRESENT" -eq 1 ]; then
            cp -p "$BACKUP_DIR/session.lua" "$INSTALL_DIR/session.lua" || rollback_failed=1
        else
            rm -f "$INSTALL_DIR/session.lua"
        fi
        cp -p "$BACKUP_DIR/haut-network-guard.init" "$INIT_FILE" || rollback_failed=1
        if [ "$WAS_RUNNING" -eq 1 ]; then
            "$INIT_FILE" start >/dev/null 2>&1 || rollback_failed=1
        fi
    fi

    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    if [ "$rollback_failed" -eq 1 ]; then
        echo "错误: 自动恢复未完成，备份保留于 $BACKUP_DIR"
        status=1
    else
        [ -n "$BACKUP_DIR" ] && rm -rf "$BACKUP_DIR"
    fi
    exit "$status"
}

trap cleanup EXIT

download_file() {
    url="$1"
    dest="$2"
    tmp="${dest}.tmp"

    curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$tmp"
    mv "$tmp" "$dest"
}

validate_program_dir() {
    dir="$1"
    for file in version.lua crypto.lua api.lua log.lua protocol.lua session.lua main.lua; do
        if [ ! -s "$dir/$file" ]; then
            echo "错误: 缺少或为空的程序文件: $file"
            return 1
        fi
        if command -v lua >/dev/null 2>&1; then
            HAUT_VALIDATE_FILE="$dir/$file" lua -e 'assert(loadfile(os.getenv("HAUT_VALIDATE_FILE")))' </dev/null >/dev/null 2>&1 || {
                echo "错误: Lua 语法校验失败: $file"
                return 1
            }
        else
            echo "错误: 未安装 Lua，无法验证程序"
            return 1
        fi
    done
}


sha256_of() {
    file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk -F'= ' '{print $2}'
    else
        echo "错误: 缺少 sha256sum 或 openssl，无法校验发布文件" >&2
        return 1
    fi
}

prepare_checksums() {
    case "$REPO_REF" in
        v*)
            CHECKSUM_FILE="$TMP_DIR/OpenWrt-SHA256SUMS"
            download_file "https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases/download/$REPO_REF/OpenWrt-SHA256SUMS" "$CHECKSUM_FILE"
            test -s "$CHECKSUM_FILE"
            ;;
        *) ;;
    esac
}

verify_checksum() {
    relative="$1"
    file="$2"
    [ -z "$CHECKSUM_FILE" ] && return 0
    expected=$(awk -v path="OpenWrt/$relative" '$2 == path { print $1; exit }' "$CHECKSUM_FILE")
    [ -n "$expected" ] || { echo "错误: Release 清单缺少 OpenWrt/$relative"; return 1; }
    actual=$(sha256_of "$file")
    [ "$actual" = "$expected" ] || { echo "错误: 文件校验失败: $relative"; return 1; }
}

verify_service_health() {
    attempt=0
    while [ "$attempt" -lt 5 ]; do
        if "$INIT_FILE" status >/dev/null 2>&1; then return 0; fi
        attempt=$((attempt + 1))
        sleep 1
    done
    echo "错误: 升级后服务状态检查失败"
    return 1
}

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 升级检查"
echo "=========================================="
echo ""
echo "源版本: $REPO_REF"
echo ""

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

# 获取本地版本
LOCAL_VERSION="未安装"
if [ -f "$MAIN_LUA" ]; then
    if [ -f "$INSTALL_DIR/version.lua" ]; then
        LOCAL_VERSION=$(sed -n 's/^return "\([^"]*\)".*/\1/p' "$INSTALL_DIR/version.lua")
    else
        LOCAL_VERSION=$(grep -o 'VERSION = "[^"]*"' "$MAIN_LUA" 2>/dev/null | grep -o '"[^"]*"' | tr -d '"')
    fi
    [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION="未知"
fi
if [ "$LOCAL_VERSION" != "未安装" ] && ! printf '%s\n' "$LOCAL_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    LOCAL_VERSION="未知"
fi
echo "本地版本: $LOCAL_VERSION"

# 获取远端版本
echo "正在检查最新版本..."
REMOTE_VERSION_SOURCE=$(curl -fsSL --connect-timeout 10 --max-time 60 "$REPO_URL/files/usr/lib/haut-network-guard/version.lua")
if [ -z "$REMOTE_VERSION_SOURCE" ]; then
    echo "错误: 无法连接到 GitHub，请检查网络"
    exit 1
fi

REMOTE_VERSION=$(echo "$REMOTE_VERSION_SOURCE" | sed -n 's/^return "\([^"]*\)".*/\1/p')
if ! printf '%s\n' "$REMOTE_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "错误: 无法解析远端版本号"
    exit 1
fi
case "$REPO_REF" in
    v*)
        EXPECTED_VERSION="${REPO_REF#v}"
        if [ "$REMOTE_VERSION" != "$EXPECTED_VERSION" ]; then
            echo "错误: tag 与远端程序版本不一致: $REPO_REF -> $REMOTE_VERSION"
            exit 1
        fi
        ;;
esac
echo "最新版本: $REMOTE_VERSION"
echo ""

# 比较版本
if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
    echo "当前已是最新版本，无需升级。"
    exit 0
fi

if [ "$LOCAL_VERSION" = "未安装" ]; then
    echo "未检测到安装，请先运行安装脚本。"
    exit 1
fi

COMPARE_RESULT="$(version_cmp "$REMOTE_VERSION" "$LOCAL_VERSION")"
if [ "$COMPARE_RESULT" -gt 0 ]; then
    echo "发现新版本: $LOCAL_VERSION -> $REMOTE_VERSION"
else
    echo "目标版本变更: $LOCAL_VERSION -> $REMOTE_VERSION"
fi
echo "正在升级..."
echo ""

# 下载和校验期间保持旧服务运行。
echo "[1/4] 准备备份..."

mkdir -p "$ROOT_PREFIX/tmp"
TMP_DIR="$(mktemp -d "$ROOT_PREFIX/tmp/haut-network-guard-upgrade.XXXXXX")"
BACKUP_DIR="$(mktemp -d "$ROOT_PREFIX/tmp/haut-network-guard-backup.XXXXXX")"
prepare_checksums

if [ -f "$INSTALL_DIR/version.lua" ]; then
    cp -p "$INSTALL_DIR/version.lua" "$BACKUP_DIR/version.lua"
    OLD_VERSION_PRESENT=1
fi
cp -p "$INSTALL_DIR/crypto.lua" "$BACKUP_DIR/crypto.lua"
cp -p "$INSTALL_DIR/api.lua" "$BACKUP_DIR/api.lua"
cp -p "$INSTALL_DIR/log.lua" "$BACKUP_DIR/log.lua"
cp -p "$INSTALL_DIR/protocol.lua" "$BACKUP_DIR/protocol.lua"
cp -p "$INSTALL_DIR/main.lua" "$BACKUP_DIR/main.lua"
if [ -f "$INSTALL_DIR/session.lua" ]; then
    cp -p "$INSTALL_DIR/session.lua" "$BACKUP_DIR/session.lua"
    OLD_SESSION_PRESENT=1
fi
cp -p "$INIT_FILE" "$BACKUP_DIR/haut-network-guard.init"

# 下载新文件（不覆盖配置）
echo "[2/4] 下载程序文件..."
download_file "$REPO_URL/files/usr/lib/haut-network-guard/version.lua" "$TMP_DIR/version.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/crypto.lua" "$TMP_DIR/crypto.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/api.lua" "$TMP_DIR/api.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/log.lua" "$TMP_DIR/log.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/protocol.lua" "$TMP_DIR/protocol.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/session.lua" "$TMP_DIR/session.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/main.lua" "$TMP_DIR/main.lua"

echo "[3/4] 更新服务脚本..."
download_file "$REPO_URL/files/etc/init.d/haut-network-guard" "$TMP_DIR/haut-network-guard.init"

echo "      校验下载文件和 Lua 语法..."
validate_program_dir "$TMP_DIR"
test -s "$TMP_DIR/haut-network-guard.init"
sh -n "$TMP_DIR/haut-network-guard.init"
for file in version.lua crypto.lua api.lua log.lua protocol.lua session.lua main.lua; do
    verify_checksum "files/usr/lib/haut-network-guard/$file" "$TMP_DIR/$file"
done
verify_checksum "files/etc/init.d/haut-network-guard" "$TMP_DIR/haut-network-guard.init"
STAGED_VERSION=$(sed -n 's/^return "\([^"]*\)".*/\1/p' "$TMP_DIR/version.lua")
if ! printf '%s\n' "$STAGED_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || [ "$STAGED_VERSION" != "$REMOTE_VERSION" ]; then
    echo "错误: 下载期间远端版本发生变化，请重新运行升级"
    exit 1
fi
if "$INIT_FILE" status >/dev/null 2>&1; then WAS_RUNNING=1; fi
SWITCH_STARTED=1
if [ "$WAS_RUNNING" -eq 1 ]; then "$INIT_FILE" stop; fi

cp -f "$TMP_DIR/version.lua" "$INSTALL_DIR/version.lua"
cp -f "$TMP_DIR/crypto.lua" "$INSTALL_DIR/crypto.lua"
cp -f "$TMP_DIR/api.lua" "$INSTALL_DIR/api.lua"
cp -f "$TMP_DIR/log.lua" "$INSTALL_DIR/log.lua"
cp -f "$TMP_DIR/protocol.lua" "$INSTALL_DIR/protocol.lua"
cp -f "$TMP_DIR/session.lua" "$INSTALL_DIR/session.lua"
cp -f "$TMP_DIR/main.lua" "$INSTALL_DIR/main.lua"
cp -f "$TMP_DIR/haut-network-guard.init" "$INIT_FILE"
chmod +x "$INIT_FILE"

echo "      校验程序文件和 Lua 语法..."
validate_program_dir "$INSTALL_DIR"
for file in version.lua crypto.lua api.lua log.lua protocol.lua session.lua main.lua; do
    cmp "$TMP_DIR/$file" "$INSTALL_DIR/$file"
done
cmp "$TMP_DIR/haut-network-guard.init" "$INIT_FILE"

# 重启服务
echo "[4/4] 恢复服务状态..."
if [ "$WAS_RUNNING" -eq 1 ]; then
    "$INIT_FILE" start
    verify_service_health
else
    echo "      升级前服务已停止，继续保持停止"
fi
UPGRADE_SUCCESS=1

echo ""
echo "=========================================="
echo "  升级完成! ($LOCAL_VERSION -> $REMOTE_VERSION)"
echo "=========================================="
echo ""
echo "配置文件已保留，无需重新配置。"
echo "查看日志: logread | grep haut-network-guard"
echo ""
