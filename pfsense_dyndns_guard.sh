#!/bin/sh
# DynDNS guard for pfSense. Each CARP VIP owner enables its own Cloudflare
# DynDNS entry and forces a sync. The non-owner disables its copy, so only one
# firewall publishes each record.
#
#   vhid 1   (192.168.1.1, LAN gateway)  -> www.simonleroux.ca
#   vhid 201 (192.168.1.2, VPN control)  -> vpn.simonleroux.ca
#
# Each DynDNS entry exists on both firewalls. pfSense handles the Cloudflare
# update itself. This script only toggles the entry's enable flag in config.xml
# and runs /etc/rc.dyndns.update for the WAN.
#
# Checks the CARP state every 5 seconds, so no cron job is needed.
# Start at boot with Shellcmd: /bin/sh /root/dyndns_guard.sh
# Install to /root/dyndns_guard.sh (chmod 700). See README.md.

VERSION="1.1.1"

PHP="/usr/local/bin/php"
DOMAIN="simonleroux.ca"
IFACE="wan"
TAG="dyndns_guard"
PIDFILE="/var/run/dyndns_guard.pid"
# vhid:host pairs
MAP="1:www 201:vpn"
# Public resolver to check what Cloudflare is serving
DNS_RESOLVER="1.1.1.1"
# Minimum seconds between forced syncs for one host, so a slow DNS
# update can't cause a sync every 5 seconds
RESYNC_MIN_INTERVAL=300

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

# CARP state of a vhid on any interface: MASTER, BACKUP, INIT, or empty
carp_state() {
    ifconfig | awk -v v="$1" '$1=="carp:" && $3=="vhid" && $4==v {print $2}'
}

# Prints 1 if the DynDNS entry for $1 is enabled in config.xml, else 0
entry_enabled() {
    $PHP -r '
require_once("config.inc");
list(, $host, $domain) = $argv;
foreach (config_get_path("dyndnses/dyndns", []) as $entry) {
    if ($entry["host"] === $host && $entry["domainname"] === $domain) {
        echo array_key_exists("enable", $entry) ? "1\n" : "0\n";
        exit(0);
    }
}
echo "0\n";
' "$1" "$DOMAIN"
}

# Sets the enable flag for the DynDNS entry for $2 ("enable" or "disable") and saves config.xml
set_entry() {
    $PHP -r '
require_once("config.inc");
list(, $action, $host, $domain) = $argv;
foreach (config_get_path("dyndnses/dyndns", []) as $i => $entry) {
    if ($entry["host"] !== $host || $entry["domainname"] !== $domain) {
        continue;
    }
    if ($action === "enable") {
        config_set_path("dyndnses/dyndns/$i/enable", "");
    } else {
        config_del_path("dyndnses/dyndns/$i/enable");
    }
    write_config("dyndns_guard: $action DynDNS entry $host.$domain");
    exit(0);
}
exit(1);
' "$1" "$2" "$DOMAIN"
}

# This firewall's WAN IP, as pfSense sees it
wan_ip() {
    $PHP -r 'require_once("interfaces.inc"); echo get_interface_ip($argv[1]);' "$IFACE"
}

# Prints the first A record for $1.$DOMAIN as seen by $DNS_RESOLVER
dns_lookup() {
    nslookup "$1.$DOMAIN" "$DNS_RESOLVER" 2>/dev/null | awk '/^Address/ && !/#/ {print $2; exit}'
}

# Runs rc.dyndns.update, at most once per RESYNC_MIN_INTERVAL for host $1.
# $2 is the reason, for the log
force_sync() {
    stamp="/var/run/dyndns_guard.$1.resync"
    now=$(date +%s)
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt "$RESYNC_MIN_INTERVAL" ]; then
        return
    fi
    echo "$now" > "$stamp"
    $PHP -f /etc/rc.dyndns.update "$IFACE"
    logger -t "$TAG" "$2, forced a sync for $1.$DOMAIN"
}

# On the MASTER, check that public DNS shows this firewall's WAN IP.
# If not, force a sync
verify_dns() {
    want=$(wan_ip)
    if [ -z "$want" ]; then
        return
    fi
    got=$(dns_lookup "$1")
    if [ "$got" != "$want" ]; then
        force_sync "$1" "$1.$DOMAIN resolves to '${got:-nothing}', expected $want"
    fi
}

reconcile() {
    for pair in $MAP; do
        vhid=${pair%%:*}
        host=${pair#*:}

        state=$(carp_state "$vhid")
        if [ -z "$state" ]; then
            continue
        fi

        enabled=$(entry_enabled "$host")

        if [ "$state" = "MASTER" ] && [ "$enabled" = "0" ]; then
            if set_entry enable "$host"; then
                logger -t "$TAG" "vhid $vhid is MASTER, enabled $host.$DOMAIN"
                force_sync "$host" "vhid $vhid became MASTER"
            fi
        elif [ "$state" = "MASTER" ] && [ "$enabled" = "1" ]; then
            verify_dns "$host"
        elif [ "$state" != "MASTER" ] && [ "$enabled" = "1" ]; then
            if set_entry disable "$host"; then
                logger -t "$TAG" "vhid $vhid is $state, disabled $host.$DOMAIN"
            fi
        fi
    done
}

reconcile

while true; do
    sleep 5
    reconcile
done
