#!/bin/sh
# DNS updater status: service and timer state, next run, and the last run's log.
#
# Usage:
#   sudo sh ddns-status.sh      show status and the last run
#   sudo sh ddns-status.sh -f   follow the log live (Ctrl+C to stop)

SERVICE="dns_updater.service"
TIMER="dns_updater.timer"

if [ "$1" = "-f" ]; then
    exec journalctl -u "$SERVICE" -f
fi

echo ""
echo "🔍 STETNET DNS Updater Status"
echo "---------------------------------------"

echo ""
echo "📦 Service:"
if systemctl is-active --quiet "$SERVICE"; then
    echo "✅ $SERVICE is running right now"
else
    echo "ℹ️  $SERVICE is idle (normal, the timer starts it)"
fi
result=$(systemctl show -p Result --value "$SERVICE")
if [ "$result" = "success" ]; then
    echo "✅ Last result: success"
elif [ -n "$result" ]; then
    echo "❌ Last result: $result (see the log below)"
fi

echo ""
echo "⏱️  Timer:"
if systemctl is-active --quiet "$TIMER"; then
    echo "✅ $TIMER is active"
else
    echo "❌ $TIMER is inactive"
fi
systemctl list-timers "$TIMER" --no-pager

echo ""
echo "📝 Last run log:"
# InvocationID changes on every run, so this always picks the latest one
invocation=$(systemctl show -p InvocationID --value "$SERVICE")
if [ -n "$invocation" ]; then
    journalctl _SYSTEMD_INVOCATION_ID="$invocation" --no-pager
else
    echo "No run recorded yet."
fi

if [ "$(id -u)" -ne 0 ]; then
    echo ""
    echo "💡 Not running as root. Use sudo to see all log messages."
fi
echo ""
