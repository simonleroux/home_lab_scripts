# Changelog

Every change to the scripts is recorded here. Each script has a `VERSION` line; bump it when you change that file and note the new version in the entry below.

## 1.1.1 - 2026-10-24

### Changed
- `menu.sh` (VERSION 1.1.1): version bumped with this release. No menu behaviour change.
- `pfsense_dyndns_guard.sh` (VERSION 1.1.1): on the MASTER, checks every 5 seconds that public DNS (`nslookup` against 1.1.1.1) shows this firewall's WAN IP. If it doesn't, it forces a DynDNS sync and logs what DNS returned. Forced syncs are limited to one per host every 300 seconds. The enable-and-sync path uses the same limit.

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
