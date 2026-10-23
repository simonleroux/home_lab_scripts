#!/bin/sh
# Home Lab DNS Updater menu. Run on the DNS server:
#   curl -fsSL https://raw.githubusercontent.com/simonleroux/home_lab_scripts/refs/heads/main/menu.sh | sudo sh

REPO_URL="https://raw.githubusercontent.com/simonleroux/home_lab_scripts/refs/heads/main"
TMP_DIR="/tmp/home_lab_scripts"
CONF_DIR="/etc/home_lab"
ENV_FILE="$CONF_DIR/dns_updater.env"

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Run as root: curl -fsSL $REPO_URL/menu.sh | sudo sh"
    exit 1
fi
mkdir -p "$TMP_DIR"

show_menu() {
    echo "====================================="
    echo "       STETNET DNS Scripts           "
    echo "====================================="
    echo "1) Install Automatic DNS Update"
    echo "2) Update installed scripts (keeps your settings)"
    echo "3) Uninstall Automatic Cloudflare/NextDNS Update"
    echo "4) Exit"
    echo "====================================="
}

# Read a KEY="value" line from the settings file (empty if missing)
read_setting() {
    [ -f "$ENV_FILE" ] || return 0
    sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$ENV_FILE" | head -n1
}

load_settings() {
    DDNS_INTERVAL_SEC=$(read_setting DDNS_INTERVAL_SEC)
    DDNS_VIP=$(read_setting DDNS_VIP)
    DDNS_RECORD_NAME=$(read_setting DDNS_RECORD_NAME)
    DDNS_ZONE_NAME=$(read_setting DDNS_ZONE_NAME)
    CF_API_TOKEN=$(read_setting CF_API_TOKEN)
}

write_settings() {
    mkdir -p "$CONF_DIR"
    cat > "$ENV_FILE" << EOF
# Settings for dns_updater. Written by menu.sh, read by systemd. Kept across updates.
DDNS_INTERVAL_SEC="$DDNS_INTERVAL_SEC"
DDNS_VIP="$DDNS_VIP"
DDNS_RECORD_NAME="$DDNS_RECORD_NAME"
DDNS_ZONE_NAME="$DDNS_ZONE_NAME"
CF_API_TOKEN="$CF_API_TOKEN"
EOF
    chmod 600 "$ENV_FILE"
}

# Shows the token as ****abcd so it isn't printed in full
mask() {
    if [ -n "$1" ]; then
        echo "****${1#"${1%????}"}"
    fi
}

# ask LABEL CURRENT [SHOW_FN]: Enter keeps CURRENT, "-" clears it.
# Prompts go to stderr so the answer is the only thing on stdout.
ask() {
    shown=$2
    [ -n "$3" ] && shown=$(mask "$2")
    if [ -n "$shown" ]; then
        printf "%s [%s]: " "$1" "$shown" >&2
    else
        printf "%s: " "$1" >&2
    fi
    read -r answer < /dev/tty
    if [ "$answer" = "-" ]; then
        echo ""
    else
        echo "${answer:-$2}"
    fi
}

configure() {
    load_settings
    echo ""
    echo "📝 Settings (press Enter to keep the value in brackets)"
    echo ""
    DDNS_INTERVAL_SEC=$(ask "⏱️  Check interval in seconds" "${DDNS_INTERVAL_SEC:-10}")
    DDNS_VIP=$(ask "🖧  VIP shared by the DNS servers (e.g. 192.168.1.3)" "$DDNS_VIP")
    DDNS_ZONE_NAME=$(ask "🟠 Cloudflare zone name (e.g. example.com)" "$DDNS_ZONE_NAME")
    DDNS_RECORD_NAME=$(ask "🌐 Record to keep updated (e.g. www.example.com)" "$DDNS_RECORD_NAME")
    CF_API_TOKEN=$(ask "🟠 Cloudflare API token (DNS:Edit)" "$CF_API_TOKEN" secret)

    if [ -z "$DDNS_VIP" ] || [ -z "$DDNS_ZONE_NAME" ] || [ -z "$DDNS_RECORD_NAME" ] || [ -z "$CF_API_TOKEN" ]; then
        echo "❌ VIP, zone name, record name and API token are required. Nothing saved."
        return 1
    fi
    case $DDNS_INTERVAL_SEC in
        ''|*[!0-9]*|0)
            echo "❌ Interval must be a whole number of seconds, above 0. Nothing saved."
            return 1
            ;;
    esac
    write_settings
    echo "💾 Settings saved to $ENV_FILE"
}

fetch_files() {
    for f in install_dns_updater.sh dns_updater.sh ddns-status.sh uninstall_dns_updater.sh; do
        curl -fsSL --max-time 60 "$REPO_URL/$f" -o "$TMP_DIR/$f" || { echo "❌ Could not download $f"; return 1; }
    done
}

# Downloads the latest files and applies them with the saved settings
apply() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "❌ No settings yet. Choose Install first."
        return 1
    fi
    fetch_files || return 1
    sh "$TMP_DIR/install_dns_updater.sh"
}

uninstall() {
    printf "Uninstall DNS updater from this server? [y/N]: "
    read -r confirm < /dev/tty
    [ "$confirm" = "y" ] || { echo "Aborting."; return 0; }
    fetch_files || return 1
    sh "$TMP_DIR/uninstall_dns_updater.sh"
    printf "Also delete the saved settings in %s? [y/N]: " "$ENV_FILE"
    read -r confirm < /dev/tty
    if [ "$confirm" = "y" ]; then
        rm -f "$ENV_FILE"
        echo "🗑️  Settings deleted."
    fi
}

while true; do
    show_menu
    echo -n "Select an option [1-4]: "
    read -r choice < /dev/tty
    echo ""
    case $choice in
        1)
            configure && apply
            ;;
        2)
            apply
            ;;
        3)
            uninstall
            ;;
        4)
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
    echo ""
    echo -n "Press Enter to return to menu..."
    read -r dummy < /dev/tty
done
