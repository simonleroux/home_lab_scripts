# home_lab_script
## Home Lab DNS Updater

Keeps a Cloudflare A record (and an optional NextDNS link) pointed at your current public IP. Installs from this repo, the same way as `unify_scripts`.

### Install or update (run on the DNS server)

```bash
curl -fsSL https://raw.githubusercontent.com/simonleroux/home_lab_scripts/refs/heads/main/menu.sh | sudo sh
```

Menu:

```
=====================================
       STETNET DNS Scripts           
=====================================
1) Install Automatic Cloudflare/NextDNS Update
2) Update installed scripts (keeps your settings)
3) Uninstall Automatic Cloudflare/NextDNS Update
4) Exit
=====================================
```

- **Install** asks for the settings, saves them, then installs.
- **Update** re-downloads the latest scripts and applies them with the saved settings. You're not asked anything.
- **Change settings** asks again, with the current values as defaults. Press Enter to keep a value, or type `-` to clear the NextDNS URL.

Settings to enter: check interval (minutes), VIP shared by the DNS servers, Cloudflare zone name, record to update, and Cloudflare API token. The zone and record IDs are looked up automatically.

Install on **both** DNS servers. Each one runs the timer, but only the node that holds the VIP updates Cloudflare, so the two never fight over the record.

### Privileges

The updater must run as **root**. It fetches the external IP inside the `ddns_ns` network namespace, and `ip netns exec` fails for any other user (`Operation not permitted`). The systemd service runs as root. Running it by hand needs `sudo`:

```bash
sudo sh /home/siler/Script/ddns-updater.sh
```

The script is owned by root and the settings file is mode 600, so the token is not readable by other users.

### Files on the server

- `/home/siler/Script/ddns-updater.sh`: the updater, run by the timer (root-owned)
- `/etc/systemd/system/dns_updater.{service,timer}`: systemd units (service runs as `User=root`)
- `/etc/home_lab/dns_updater.env`: saved settings (mode 600). Updates never overwrite it.

### Requirements

- `curl`, `jq`, `ip` (iproute2), `systemd`. Install missing tools with `sudo apt install curl jq iproute2`.
- The `ddns_ns` network namespace must already exist. The installer warns if it doesn't.

### Check or remove

```bash
systemctl list-timers dns_updater.timer
journalctl -u dns_updater.service -n 20
```

Uninstall from the menu (option 5). It removes the timer and script, and asks before deleting the settings.
