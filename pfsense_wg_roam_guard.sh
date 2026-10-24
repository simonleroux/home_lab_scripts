#!/bin/sh
# WireGuardRoam guard for pfSense. Keeps tun_wg3 (WireGuardRoam) up only on the
# CARP master of vhid 201, the VIP that holds 192.168.1.2 (Inbound VPN control).
# The backup firewall takes the tunnel down.
#
# Checks the live CARP state of vhid 201 every 5 seconds and sets the tunnel to
# match. No cron job needed. Each change is logged with the wg_roam_guard tag.
#
# Start at boot with Shellcmd: /bin/sh /root/wg_roam_guard.sh
# The script backgrounds itself, so Shellcmd returns straight away.
# Install to /root/wg_roam_guard.sh (chmod 700). See README.md.

VERSION="1.0.0"

IF="tun_wg3"
VHID="201"
TAG="wg_roam_guard"
PIDFILE="/var/run/wg_roam_guard.pid"

# Start in the background, once only
if [ "$1" != "run" ]; then
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        exit 0
    fi
    # Detach stdin as well, so the watcher doesn't hold the terminal
    /usr/bin/nohup /bin/sh "$0" run < /dev/null > /dev/null 2>&1 &
    exit 0
fi

echo $$ > "$PIDFILE"

# Bring the tunnel in line with the live CARP state of vhid 201
reconcile() {
    # CARP line looks like: "carp: BACKUP vhid 201 advbase 1 advskew 100"
    state=$(ifconfig | awk -v v="$VHID" '$1=="carp:" && $3=="vhid" && $4==v {print $2}')

    if [ -z "$state" ]; then
        logger -t "$TAG" "no CARP state for vhid $VHID, leaving $IF unchanged"
        return 1
    fi

    # The flags are on the first line of ifconfig output, e.g. flags=10080c1<UP,RUNNING,...>
    if ifconfig "$IF" | head -n1 | grep -qE "[<,]UP[,>]"; then
        up=1
    else
        up=0
    fi

    if [ "$state" = "MASTER" ] && [ "$up" -eq 0 ]; then
        ifconfig "$IF" up && logger -t "$TAG" "vhid $VHID is MASTER, brought $IF up"
    elif [ "$state" != "MASTER" ] && [ "$up" -eq 1 ]; then
        ifconfig "$IF" down && logger -t "$TAG" "vhid $VHID is $state, brought $IF down"
    fi
}

reconcile

# Check the live CARP state every few seconds. Polling doesn't depend on pfSense
# logging a CARP message for every transition: one was missing during a failover test.
while true; do
    reconcile
    sleep 5
done

