#!/bin/sh
# WireGuard guard for pfSense. Keeps the WireGuard tunnels listed in
# /root/wg_roam_guard.conf up only on the CARP master of vhid 201, the VIP that
# holds 192.168.1.2 (Inbound VPN control). The backup firewall takes them down.
#
# Checks the live CARP state of vhid 201 every 5 seconds and sets each tunnel to
# match. The config is read on every check, so the menu's choice takes effect
# without a restart. Each change is logged with the wg_roam_guard tag.
#
# Start at boot with Shellcmd: /bin/sh /root/wg_roam_guard.sh
# The script backgrounds itself, so Shellcmd returns straight away.
# Install to /root/wg_roam_guard.sh (chmod 700). See README.md.

VERSION="1.1.2"

VHID="201"
TAG="wg_roam_guard"
CONF="/root/wg_roam_guard.conf"
PIDFILE="/var/run/wg_roam_guard.pid"
# Seconds between CARP checks. The new master brings its tunnel up within this time
CHECK_INTERVAL=10
# Seconds the backup keeps its tunnel up after losing the VIP. Clients whose
# cached DNS still points here (TTL 60) can reach the LAN until DNS moves
BACKUP_GRACE=90
# Epoch time the backup first saw it no longer held the VIP. Empty while master
backup_since=""

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

# Bring each listed tunnel in line with the live CARP state of vhid 201
reconcile() {
    # The interfaces the menu chose, e.g. IFACES="tun_wg3 tun_wg0"
    ifaces=$(sed -n 's/^IFACES="\(.*\)"$/\1/p' "$CONF" 2>/dev/null)
    if [ -z "$ifaces" ]; then
        return 0
    fi

    # CARP line looks like: "carp: BACKUP vhid 201 advbase 1 advskew 100"
    state=$(ifconfig | awk -v v="$VHID" '$1=="carp:" && $3=="vhid" && $4==v {print $2}')
    if [ -z "$state" ]; then
        logger -t "$TAG" "no CARP state for vhid $VHID, leaving tunnels unchanged"
        return 1
    fi

    # Start the grace period when this firewall first stops being master
    if [ "$state" = "MASTER" ]; then
        backup_since=""
    elif [ -z "$backup_since" ]; then
        backup_since=$(date +%s)
        logger -t "$TAG" "vhid $VHID is $state, keeping tunnels up for ${BACKUP_GRACE}s"
    fi

    for IF in $ifaces; do
        # The flags are on the first line of ifconfig output, e.g. flags=10080c1<UP,RUNNING,...>
        if ifconfig "$IF" | head -n1 | grep -qE "[<,]UP[,>]"; then
            up=1
        else
            up=0
        fi

        if [ "$state" = "MASTER" ] && [ "$up" -eq 0 ]; then
            ifconfig "$IF" up && logger -t "$TAG" "vhid $VHID is MASTER, brought $IF up"
        elif [ "$state" != "MASTER" ] && [ "$up" -eq 1 ] && [ $(( $(date +%s) - backup_since )) -ge "$BACKUP_GRACE" ]; then
            ifconfig "$IF" down && logger -t "$TAG" "vhid $VHID is $state, brought $IF down after ${BACKUP_GRACE}s"
        fi
    done
}

reconcile

# Check the live CARP state every few seconds. Polling doesn't depend on pfSense
# logging a CARP message for every transition: one was missing during a failover test.
while true; do
    reconcile
    sleep "$CHECK_INTERVAL"
done
