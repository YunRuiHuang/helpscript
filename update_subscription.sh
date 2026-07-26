#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$HOME/.config/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
UI_DIR="$CONFIG_DIR/ui"
PROVIDER_DIR="$CONFIG_DIR/providers"
CONTROLLER_PORT="9091"
MIXED_PORT="2017"

usage() {
    cat <<EOF
用法：
  $0 "订阅链接"

示例：
  $0 "https://example.com/app/status/new/xxxxxxxx"

说明：
  脚本不会自行下载订阅。
  它会把链接写入 Mihomo 的 proxy-providers，
  之后由 Mihomo 自己获取和定时更新节点。
EOF
}

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

SUBSCRIPTION_URL="$1"

if [[ ! "$SUBSCRIPTION_URL" =~ ^https?:// ]]; then
    echo "错误：订阅地址必须以 http:// 或 https:// 开头。"
    exit 1
fi

mkdir -p "$CONFIG_DIR" "$PROVIDER_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP="$CONFIG_FILE.bak.$(date '+%Y%m%d_%H%M%S')"
    cp "$CONFIG_FILE" "$BACKUP"
    echo "旧配置已备份到："
    echo "  $BACKUP"
fi

cat > "$CONFIG_FILE" <<EOF
mixed-port: ${MIXED_PORT}
allow-lan: true
bind-address: "*"

mode: rule
log-level: info
ipv6: false

external-controller: 0.0.0.0:${CONTROLLER_PORT}
external-ui: ${UI_DIR}
secret: ""

proxy-providers:
  xgcloud:
    type: http
    url: "${SUBSCRIPTION_URL}"
    path: ./providers/xgcloud.yaml
    interval: 86400

    header:
      User-Agent:
        - "Clash-Verge"

    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 300
      timeout: 5000
      lazy: true

proxy-groups:
  - name: "节点选择"
    type: select
    proxies:
      - "自动选择"
      - DIRECT
    use:
      - xgcloud

  - name: "自动选择"
    type: url-test
    use:
      - xgcloud
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 100
    lazy: true

rules:
  - MATCH,节点选择
EOF

chmod 600 "$CONFIG_FILE"

echo
echo "正在检查配置……"

if ! /usr/local/bin/mihomo -t -d "$CONFIG_DIR"; then
    echo
    echo "错误：配置检查失败。"

    if [[ -n "${BACKUP:-}" && -f "$BACKUP" ]]; then
        cp "$BACKUP" "$CONFIG_FILE"
        echo "已经恢复旧配置。"
    fi

    exit 1
fi

echo "配置检查通过。"
echo "正在重启 Mihomo……"

sudo systemctl restart mihomo

sleep 2

if ! systemctl is-active --quiet mihomo; then
    echo
    echo "错误：Mihomo 没有正常启动。"

    if [[ -n "${BACKUP:-}" && -f "$BACKUP" ]]; then
        cp "$BACKUP" "$CONFIG_FILE"
        sudo systemctl restart mihomo
        echo "已经恢复旧配置并重新启动。"
    fi

    journalctl -u mihomo -n 30 --no-pager
    exit 1
fi

SERVER_IP="$(hostname -I | awk '{print $1}')"

echo
echo "========================================"
echo " 订阅配置完成"
echo "========================================"
echo
echo "Mihomo 将自行获取订阅节点。"
echo
echo "MetaCubeXD："
echo "  http://${SERVER_IP}:${CONTROLLER_PORT}/ui"
echo
echo "局域网 Mixed 代理："
echo "  ${SERVER_IP}:${MIXED_PORT}"
echo
echo "查看订阅获取日志："
echo "  journalctl -u mihomo -f"
