#!/bin/sh

set -e

# Docker container ID
id="$(docker inspect --format '{{ printf "%.12s" .Id }}' "$1")"

# Interface names
ext="nw-$id"
int="nwt-$$"

# IPv4 addresses
ipv4="$2"
gwv4="$3"

# IPv6 addresses
ipv6="$4"
gwv6="$5"

# Temporary network namespace name
ns="$int"

# Determine Docker container PID
pid="$(docker inspect --format='{{ .State.Pid }}' "$id")"

# Create temporary name for network namespace
mkdir -p /var/run/netns
ln -f -s "/proc/$pid/ns/net" "/var/run/netns/$ns"

# Remove temporary namespace on exit
clean_netns() {
	rm -f "/var/run/netns/$ns"
}

trap 'clean_netns' EXIT

# Create veth pair
ip link add "$ext" type veth peer name "$int"

# Remove veth pair on failure
clean_veth() {
	ip link del "$ext"
}

trap 'clean_veth; clean_netns' EXIT

# Save link-layer addresses
llext="$(cat "/sys/class/net/$ext/address")"
llint="$(cat "/sys/class/net/$int/address")"

# Move interface to container namespace
ip link set "$int" netns "$ns"

# Setup host interface
ip link set "$ext" up

ip -4 address add "$gwv4" peer "$ipv4/32" dev "$ext"
ip -4 neighbour replace "$ipv4" lladdr "$llint" nud permanent dev "$ext"

ip -6 address add "$gwv6" peer "$ipv6/128" dev "$ext"
ip -6 neighbour replace "$ipv6" lladdr "$llint" nud permanent dev "$ext"

# Setup container interface
ip netns exec "$ns" sh -e <<EOF
ip link set '$int' name eth0
ip link set eth0 up

ip -4 address add '$ipv4/32' dev eth0
ip -4 neighbour replace '$gwv6' lladdr '$llext' nud permanent dev eth0
ip -4 route add '$gwv4/32' dev eth0
ip -4 route add default via "$gwv4"

ip -6 address add '$ipv6' dev eth0
ip -6 neighbour replace '$gwv6' lladdr '$llext' nud permanent dev eth0
ip -6 route add '$gwv6/32' dev eth0
ip -6 route add default via '$gwv6'
EOF

# Reset trap
trap 'clean_netns' EXIT
