#!/bin/sh

set -e

msg() {
	local format="$1"
	shift 1
	printf "%s: $format\n\n" "$0" "$@"
}

die() {
	local status="$1"
	shift 1
	msg "$@" 1>&2
	exit "$status"
}

usage() {
	printf "Usage: %s [options] [container ID]\n" $0
}

optreq() {
	if [ "$1" -lt 2 ]
	then
		die 1 "Option requires an argument: %s" "$2"
	fi
}

# Parse command‐line arguments
while [ $# -gt 0 ]
do
	case "$1" in
	(--help|-h)
		usage
		exit 0;;

	(--ipv4|-4)
		optreq $# "$1"
		ipv4="$2"
		shift;;

	(--ipv6|-6)
		optreq $# "$1"
		ipv6="$2"
		shift;;

	(--host-ipv4)
		optreq $# "$1"
		host_ipv4="$2"
		shift;;

	(--host-ipv6)
		optreq $# "$1"
		host_ipv6="$2"
		shift;;

	(--interface|-i)
		optreq $# "$1"
		interface="$2"
		shift;;

	(--host-interface)
		optreq $# "$1"
		host_interface="$2"
		shift;;

	(--temp-interface)
		optreq $# "$1"
		temp_interface="$2"
		shift;;

	(--temp-namespace)
		optreq $# "$1"
		temp_namespace="$2"
		shift;;

	(--forwarding)
		forwarding=1

	(--)
		shift
		break;;

	(-*)
		die 1 "Unrecognised option: %s" "$1";;

	(*)
		break;;
	esac

	shift
done

if [ $# -lt 1 ]
then
	die 1 "Docker container ID required."
fi

# Docker container ID
id="$(docker inspect --format '{{ printf "%.12s" .Id }}' "$1")"

# Default values
: ${interface:=eth0}
: ${host_interface:=nw-$id}
: ${temp_interface:=nwt-$$}
: ${temp_namespace:=nwt-$$}

# Determine Docker container PID
pid="$(docker inspect --format='{{ .State.Pid }}' "$id")"

# Create temporary name for network namespace
mkdir -p /var/run/netns
ln -f -s "/proc/$pid/ns/net" "/var/run/netns/$temp_namespace"

# Remove temporary namespace on exit
clean_netns() {
	rm -f "/var/run/netns/$temp_namespace"
}

trap 'clean_netns' EXIT

# Create veth pair
ip link add "$host_interface" type veth peer name "$temp_interface"

# Remove veth pair on failure
clean_veth() {
	ip link del "$host_interface"
}

trap 'clean_veth; clean_netns' EXIT

# Save link-layer addresses
host_ll="$(cat "/sys/class/net/$host_interface/address")"
temp_ll="$(cat "/sys/class/net/$temp_interface/address")"

# Move interface to container namespace
ip link set "$temp_interface" netns "$temp_namespace"

# Setup host interface
ip link set "$host_interface" up

if [ -n "$ipv4" ]
then
	ip -4 address add "$host_ipv4" dev "$host_interface"
	ip -4 neighbour replace "$ipv4" lladdr "$temp_ll" nud permanent dev "$host_interface"
	ip -4 route add "$ipv4/32" dev "$host_interface"
fi

if [ -n "$ipv6" ]
then
	ip -6 address add "$host_ipv6" dev "$host_interface"
	ip -6 neighbour replace "$ipv6" lladdr "$temp_ll" nud permanent dev "$host_interface"
	ip -6 route add "$ipv6/128" dev "$host_interface"
fi

# Setup container interface
ip netns exec "$temp_namespace" env \
	interface="$interface" \
	temp_interface="$temp_interface" \
	ipv4="$ipv4" \
	ipv6="$ipv6" \
	host_ipv4="$host_ipv4" \
	host_ipv6="$host_ipv6" \
	host_ll="$host_ll" \
	sh -e <<EOF
ip link set "\$temp_interface" name "\$interface"
ip link set "\$interface" up

if [ -n "\$ipv4" ]
then
	ip -4 address add "\$ipv4/32" dev "\$interface"
	ip -4 neighbour replace "\$host_ipv4" lladdr "\$host_ll" nud permanent dev "\$interface"
	ip -4 route add "\$host_ipv4/32" dev "\$interface"
	ip -4 route add default via "\$host_ipv4" dev "\$interface"
fi

if [ -n "\$ipv6" ]
then
	ip -6 address add "\$ipv6/128" dev "\$interface"
	ip -6 neighbour replace "\$host_ipv6" lladdr "\$host_ll" nud permanent dev "\$interface"
	ip -6 route add "\$host_ipv6/128" dev "\$interface"
	ip -6 route add default via "\$host_ipv6" dev "\$interface"
fi
EOF

# Reset trap
trap 'clean_netns' EXIT
