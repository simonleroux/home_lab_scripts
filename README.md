# home_lab_scripts

Scripts for the home lab's pfSense firewalls. A CARP pair (`pfSense-101` and `pfSense-102`) shares two VIPs:

- `192.168.1.1` (vhid 1, LAN gateway): the owner publishes `www.simonleroux.ca`
- `192.168.1.2` (vhid 201, VPN control): the owner publishes `vpn.simonleroux.ca` and holds the WireGuardRoam tunnel

Each firewall checks which VIPs it owns, so the two never publish the same record or hold the tunnel at the same time.

## pfSense menu

Install, update, check and remove the guards from the menu. Run this on each firewall, as root:

```sh
fetch -qo - https://raw.githubusercontent.com/simonleroux/home_lab_scripts/refs/heads/main/menu.sh | sh
```

```
=====================================
       STETNET pfSense Scripts       
=====================================
1) Install WireGuardRoam guard
2) Install DynDNS guard
3) Update installed scripts (keeps your settings)
4) Check status
5) Uninstall
6) Exit
=====================================
```

- **Install** downloads the script to `/root`, makes it executable, stops any older copy, and starts it. The menu then checks for a Shellcmd entry.
- **Update installed scripts** re-downloads and restarts every guard that is installed. Nothing is asked, and the scripts keep no per-firewall settings.
- **Check status** shows the CARP state, whether each guard is running, whether it starts at boot, and its last log lines.
- **Uninstall** stops and removes the chosen guard. It doesn't remove the Shellcmd entry, so the menu tells you to remove that under Services > Shellcmd.

### Start at boot

The menu can't add Shellcmd entries, so add one for each guard the first time you install it: **Services > Shellcmd**, command `/bin/sh /root/<script>.sh` (for example `/bin/sh /root/wg_roam_guard.sh`). The guard starts its own background watcher, so Shellcmd returns straight away.

## WireGuardRoam guard

`pfsense_wg_roam_guard.sh` keeps the `WireGuardRoam` tunnel (`tun_wg3`) up only on the CARP master of vhid 201. The backup firewall takes the tunnel down.

It checks the live CARP state every 5 seconds and sets the tunnel to match. It doesn't rely on pfSense's log messages, because one CARP transition was missing from the log during testing. Changes are logged with the `wg_roam_guard` tag.

Failover was tested in both directions. Putting `pfSense-102` in persistent CARP maintenance mode dropped the tunnel on `102` and brought it up on `101`. Leaving maintenance mode reversed both.

The guard changes only the running interface state. The GUI still shows the interface as enabled, and the script sets it on each run.

## DynDNS guard

`pfsense_dyndns_guard.sh` decides which firewall publishes each Cloudflare record, based on the CARP owner of each VIP:

- Owner of `192.168.1.1` (vhid 1) enables the `www` DynDNS entry.
- Owner of `192.168.1.2` (vhid 201) enables the `vpn` DynDNS entry.
- The non-owner disables its copy of each entry.

Both firewalls keep both entries. pfSense does the Cloudflare update itself, so the script never calls the Cloudflare API. When an entry is enabled, the script runs `/etc/rc.dyndns.update wan` to publish it straight away. HA config sync doesn't cover DynDNS, so each firewall's entries stay local.

The guard writes `config.xml` when it changes an entry, so the change shows up in the GUI under Services > Dynamic DNS.

## Check the guards

```sh
ps -ax -o pid,command | grep -E "wg_roam_guard|dyndns_guard" | grep -v grep
sudo sh -c 'grep -E "wg_roam_guard|dyndns_guard" /var/log/system.log | grep -v sudo | tail -n 5'
ifconfig | grep "carp: .* vhid"
ifconfig tun_wg3 | head -n1
```

`sudo` is needed to read `/var/log/system.log`. The `grep -v sudo` removes the lines your own `sudo` commands add, which would otherwise show up as matches.

## Versions

Each script has a `VERSION` line, and `CHANGELOG.md` lists what changed in each version. The menu shows the menu version and each guard's installed version. Update shows the server version too, so you can see whether an update is available. When you change a script, bump its `VERSION` and add an entry to the changelog.
