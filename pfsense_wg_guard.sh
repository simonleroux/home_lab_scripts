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

VERSION="1.1.9"

VHID="201"
TAG="wg_roam_guard"
CONF="/root/wg_roam_guard.conf"
PIDFILE="/var/run/wg_roam_guard.pid"
# Seconds between checks. Short, so the new master brings its tunnel up fast
# and the backup notices when DNS moves
CHECK_INTERVAL=2
PHP="/usr/local/bin/php"
DOMAIN="simonleroux.ca"
HOST="vpn"
IFACE="wan"
# Public resolver used only to find the zone's nameserver. The firewall's own
# resolver can fail, so it isn't used here
BOOTSTRAP_RESOLVER="1.1.1.1"
# The backup drops its tunnels this many seconds after it sees DNS move to the
# new master. The advisory goes out at that moment, so the remote side reconnects
# within this window
DNS_MOVED_DELAY=10
# Safety limit: the backup drops its tunnels after this many seconds even if DNS
# hasn't moved
BACKUP_MAX=240
# UDP port the UniFi listeners use for failover advisories. The destination
# is found per tunnel, from the gateway in the tunnel's subnet
ADVISORY_PORT=50000
# Epoch times: when this firewall stopped being master, and when DNS first moved
# away from it. Empty while master
backup_since=""
moved_since=""

# This firewall's WAN IP, as pfSense sees it
wan_ip() {
    $PHP -r 'require_once("interfaces.inc"); echo get_interface_ip($argv[1]);' "$IFACE"
}

# Address of the zone's Cloudflare nameserver. Asking it directly skips any
# caching resolver, so the answer is the same here as on the UniFi side. The
# nameserver's own name is looked up through BOOTSTRAP_RESOLVER, because the
# firewall's local resolver can fail
auth_ns_ip() {
    ns=$(nslookup -type=ns "$DOMAIN" "$BOOTSTRAP_RESOLVER" 2>/dev/null | awk '/nameserver/ {print $NF; exit}')
    if [ -z "$ns" ]; then
        return
    fi
    nslookup "$ns" "$BOOTSTRAP_RESOLVER" 2>/dev/null | awk '/^Address/ && !/#/ {print $2; exit}'
}

# Prints the first A record for $HOST.$DOMAIN as served by the zone's nameserver
dns_lookup() {
    server=$(auth_ns_ip)
    if [ -z "$server" ]; then
        return
    fi
    nslookup "$HOST.$DOMAIN" "$server" 2>/dev/null | awk '/^Address/ && !/#/ {print $2; exit}'
}

# True if any tunnel in $ifaces is up
tunnels_up() {
    for IF in $ifaces; do
        if ifconfig "$IF" | head -n1 | grep -qE "[<,]UP[,>]"; then
            return 0
        fi
    done
    return 1
}

# The gateway configured in pfSense that sits in the same subnet as the given
# tunnel address. Args: local address, netmask in hex (e.g. 0xfffffff8)
gateway_in_subnet() {
    $PHP -r '
require_once("config.inc");
list(, $local, $maskhex) = $argv;
$mask = hexdec($maskhex);
$net = ip2long($local) & $mask;
foreach (config_get_path("gateways/gateway_item", []) as $g) {
    $gw = $g["gateway"] ?? "";
    if (filter_var($gw, FILTER_VALIDATE_IP) && $gw !== $local && (ip2long($gw) & $mask) === $net) {
        echo $gw;
        exit(0);
    }
}
exit(1);
' "$1" "$2"
}

# Tells the UniFi on each managed tunnel that a failover is starting. The
# destination is the gateway in that tunnel's subnet. The payload is the
# tunnel's public key. Sent three times, one second apart, in the background
advise_unifis() {
    for ifn in $ifaces; do
        local_ip=$(ifconfig "$ifn" | awk '/inet /{print $2; exit}')
        mask_hex=$(ifconfig "$ifn" | awk '/inet /{print $4; exit}')
        host=$(gateway_in_subnet "$local_ip" "$mask_hex")
        if [ -z "$host" ]; then
            logger -t "$TAG" "no gateway in the subnet of $ifn ($local_ip $mask_hex), not advising"
            continue
        fi
        key=$(wg show "$ifn" public-key 2>/dev/null)
        if [ -z "$key" ]; then
            logger -t "$TAG" "no public key for $ifn, not advising $host"
            continue
        fi
        (
            for n in 1 2 3; do
                printf 'failover %s\n' "$key" | nc -u -w1 "$host" "$ADVISORY_PORT"
                sleep 1
            done
        ) &
        logger -t "$TAG" "advised $host of failover on $ifn"
    done
}

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

    # Track when this firewall stopped being master, and when DNS moved away from it
    if [ "$state" = "MASTER" ]; then
        backup_since=""
        moved_since=""
    elif [ -z "$backup_since" ]; then
        backup_since=$(date +%s)
        logger -t "$TAG" "vhid $VHID is $state, keeping tunnels up until DNS moves"
    fi

    # Decide whether a backup should drop its tunnels now
    drop=0
    if [ "$state" != "MASTER" ] && [ -n "$backup_since" ] && tunnels_up; then
        now=$(date +%s)
        if [ $((now - backup_since)) -ge "$BACKUP_MAX" ]; then
            drop=1
        else
            want=$(wan_ip)
            got=$(dns_lookup)
            if [ -n "$want" ] && [ -n "$got" ] && [ "$got" != "$want" ]; then
                # DNS is live on the new master. Advise the remote side now, then
                # drop the tunnels after the delay
                if [ -z "$moved_since" ]; then
                    moved_since=$now
                    logger -t "$TAG" "DNS now shows $got, advising and dropping tunnels in ${DNS_MOVED_DELAY}s"
                    advise_unifis
                fi
                if [ $((now - moved_since)) -ge "$DNS_MOVED_DELAY" ]; then
                    drop=1
                fi
            else
                moved_since=""
            fi
        fi
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
        elif [ "$state" != "MASTER" ] && [ "$up" -eq 1 ] && [ "$drop" -eq 1 ]; then
            ifconfig "$IF" down && logger -t "$TAG" "vhid $VHID is $state, brought $IF down"
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
