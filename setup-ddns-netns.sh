#!/bin/bash
# Creates the ddns_ns network namespace used by the DDNS updater for the VPN record.
# Moves the second NIC (eth1, shown as ens192) into the namespace, so the
# namespace has its own route out through the VPN gateway.
#
# Per-server values, set these for each DNS server before running:
#   nextdns101: NIC address 192.168.1.121/24, gateway 192.168.1.2, DNS 192.168.1.3
#   nextdns102: NIC address 192.168.1.122/24, gateway 192.168.1.2, DNS 192.168.1.3
#   (Both already have this namespace. Don't run this on a server that has it.)
#
# Installed to /usr/local/bin/setup-ddns-netns.sh by the steps in the README.
# Runs at boot from ddns-netns-setup.service.

# Create namespace
ip netns add ddns_ns

# Move eth1 into the namespace
ip link set eth1 netns ddns_ns

# Configure eth1 inside the namespace
# We need to give it an IP address in the 192.168.1.x subnet
ip netns exec ddns_ns ip addr add 192.168.1.121/24 dev ens192
ip netns exec ddns_ns ip link set ens192 up

# Add the specific gateway (192.168.1.2) inside the namespace
ip netns exec ddns_ns ip route add default via 192.168.1.2 dev ens192

# Set up DNS inside the namespace so curl can resolve domain names
mkdir -p /etc/netns/ddns_ns
echo "nameserver 192.168.1.3" > /etc/netns/ddns_ns/resolv.conf
