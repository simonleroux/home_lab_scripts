#!/bin/sh
# STETNET pfSense Scripts menu. Installs, updates, checks and removes the
# scripts that run on the pfSense firewalls. Run on the firewall as root:
#   fetch -qo - https://raw.githubusercontent.com/simonleroux/home_lab_scripts/refs/heads/main/menu.sh | sh

REPO_URL="https://raw.githubusercontent.com/simonleroux/home_lab_scripts/refs/heads/main"
TMP_DIR="/tmp/stetnet_pfsense"
CONFIG="/cf/conf/config.xml"

# Each script: repo file, install path, name, log tag
WG_FILE="pfsense_wg_roam_guard.sh"
WG_DEST="/root/wg_roam_guard.sh"
WG_NAME="WireGuardRoam guard"
WG_TAG="wg_roam_guard"

DYN_FILE="pfsense_dyndns_guard.sh"
DYN_DEST="/root/dyndns_guard.sh"
DYN_NAME="DynDNS guard"
DYN_TAG="dyndns_guard"

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Run as root."
    exit 1
fi

show_menu() {
    echo "====================================="
    echo "       STETNET pfSense Scripts       "
    echo "====================================="
    echo "1) Install WireGuardRoam guard"
    echo "2) Install DynDNS guard"
    echo "3) Update installed scripts (keeps your settings)"
    echo "4) Check status"
    echo "5) Uninstall"
    echo "6) Exit"
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
    echo "🔧 Installing $3..."
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
    echo "✅ $2 removed."
    if shellcmd_present "$1"; then
        echo "ℹ️  Remove the Shellcmd entry for $1 under Services > Shellcmd."
    fi
}

# Updates every script that is already installed, keeping its settings
update_installed() {
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
    echo -n "Select an option [1-6]: "
    read -r choice < /dev/tty
    echo ""
    case $choice in
        1)
            install_script "$WG_FILE" "$WG_DEST" "$WG_NAME" "$WG_TAG"
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
        6)
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
