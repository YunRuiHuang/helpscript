#!/usr/bin/env bash
set -e

echo "====================================="
echo "      Mihomo Installer"
echo "====================================="

ARCH=$(uname -m)

case "$ARCH" in
    x86_64)
        FILE="mihomo-linux-amd64-alpha.gz"
        ;;
    aarch64|arm64)
        FILE="mihomo-linux-arm64-alpha.gz"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

CONFIG_DIR="$HOME/.config/mihomo"
UI_DIR="$CONFIG_DIR/ui"

mkdir -p "$CONFIG_DIR"
mkdir -p "$UI_DIR"

TMP=$(mktemp -d)
cd "$TMP"

echo
echo "Downloading Mihomo..."

wget -q "https://github.com/MetaCubeX/mihomo/releases/latest/download/$FILE"

gunzip "$FILE"

BIN="${FILE%.gz}"

chmod +x "$BIN"

sudo mv "$BIN" /usr/local/bin/mihomo

echo
echo "Downloading MetaCubeXD..."

wget -q https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz

rm -rf "$UI_DIR"/*

tar -xzf compressed-dist.tgz -C "$UI_DIR"

if [ ! -f "$CONFIG_DIR/config.yaml" ]; then

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

echo
echo "Creating systemd service..."

sudo tee /etc/systemd/system/mihomo.service >/dev/null <<EOF
[Unit]
Description=Mihomo
After=network.target

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
echo "====================================="
echo "Installed successfully!"
echo "====================================="
echo
echo "WebUI:"
echo "http://$(hostname -I | awk '{print $1}'):9090/ui"
echo
echo "Config:"
echo "$CONFIG_DIR/config.yaml"
echo
echo "Useful commands:"
echo
echo "systemctl status mihomo"
echo "journalctl -u mihomo -f"
echo "systemctl restart mihomo"
echo "systemctl stop mihomo"
echo