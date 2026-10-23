#!/bin/sh
# DDNS updater for a VIP pair of DNS servers. Only the node that owns the VIP
# updates Cloudflare, so both servers can run this on the timer.
#
# Two records are kept up to date:
#   DDNS_NETNS_RECORD  (vpn.*)  IP seen from inside the ddns_ns namespace (VPN gateway).
#                               The IP lookup and Cloudflare calls both go through the namespace.
#   DDNS_DIRECT_RECORD (www.*)  IP seen from the normal default route. No namespace.
#
# Settings come from /etc/home_lab/dns_updater.env (loaded by systemd, or by this
# script when run by hand). Must run as root: "ip netns exec" needs root.

NETNS="ddns_ns"
ENV_FILE="/etc/home_lab/dns_updater.env"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root, e.g. sudo sh /home/siler/Script/ddns-updater.sh"
    exit 1
fi

# Load the saved settings, so a manual run behaves like the timer
if [ -f "$ENV_FILE" ]; then
    . "$ENV_FILE"
fi

for var in DDNS_VIP DDNS_ZONE_NAME CF_API_TOKEN DDNS_NETNS_RECORD DDNS_DIRECT_RECORD; do
    eval "value=\${$var:-}"
    if [ -z "$value" ]; then
        log "ERROR: $var is not set. Run menu.sh and choose Install."
        exit 1
    fi
done

# Run curl inside the namespace (netns) or on the normal route (direct)
net_curl() {
    mode=$1
    shift
    if [ "$mode" = netns ]; then
        ip netns exec "$NETNS" curl -s --max-time 10 "$@"
    else
        curl -s --max-time 10 "$@"
    fi
}

# Cloudflare API call over the given route
cf_api() {
    mode=$1
    shift
    net_curl "$mode" "$@" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json"
}

# Update one record. $1 = record name, $2 = netns or direct
update_record() {
    name=$1
    mode=$2

    log "[$name] checking via $mode route..."

    current_ip=$(net_curl "$mode" https://cloudflare.com/cdn-cgi/trace | grep '^ip=' | cut -d= -f2)
    if [ -z "$current_ip" ]; then
        log "ERROR: [$name] could not retrieve external IP."
        return 1
    fi
    log "[$name] current external IP is: $current_ip"

    zone_id=$(cf_api "$mode" -X GET "https://api.cloudflare.com/client/v4/zones?name=$DDNS_ZONE_NAME" | jq -r '.result[0].id')
    if [ -z "$zone_id" ] || [ "$zone_id" = "null" ]; then
        log "ERROR: [$name] could not find Zone ID for $DDNS_ZONE_NAME"
        return 1
    fi

    record_data=$(cf_api "$mode" -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$name&type=A")
    record_id=$(echo "$record_data" | jq -r '.result[0].id')
    record_ip=$(echo "$record_data" | jq -r '.result[0].content')
    if [ -z "$record_id" ] || [ "$record_id" = "null" ]; then
        log "ERROR: [$name] could not find A record"
        return 1
    fi
    log "[$name] found record ID $record_id (current IP: $record_ip)"

    if [ "$current_ip" = "$record_ip" ]; then
        log "[$name] IP matches ($current_ip). No update required."
        return 0
    fi

    log "[$name] IP mismatch, updating to $current_ip..."
    response=$(cf_api "$mode" -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
        --data "{\"content\":\"$current_ip\",\"name\":\"$name\",\"proxied\":false,\"type\":\"A\"}")

    if echo "$response" | jq -e '.success' > /dev/null; then
        log "SUCCESS: [$name] updated to $current_ip"
        return 0
    fi
    log "ERROR: [$name] update failed. Response: $response"
    return 1
}

log "Starting DDNS check..."

# 1. Only the VIP owner updates
if ! ip addr show | grep -q "inet $DDNS_VIP/"; then
    log "Node does not own VIP $DDNS_VIP, exiting"
    exit 0
fi
log "Node owns VIP $DDNS_VIP. Proceeding with update check."

# 2. Update both records. Keep going if one fails, and report failure at the end.
status=0

# The VPN record needs the namespace. The normal record doesn't, so it still updates if the namespace is missing.
if ip netns list | grep -qw "$NETNS"; then
    update_record "$DDNS_NETNS_RECORD" netns || status=1
else
    log "ERROR: network namespace $NETNS does not exist, skipping $DDNS_NETNS_RECORD."
    status=1
fi
update_record "$DDNS_DIRECT_RECORD" direct || status=1

log "DDNS check complete."
exit $status
