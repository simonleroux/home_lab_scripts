# Changelog

Every change to the scripts is recorded here. Each script has a `VERSION` line; bump it when you change that file and note the new version in the entry below.

## 1.1.17 - 2026-10-27

### Changed
- `menu.sh` (VERSION 1.1.17): version bumped with this release. No menu behaviour change.
- `pfsense_wg_guard.sh` (VERSION 1.1.8): DNS is checked against the zone's own Cloudflare nameserver, not 1.1.1.1, so the backup sees the new IP as soon as it's live, without a resolver cache delay. When the new IP is seen, the backup sends the advisory at once and drops its tunnels 10 seconds later. The 90-second wait from 1.1.7 is removed, and so is the two-checks-in-a-row rule.

## 1.1.16 - 2026-10-27

### Changed
- `menu.sh` (VERSION 1.1.16): version bumped with this release. No menu behaviour change.
- `pfsense_wg_guard.sh` (VERSION 1.1.7): the backup keeps its tunnels up for 90 seconds after DNS moves to the new master, instead of 15. Traffic keeps flowing through the old firewall until the remote side reconnects, so the outage is only the switch-over. The safety limit is now 240 seconds. The failover can take about a minute, but the outage should be a few seconds.

## 1.1.15 - 2026-10-27

### Changed
- `menu.sh` (VERSION 1.1.15): version bumped with this release. No menu behaviour change.
- `pfsense_wg_guard.sh` (VERSION 1.1.6): the failover advisory's destination is now found per tunnel. The guard reads each managed tunnel's address and netmask, then sends to the pfSense gateway in the same subnet (on the current setup: 192.168.254.6 for tun_wg1, 192.168.254.14 for tun_wg2, 192.168.254.22 for tun_wg3). The hardcoded 192.168.11.1, 12.1 and 13.1 addresses are removed. The UniFi listeners must listen on their tunnel addresses, not their LAN addresses. Port 50000 is unchanged.

## 1.1.14 - 2026-10-27

### Changed
- `pfsense_wg_roam_guard.sh` renamed to `pfsense_wg_guard.sh`, since the guard manages any chosen tunnel. The firewall install path (`/root/wg_roam_guard.sh`), the config file and the log tag are unchanged, so existing installs and Shellcmd entries keep working.
- `pfsense_wg_guard.sh` (VERSION 1.1.5): same behaviour as 1.1.4, under the new file name.
- `menu.sh` (VERSION 1.1.14): fetches `pfsense_wg_guard.sh` from the repo. No other menu change.
- README: refers to the new file name.

## 1.1.13 - 2026-10-27

### Changed
- `menu.sh` (VERSION 1.1.13): version bumped with this release. No menu behaviour change.
- `pfsense_wg_roam_guard.sh` (VERSION 1.1.4): when DNS for `vpn.simonleroux.ca` shows another firewall's IP on two checks in a row, the backup sends a UDP advisory to each UniFi (192.168.11.1, 192.168.12.1, 192.168.13.1 on tun_wg1, tun_wg2, tun_wg3). It goes out over that tunnel, three times, to port 50000. Payload: `failover <tunnel public key>`. The UniFi listener starts its 30-second fast window on receipt, then falls back to its normal check. The tunnel drop still waits 15 seconds after the advisory.

## 1.1.12 - 2026-10-27

### Changed
- `menu.sh` (VERSION 1.1.12): version bumped with this release. No menu behaviour change.
- `pfsense_wg_roam_guard.sh` (VERSION 1.1.3): replaces the fixed 90-second backup grace with a DNS check. The CARP check runs every 2 seconds. While the backup holds the VIP's tunnel, it keeps it up as long as DNS for `vpn.simonleroux.ca` points at its own WAN IP. Once DNS shows another IP, it drops the tunnels 15 seconds later, which leaves time for the remote side's check to reconnect. A 180-second limit drops them even if DNS never moves. This supersedes the 90-second grace from 1.1.1 and the 10-second interval from 1.1.2.

## 1.1.11 - 2026-10-27

### Changed
- `menu.sh` (VERSION 1.1.11): version bumped with this release. No menu behaviour change.
- `pfsense_wg_roam_guard.sh` (VERSION 1.1.2): the CARP check runs every 10 seconds, so the new master brings its tunnel up within 10 seconds of taking the VIP. The backup keeps its tunnel up for 90 seconds after losing the VIP, so clients whose cached DNS still points at it keep working until the DNS record moves. Both firewalls can have the tunnel up at the same time during that window.

## 1.1.10 - 2026-10-27

### Changed
- `menu.sh` (VERSION 1.1.10): version bumped with this release. No menu behaviour change.
- `pfsense_wg_roam_guard.sh` (VERSION 1.1.1): the CARP check runs every 2 seconds instead of 5, so the new master brings its tunnel up sooner. The backup keeps its tunnel up for 90 seconds after losing the VIP, so clients whose cached DNS still points at it keep working until the DNS record moves. Both firewalls can have the tunnel up at the same time during that window.

## 1.1.9 - 2026-10-27

### Changed
- `menu.sh` (VERSION 1.1.9): menu option 1 is now "Install WireGuard guard" instead of "Install WireGuardRoam guard". The option does the same thing.
- `pfsense_dyndns_guard.sh` and `pfsense_wg_roam_guard.sh`: unchanged, still at their current versions.

## 1.1.8 - 2026-10-24

### Changed
- `menu.sh` (VERSION 1.1.8): the header shows whether the menu and each guard are up to date, compared with GitHub. It says "UPDATE AVAILABLE" with the server version when they differ. Server version checks now use a timestamp in the URL, so GitHub's cache doesn't hide new releases.
- `pfsense_dyndns_guard.sh` and `pfsense_wg_roam_guard.sh`: unchanged, still at their current versions.

## 1.1.7 - 2026-10-24

### Changed
- `menu.sh` (VERSION 1.1.7): Exit is option 0 instead of 6. The prompt reads `[0-5]`. Exit still ends the menu with exit code 0.
- `pfsense_dyndns_guard.sh` and `pfsense_wg_roam_guard.sh`: unchanged, still at their current versions.

## 1.1.6 - 2026-10-24

### Changed
- `pfsense_dyndns_guard.sh` (VERSION 1.1.6): a mismatch now calls `services_dyndns_configure_client` for the host that's out of date, with `force` set. This is the call the GUI's "Save & Force Update" makes. 1.1.5's `services_dnsupdate_process` call ran without error but didn't update Cloudflare for `vpn`. The forced update now covers only the host that mismatched, not every WAN entry.
- `menu.sh` (VERSION 1.1.6): version bumped with this release. No menu behaviour change.

## 1.1.5 - 2026-10-24

### Changed
- `pfsense_dyndns_guard.sh` (VERSION 1.1.5): a mismatch now triggers a forced DynDNS update (`services_dnsupdate_process` with `forced` set) instead of `rc.dyndns.update`. `rc.dyndns.update` skips entries whose cached IP matches the WAN IP, even when Cloudflare has a different value, which is what left `vpn` stale after the failover. The forced update covers all WAN DynDNS entries, so a mismatch on either host updates both.
- `menu.sh` (VERSION 1.1.5): version bumped with this release. No menu behaviour change.

## 1.1.4 - 2026-10-24

### Changed
- `pfsense_dyndns_guard.sh` (VERSION 1.1.4): the log now says "requested a DynDNS sync" instead of "forced a sync", because the guard can't see whether pfSense sent an update. When a mismatch is fixed, the guard logs that the record now resolves to the expected IP.
- `menu.sh` (VERSION 1.1.4): version bumped with this release. No menu behaviour change.

## 1.1.3 - 2026-10-24

### Changed
- `pfsense_dyndns_guard.sh` (VERSION 1.1.3): the DNS check on the firewall queries `1.1.1.1`. This reverts the `192.168.1.3` change from 1.1.2, which applied only to checks run from a PC.
- `menu.sh` (VERSION 1.1.3): version bumped with this release. No menu behaviour change.

## 1.1.2 - 2026-10-24

### Changed
- `pfsense_dyndns_guard.sh` (VERSION 1.1.2): the DNS check queried `192.168.1.3`. Reverted in 1.1.3.
- `menu.sh` (VERSION 1.1.2): version bumped with this release. No menu behaviour change.

## 1.1.1 - 2026-10-24

### Changed
- `menu.sh` (VERSION 1.1.1): version bumped with this release. No menu behaviour change.
- `pfsense_dyndns_guard.sh` (VERSION 1.1.1): on the MASTER, checks every 5 seconds that DNS shows this firewall's WAN IP. If it doesn't, it forces a DynDNS sync and logs what DNS returned. Forced syncs are limited to one per host every 300 seconds. The enable-and-sync path uses the same limit.

## 1.1.0 - 2026-10-24

### Changed
- `pfsense_wg_roam_guard.sh` (VERSION 1.1.0): manages every WireGuard tunnel listed in `/root/wg_roam_guard.conf`, not only `tun_wg3`. The config is read on every check, so changes apply without a restart.
- `menu.sh` (VERSION 1.1.0): Install WireGuardRoam guard lists the `tun_wg` interfaces, with their pfSense descriptions, and asks which to manage. Enter keeps the current choice. Status shows the tunnels being managed. Uninstall removes the choice too.

## 1.0.0 - 2026-10-24

### Added
- `menu.sh` manages the pfSense guards: install, update, status and uninstall. It shows the menu version and each guard's installed version, and the update option shows the server version.
- `pfsense_wg_roam_guard.sh` (VERSION 1.0.0): keeps `tun_wg3` (WireGuardRoam) up only on the CARP master of vhid 201. It checks the live CARP state every 5 seconds.
- `pfsense_dyndns_guard.sh` (VERSION 1.0.0): enables the `www` DynDNS entry on the owner of vhid 1 and the `vpn` entry on the owner of vhid 201, disables the other copy, and forces a sync when enabling.
- `VERSION` in every script, and this changelog.

### Removed
- The Linux updater (`dns_updater.sh`, `install_dns_updater.sh`, `uninstall_dns_updater.sh`, `ddns-status.sh`) and the namespace setup (`setup-ddns-netns.sh`, `ddns-netns-setup.service`). pfSense now publishes both records.

### Known issues
- The guards change only the running interface state for the tunnel. The GUI still shows it enabled, and the guard sets it again on each run.
- The guards depend on `ifconfig`'s CARP output format, so a pfSense upgrade that changes it would need a check.
