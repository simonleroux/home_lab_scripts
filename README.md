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

Settings to enter: check interval (seconds, default 10), VIP shared by the DNS servers, Cloudflare zone name, the VPN record (updated through the `ddns_ns` namespace), the normal record (updated over the default route), and the Cloudflare API token. The zone and record IDs are looked up automatically.

Example: `vpn.example.com` goes through the namespace and `www.example.com` uses the normal connection.

The settings file used to have one `DDNS_RECORD_NAME`. Install asks for the two new record names, so enter them once after updating.

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
sudo sh /home/siler/Script/ddns-status.sh      # service, timer, next run, last run's log
sudo sh /home/siler/Script/ddns-status.sh -f   # follow the log live (Ctrl+C to stop)
```

The status script needs `sudo` to see every log message. Without it, the journal hides messages from other users.

Uninstall from the menu (option 3). It removes the timer and script, and asks before deleting the settings.

### VPN namespace setup (`vpn.*` record)

The `vpn.*` record's IP is read from inside the `ddns_ns` network namespace, so it reflects the VPN gateway and not the normal connection. The namespace is created at boot by `ddns-netns-setup.service`, and the updater starts after it.

Files in this repo:

- `setup-ddns-netns.sh`: creates the namespace, moves the second NIC (`eth1`, shown as `ens192`) into it, and sets its address, gateway (`192.168.1.2`) and DNS (`192.168.1.3`). Installs to `/usr/local/bin/setup-ddns-netns.sh`.
- `ddns-netns-setup.service`: runs the script once at boot. Installs to `/etc/systemd/system/`.

Set up a server (run once, as root):

```bash
sudo cp setup-ddns-netns.sh /usr/local/bin/setup-ddns-netns.sh
sudo chmod 755 /usr/local/bin/setup-ddns-netns.sh
sudo cp ddns-netns-setup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ddns-netns-setup.service
```

Each server needs its own values in the script: the NIC address, gateway and DNS (see the header of `setup-ddns-netns.sh`). Check the second NIC's name and address with `ip -br addr` before running it. The script assumes the NIC is `eth1`, so if the name differs, edit the `ip link set` line.

Check the namespace:

```bash
ip netns list
sudo ip netns exec ddns_ns ip route
cat /etc/netns/ddns_ns/resolv.conf
```

The namespace's default route should go through the gateway (`192.168.1.2`), and the host's default route should stay on `ens160`.

Moving the NIC removes it from the host. Make sure you have console or out-of-band access before running the setup on a server you reach over the network.
