#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage:"
    echo "  $0 <subscription_url>"
    exit 1
fi

URL="$1"

CONFIG_DIR="$HOME/.config/mihomo"
CONFIG="$CONFIG_DIR/config.yaml"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

echo "Downloading subscription..."

curl -fsSL "$URL" -o "$TMP"

echo "Checking config..."

if ! grep -q "^proxies:" "$TMP" && \
   ! grep -q "^proxy-providers:" "$TMP"; then
    echo "Downloaded file doesn't look like a Mihomo/Clash configuration."
    exit 1
fi

echo "Appending WebUI settings..."

cat >> "$TMP" <<EOF

################################################
# Added by update_subscription.sh
################################################

external-controller: 0.0.0.0:9091
external-ui: $CONFIG_DIR/ui
secret: ""

EOF

cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

mv "$TMP" "$CONFIG"

echo "Restarting Mihomo..."

sudo systemctl restart mihomo

echo
echo "Done!"
echo
echo "Open:"
echo "http://$(hostname -I | awk '{print $1}'):9091/ui"