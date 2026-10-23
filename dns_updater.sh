#!/bin/sh
# DDNS updater for a VIP pair of DNS servers. Only the node that owns the VIP
# updates the Cloudflare A record, so both servers can run this on the timer.
# Settings come from /etc/home_lab/dns_updater.env (loaded by systemd).
#
# Must run as root: the external IP is fetched inside the ddns_ns network
# namespace, and "ip netns exec" needs root.

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

for var in DDNS_VIP DDNS_RECORD_NAME DDNS_ZONE_NAME CF_API_TOKEN; do
    eval "value=\${$var:-}"
    if [ -z "$value" ]; then
        log "ERROR: $var is not set. Run menu.sh and choose Install."
        exit 1
    fi
done

# Call the Cloudflare API from inside the namespace
cf_api() {
    ip netns exec "$NETNS" curl -s --max-time 10 "$@" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json"
}

log "Starting DDNS check..."

# 1. Check if this server owns the VIP
if ! ip addr show | grep -q "inet $DDNS_VIP/"; then
    log "Node does not own VIP $DDNS_VIP, exiting"
    exit 0
fi

log "Node owns VIP $DDNS_VIP. Proceeding with update check."

if ! ip netns list | grep -qw "$NETNS"; then
    log "ERROR: network namespace $NETNS does not exist."
    exit 1
fi

# 2. Get current external IP
log "Fetching current external IP..."
CURRENT_EXT_IP=$(ip netns exec "$NETNS" curl -s --max-time 10 https://cloudflare.com/cdn-cgi/trace | grep '^ip=' | cut -d= -f2)

if [ -z "$CURRENT_EXT_IP" ]; then
    log "ERROR: Could not retrieve external IP."
    exit 1
fi
log "Current external IP is: $CURRENT_EXT_IP"

# 3. Look up the Zone ID and Record ID through the API
log "Searching for Zone and Record ID for $DDNS_RECORD_NAME..."

ZONE_ID=$(cf_api -X GET "https://api.cloudflare.com/client/v4/zones?name=$DDNS_ZONE_NAME" | jq -r '.result[0].id')
if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
    log "ERROR: Could not find Zone ID for $DDNS_ZONE_NAME"
    exit 1
fi

RECORD_DATA=$(cf_api -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DDNS_RECORD_NAME&type=A")
RECORD_ID=$(echo "$RECORD_DATA" | jq -r '.result[0].id')
RECORD_IP=$(echo "$RECORD_DATA" | jq -r '.result[0].content')

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" = "null" ]; then
    log "ERROR: Could not find A record for $DDNS_RECORD_NAME"
    exit 1
fi

log "Found Record ID: $RECORD_ID (Current IP: $RECORD_IP)"

# 4. Compare and update if needed
if [ "$CURRENT_EXT_IP" != "$RECORD_IP" ]; then
    log "IP mismatch detected. Initiating update to Cloudflare..."

    RESPONSE=$(cf_api -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        --data "{\"content\":\"$CURRENT_EXT_IP\",\"name\":\"$DDNS_RECORD_NAME\",\"proxied\":false,\"type\":\"A\"}")

    if echo "$RESPONSE" | jq -e '.success' > /dev/null; then
        log "SUCCESS: Updated $DDNS_RECORD_NAME to $CURRENT_EXT_IP"
    else
        log "ERROR: Update failed. Response: $RESPONSE"
        exit 1
    fi
else
    log "IP matches ($CURRENT_EXT_IP). No update required."
fi

log "DDNS check complete."
exit 0
