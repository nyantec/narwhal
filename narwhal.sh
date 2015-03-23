#!/bin/bash

set -e -o pipefail

# Docker container ID
id="$(docker inspect --format '{{ .Id }}' "$1" | cut -c 1-12)"

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
ln -f -s "/proc/$pid/ns/net" "/var/run/netns/$ns"
trap 'rm -f "/var/run/netns/$ns"' EXIT

# Create veth pair
ip link add "$ext" type veth peer name "$int"

# Move interface to container namespace
ip link set "$int" netns "$ns"

# Setup host interface
ip link set "$ext" up
ip -4 address add "$gwv4" peer "$ipv4/32" dev "$ext"
ip -6 address add "$gwv6" peer "$ipv6/128" dev "$ext"

# Setup container interface
ip netns exec "$ns" bash -e <<EOF
ip link set '$int' name eth0
ip link set eth0 up

ip -4 address add '$ipv4' peer '$gwv4/32' dev eth0
ip -4 route add default via "$gwv4"

ip -6 address add '$ipv6' peer '$gwv6/128' dev eth0
ip -6 route add default via '$gwv6'
EOF
