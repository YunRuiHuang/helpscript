#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$HOME/.config/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
UI_DIR="$CONFIG_DIR/ui"
URL_FILE="$CONFIG_DIR/subscription_url.txt"
CONTROLLER_PORT="9091"

usage() {
    cat <<EOF
用法：

  第一次保存订阅并更新：
    $0 "https://你的订阅链接"

  以后直接更新：
    $0

订阅地址保存在：
  $URL_FILE
EOF
}

# 第一次运行时接收 URL；以后不传参数则读取已保存地址
if [[ $# -gt 1 ]]; then
    usage
    exit 1
fi

mkdir -p "$CONFIG_DIR"

if [[ $# -eq 1 ]]; then
    SUBSCRIPTION_URL="$1"
    printf '%s\n' "$SUBSCRIPTION_URL" > "$URL_FILE"
    chmod 600 "$URL_FILE"
elif [[ -f "$URL_FILE" ]]; then
    SUBSCRIPTION_URL="$(cat "$URL_FILE")"
else
    echo "错误：尚未保存订阅链接。"
    usage
    exit 1
fi

if [[ -z "$SUBSCRIPTION_URL" ]]; then
    echo "错误：订阅链接为空。"
    exit 1
fi

TMP_DOWNLOADED="$(mktemp)"
TMP_CONFIG="$(mktemp)"
TMP_TEST_DIR="$(mktemp -d)"

cleanup() {
    rm -f "$TMP_DOWNLOADED" "$TMP_CONFIG"
    rm -rf "$TMP_TEST_DIR"
}
trap cleanup EXIT

echo "==> 正在下载订阅配置……"

curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --connect-timeout 15 \
    --max-time 60 \
    -A "clash-verge/v1.7.7" \
    "$SUBSCRIPTION_URL" \
    -o "$TMP_DOWNLOADED"

if [[ ! -s "$TMP_DOWNLOADED" ]]; then
    echo "错误：下载结果为空。"
    exit 1
fi

# 防止把登录网页、JS 防护页面等误当成配置
if grep -Eiq '^[[:space:]]*<(html|!doctype|script)' "$TMP_DOWNLOADED"; then
    echo "错误：服务器返回的是网页或 JavaScript，不是 Clash/Mihomo YAML 配置。"
    exit 1
fi

# 至少应包含代理、代理组或代理提供者之一
if ! grep -Eq '^(proxies|proxy-groups|proxy-providers):' "$TMP_DOWNLOADED"; then
    echo "错误：下载内容看起来不像完整的 Clash/Mihomo 配置。"
    echo
    echo "文件开头如下："
    head -n 10 "$TMP_DOWNLOADED"
    exit 1
fi

echo "==> 正在加入本机 WebUI 和局域网代理设置……"

# 删除订阅文件中可能已有的同名顶层设置，避免 YAML 重复键
awk '
BEGIN {
    skip_block = 0
}
{
    # 当进入下一个顶层字段时，停止跳过
    if ($0 ~ /^[^[:space:]#][^:]*:/) {
        skip_block = 0
    }

    # 删除这些顶层字段；目前都是单行字段
    if ($0 ~ /^(mixed-port|allow-lan|bind-address|external-controller|external-ui|secret):/) {
        next
    }

    print
}
' "$TMP_DOWNLOADED" > "$TMP_CONFIG"

cat >> "$TMP_CONFIG" <<EOF

# 以下设置由 update_subscription.sh 添加
mixed-port: 7890
allow-lan: true
bind-address: "*"

external-controller: 0.0.0.0:${CONTROLLER_PORT}
external-ui: ${UI_DIR}
secret: ""
EOF

echo "==> 正在测试新配置……"

# 使用独立目录测试，避免污染当前运行配置
cp "$TMP_CONFIG" "$TMP_TEST_DIR/config.yaml"

if ! /usr/local/bin/mihomo -t -d "$TMP_TEST_DIR"; then
    echo
    echo "错误：新配置未通过 Mihomo 检查。"
    echo "当前正在使用的 config.yaml 没有被修改。"
    exit 1
fi

echo "==> 配置测试通过。"

if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP_FILE="$CONFIG_FILE.bak.$(date '+%Y%m%d_%H%M%S')"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo "==> 旧配置已备份到："
    echo "    $BACKUP_FILE"
fi

install -m 600 "$TMP_CONFIG" "$CONFIG_FILE"

echo "==> 正在重启 Mihomo……"

sudo systemctl restart mihomo

sleep 1

if ! systemctl is-active --quiet mihomo; then
    echo "错误：Mihomo 重启后未正常运行。"
    echo
    journalctl -u mihomo -n 30 --no-pager
    exit 1
fi

SERVER_IP="$(hostname -I | awk '{print $1}')"

echo
echo "========================================"
echo " 订阅更新成功"
echo "========================================"
echo
echo "MetaCubeXD："
echo "  http://${SERVER_IP}:${CONTROLLER_PORT}/ui"
echo
echo "局域网代理："
echo "  地址：${SERVER_IP}"
echo "  HTTP / SOCKS Mixed 端口：7890"
echo
echo "以后更新只需运行："
echo "  $0"