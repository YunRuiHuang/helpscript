#!/usr/bin/env bash
set -euo pipefail

########################################
# install_mihomo.sh
#
# Usage:
# ./install_mihomo.sh \
#   --mihomo ~/Downloads/mihomo-linux-amd64-v1.19.29.gz \
#   --ui ~/Downloads/compressed-dist.tgz
########################################

MIHOMO=""
UI=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mihomo)
            MIHOMO="$2"
            shift 2
            ;;
        --ui)
            UI="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage:"
            echo "  $0 --mihomo <mihomo.gz> --ui <compressed-dist.tgz>"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$MIHOMO" || -z "$UI" ]]; then
    echo "Usage:"
    echo "  $0 --mihomo <mihomo.gz> --ui <compressed-dist.tgz>"
    exit 1
fi

if [[ ! -f "$MIHOMO" ]]; then
    echo "Mihomo package not found:"
    echo "  $MIHOMO"
    exit 1
fi

if [[ ! -f "$UI" ]]; then
    echo "MetaCubeXD package not found:"
    echo "  $UI"
    exit 1
fi

CONFIG_DIR="$HOME/.config/mihomo"
UI_DIR="$CONFIG_DIR/ui"

mkdir -p "$CONFIG_DIR"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> Installing Mihomo..."

cp "$MIHOMO" "$TMP/"
cd "$TMP"

GZ=$(basename "$MIHOMO")
gunzip "$GZ"

BIN="${GZ%.gz}"

chmod +x "$BIN"

sudo install -m 755 "$BIN" /usr/local/bin/mihomo

echo "==> Installing MetaCubeXD..."

rm -rf "$UI_DIR"
mkdir -p "$UI_DIR"

tar -xzf "$UI" -C "$UI_DIR"

if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then

cat > "$CONFIG_DIR/config.yaml" <<EOF
mixed-port: 7890

allow-lan: true

bind-address: "*"

mode: rule

log-level: info

external-controller: 0.0.0.0:9090

external-ui: $UI_DIR

secret: ""

dns:
  enable: true
  ipv6: false
EOF

fi

echo "==> Installing systemd service..."

sudo tee /etc/systemd/system/mihomo.service >/dev/null <<EOF
[Unit]
Description=Mihomo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$CONFIG_DIR
ExecStart=/usr/local/bin/mihomo -d $CONFIG_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable mihomo
sudo systemctl restart mihomo

echo
echo "========================================"
echo " Mihomo Installed Successfully"
echo "========================================"
echo
echo "Version:"
mihomo -v || true
echo
echo "WebUI:"
echo "http://$(hostname -I | awk '{print $1}'):9090/ui"
echo
echo "Config:"
echo "  $CONFIG_DIR/config.yaml"
echo
echo "Commands:"
echo "  systemctl status mihomo"
echo "  journalctl -u mihomo -f"
echo "  systemctl restart mihomo"
echo "  systemctl stop mihomo"