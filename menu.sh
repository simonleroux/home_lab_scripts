#!/bin/sh
# STETNET pfSense Scripts menu. Installs, updates, checks and removes the
# scripts that run on the pfSense firewalls. Run on the firewall as root:
#   fetch -qo - https://raw.githubusercontent.com/simonleroux/home_lab_scripts/refs/heads/main/menu.sh | sh

VERSION="1.1.11"

PHP="/usr/local/bin/php"
REPO_URL="https://raw.githubusercontent.com/simonleroux/home_lab_scripts/refs/heads/main"
TMP_DIR="/tmp/stetnet_pfsense"
CONFIG="/cf/conf/config.xml"

# Each script: repo file, install path, name, log tag
WG_FILE="pfsense_wg_roam_guard.sh"
WG_DEST="/root/wg_roam_guard.sh"
WG_NAME="WireGuardRoam guard"
WG_TAG="wg_roam_guard"
WG_CONF="/root/wg_roam_guard.conf"

DYN_FILE="pfsense_dyndns_guard.sh"
DYN_DEST="/root/dyndns_guard.sh"
DYN_NAME="DynDNS guard"
DYN_TAG="dyndns_guard"

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Run as root."
    exit 1
fi

# Lists the WireGuard interfaces as "name|description". The description comes
# from pfSense's config when the interface is assigned, otherwise "not assigned".
wg_interfaces() {
    assigned=$($PHP -r 'require_once("config.inc"); foreach (config_get_path("interfaces", []) as $if) { if (isset($if["if"]) && strncmp($if["if"], "tun_wg", 6) === 0) { echo $if["if"], "|", $if["descr"] ?? "", "\n"; } }' 2>/dev/null)
    for name in $(ifconfig -l | tr ' ' '\n' | grep '^tun_wg'); do
        descr=$(echo "$assigned" | sed -n "s/^$name|//p" | head -n1)
        echo "$name|${descr:-not assigned}"
    done
}

# Asks which WireGuard interfaces the guard should manage, and saves the choice.
# Enter keeps the current choice. Returns 1 if nothing is selected.
choose_wg_interfaces() {
    mkdir -p "$TMP_DIR"
    list="$TMP_DIR/wg_list"
    wg_interfaces > "$list"
    if [ ! -s "$list" ]; then
        echo "❌ No tun_wg interfaces found on this firewall."
        return 1
    fi

    current=$(sed -n 's/^IFACES="\(.*\)"$/\1/p' "$WG_CONF" 2>/dev/null)

    echo "WireGuard interfaces on this firewall:"
    i=0
    while IFS='|' read -r name descr; do
        i=$((i + 1))
        mark=" "
        case " $current " in
            *" $name "*) mark="x" ;;
        esac
        echo "  $i) [$mark] $name  ($descr)"
    done < "$list"
    echo ""

    echo -n "Numbers to manage, separated by spaces [current: ${current:-none}] (Enter keeps it): "
    read -r picks < /dev/tty
    if [ -z "$picks" ]; then
        if [ -z "$current" ]; then
            echo "❌ Nothing selected."
            return 1
        fi
        echo "Keeping: $current"
        return 0
    fi

    ifaces=""
    for n in $picks; do
        name=$(sed -n "${n}p" "$list" | cut -d'|' -f1)
        if [ -z "$name" ]; then
            echo "❌ Invalid choice: $n"
            return 1
        fi
        ifaces="$ifaces $name"
    done
    ifaces=${ifaces# }

    printf 'IFACES="%s"\n' "$ifaces" > "$WG_CONF"
    chmod 600 "$WG_CONF"
    echo "✅ The WireGuard guard will manage: $ifaces"
}

# VERSION from an installed script, or a status word
installed_version() {
    if [ -f "$1" ]; then
        v=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$1" | head -n1)
        echo "${v:-unknown (older install)}"
    else
        echo "not installed"
    fi
}

# VERSION as published on GitHub for one of the repo's files. The timestamp
# in the URL stops GitHub's cache from returning an old copy
server_version() {
    v=$(fetch -qo - "$REPO_URL/$1?t=$(date +%s)" 2>/dev/null | sed -n 's/^VERSION="\(.*\)"$/\1/p' | head -n1)
    echo "${v:-unavailable}"
}

# Says whether an installed version matches the server. $1 installed, $2 server
version_status() {
    case "$1" in
        "not installed") echo "not installed" ;;
        "$2") echo "up to date" ;;
        *)
            if [ "$2" = "unavailable" ]; then
                echo "could not reach server"
            else
                echo "UPDATE AVAILABLE, server $2 (use option 3)"
            fi
            ;;
    esac
}

show_menu() {
    menu_server=$(server_version menu.sh)
    wg_installed=$(installed_version "$WG_DEST")
    dyn_installed=$(installed_version "$DYN_DEST")
    wg_server=$(server_version "$WG_FILE")
    dyn_server=$(server_version "$DYN_FILE")
    echo "====================================="
    echo "       STETNET pfSense Scripts       "
    echo "       Menu version: $VERSION ($(version_status "$VERSION" "$menu_server"))"
    echo "       WireGuard guard: $wg_installed ($(version_status "$wg_installed" "$wg_server"))"
    echo "       DynDNS guard:    $dyn_installed ($(version_status "$dyn_installed" "$dyn_server"))"
    echo "====================================="
    echo "1) Install WireGuard guard"
    echo "2) Install DynDNS guard"
    echo "3) Update installed scripts (keeps your settings)"
    echo "4) Check status"
    echo "5) Uninstall"
    echo "0) Exit"
    echo "====================================="
}

# Downloads a repo file into the temp folder
fetch_file() {
    mkdir -p "$TMP_DIR"
    fetch -q -o "$TMP_DIR/$1" "$REPO_URL/$1"
}

# Stops a running guard. The pattern is the install path followed by "run",
# which is how each guard starts its background watcher.
stop_script() {
    pkill -f "$1 run" 2>/dev/null
    sleep 1
}

# True if a Shellcmd entry for this script is in config.xml
shellcmd_present() {
    grep -q "$1" "$CONFIG" 2>/dev/null
}

# install_script REPO_FILE INSTALL_PATH NAME TAG
install_script() {
    echo "🔧 Installing $3 version $(server_version "$1")..."
    if ! fetch_file "$1"; then
        echo "❌ Could not download $1"
        return 1
    fi

    stop_script "$2"
    install -m 700 -o root -g wheel "$TMP_DIR/$1" "$2" || return 1

    # The script starts its own background watcher, then returns
    sh "$2"
    sleep 2

    if pgrep -f "$2 run" > /dev/null; then
        echo "✅ $3 is running"
    else
        echo "❌ $3 did not start. Check the log with: sudo sh -c 'grep $4 /var/log/system.log | tail -n 5'"
    fi

    if shellcmd_present "$2"; then
        echo "✅ Shellcmd entry found, it will start at boot"
    else
        echo "ℹ️  Add a Shellcmd entry (Services > Shellcmd) with the command: /bin/sh $2"
    fi
}

# Prints the status of one script. $1 = install path, $2 = name, $3 = log tag
status_script() {
    echo ""
    echo "--- $2"
    if [ ! -f "$1" ]; then
        echo "Not installed."
        return 0
    fi
    echo "Version: $(installed_version "$1")"
    if pgrep -f "$1 run" > /dev/null; then
        echo "Running: yes"
    else
        echo "Running: NO"
    fi
    if shellcmd_present "$1"; then
        echo "Starts at boot: yes"
    else
        echo "Starts at boot: NO (add a Shellcmd entry: /bin/sh $1)"
    fi
    echo "Last log lines:"
    grep "$3" /var/log/system.log 2>/dev/null | grep -v sudo | tail -n 3
}

uninstall_script() {
    echo "🗑️  Removing $2..."
    stop_script "$1"
    rm -f "$1"
    # The WireGuard guard's interface choice goes with it
    if [ "$1" = "$WG_DEST" ]; then
        rm -f "$WG_CONF"
    fi
    echo "✅ $2 removed."
    if shellcmd_present "$1"; then
        echo "ℹ️  Remove the Shellcmd entry for $1 under Services > Shellcmd."
    fi
}

# Updates every script that is already installed, keeping its settings
update_installed() {
    echo "Menu: installed $VERSION, server $(server_version menu.sh)"
    echo "(Run the curl command again to get a newer menu.)"
    echo ""
    updated=0
    for entry in "$WG_FILE|$WG_DEST|$WG_NAME|$WG_TAG" "$DYN_FILE|$DYN_DEST|$DYN_NAME|$DYN_TAG"; do
        file=${entry%%|*}
        rest=${entry#*|}
        dest=${rest%%|*}
        rest=${rest#*|}
        name=${rest%%|*}
        tag=${rest#*|}
        if [ -f "$dest" ]; then
            install_script "$file" "$dest" "$name" "$tag"
            updated=1
        fi
    done
    if [ "$updated" -eq 0 ]; then
        echo "Nothing installed yet. Choose an Install option first."
    fi
}

while true; do
    show_menu
    echo -n "Select an option [0-5]: "
    read -r choice < /dev/tty
    echo ""
    case $choice in
        1)
            choose_wg_interfaces && install_script "$WG_FILE" "$WG_DEST" "$WG_NAME" "$WG_TAG"
            ;;
        2)
            install_script "$DYN_FILE" "$DYN_DEST" "$DYN_NAME" "$DYN_TAG"
            ;;
        3)
            update_installed
            ;;
        4)
            echo "CARP state:"
            ifconfig | grep "carp: .* vhid" || echo "No CARP VIPs found."
            echo "WireGuard tunnels managed: $(sed -n 's/^IFACES="\(.*\)"$/\1/p' "$WG_CONF" 2>/dev/null)"
            status_script "$WG_DEST" "$WG_NAME" "$WG_TAG"
            status_script "$DYN_DEST" "$DYN_NAME" "$DYN_TAG"
            ;;
        5)
            echo "Which one to remove?"
            echo "1) $WG_NAME"
            echo "2) $DYN_NAME"
            echo "3) Both"
            echo -n "Select [1-3]: "
            read -r which < /dev/tty
            echo -n "Are you sure? [y/N]: "
            read -r confirm < /dev/tty
            if [ "$confirm" = "y" ]; then
                case $which in
                    1) uninstall_script "$WG_DEST" "$WG_NAME" ;;
                    2) uninstall_script "$DYN_DEST" "$DYN_NAME" ;;
                    3)
                        uninstall_script "$WG_DEST" "$WG_NAME"
                        uninstall_script "$DYN_DEST" "$DYN_NAME"
                        ;;
                    *) echo "Invalid option." ;;
                esac
            else
                echo "Aborting."
            fi
            ;;
        0)
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
