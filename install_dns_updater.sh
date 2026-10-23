#!/bin/sh
# Installs or updates dns_updater on this server from the settings saved in
# /etc/home_lab/dns_updater.env. Run by menu.sh as root; it does not prompt.
# Safe to re-run: the script and systemd units are replaced, settings are kept.
#
# Usage: sudo sh install_dns_updater.sh

set -e

NAME="dns_updater"
# The script lives here on the server. Owned by root because it runs as root
# (it needs root for the ddns_ns network namespace).
SCRIPT_DIR="/home/siler/Script"
SCRIPT_FILE="ddns-updater.sh"
ENV_FILE="/etc/home_lab/$NAME.env"
SERVICE_PATH="/etc/systemd/system/$NAME.service"
TIMER_PATH="/etc/systemd/system/$NAME.timer"
SRC_DIR=$(cd "$(dirname "$0")" && pwd)

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Run this as root."
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "❌ No settings found in $ENV_FILE. Run menu.sh and choose Install first."
    exit 1
fi

for tool in curl jq ip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ $tool is missing. Install it with: apt install $tool"
        exit 1
    fi
done

if ! ip netns list | grep -qw ddns_ns; then
    echo "⚠️  Network namespace ddns_ns does not exist yet. The updater will fail until it does."
fi

INTERVAL_MIN=$(sed -n 's/^DDNS_INTERVAL_MIN="\(.*\)"$/\1/p' "$ENV_FILE" | head -n1)
INTERVAL_MIN="${INTERVAL_MIN:-5}"

echo "🔧 Installing $SCRIPT_FILE to $SCRIPT_DIR..."
mkdir -p "$SCRIPT_DIR"
install -m 755 -o root -g root "$SRC_DIR/$NAME.sh" "$SCRIPT_DIR/$SCRIPT_FILE"

echo "🔧 Writing systemd service and timer ($INTERVAL_MIN min interval)..."
cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Home lab: $NAME
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
# Must run as root: ip netns exec needs it
User=root
EnvironmentFile=$ENV_FILE
ExecStart=/bin/sh $SCRIPT_DIR/$SCRIPT_FILE
EOF

cat > "$TIMER_PATH" << EOF
[Unit]
Description=Run $NAME every $INTERVAL_MIN minutes

[Timer]
OnBootSec=30
OnUnitActiveSec=${INTERVAL_MIN}min
Unit=$NAME.service

[Install]
WantedBy=timers.target
EOF

echo "⚙️  Enabling and restarting timer..."
systemctl daemon-reload
systemctl enable "$NAME.timer"
systemctl restart "$NAME.timer"

echo "✅ $NAME installed on $(hostname), running every $INTERVAL_MIN min."
