#!/bin/sh
# Removes dns_updater from the server it runs on. Run as root.
# The settings file in /etc/home_lab is kept; delete it by hand if you no longer need it.

NAME="dns_updater"
SCRIPT_DIR="/home/siler/Script"
SCRIPT_FILE="ddns-updater.sh"

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Run this as root."
    exit 1
fi

echo "🔧 Stopping and disabling $NAME timer..."
systemctl stop "$NAME.timer" 2>/dev/null
systemctl disable "$NAME.timer" 2>/dev/null
systemctl stop "$NAME.service" 2>/dev/null

echo "🗑️  Removing systemd units and scripts..."
rm -f "/etc/systemd/system/$NAME.service" "/etc/systemd/system/$NAME.timer"
# Only remove the script itself; the folder may hold other scripts
rm -f "$SCRIPT_DIR/$SCRIPT_FILE" "$SCRIPT_DIR/ddns-status.sh"

systemctl daemon-reload
systemctl reset-failed 2>/dev/null

echo "✅ $NAME removed from $(hostname)."
